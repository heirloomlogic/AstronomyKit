#!/usr/bin/env python3
"""Bind fresh native planetary-event measurements to their source and runtime files."""
import argparse
import hashlib
import importlib.util
import json
import math
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT/'Scripts/saturn-data/native-evidence.json'


def source_hashes():
    paths = list((ROOT/'Sources/AstronomyKit/Engine').rglob('*.swift'))
    paths += list((ROOT/'Scripts/reference-data/sources/planetary-apsides').glob('*.json'))
    paths += [ROOT/p for p in [
        'Scripts/record-planetary-event-evidence.py', 'Scripts/assess-saturn-apsides.py',
        'Scripts/assess-pluto-de441.py', 'Scripts/assess-moon-de441.py', 'Scripts/qualify-moon-de441.py',
        'Scripts/generate-moon-tables.py', 'Scripts/generate-moon-de441.py', 'Scripts/generate-saturn-tables.py', 'Scripts/test_saturn_ephemeris.py',
        'Sources/CLibAstronomy/EphemerisTime/dtdb.c', 'Sources/CLibAstronomy/astronomy.c',
        'Sources/AstronomyKit/Apsis.swift', 'Sources/AstronomyKit/Time.swift', 'Sources/AstronomyKit/CelestialBody.swift',
        'Tests/AstronomyKitTests/IndependentReferenceFixtures.swift',
        'Scripts/reference-data/capture-planetary-apsides.py', 'Scripts/reference-data/test_capture_planetary_apsides.py',
        'Scripts/reference-data/build-fixtures.py', 'Scripts/reference-data/planetary-apsis-evidence.json',
        'Scripts/reference-data/sources/horizons/saturn-apsis-precision.json',
        'Scripts/reference-data/sources/horizons/saturn-apsis-precision.query.json',
        'Scripts/saturn-data/assessment.json', 'Scripts/saturn-data/direct-fixtures.json',
        'Scripts/saturn-data/barycenter-reference.json', 'Scripts/saturn-data/barycenter-reference.query.json',
        'Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json',
        'Tests/AstronomyKitTests/Engine/Events/EnginePlanetaryEventTests.swift',
        'Tests/AstronomyKitTests/Engine/Planets/EngineSaturnEphemerisTests.swift',
        'Tests/AstronomyKitTests/Engine/Planets/EngineSaturnMeasurementTests.swift',
    ]]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def measurements(directory, configuration):
    directory = Path(directory)
    result = {name: json.loads((directory/f'link3-{name}-{configuration}.json').read_bytes()) for name in ['saturn', 'source']}
    result['parity'] = json.loads((directory/f'link3-{configuration}.json').read_bytes())
    result['coefficients'] = json.loads((directory/f'saturn-assessment/source-{configuration}.json').read_bytes())
    return result


def validate(result):
    references = json.loads((ROOT/'Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json').read_bytes())['saturnApsides']
    if [r['referenceJulianDateTT'] for r in result['saturn']] != [r['julianDateTT'] for r in references]:
        raise ValueError('Saturn selection differs')
    if any(not math.isfinite(r['signedTimingErrorSeconds']) or abs(r['signedTimingErrorSeconds']) >= 60 for r in result['saturn']):
        raise ValueError('Saturn sixty-second criterion failed')
    expected = json.loads((ROOT/'Scripts/reference-data/planetary-apsis-evidence.json').read_bytes())['cases']
    if [r['body'] for r in result['source']] != [r['body'] for r in expected]:
        raise ValueError('planetary source selection differs')
    for measured, source in zip(result['source'], expected):
        bracket = (measured['sourceLowerJDTT'], measured['sourceUpperJDTT'])
        if bracket not in [(r['lowerJDTT'], r['upperJDTT']) for r in source['roots']]:
            raise ValueError('source bracket changed')
        residual = (measured['nativeJDTT'] - sum(bracket)/2)*86400
        if not math.isfinite(residual) or abs(residual - measured['nativeMinusSourceSeconds']) > 1e-9:
            raise ValueError('invalid residual')
        if measured['body'] not in ['jupiter', 'uranus', 'neptune'] and abs(residual) >= 60:
            raise ValueError('qualified source case missed sixty seconds')
    if result['coefficients']['rows'] != len(json.loads((ROOT/'Scripts/saturn-data/direct-fixtures.json').read_bytes())['rows']):
        raise ValueError('coefficient sample selection differs')


