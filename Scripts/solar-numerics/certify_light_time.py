#!/usr/bin/env python3
"""Certify finite public scalar candidates near exact-model light-time discontinuities."""
import argparse
import json
import math
from pathlib import Path
from fractions import Fraction as Q
import re

from intervals import Interval as I, DeltaT, Earth, year_start, equatorial_matrix
from numerics import ROOT, BINDINGS, source_hashes, check_hashes

C = Q(299792458)*86400/149597870700
TAU = Q('1e-9')
JUMPS = [1900, 1920, 1941, 1961, 1986, 2005, 2050]


def constants():
    artifact = json.loads((ROOT/'Scripts/solar-numerics/derived-earth.json').read_text())
    check_hashes(ROOT, artifact['sourceSHA256'])
    terms = {key: Q(value['rational']) for key, value in artifact['terms'].items()}
    matrix = equatorial_matrix()
    gram = [[sum(matrix[k][i]*matrix[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    norm = Q('1.000001')
    if max(sum(abs(value) for value in row) for row in gram) > norm**2:
        raise ValueError('Fixed EQJ matrix exceeds its norm enclosure')
    v, a, d, p, t = Q('.019'), Q('1.001'), Q('2.5e-6'), Q('1e-9'), Q('.006')
    if terms['speedAUPerTTDay']*norm > v or terms['joinSumAU']*norm > p or terms['radiusMaximumAU']*norm/C > t:
        raise ValueError('Earth model exceeds convergence constants')
    source = (ROOT/'Sources/AstronomyKit/Engine/Foundation/EngineSearch.swift').read_text()
    if 'static let iterationLimit = 10' not in source or 'for _ in 0..<iterationLimit' not in source or 'abs(next.tt - backdated.tt) < 1.0e-9' not in source:
        raise ValueError('Light-time iteration count or stop expression changed')
    constants_source = (ROOT/'Sources/AstronomyKit/Engine/Foundation/EngineConstants.swift').read_text()
    literal = re.search(r'speedOfLightAUPerDay = ([0-9_.]+)', constants_source)[1].replace('_', '')
    if float(literal) != float(C):
        raise ValueError('Native light-speed constant no longer rounds the SI/IAU value')
    delta = DeltaT()
    slope = max(delta.derivative_at_year(I(year, year+1), year).abs_upper()/(year_start(year+1)-year_start(year))
                for year in range(1898, 2102))
    jumps = [(delta.at_year(I(year), year)-delta.at_year(I(year), year-1)).abs_upper()/86400 for year in JUMPS]
    if 1+slope/86400 > a or sum(jumps) > d:
        raise ValueError('DeltaT model exceeds convergence constants')
    k, increment = a*v/C, (v*d+p)/C
    b10 = k**9*t + increment*(1-k**9)/(1-k)
    width = (1+k)*b10 + p/C
    if a*b10 >= TAU or b10 >= min(year_start(b)-year_start(a) for a,b in zip(JUMPS,JUMPS[1:])):
        raise ValueError('Exceptional-strip localization precondition failed')
    return {'a': a, 'V': v, 'D': d, 'P': p, 'T': t, 'k': k, 'B10': b10, 'halfWidth': width,
            'deltaTSlopeSecondsPerDay': slope, 'deltaTJumpSumDays': sum(jumps)}


def float_candidates(interval):
    value = float(interval.lo)
    while Q(value) < interval.lo:
        value = math.nextafter(value, math.inf)
    while Q(math.nextafter(value, -math.inf)) >= interval.lo:
        value = math.nextafter(value, -math.inf)
    result = []
    while Q(value) <= interval.hi:
        result.append(value)
        value = math.nextafter(value, math.inf)
        if len(result) > 1_000_000:
            raise ValueError('Exceptional scalar strip unexpectedly large')
    return result


def segments():
    text = (ROOT/'Sources/AstronomyKit/UTCOffsetTable.swift').read_text()
    return [tuple(Q(value.strip()) for value in row) for row in
            re.findall(r'Segment\(start: ([^,]+), offset: ([^,]+), rate: ([^)]+)\)', text)]


def inverse(tt, around, delta, model):
    domain = I(around-Q('.001'), around+Q('.001'))
    if delta.forward(I(domain.lo), model).hi >= tt.lo or delta.forward(I(domain.hi), model).lo <= tt.hi:
        raise ValueError('Inverse root is not bracketed')
    for _ in range(16):
        next_value = tt-delta.seconds(domain, model)/86400
        domain = I(max(domain.lo, next_value.lo), min(domain.hi, next_value.hi))
    return domain


def pairs(scalar, scale, center, delta, model):
    if scale == 'ut':
        return scalar, delta.forward(scalar, model)
    if scale == 'tt':
        return inverse(scalar, center, delta, model), scalar
    civil = scalar/86400+Q('365.5')
    table = segments()
    selected = [row for row in table if row[0] <= civil.lo]
    if not selected:
        if civil.hi >= table[0][0]:
            raise ValueError('Civil interval crosses table start')
        return civil, delta.forward(civil, model)
    start, offset, rate = selected[-1]
    if any(civil.lo < row[0] <= civil.hi for row in table):
        raise ValueError('Civil interval crosses an offset boundary')
    tt = civil+(offset+rate*(civil-start))/86400
    return inverse(tt, center, delta, model), tt


def successful_return(ut, tt, model, delta, earth):
    trace = []
    for iteration in range(1, 11):
        next_ut = ut-earth.radius(tt)/C
        next_tt = delta.forward(next_ut, model)
        residual = (next_tt-tt).abs_upper()
        trace.append(residual)
        if residual < TAU:
            return iteration, trace
        tt = next_tt
    return None, trace


def scalar_domain(strip, scale, delta, model):
    if scale == 'ut':
        return strip
    tt = delta.forward(strip, model)
    if scale == 'tt':
        return tt
    table = segments()
    if strip.hi < table[0][0]:
        return (strip-Q('365.5'))*86400
    possible = []
    for index, (start, offset, rate) in enumerate(table):
        civil = (tt-offset/86400+rate*start/86400)/(1+rate/86400)
        end = table[index+1][0] if index+1 < len(table) else Q(1000000)
        if civil.lo >= start and civil.hi < end:
            possible.append(civil)
    if len(possible) != 1:
        raise ValueError('Civil scalar strip is not within one offset segment')
    return (possible[0]-Q('365.5'))*86400


def certify():
    bounds = constants()
    delta, earth = DeltaT(), Earth()
    records, excluded = [], []
    for model in ['espenakMeeus', 'jplHorizons']:
        for year in JUMPS:
            if model == 'jplHorizons' and year > 2017:
                continue
            b = year_start(year)
            for side in [-1, 0]:
                x = I(b)+delta.at_year(I(year), year+side)/86400
                if x.hi+bounds['a']*bounds['B10'] < earth.start or x.lo-bounds['a']*bounds['B10'] >= earth.stop:
                    excluded.append({'model': model, 'year': year, 'side': side, 'reason': 'one-sided emission outside polynomial domain'})
                    continue
                center = I(b)+earth.radius(x)/C
                strip = center+I(-bounds['halfWidth'], bounds['halfWidth'])
                # Arrival roots are on one smooth branch, separated from every model jump.
                if any(strip.lo-Q('.001') <= year_start(j) <= strip.hi+Q('.001') for j in JUMPS):
                    raise ValueError('Arrival inverse bracket intersects a DeltaT jump')
                midpoint = (center.lo+center.hi)/2
                for scale in ['ut', 'tt', 'date']:
                    candidates = float_candidates(scalar_domain(strip, scale, delta, model))
                    batches = []
                    def visit(values):
                        if not values:
                            return
                        initial_ut, initial_tt = pairs(I(Q(values[0]), Q(values[-1])), scale, midpoint, delta, model)
                        iteration, trace = successful_return(initial_ut, initial_tt, model, delta, earth)
                        if iteration is not None:
                            batches.append({'first': values[0].hex(), 'last': values[-1].hex(), 'count': len(values),
                                            'iteration': iteration, 'residualUpper': str(trace[-1])})
                        elif len(values) == 1:
                            raise ValueError(f'Unresolved public input: {model} {year} {scale} {values[0].hex()}, residuals={list(map(str,trace))}')
                        else:
                            middle = len(values)//2
                            visit(values[:middle])
                            visit(values[middle:])
                    visit(candidates)
                    records.append({'model': model, 'year': year, 'side': side, 'scale': scale,
                                    'strip': [str(strip.lo), str(strip.hi)], 'count': len(candidates), 'batches': batches})
                    print(f'{model} {year} {side} {scale}: {len(candidates)} candidates, {len(batches)} interval batches', flush=True)
    paths = sorted(set(BINDINGS + [
        'Scripts/solar-numerics/derived-earth.json', 'Scripts/solar-numerics/intervals.py',
        'Scripts/solar-numerics/certify_light_time.py',
        'Sources/AstronomyKit/Engine/Orientation/EngineRotations.swift', 'Sources/AstronomyKit/Time.swift',
    ]))
    return {'kind': 'exact-model-finite-light-time-return', 'schemaVersion': 1,
            'domain': 'Ideal model pairs whose entire light-time path is inside Earth polynomial coverage; named models; binary64 UT, TT or Foundation Date scalar',
            'dependency': 'The derived Earth artifact must also pass numerics.py --check',
            'sourceSHA256': source_hashes(ROOT, paths),
            'constants': {key: str(value) for key,value in bounds.items()}, 'records': records, 'excluded': excluded}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'Scripts/solar-numerics/derived-light-convergence.json')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    actual = json.dumps(certify(), indent=2, sort_keys=True)+'\n'
    if args.check:
        if args.output.read_text() != actual:
            raise SystemExit('Finite convergence certificate differs from reconstructed canonical coverage')
        print('Finite light-time convergence certificate verified')
    else:
        args.output.write_text(actual)
        print(args.output)


if __name__ == '__main__':
    main()
