#!/usr/bin/env python3
"""Capture and replay the frozen Pluto geocentric observer references."""
import argparse
import csv
import hashlib
import importlib.util
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/pluto-data'
SPEC = importlib.util.spec_from_file_location('references', ROOT / 'Scripts/reference-data/build-fixtures.py')
references = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(references)
EPOCHS = {
    9: [-766524., -600000., -400000., -200000., 200000., 400000., 600000., 766524.],
    999: [-58400., -36556.5, -36556.25, -36540.5, -36524.5, 0., 47846.5, 47846.75, 47862.5, 47878.5, 47878.75, 58400.],
}


def query(target):
    result = references.observer_query(str(target), [2451545. + t for t in EPOCHS[target]])
    result.update({key: references.quoted(value) for key, value in {
        'TIME_TYPE': 'TT', 'TLIST_TYPE': 'JD', 'CAL_FORMAT': 'JD',
        'QUANTITIES': '1,2,21,45', 'EXTRA_PREC': 'YES',
    }.items()})
    return result


def parse(target, data):
    try:
        references.validate_horizons_response(str(target), data)
    except RuntimeError as error:
        raise ValueError(str(error)) from error
    result = json.loads(data)['result']
    name, source = ('Pluto Barycenter', 'DE441') if target == 9 else ('Pluto', 'plu060_merged')
    requirements = [
        rf'Target body name: {name} \({target}\) +\{{source: {source}\}}',
        r'Center body name: Earth \(399\) +\{source: DE441\}',
        r'Center-site name: GEOCENTRIC', r'Atmos refraction: NO \(AIRLESS\)',
    ]
    if any(re.search(pattern, result) is None for pattern in requirements):
        raise ValueError('unexpected target, source, observer, or refraction semantics')
    header = next((line for line in result.splitlines() if line.startswith('Date_')), '')
    expected = ['Date_________JDTT', '', '', 'R.A.___(ICRF)', 'DEC____(ICRF)',
                'R.A.__(a-app)', 'DEC___(a-app)', '1-way_down_LT', 'RA_(ICRF-a-app)', 'DEC_(ICRF-a-app)', '']
    if [c.strip() for c in next(csv.reader([header]))] != expected:
        raise ValueError('unexpected time scale, frame, or column layout')
    lines = result.split('$$SOE\n')[1].split('$$EOE')[0].splitlines()
    if len(lines) != len(EPOCHS[target]):
        raise ValueError('missing or extra observer epochs')
    rows = []
    for tt, line in zip(EPOCHS[target], lines):
        columns = [c.strip() for c in next(csv.reader([line]))]
        if len(columns) != 11 or columns[1:3] != ['', ''] or columns[-1] != '':
            raise ValueError('unexpected row layout')
        jd, *values = [float(columns[i]) for i in [0, 3, 4, 5, 6, 7, 8, 9]]
        if not all(math.isfinite(v) for v in [jd, *values]) or jd != tt + 2451545.:
            raise ValueError('invalid value or changed epoch')
        for ra, dec in [values[0:2], values[2:4], values[5:7]]:
            if not (0 <= ra < 360 and -90 <= dec <= 90):
                raise ValueError('invalid direction')
        if not 0 < values[4] < 1440:
            raise ValueError('invalid light time')
        rows.append(dict(tt=tt, target=target, astrometricICRFDeg=values[:2], apparentEQDDeg=values[2:4],
                         lightTimeMinutes=values[4], apparentICRFDeg=values[5:7]))
    return rows


def fixture():
    sources, rows = [], []
    for target in EPOCHS:
        path = DATA / 'observer-sources' / f'horizons-{target}.json'
        data = path.read_bytes()
        rows += parse(target, data)
        sources.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                            query=query(target), url=references.horizons_url(query(target))))
    return dict(schemaVersion=1, observationTimeScale='JD TT', angularToleranceArcminutes=1,
                selection='Frozen before retrieval: eight outer barycenter epochs and twelve center epochs including both 32-day blends.',
                sources=sources, rows=rows)


