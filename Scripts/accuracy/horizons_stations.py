#!/usr/bin/env python3
"""Independent station cross-check using JPL apparent ICRF directions and ERFA.

Fetch is explicit. Re-evaluation uses archived HTTP responses without a network.
This diagnoses the frozen oracle; it never overwrites the original references.
Requires the diagnostic requirements-horizons.txt environment.
"""
import argparse
import csv
import datetime as dt
import hashlib
import importlib.metadata
import json
import math
import re
from pathlib import Path
import urllib.parse
import urllib.request

import erfa
import numpy as np
import swisseph as swe

from measure import EPOCH, Model, fixtures

TARGETS = {'mercury': 1, 'venus': 2, 'mars': 4, 'jupiter': 5, 'saturn': 6}
# Horizons canonicalizes the moonless planets' barycentres to 199/299.
RESPONSE_IDS = {'mercury': 199, 'venus': 299, 'mars': 4, 'jupiter': 5, 'saturn': 6}
HOURS = [-2, -1, -.5, 0, .5, 1, 2]
FLAGS = swe.FLG_MOSEPH | swe.FLG_SPEED


def selections():
    result = {}
    for case, oracle in fixtures():
        for index, event in enumerate(oracle['events']):
            if event['kind'] != 'station':
                continue
            body = event['bodies'][0]
            ut = (dt.datetime.fromisoformat(event['instant']) - EPOCH).total_seconds()/86400
            tt = ut + swe.deltat_ex(ut+2451545, swe.FLG_MOSEPH)
            result.setdefault(body, []).append(dict(caseID=case, eventIndex=index, original=event, tt=tt))
    return result


def request(body, events):
    return {'format': 'json', 'COMMAND': f"'{TARGETS[body]}'", 'CENTER': "'500@399'",
              'EPHEM_TYPE': "'OBSERVER'", 'TIME_TYPE': "'TT'", 'TLIST_TYPE': "'JD'",
              'TLIST': ','.join(f"'{2451545+e['tt']+h/24:.12f}'" for e in events for h in HOURS),
              'QUANTITIES': "'45'", 'ANG_FORMAT': "'DEG'", 'EXTRA_PREC': "'YES'",
              'CSV_FORMAT': "'YES'", 'CAL_FORMAT': "'BOTH'", 'TIME_DIGITS': "'FRACSEC'", 'REF_SYSTEM': "'ICRF'", 'APPARENT': "'AIRLESS'"}


