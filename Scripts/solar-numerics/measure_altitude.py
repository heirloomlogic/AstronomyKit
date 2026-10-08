#!/usr/bin/env python3
"""Measure the complete native geometric-altitude model against extended precision."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time

import measure
import solar_reference as solar
from numerics import ROOT, ENGINE, BINDINGS, source_hashes, check_hashes

mp = solar.mp
PATHS = sorted(set(BINDINGS + measure.TOOLS + [
    'Scripts/solar-numerics/solar_reference.py', 'Scripts/solar-numerics/measure_altitude.py',
    'Tests/AstronomyKitTests/Engine/Numerics/NativeAltitudeProbe.swift',
    'Sources/AstronomyKit/SolarAltitudeObservation.swift', 'Sources/AstronomyKit/SolarAltitudeBounds.swift',
    'Sources/AstronomyKit/Position.swift', 'Sources/AstronomyKit/Time.swift', 'Sources/AstronomyKit/Observer.swift',
    *[ENGINE + path for path in [
        'Positions/EngineGeocentric.swift', 'Positions/EngineEquatorial.swift',
        'Orientation/EngineObserver.swift', 'Orientation/EngineFrameRotations.swift',
        'Orientation/EnginePrecession.swift', 'Orientation/EngineEquationOfEquinoxes.swift',
        'Orientation/Generated/EquinoxComplementaryTerms.swift', 'Orientation/EngineHorizon.swift',
        'Orientation/EngineRefraction.swift', 'Orientation/EngineRotations.swift']],
]))
OBSERVERS = [[0.0, 0.0, 0.0], [51.5, -0.12, 46.0], [89.999, 180.0, 0.0],
             [-90.0, -180.0, 0.0], [27.9881, 86.925, 10000.0], [-33.87, 151.21, -10000.0]]


def grid():
    epochs = measure.grid()
    # Native/exact-real stopping branches differ at these backdated model seams.
    for year, center in [(1941, -21549.494320910424), (2005, 1826.5056790659519), (2050, 18262.505679351943)]:
        for offset in range(-3, 4):
            value = center
            for _ in range(abs(offset)):
                value = math.nextafter(value, math.inf if offset > 0 else -math.inf)
            for model in ['espenakMeeus', 'jplHorizons']:
                epochs.append({'id': f'backdate-{year}-{offset}-{model}', 'days': value, 'scale': 'ut', 'model': model})
    for index, civil_day in enumerate([-18262.5, -14244.5-1e-8, -14244.5, -14244.5+1e-8, -0.5, 1826.5056790659519, 6209.5, 36000.25]):
        for model in ['espenakMeeus', 'jplHorizons']:
            epochs.append({'id': f'civil-{index}-{model}', 'days': (civil_day-365.5)*86400, 'scale': 'date', 'model': model})
    return [{'id': epoch['id'] + f'-observer-{index}', 'value': epoch['days'], 'scale': epoch['scale'],
             'model': epoch['model'], 'observer': observer[:]} for epoch in epochs for index, observer in enumerate(OBSERVERS)]


def validate_requests(requests):
    if requests != grid():
        raise ValueError('Recorded requests differ from the complete canonical request grid')


def comparisons(records, requests):
    if len(records) != len(requests) or len({r['request']['id'] for r in records}) != len(records):
        raise ValueError('Missing or duplicate native output rows')
    for row, request in zip(records, requests):
        if row['request'] != request:
            raise ValueError('Native result is associated with the wrong request')
    model = solar.Solar()
    rows = []
    for record, request in zip(records, requests):
        values = {key: measure.decode(bits) for key, bits in record['values'].items()}
        if request['scale'] != 'date' and values[request['scale']].hex() != request['value'].hex():
            raise ValueError('Native supplied time-scale bits changed')
        if not all(math.isfinite(value) for value in values.values()):
            raise ValueError('Nonfinite native result')
        if 'observation' in record and record['observation']['altitude'] != record['values']['altitude']:
            raise ValueError('Public observation is not bit-identical to the native geometric altitude')
        ut, tt = solar.ref.exact(values['ut']), solar.ref.exact(values['tt'])
        result = model.altitude(ut, tt, request['model'], request['observer'])
        expected = {'altitude': result['altitude'], 'azimuth': result['azimuth'],
                    **dict(zip(['sunX', 'sunY', 'sunZ'], result['vector']))}
        errors = {key: solar.ref.exact(values[key]) - value for key, value in expected.items()}
        errors['azimuth'] = (errors['azimuth'] + 180) % 360 - 180
        trace = [{key: mp.nstr(value, 75) for key, value in step.items()} for step in result['trace']]
        pair = solar.input_pair(request['value'], request['scale'], request['model'], values['ut'])
        origin = None
        if pair is not None:
            reference_ut,reference_tt = pair
            reference_altitude = model.altitude(reference_ut,reference_tt,request['model'],request['observer'])['altitude']
            origin = {'ut':mp.nstr(reference_ut,75),'tt':mp.nstr(reference_tt,75),'altitude':mp.nstr(reference_altitude,75),
                      'signedUTErrorDays':mp.nstr(ut-reference_ut,25),'signedTTErrorDays':mp.nstr(tt-reference_tt,25),
                      'signedAltitudeErrorDegrees':mp.nstr(solar.ref.exact(values['altitude'])-reference_altitude,25)}
        elif 'observation' in record:
            raise ValueError('A public observation was returned for an input without an exact model inverse')
        rows.append({**record, 'reference': {key: mp.nstr(value, 75) for key, value in expected.items()},
                     'signedError': {key: mp.nstr(value, 25) for key, value in errors.items()},
                     'inputReference':origin, 'referenceTrace': trace, 'iterationFlip': len(trace) != len(record['trace']),
                     'inverseResidualDays': mp.nstr(tt - (ut + solar.ref.delta_t(ut, request['model']) / 86400), 25)})
    return rows


def input_maximum(rows):
    return mp.nstr(max(abs(mp.mpf(row['inputReference']['signedAltitudeErrorDegrees'])) for row in rows if row['inputReference']),25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--recheck', action='store_true')
    args = parser.parse_args()
    if mp.__version__ != '1.3.0':
        raise SystemExit('Install pinned requirements.txt')
    if args.recheck:
        saved = json.loads(args.output.read_text())
        validate_requests(saved['requests'])
        if set(saved['sourceSHA256']) != set(PATHS):
            raise ValueError('Source binding coverage changed')
        check_hashes(ROOT, saved['sourceSHA256'])
        measure.verify_summary(saved)
        if input_maximum(saved['rows']) != saved['sampledMaximumInputAltitudeErrorDegrees']:
            raise ValueError('Recorded input-reference maximum differs from its rows')
        if comparisons(saved['rows'], grid()) != saved['rows']:
            raise ValueError('Recorded reference is not the current evaluator output')
        print(f"Re-executed {len(saved['rows'])} altitude rows")
        return
    requests = grid()
    workspace = ROOT / '.context' / f'altitude-numerics-{args.configuration}'
    workspace.mkdir(parents=True, exist_ok=True)
    input_path, output_path = workspace / 'input.json', workspace / 'native.json'
    input_path.write_text(json.dumps(requests, indent=2) + '\n')
    output_path.unlink(missing_ok=True)
    command = ['swift', 'test', '-c', args.configuration, '--filter', 'NativeAltitudeProbe.export']
    with (workspace / 'build.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    environment = dict(os.environ, ASTRONOMYKIT_ALTITUDE_INPUT=str(input_path), ASTRONOMYKIT_ALTITUDE_OUTPUT=str(output_path))
    begin = time.perf_counter()
    with (workspace / 'run.log').open('w') as log:
        subprocess.run(['/usr/bin/time', '-l' if platform.system() == 'Darwin' else '-v', *command, '--skip-build'], cwd=ROOT, env=environment,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    elapsed = time.perf_counter() - begin
    rows = comparisons(json.loads(output_path.read_text()), requests)
    report = {'schemaVersion': 1, 'status': 'sampled-native-altitude-at-recorded-pair-and-exact-public-input-not-a-certificate',
              'configuration': args.configuration, 'precisionDecimalDigits': mp.mp.dps, 'referenceLibrary': 'mpmath 1.3.0',
              'pythonVersion': platform.python_version(), 'platform': platform.platform(), 'architecture': platform.machine(),
              'swiftVersion': subprocess.check_output(['swift', '--version'], text=True, stderr=subprocess.STDOUT).strip(),
              'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'sourceSHA256': source_hashes(ROOT, PATHS), 'nativeProcessSecondsIncludingRunner': elapsed,
              'nativeProcessLog': (workspace / 'run.log').read_text(), 'requests': requests, 'rows': rows,
              'sampledMaximumAbsoluteError': measure.summary(rows),
              'sampledMaximumInputAltitudeErrorDegrees':input_maximum(rows),
              'excluded': ['continuous arithmetic or libm bounds', 'other compilers or architectures']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'rows': len(rows), 'flips': sum(row['iterationFlip'] for row in rows), 'maxima': report['sampledMaximumAbsoluteError']}, indent=2))


if __name__ == '__main__':
    main()
