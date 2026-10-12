#!/usr/bin/env python3
"""Reproduce rational regularity and derivative bounds for the long-term model."""
import argparse
from fractions import Fraction as Q
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Scripts/solar-numerics'))
import precession_bounds as bounds
from numerics import source_hashes, record

OUTPUT = ROOT / 'Scripts/orientation-data/long-term/qualification.json'
PATHS = bounds.PATHS + [
    'Scripts/qualify-long-term-precession.py', 'Scripts/solar-numerics/intervals.py',
    'Scripts/solar-numerics/numerics.py',
]


def derive():
    enclosures = {}
    for name, limit in [('acceptedTT', Q(40)), ('altitudeCertificate', Q('1.02'))]:
        print(f'Enclosing {name}: +/-{limit} Julian centuries', flush=True)
        result = bounds.enclose(limit)
        enclosures[name] = {key: record(value, 'lower' if key.endswith('Lower') else 'upper')
                            for key,value in result.items()}
    return {'kind': 'vondrak-2011-model-regularity-and-rates', 'schemaVersion': 1,
            'sourceSHA256': source_hashes(ROOT, PATHS),
            'model': 'ERFA v2.0.1 unbiased ltp poles, Vondrak 2011 with 2012 corrigendum',
            'units': 'radicands and cross norms dimensionless; rates degrees per TT day',
            'claim': 'Exact-decimal coefficient model, outward rational intervals, complete interval partitions',
            'excludes': ['physical-model error', 'floating-point evaluation error', 'nutation accuracy', 'sidereal-model accuracy'],
            'enclosures': enclosures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = derive()
    if args.check:
        if json.loads(OUTPUT.read_text()) != result:
            raise SystemExit('Long-term precession qualification is stale')
        print('Long-term precession interval qualification reproduced.')
    else:
        OUTPUT.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
