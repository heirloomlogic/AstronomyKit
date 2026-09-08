#!/usr/bin/env python3
"""Reproducible, isolated polynomial and frequency-reuse experiments.

No shipping source is edited. Generated artifacts go under --output.
"""
import argparse
import ctypes as C
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REVISION = '8a1680535d7f4afc523dbe9e9041435dca9ddc10'
BODIES = ['Mercury', 'Venus', 'Earth', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune']
START, STOP = -36524.5, 36889.5
DEGREES, WIDTHS = [12, 16, 20, 24], [2, 4, 8, 16, 32]
POSITION_LIMIT, VELOCITY_LIMIT = 2.5e-13, 2.5e-13
SUFFIX = '.dylib' if sys.platform == 'darwin' else '.so'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+'\n')


def compile_library(output, name, source, extra=(), optimization='-O2'):
    croot = output/'frozen/Sources/CLibAstronomy'
    library = output/(name+SUFFIX)
    command = ['clang', optimization, '-dynamiclib' if sys.platform == 'darwin' else '-shared',
               '-fPIC', '-pthread', '-I', str(output), '-I', str(croot),
               '-I', str(croot/'include'), '-I', str(croot/'generated'), str(source),
               *map(str, extra), *map(str, sorted((croot/'detmath').glob('*.c'))),
               '-lm', '-o', str(library)]
    subprocess.run(command, check=True)
    save(output/(name+'-build.json'), {'command': command, 'sourceSHA256': sha(source),
                                     'binarySHA256': sha(library)})
    return library


def prepare(output, fit='integrated'):
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT/'Scripts/generate-models.py'), '--check'], check=True)
    source = subprocess.check_output(['git', 'show', f'{REVISION}:Sources/CLibAstronomy/astronomy.c'],
                                     cwd=ROOT)
    # Recover every dependency of the original generator into the build directory.
    # Production native math must not silently change the archived fit definition.
    inputs={}
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',REVISION,
                                   'Sources/CLibAstronomy'],cwd=ROOT,text=True).splitlines()
    for name in paths:
        destination=output/'frozen'/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(subprocess.check_output(['git','show',f'{REVISION}:{name}'],cwd=ROOT))
        inputs[name]=sha(destination)
    save(output/'reference-inputs.json',{'revision':REVISION,'inputs':inputs})
    (output/'reference.c').write_bytes(source)
    compile_library(output, 'reference', output/'reference.c', [ROOT/'Scripts/accuracy/sample.c'])
    path = compile_library(output, 'fit', HERE/'fit.c')
    lib = C.CDLL(str(path))
    if fit=='position':
        lib.ak_poly_fit=lib.ak_poly_fit_position
    pointer = C.POINTER(C.c_double)
    lib.ak_poly_fit.argtypes = [C.c_int, C.c_double, C.c_double, C.c_int, pointer]
    lib.ak_poly_fit.restype = None
    lib.ak_poly_check.argtypes = [C.c_int, C.c_double, C.c_double, C.c_int, pointer, pointer]
    lib.ak_poly_check.restype = None
    lib.ak_poly_bench.argtypes = [C.c_int]
    lib.ak_poly_bench.restype = C.c_double
    lib.fit_method=fit
    return lib


def fit_check(lib, body, start, width, degree):
    coeff = (C.c_double*(3*(degree+1)))()
    errors = (C.c_double*3)()
    lib.ak_poly_fit(body, start, width, degree, coeff)
    lib.ak_poly_check(body, start, width, degree, coeff, errors)
    if not all(math.isfinite(x) for x in (*coeff, *errors)):
        raise ValueError('Non-finite coefficient or validation result')
    return coeff, list(errors)


