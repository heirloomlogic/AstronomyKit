#!/usr/bin/env python3
"""Reconstruct RP1301's G0 Besselian magnitude and compare physical-disc candidates."""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'Scripts/eclipse-data'
EPOCH_TOLERANCE_DAYS = 5e-10


def polynomial(coefficients, t):
    return math.fsum(value*t**power for power, value in enumerate(coefficients))


def build(references, physical):
    report = references['rp1301']
    elements = report['besselian']
    method = report['methodSource']
    t = elements['greatestTDT']-elements['t0TDT']
    values = {key: polynomial(coefficients, t) for key, coefficients in elements['coefficients'].items()}
    declination = math.radians(values['d'])
    flattening = 1/method['earthPolarToEquatorialRatio']**2-1
    x, y = values['x'], values['y']
    a = 1+flattening*math.sin(declination)**2
    b = 2*flattening*y*math.cos(declination)*math.sin(declination)
    c = x*x+y*y+flattening*(y*math.cos(declination))**2-1
    zeta = (-b+math.sqrt(b*b-4*a*c))/(2*a)
    observer_l1 = values['l1']-zeta*elements['tanF1']
    observer_l2 = values['l2']-zeta*elements['tanF2']
    mixed = (observer_l1-observer_l2)/(observer_l1+observer_l2)
    candidates = []
    for row in physical:
        if abs(row['tt']-report['greatestTT']) > EPOCH_TOLERANCE_DAYS:
            continue
        candidates.append({'case': row['case'], 'diameterRatio': row['diameterRatio'], 'physicalOverlapArea': row['areaObscuration'], 'ratioResidualFromPrintedMagnitude': row['diameterRatio']-report['greatestMagnitude']})
    result = {'schemaVersion': 1, 'sourceLabel': report['greatestLabel'], 'sourcePrintedMagnitude': report['greatestMagnitude'], 'conditionalPrintInterval': [report['ratioLower'], report['ratioUpper']], 'sourceConventions': {'rp1301L1UsesK1': report['k1'], 'rp1301L2UsesK2': report['k2'], 'observerReduction': "L'=l-zeta*tan(f)", 'centralMagnitude': "(L1'-L2')/(L1'+L2')", 'physicalCandidateEpochToleranceSeconds': EPOCH_TOLERANCE_DAYS*86400, 'methodSource': method}, 'evaluatedBesselianElements': values, 'axisSurfaceZeta': zeta, 'observerPlaneL1': observer_l1, 'observerPlaneL2': observer_l2, 'mixedRadiusMagnitude': mixed, 'mixedRadiusMagnitudeSquared': mixed*mixed, 'mixedMagnitudeInsidePrintInterval': report['ratioLower'] <= mixed <= report['ratioUpper'], 'physicalDiscCandidates': candidates, 'table4Controls': report['samples'], 'interpretation': 'RP1301 G0 is reproducible as a central Besselian magnitude that combines the k1 penumbral and k2 umbral elements. Squaring it is not a physical single-radius overlap-area reference. Table 4 directly publishes diameter ratio and obscuration controls.'}
    if not result['mixedMagnitudeInsidePrintInterval'] or len(candidates) != 4:
        raise ValueError('RP1301 G0 reconstruction failed')
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    result=build(json.loads((DATA/'global-references.json').read_bytes()),json.loads((DATA/'radius-comparison.json').read_bytes()))
    expected=(json.dumps(result,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
    output=DATA/'rp1301-g0-decomposition.json'
    if args.check:
        if output.read_bytes()!=expected:raise SystemExit('RP1301 G0 decomposition differs')
    else:output.write_bytes(expected)
    print('RP1301 G0 decomposition matches archived elements and physical-disc candidates')

if __name__=='__main__':main()
