#!/usr/bin/env python3
"""Compare optimized native libraries without changing any accuracy references."""

import argparse
import ctypes
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Scripts/accuracy'))
from measure import Model


class Time(ctypes.Structure):
    _fields_ = [(name, ctypes.c_double) for name in ('ut', 'tt', 'psi', 'eps', 'st')]


class Vector(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int), *[(name, ctypes.c_double) for name in ('x', 'y', 'z')],
                ('t', Time)]


class State(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int),
                *[(name, ctypes.c_double) for name in ('x', 'y', 'z', 'vx', 'vy', 'vz')], ('t', Time)]


class Distance(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int), ('value', ctypes.c_double)]


def equal(actual, expected, label):
    if not all(math.isfinite(x) for x in (*actual, *expected)):
        raise ValueError(f'Nonfinite numerical result: {label}')
    if struct.pack(f'{len(actual)}d', *actual) != struct.pack(f'{len(expected)}d', *expected):
        raise ValueError(f'Changed result: {label}: {actual} != {expected}')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    reference, candidate = (Model(p.resolve()) for p in (args.reference, args.candidate))
    frozen = ROOT / 'Scripts/accuracy/results/production/range-references.json.gz'
    positions = json.loads(gzip.decompress(frozen.read_bytes()))['positions']
    # The archived population uses TT. ak_sample_tt follows that same convention.
    for model in (reference, candidate):
        model.sample = model.library.ak_sample_tt
        model.sample.argtypes = [ctypes.c_int, ctypes.c_double, ctypes.c_int,
                                 ctypes.POINTER(ctypes.c_double)]
        model.sample.restype = ctypes.c_int
    for body, tt, *_ in positions:
        expected = reference.position(body, tt)
        equal(candidate.position(body, tt), expected, (body, tt, 'monthly'))
        equal(candidate.position(body, tt), expected, (body, tt, 'repeat'))

    checks = 0
    for name, result_type, fields in (
        ('Astronomy_HelioDistance', Distance, ('value',)),
        ('Astronomy_HelioVector', Vector, ('x', 'y', 'z')),
        ('Astronomy_HelioState', State, ('x', 'y', 'z', 'vx', 'vy', 'vz')),
        ('Astronomy_BaryState', State, ('x', 'y', 'z', 'vx', 'vy', 'vz')),
    ):
        functions = [getattr(m.library, name) for m in (reference, candidate)]
        for function in functions:
            function.argtypes = [ctypes.c_int, Time]
            function.restype = result_type
        for body in range(8):
            for tt in (-730500.0, -36525.0, -0.0, 0.0, 9000.125, 36525.0, 730500.0):
                for ut in (tt, tt + 0.25):
                    at = Time(ut, tt, 0.125, -0.25, 3.0)
                    expected, actual = (function(body, at) for function in functions)
                    if actual.status != 0 or expected.status != 0:
                        raise ValueError(f'Calculation failed: {name} {body} {tt}')
                    equal([getattr(actual, f) for f in fields],
                          [getattr(expected, f) for f in fields], (name, body, tt))
                    if hasattr(actual, 't'):
                        equal([getattr(actual.t, f) for f, _ in Time._fields_],
                              [getattr(at, f) for f, _ in Time._fields_], (name, 'time metadata'))
                    checks += 1
    report = {'passed': True, 'monthlyPositions': len(positions), 'monthlyReplayChecks': len(positions),
              'stateVectorDistanceChecks': checks, 'referenceSHA256': sha(args.reference),
              'candidateSHA256': sha(args.candidate), 'frozenPopulationSHA256': sha(frozen),
              'scriptSHA256': sha(Path(__file__)),
              'scope': 'Bitwise equivalence to the restored model; independent accuracy gates remain separate.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