def screen(output, lib):
    report = {'revision': REVISION, 'fitMethod': lib.fit_method, 'protocolSHA256': sha(HERE/'PROTOCOL.md'),
              'fitSourceSHA256': sha(HERE/'fit.c'), 'configurations': []}
    timings = {d: statistics.median(lib.ak_poly_bench(d) for _ in range(5)) for d in DEGREES}
    report['evaluationSeconds'] = timings
    for body, name in enumerate(BODIES):
        for width in WIDTHS:
            count = math.ceil((STOP-START)/width)
            selected = sorted({round(i*(count-1)/11) for i in range(12)})
            for degree in DEGREES:
                maxima = [0.0, 0.0]
                for index in selected:
                    start = START+index*width
                    _, errors = fit_check(lib, body, start, width, degree)
                    maxima = [max(a,b) for a,b in zip(maxima, errors)]
                row = {'body': name, 'width': width, 'degree': degree,
                       'segments': count, 'bytes': count*3*(degree+1)*8,
                       'maxPositionAU': maxima[0], 'maxVelocityAUPerDay': maxima[1],
                       'pass': maxima[0] <= POSITION_LIMIT and maxima[1] <= VELOCITY_LIMIT}
                report['configurations'].append(row)
                save(output/'screen.json', report)
        passed = [r for r in report['configurations'] if r['body']==name and r['pass']]
        print(name, 'passing configurations:', len(passed), flush=True)
    # Solve the small multiple-choice knapsack by enumerating the Pareto frontier.
    # Cost is sum of equal-weight per-body evaluation times; <=5% timing differences
    # are tied at the degree level, then bytes select the smaller artifact.
    fastest = min(timings.values())
    costs = {d: round(timings[d]/fastest/0.05)*0.05 for d in DEGREES}
    frontier = [(0, 0.0, [])]
    for name in BODIES:
        choices = [r for r in report['configurations'] if r['body']==name and r['pass']]
        if not choices:
            raise RuntimeError(f'No qualifying configuration for {name}; see screen.json')
        expanded = [(size+r['bytes'], cost+costs[r['degree']], rows+[r])
                    for size,cost,rows in frontier for r in choices if size+r['bytes'] <= 32*1024*1024]
        frontier = []
        best = math.inf
        for size,cost,rows in sorted(expanded, key=lambda x:(x[0],x[1])):
            if cost < best:
                frontier.append((size,cost,rows)); best=cost
    if not frontier:
        raise RuntimeError('No qualifying configuration under 32 MiB')
    size,cost,selection = min(frontier, key=lambda x:(x[1],x[0]))
    save(output/'selection.json', {'bytes': size, 'configurations': selection,
                                  'screenSHA256': sha(output/'screen.json')})
    print('Selected', size, 'bytes:', [(r['body'],r['width'],r['degree']) for r in selection], flush=True)


def generate(output, lib):
    import array
    selected = json.loads((output/'selection.json').read_text())
    report = {'protocolSHA256': sha(HERE/'PROTOCOL.md'), 'revision': REVISION,
              'fitMethod': lib.fit_method, 'bodies': []}
    for body, row in enumerate(selected['configurations']):
        name, width, degree = row['body'], row['width'], row['degree']
        if name != BODIES[body]:
            raise ValueError('Selection body order changed')
        coefficients = array.array('d')
        valid = bytearray()
        maxima = [0.0, 0.0]
        started = time.monotonic()
        for index in range(row['segments']):
            start = START+index*width
            coeff, errors = fit_check(lib, body, start, width, degree)
            coefficients.extend(coeff)
            valid.append(errors[0]<=POSITION_LIMIT and errors[1]<=VELOCITY_LIMIT)
            maxima = [max(a,b) for a,b in zip(maxima, errors)]
            if index%1000 == 0:
                print(name, index, '/', row['segments'], 'fallbacks', valid.count(0), flush=True)
        if sys.byteorder != 'little':
            coefficients.byteswap()
        path = output/(name+'.bin')
        path.write_bytes(coefficients.tobytes())
        (output/(name+'.valid')).write_bytes(valid)
        result = {**row, 'fallbacks': valid.count(0), 'maxPositionAU': maxima[0],
                  'maxVelocityAUPerDay': maxima[1], 'samples': len(valid)*51,
                  'coefficientSHA256': sha(path), 'validitySHA256': sha(output/(name+'.valid')),
                  'seconds': time.monotonic()-started}
        report['bodies'].append(result)
        save(output/'generation.json', report)
        print(name, result, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'screen', 'generate'])
    parser.add_argument('--output', type=Path, default=ROOT/'.build/polynomial-regeneration')
    parser.add_argument('--fit', choices=['integrated', 'position'], default='integrated')
    args = parser.parse_args()
    output = args.output.resolve()
    lib = prepare(output, args.fit)
    if args.command!='prepare':
        (screen if args.command=='screen' else generate)(output, lib)


if __name__ == '__main__':
    main()
