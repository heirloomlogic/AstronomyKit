#!/usr/bin/env python3
"""Replay frozen reference populations through the repaired production APIs."""
import argparse
import importlib.util
import json
import math
from pathlib import Path


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


H = module('bundled_lunar_holdout', 'qualify-lunar-candidate-holdout.py')
B = module('bundled_builder', 'build-bundled-runner.py')
G = H.G
Q = G.Q
ROOT = Q.ROOT
REPORT = ROOT / 'Documentation/Migration/bundled-public-api-assessment.json'


def match_events(case, reference, actual, allowance):
    if len(reference) != len(actual) or [r['kind'] for r in reference] != [r['kind'] for r in actual]:
        return [], [{'case': case, 'reference': reference, 'actual': actual}]
    events = []
    for ref, result in zip(reference, actual):
        error = (result['julianDateTT'] - ref['julianDateTT']) * 86400
        events.append({'case': case, 'reference': ref, 'actual': result, 'signedTimeErrorSeconds': error,
                       'nominalWithinTarget': abs(error) < 60,
                       'numericalEnvelopeClassification': Q.event_classification(error, allowance)})
    return events, []


def lunar_holdout(binary):
    # This population was frozen before production integration. Its original
    # candidate report and input locks remain intact; this is a public API replay.
    plan = json.loads(H.PLAN.read_bytes())
    if plan['policySHA256'] != Q.digest(Q.POLICY.read_bytes()):
        raise ValueError('holdout owner policy drift')
    rows, metadata = H.pair('positions', Q.parameters('301', '399', 'NONE', plan['positionJulianDatesTT']))
    requests = [{'operation': 'position', 'body': Q.BODY_CODES['Moon'], 'mode': 'geocentric-none', 'julianDateTT': r['julianDateTT']} for r in rows]
    actual = Q.public_batch(requests, binary)
    bias = G.erfa.pmat06(2451545.0, 0.0)
    positions = []
    for ref, result in zip(rows, actual):
        icrf = bias.T @ G.numpy.array(result['positionAU'])
        angle = Q.angle_arcminutes(icrf, ref['positionAU'])
        error = (math.hypot(*icrf) - ref['rangeAU']) / ref['rangeAU'] * 1e6
        positions.append({'reference': ref, 'actual': result, 'angleErrorArcminutes': angle, 'signedRangeErrorPPM': error})
    events, failures, provenance = [], [], {'positions': metadata}
    for window in plan['eventWindows']:
        references, meta = H.references(window, plan)
        provenance[window['id']] = meta
        requests = [{'operation': operation, 'startJulianDateTT': window['startJulianDateTT'], 'stopJulianDateTT': window['startJulianDateTT'] + window['durationDays']} for operation in ['lunar-apsides', 'lunar-nodes']]
        for family, result in zip(['apsis', 'node'], Q.public_batch(requests, binary)):
            matched, invalid = match_events(window['id'] + '/' + family, references[family], result['events'], plan['referenceNumericalAllowanceSeconds'])
            events.extend(matched)
            failures.extend(invalid)
    return {'positions': positions, 'events': events, 'identityFailures': failures, 'provenance': provenance,
            'summary': {'positionCount': len(positions), 'eventCount': len(events), 'identityFailures': len(failures),
                        'maximumAngleErrorArcminutes': max(p['angleErrorArcminutes'] for p in positions),
                        'maximumAbsoluteRangeErrorPPM': max(abs(p['signedRangeErrorPPM']) for p in positions),
                        'maximumAbsoluteTimeErrorSeconds': max(abs(e['signedTimeErrorSeconds']) for e in events),
                        'angularExceedances': sum(p['angleErrorArcminutes'] > 1 for p in positions),
                        'distanceExceedances': sum(abs(p['signedRangeErrorPPM']) > 100 for p in positions),
                        'nominalTimingExceedances': sum(not e['nominalWithinTarget'] for e in events)}}


def assess(binary):
    build = B.validate(binary)
    positions = Q.assess(binary)
    geometric = G.assess(binary)
    holdout = lunar_holdout(binary)
    paths = [Path(__file__), H.PLAN, Path(H.__file__)]
    paths += list(H.RAW.glob('*.json'))
    paths += list((ROOT / 'Sources/CLibAstronomy/EphemerisData').glob('*'))
    paths += list((ROOT / 'Documentation/Migration/LunarBundledSources').glob('*'))
    inputs = dict(positions['inputSHA256'])
    inputs.update(geometric['inputSHA256'])
    inputs.update({str(p.relative_to(ROOT)): Q.digest(p.read_bytes()) for p in paths if p.is_file()})
    compact_positions = [{key: value for key, value in row.items() if key != 'reference'} | {'julianDateTT': row['reference']['julianDateTT']} for row in positions['positions']]
    B.validate(binary)
    return {'schemaVersion': 1, 'classification': 'finite-production-public-api-replay-not-continuous-or-physical-uncertainty-qualification',
            'baselineEvidenceCommit': 'ec134360', 'inputSHA256': inputs, 'executableProvenance': positions['executableProvenance'], 'boundBuild': build,
            'referenceEnvironment': geometric['referenceEnvironment'], 'positionSummary': positions['positionSummary'],
            'positions': compact_positions, 'lunarApsides': positions['lunarApsides'], 'positionTotals': positions['totals'],
            'eventIdentityFailures': positions['eventIdentityFailures'], 'geometricEvents': geometric['events'],
            'geometricSummary': geometric['summary'], 'geometricTotals': geometric['totals'],
            'geometricIdentityFailures': geometric['identityFailures'], 'lunarCandidateHoldoutReplay': holdout,
            'limitations': positions['limitations'] + geometric['limitations'] + [
                'Old position/alignment populations are retrospective. The lunar candidate holdout is replayed through production APIs after prototype use.',
                'Production lunar holdout positions are transformed EQJ to ICRF using the transpose of the official ERFA J2000 bias matrix.',
                'Unmodified Neptune and all diagnostic corrected-distance failures remain visible; this report does not close the general accuracy qualification issue.'],
            'uncoveredEventFamilies': sorted(set(positions['uncoveredEventFamilies'] + geometric['uncoveredEventFamilies']))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['report', 'check'])
    parser.add_argument('--binary', type=Path, default=Q.BINARY)
    args = parser.parse_args()
    report = assess(args.binary)
    data = Q.encoded(report)
    if args.action == 'check':
        if REPORT.read_bytes() != data:
            raise ValueError('bundled public API replay drift')
    else:
        if REPORT.exists():
            raise ValueError('report already frozen')
        REPORT.write_bytes(data)
    print(json.dumps({'positions': report['positionTotals'], 'geometric': report['geometricTotals'], 'lunarHoldout': report['lunarCandidateHoldoutReplay']['summary']}, sort_keys=True))


if __name__ == '__main__':
    main()