def fetch(directory, selected):
    directory.mkdir(parents=True, exist_ok=True)
    manifest = {}
    # Requests are sequential, respecting JPL's service limits.
    for body, events in selected.items():
        params = request(body, events)
        url = 'https://ssd.jpl.nasa.gov/api/horizons.api?' + urllib.parse.urlencode(params)
        data = urllib.request.urlopen(url, timeout=45).read()
        response = json.loads(data)
        if 'error' in response or '$$SOE' not in response.get('result', ''):
            raise ValueError(response.get('error', 'Missing Horizons ephemeris'))
        (directory/f'{body}-request.json').write_text(json.dumps(params, indent=2)+'\n')
        (directory/f'{body}-response.json').write_bytes(data)
        manifest[body] = {'request': params, 'responseSHA256': hashlib.sha256(data).hexdigest()}
        print('Fetched', body, flush=True)
    (directory/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')


def longitude(jd, ra, dec):
    ra, dec = math.radians(ra), math.radians(dec)
    xyz = np.array([math.cos(dec)*math.cos(ra), math.cos(dec)*math.sin(ra), math.sin(dec)])
    # ICRF -> IAU2006 mean ecliptic/equinox of date; then true longitude origin.
    vector = erfa.ecm06(2451545., jd-2451545.) @ xyz
    psi = erfa.nut00b(2451545., jd-2451545.)[0]
    return (math.degrees(math.atan2(vector[1], vector[0])+psi)) % 360


def fit(times, longitudes):
    angles = np.degrees(np.unwrap(np.radians(longitudes)))
    angles -= angles[len(angles)//2]
    fits = {}
    for degree in (2, 3, 4):
        coefficients = np.polynomial.polynomial.polyfit(times, angles, degree)
        derivative = np.polynomial.polynomial.polyder(coefficients)
        roots = np.polynomial.polynomial.polyroots(derivative)
        candidates = [r.real for r in roots if abs(r.imag) < 1e-8 and min(times) < r.real < max(times)]
        if len(candidates) != 1:
            raise ValueError('Fit did not identify exactly one local ordinary station')
        residual = max(abs(np.polynomial.polynomial.polyval(times, coefficients)-angles))
        fits[str(degree)] = {'offsetSeconds': candidates[0]*3600, 'maxFitResidualDegrees': float(residual)}
    return fits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('library', type=Path)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--output', type=Path, required=True, help='Report path outside the frozen input archive')
    args = parser.parse_args()
    for package, version in {'pyswisseph': '2.10.3.2', 'pyerfa': '2.0.1.5', 'numpy': '2.4.6'}.items():
        if importlib.metadata.version(package) != version:
            raise ValueError(f'Requires {package}=={version}')
    selected = selections()
    if args.fetch:
        fetch(args.directory, selected)
    manifest = json.loads((args.directory/'manifest.json').read_text())
    model = Model(args.library.resolve())
    rows = []
    for body, events in selected.items():
        data = (args.directory/f'{body}-response.json').read_bytes()
        if hashlib.sha256(data).hexdigest() != manifest[body]['responseSHA256']:
            raise ValueError('Horizons response checksum mismatch')
        if manifest[body]['request'] != request(body, events):
            raise ValueError('Horizons request differs from frozen selection/conventions')
        text = json.loads(data)['result']
        if not re.search(r'Target body name:.*\(' + str(RESPONSE_IDS[body]) + r'\)', text):
            raise ValueError('Wrong Horizons target identity')
        if not re.search(r'Center body name:.*\(399\)', text):
            raise ValueError('Wrong Horizons observer identity')
        if 'JDTDB' in text or 'JDUT' in text or 'JDTT' not in text or 'ICRF-a-app' not in text:
            raise ValueError('Wrong Horizons time/frame convention')
        table = list(csv.reader(text.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines()))
        if len(table) != len(events)*len(HOURS):
            raise ValueError('Horizons sample count mismatch')
        for index, event in enumerate(events):
            times, jpl, native, swiss = [], [], [], []
            for sample_index, row in enumerate(table[index*7:(index+1)*7]):
                jd, ra, dec = float(row[1]), float(row[4]), float(row[5])
                expected_jd = 2451545 + event['tt'] + HOURS[sample_index]/24
                if not all(math.isfinite(v) for v in (jd, ra, dec)) or abs(jd-expected_jd)*86400 > .001:
                    raise ValueError('Horizons sample epoch mismatch or non-finite sample')
                times.append((jd-2451545-event['tt'])*24)
                jpl.append(longitude(jd, ra, dec))
                ut = jd-2451545
                for _ in range(4):
                    ut -= model.position(body, ut)[2]-(jd-2451545)
                if abs(model.position(body, ut)[2]-(jd-2451545))*86400 > .001:
                    raise ValueError('Failed to match terrestrial time')
                native.append(model.position(body, ut)[0])
                values, returned = swe.calc(jd, getattr(swe, body.upper()), FLAGS)
                if returned != FLAGS:
                    raise ValueError('Unexpected Swiss ephemeris flags')
                swiss.append(values[0])
            fits = {name: fit(times, values) for name, values in [('jpl', jpl), ('native', native), ('swissLongitude', swiss)]}
            inner_fits = {name: fit(times[1:-1], values[1:-1])
                          for name, values in [('jpl', jpl), ('native', native), ('swissLongitude', swiss)]}
            jpl_root = fits['jpl']['4']['offsetSeconds']
            result = {**event, 'body': body, 'fits': fits, 'oneHourFits': inner_fits,
                      'samples': {'hoursFromFrozenTT': times, 'jplLongitude': jpl,
                                  'nativeLongitude': native, 'swissLongitude': swiss},
                      'jplWindowSensitivitySeconds': inner_fits['jpl']['4']['offsetSeconds']-jpl_root,
                      'nativeMinusJPLSeconds': fits['native']['4']['offsetSeconds']-jpl_root,
                      'swissLongitudeMinusJPLSeconds': fits['swissLongitude']['4']['offsetSeconds']-jpl_root,
                      'frozenSpeedReferenceMinusJPLSeconds': -jpl_root}
            rows.append(result)
            print(event['caseID'], event['eventIndex'], 'native-JPL', round(result['nativeMinusJPLSeconds'], 3),
                  'frozen speed-JPL', round(-jpl_root, 3), flush=True)
    report = {'purpose': 'Independent station diagnosis, not replacement frozen references or search completeness',
              'targetConvention': 'planetary system barycentres (JPL 1,2,4,5,6), geocentre 399',
              'timeConvention': 'common TT; original UT reference converted with its Swiss delta-T',
              'frame': 'Horizons quantity45 ICRF apparent -> ERFA ecm06 + nut00b longitude origin',
              'nativeLibrarySHA256': hashlib.sha256(args.library.read_bytes()).hexdigest(),
              'scriptSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'versions': {p: importlib.metadata.version(p) for p in ['numpy', 'pyerfa', 'pyswisseph']},
              'cases': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