def encoding_boundary_limits():
    spec = importlib.util.spec_from_file_location('saturn_assessment', ROOT/'Scripts/assess-saturn-apsides.py')
    assessment = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(assessment)
    candidate = json.loads(assessment.OUTPUT.read_bytes())['candidates']['float32']
    minimum_distances = []
    for root in candidate['roots']:
        tdb = assessment.tt_to_tdb(root['rootJDTT'])
        distances = []
        for body in candidate['bodies'].values():
            fraction = (tdb-body['startJDTDB'])/body['recordDays']
            distances.append(abs(fraction-round(fraction))*body['recordDays']*86400)
        minimum_distances.append(dict(referenceJDTT=root['referenceJDTT'], nearestRecordJoinSeconds=min(distances)))
    return dict(finiteDifferenceWidthDays=0.001,
                encodingOnlySlopePerturbationBoundAUPerDay=2*candidate['bodies']['699']['positionBoundKm']/0.001/assessment.d.AU_KM,
                existingStateDerivativeComparisonAllowanceAUPerDay=2e-9,
                roots=minimum_distances,
                scope='Position-encoding contribution only, using the Lipschitz property of vector norm. Evaluator roundoff and the physical source are separate. This does not bound event-time error near shallow roots; the six qualified roots do not test join-adjacent events.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--capture', type=Path, help='directory with fresh Debug and Release Swift measurement files')
    args = parser.parse_args()
    if bool(args.check) == bool(args.capture):
        parser.error('choose --check or --capture')
    if args.check:
        result = json.loads(OUTPUT.read_bytes())
        if result['encodingBoundaryLimits'] != encoding_boundary_limits():
            raise ValueError('encoded boundary qualification differs')
        if result['sourceSHA256'] != source_hashes():
            raise ValueError('native evidence source bindings differ; recapture after source changes')
    else:
        release = args.capture/'saturn-assessment/measurement-release.json'
        executable = ROOT/'.build/release/AstronomyKitTests.xctest/Contents/MacOS/AstronomyKitTests'
        result = dict(schemaVersion=1, sourceSHA256=source_hashes(), debug=measurements(args.capture, 'debug'), release=measurements(args.capture, 'release'),
                      resources=json.loads(release.read_bytes()), encodingBoundaryLimits=encoding_boundary_limits(),
                      buildSeconds={c:float(re.search(r'Build complete! \(([^ ]+) sec\)', (args.capture/f'link3-full-{c}.log').read_text()).group(1)) for c in ['debug','release']},
                      toolchain=subprocess.check_output(['swift', '--version'], text=True).strip(),
                      releaseExecutableBytes=executable.stat().st_size,
                      baseline=json.loads((args.capture/'saturn-assessment/baseline-binary.json').read_bytes()),
                      decodedPayloadBytes=10618464,
                      resourceScope='macOS arm64 Release test executable; first retained evaluation then first center evaluation in a new process, followed by 2000 states per model and 100 repeated Saturn apsis searches. RSS is process high-water, not isolated object ownership. Baseline executable predates Saturn integration; binary delta also includes tests.',
                      fullWeightTT=[-36524.5,47846.5], blendTT=[[-36556.5,-36524.5],[47846.5,47878.5]],
                      limitations=['Six Saturn source roots and eight native-selected diagnostic windows, not a continuous event-time bound or an orbital event census.', 'Jupiter, Uranus and Neptune fail the unchanged sixty-second comparison and remain owned by #92.', 'Public C searches are unchanged until #96, including the pre-existing sampled-refinement stopping defect.', 'Outside the Saturn source window the retained model remains; global physical-center and event accuracy are not established.'])
    for configuration in ['debug', 'release']:
        validate(result[configuration])
    if not args.check:
        OUTPUT.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    print('Verified native planetary event evidence' if args.check else 'Recorded native planetary event evidence')


if __name__ == '__main__':
    main()