def source_hashes():
    # Bind the full native engine, including generated constants and time/frame dependencies.
    paths = list((ROOT / 'Sources/AstronomyKit/Engine').rglob('*.swift'))
    paths += [Path(__file__), ROOT / 'Scripts/reference-data/build-fixtures.py',
              ROOT / 'Scripts/test_capture_pluto_observers.py', DATA / 'observer-fixtures.json',
              ROOT / 'Tests/AstronomyKitTests/Engine/Positions/EnginePlutoConsumerQualificationTests.swift']
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def validate_measurement(measurement):
    expected = fixture()['rows']
    rows = measurement['rows']
    if [(r['tt'], r['target']) for r in rows] != [(r['tt'], r['target']) for r in expected]:
        raise ValueError('measurement selection differs')
    for row, reference in zip(rows, expected):
        if not all(isinstance(v, (float, int)) and math.isfinite(v) for v in row.values()):
            raise ValueError('nonfinite measurement')
        for key in ['astrometricArcminutes', 'apparentICRFArcminutes', 'apparentEQDArcminutes']:
            if not 0 <= row[key] <= 1:
                raise ValueError('one-arcminute target missed')
        if row['horizonsLightTimeMinutes'] != reference['lightTimeMinutes']:
            raise ValueError('reference light time changed')
        if not row['emissionTT'] < row['tt']:
            raise ValueError('emission does not precede observation')
    for name in ['Earth', 'Frame']:
        count = sum(row[f'omitted{name}Arcminutes'] > 1 for row in rows)
        if count != measurement[f'omitted{name}Failures'] or count < 15:
            raise ValueError('negative control differs')


def native_evidence(debug, release):
    for measurement in [debug, release]:
        validate_measurement(measurement)
    return dict(schemaVersion=1, sourceSHA256=source_hashes(), debug=debug, release=release,
                observationTimeScale='TT, inverted to modeled UT with jplHorizons for the native UT light-time iteration',
                toleranceArcminutes=1,
                domain=dict(acceptedHeliocentricTTDays=[-766525, 766525],
                            retardedSourceTDBInterval=dict(lowerInclusive=-766536.5, upperExclusive=766535.5),
                            successfulGeocentricTTDays=[-766525, -766524.9, -766524, 766524, 766525],
                            modes=['none', 'corrected'], issue='https://github.com/heirloomlogic/AstronomyKit/issues/227',
                            preexistingBase='00119ad33521b67fa365b33d940404d5739e356b'),
                limitations=['Twenty sampled native directions, not a full-range bound.',
                             'Outer target 9 references do not qualify the physical center 999.',
                             'Endpoint tests cover velocity composition, not independent velocity accuracy; event and public API qualification remain with #92/#96.',
                             'Horizons apparent coordinates include gravitational deflection and barycentric light time; native uses heliocentric light time and first-order aberration.',
                             'Native and Horizons equator-of-date precession/nutation conventions differ.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', action='store_true', help='explicitly replace the archived publisher responses')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--record-native', nargs=2, metavar=('DEBUG_JSON', 'RELEASE_JSON'), help='record fresh opt-in Swift test outputs')
    args = parser.parse_args()
    if sum([args.capture, args.check, args.record_native is not None]) > 1:
        parser.error('--capture, --check, and --record-native are mutually exclusive')
    for target in EPOCHS:
        path = DATA / 'observer-sources' / f'horizons-{target}.json'
        if args.capture:
            data = references.download(references.horizons_url(query(target)))
            references.validate_horizons_response(str(target), data)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    output = DATA / 'observer-fixtures.json'
    encoded = (json.dumps(fixture(), indent=2, sort_keys=True) + '\n').encode()
    if args.check:
        if output.read_bytes() != encoded:
            raise SystemExit('observer fixtures or archive digests differ; regenerate explicitly')
        evidence = json.loads((DATA / 'observer-evidence.json').read_bytes())
        if evidence != native_evidence(evidence['debug'], evidence['release']):
            raise SystemExit('native evidence source bindings or metadata differ; rerun native qualification')
        print('20 Pluto observer epochs, both archive digests, and native evidence bindings verified')
    else:
        output.write_bytes(encoded)
    if args.record_native:
        measurements = [json.loads(Path(p).read_bytes()) for p in args.record_native]
        (DATA / 'observer-evidence.json').write_text(json.dumps(native_evidence(*measurements), indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
