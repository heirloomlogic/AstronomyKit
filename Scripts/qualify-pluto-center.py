#!/usr/bin/env python3
"""Qualify complete PLU060 coefficients and the two interior source blends."""
import argparse
from fractions import Fraction as F
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/pluto-data'

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

g = module('pluto_generator', 'generate-pluto-tables.py')
p = module('pluto_assessment', 'assess-pluto-de441.py')
r = module('reference_builder', 'reference-data/build-fixtures.py')
# Frozen TDB geometric dates; Horizons ends a day before the local SPK summary.
HORIZONS_TDB = [-73046.5, -73039.5, -73031.5, -73023.5, -73015.5, -72000., -58400., 0., 4748.499, 4748.5, 4748.501, 58400., 72000., 73014.5, 73022.5, 73030.5, 73038.5, 73044.5, 73045.499]
ARCHIVE = DATA / 'observer-sources/horizons-999-extended-vectors.json'


def query():
    result = r.vector_query('999', '500@10', [2451545 + t for t in HORIZONS_TDB])
    result.update({k: r.quoted(v) for k, v in {'TIME_TYPE': 'TDB', 'TLIST_TYPE': 'JD'}.items()})
    return result


def records(segment):
    start, days, words, count, values = segment
    degrees = (words - 2) // 3
    return [(start + i * days + 2451545, days,
             tuple(tuple(values[i * words + 2 + a * degrees:i * words + 2 + (a + 1) * degrees]) for a in range(3)))
            for i in range(count)]


def record(table, tdb):
    index = min(len(table) - 1, math.floor((tdb + 2451545 - table[0][0]) / table[0][1]))
    result = table[index]
    if index < 0 or not result[0] <= tdb + 2451545 <= result[0] + result[1]:
        raise ValueError('outside source records')
    return result


def add(a, b, scale=F(1)):
    return [(a[i] if i < len(a) else F(0)) + scale * (b[i] if i < len(b) else F(0)) for i in range(max(len(a), len(b)))]


def affine_product(a, offset, scale):
    result = [F(0)] * (len(a) + 1)
    for i, v in enumerate(a):
        result[i] += v * offset
        result[i + 1] += v * scale
    return result


def restricted(coefficients, start, days, left, right):
    """Exact source binary64 polynomial in u in [-1,1] over [left,right]."""
    offset = (F(left) + F(right) - 2 * F(start)) / F(days) - 1
    scale = (F(right) - F(left)) / F(days)
    previous, current = [F(1)], [offset, scale]
    result = [F(coefficients[0])]
    if len(coefficients) > 1:
        result = add(result, current, F(coefficients[1]))
    for c in coefficients[2:]:
        following = add(affine_product(current, 2 * offset, 2 * scale), previous, F(-1))
        result = add(result, following, F(c))
        previous, current = current, following
    return result


def upward(value):
    return math.nextafter(float(value), math.inf)


def polynomial_bounds(axes, days):
    positions = [upward(sum(map(abs, a))) for a in axes]
    rates = [upward(sum(i * abs(v) for i, v in enumerate(a)) * 2 / F(days)) for a in axes]
    return p.shared.norm_upper(positions), p.shared.norm_upper(rates)


def blend_bounds(center, outer, representation, conversion):
    result = []
    for left, right in [(-73047.5, -73015.5), (73014.5, 73046.5)]:
        tables = [(center[9], 1), (center[10], -1), (center[999], 1), (outer[9], -1), (outer[10], 1)]
        knots = {left, right}
        for table, _ in tables:
            first = record(table, left)[0] - 2451545
            step = table[0][1]
            while first < right:
                if first > left:
                    knots.add(first)
                first += step
        intervals = []
        for a, b in zip(sorted(knots), sorted(knots)[1:]):
            axes = [[F(0)] for _ in range(3)]
            center_axes = [[F(0)] for _ in range(3)]
            for table, sign in tables:
                start, days, coefficients = record(table, (a + b) / 2)
                for axis in range(3):
                    polynomial = restricted(coefficients[axis], start - 2451545, days, a, b)
                    axes[axis] = add(axes[axis], polynomial, F(sign))
                    if any(table is center[t] for t in (9, 10, 999)):
                        center_axes[axis] = add(center_axes[axis], polynomial, F(sign))
            position, rate = polynomial_bounds(axes, b - a)
            position = p.up(p.up(position + representation[0]) + conversion[0])
            rate = p.up(p.up(rate + representation[1]) + conversion[1])
            minimum_distance = p.shared.norm_lower([max(0., p.down(float(abs(axis[0]) - sum(map(abs, axis[1:]))))) for axis in center_axes])
            if minimum_distance <= position: raise ValueError("angular enclosure requires positive distance")
            ratio = p.up(position / minimum_distance)
            # asin(r) <= r/(1-r) for 0 <= r < 1; 3440 exceeds arcminutes per radian.
            angular_bound = p.up(p.up(ratio / p.down(1 - ratio)) * 3440)
            intervals.append(dict(startTDB=a, endTDB=b, minimumCenterDistanceKm=minimum_distance, angularErrorBoundArcminutes=angular_bound, modelDifferencePositionBoundKm=position,
                                  modelDifferenceRateBoundKmPerTDBDay=rate,
                                  blendedCenterRateErrorBoundKmPerTDBDay=p.up(rate + p.up(position * (1.875 / 32)))))
        result.append(dict(startTDB=left, endTDB=right, intervals=intervals,
                           positionBoundKm=max(v['modelDifferencePositionBoundKm'] for v in intervals),
                           rateBoundKmPerTDBDay=max(v['blendedCenterRateErrorBoundKmPerTDBDay'] for v in intervals),
                           angularBoundArcminutes=max(v['angularErrorBoundArcminutes'] for v in intervals)))
    return result


def qualify(kernel, cache):
    manifest = json.loads(g.MANIFEST.read_bytes())
    generated, _ = g.kernel_tables(kernel, manifest)
    if generated != json.loads(g.KERNEL_MANIFEST.read_bytes()):
        raise ValueError('generated PLU060 manifest differs')
    segments = g.spk_records(kernel.read_bytes())
    center = {target: records(segments[(0 if target != 999 else 9, target)]) for target in (9, 10, 999)}
    conversion, offset = {}, [0., 0.]
    for target, table in center.items():
        maximum = [0., 0.]
        for _, days, axes in table:
            # Correctly rounded normal division has relative error <= 2^-53; twice that encloses conversion to exact AU coefficients in km.
            errors = [[p.up(abs(c) * 2**-52) for c in axis] for axis in axes]
            if any(c != 0 and abs(c / g.AU_KM) < 2**-1022 for axis in axes for c in axis):
                raise ValueError('normal-division bound does not apply')
            bounds = [p.shared.norm_upper([p.up(math.fsum(a)) for a in errors]),
                      p.shared.norm_upper([p.up(math.fsum(p.up(p.up(k*k*e) * (2/days)) for k,e in enumerate(a))) for a in errors])]
            maximum = list(map(max, maximum, bounds))
            if target == 999:
                bounds = [p.shared.norm_upper([p.up(math.fsum(map(abs, a))) for a in axes]),
                          p.shared.norm_upper([p.up(math.fsum(p.up(p.up(k*k*abs(c))*(2/days)) for k,c in enumerate(a))) for a in axes])]
                offset = list(map(max, offset, bounds))
        conversion[str(target)] = dict(records=len(table), positionKm=maximum[0], rateKmPerTDBDay=maximum[1])
    evidence = json.loads((DATA / 'de441-evidence.json').read_bytes())
    reader = p.shared.CachedReader(cache, evidence['source']['retrievedByteRangesSHA256'])
    outer = {}
    for target in (9, 10):
        layout = [(p.direct.Segment(**v['segment']), p.direct.RecordMetadata(**v['metadata']), v['firstRecord'], v['recordCount']) for v in evidence['source']['segments'][str(target)]]
        outer[target] = p.load_records(reader, layout)
    candidate = evidence['candidates']['cubic-float64']
    representation = [candidate['positionBoundKm'], candidate['analyticRateBoundKmPerTDBDay']]
    blends = blend_bounds(center, outer, representation, [p.up(math.fsum(v[k] for v in conversion.values())) for k in ('positionKm', 'rateKmPerTDBDay')])
    epochs = sorted(set(HORIZONS_TDB + [-73047.499, -73047.25, -73015.501, -73015.499, 73014.499, 73014.501, 73046.25, 73046.499] + [-73047.5 + i * 146094 / 256 for i in range(1,256)]))
    rows = []
    for tdb in epochs:
        states = [p.record_at(center[target], tdb + 2451545) for target in (9,10,999)]
        rows.append(dict(tdb=tdb, positionKm=[states[0][0][a]-states[1][0][a]+states[2][0][a] for a in range(3)],
                         velocityKmPerTDBDay=[states[0][1][a]-states[1][1][a]+states[2][1][a] for a in range(3)]))
    raw = ARCHIVE.read_bytes()
    references = p.references(raw,999,'plu060_merged')
    if [v[0] for v in references] != [v + 2451545 for v in HORIZONS_TDB]:
        raise ValueError('geometric reference epochs differ')
    horizons = [dict(tdb=jd-2451545, positionKm=[x*g.AU_KM for x in position], velocityKmPerTDBDay=[x*g.AU_KM for x in velocity]) for jd,position,velocity in references]
    paths = [Path(__file__), ROOT/'Scripts/test_qualify_pluto_center.py', g.KERNEL_MANIFEST, DATA/'de441-evidence.json', ROOT/'Scripts/generate-pluto-tables.py', ROOT/'Scripts/assess-pluto-de441.py', ROOT/'Scripts/qualify-moon-de441.py', ROOT/'Scripts/assess-moon-de441.py', ROOT/'Scripts/reference-data/build-fixtures.py']
    result = dict(schemaVersion=1, sourceSHA256={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},
                  sourceStartTDB=-73047.5, sourceEndTDB=73046.5, sourceKernelSHA256=generated['source']['sha256'],
                  geometricReference=dict(path=str(ARCHIVE.relative_to(ROOT)),sha256=hashlib.sha256(raw).hexdigest(),query=query(),url=r.horizons_url(query())),
                  coefficientConversionBounds=conversion, centerOffsetPositionBoundKm=offset[0], centerOffsetRateBoundKmPerTDBDay=offset[1],
                  blends=blends, derivation='Exact rational Chebyshev restriction to the union of all source record boundaries; coefficient absolute sums bound position and derivative on each complete interval. Add the full DE441 representation and PLU060 coefficient-conversion bounds. The center distance lower bound uses each axis constant term minus its remaining absolute coefficient sum; For r = position error / distance lower bound, 3440*r/(1-r) encloses direction error in arcminutes without a transcendental-function rounding assumption. For H=(1-w)D+wC, H-C=(1-w)(D-C), with derivative bounded by rate difference plus max|dw/dTDB| times position difference; max|dw/dTDB|=1.875/32. Coefficient conversion bounds separately enclose binary64 km-to-AU division over every record.',
                  limitations=['Bounds concern the source polynomials and representation, not independent ephemeris physical accuracy or all floating-point evaluation operations.', 'Derivative bounds are per TDB day; native converts to per TT day and tests that conversion.', 'Horizons geometric and observer target 999 queries end a day before the verified local SPK summary; direct source fixtures cover that final day.', 'The 32-day interior tapers have partial physical-center weight; outside source coverage the model remains target 9.'],
                  directSourceRows=rows,horizonsRows=horizons)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel',type=Path)
    parser.add_argument('--cache',type=Path)
    parser.add_argument('--capture',action='store_true')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.check and args.kernel is None:
        saved = json.loads((DATA/'plu060-qualification.json').read_bytes())
        for name, digest in saved['sourceSHA256'].items():
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
                raise SystemExit(f'PLU060 qualification source binding differs: {name}')
        reference = saved['geometricReference']
        if hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() != reference['sha256'] or reference['query'] != query():
            raise SystemExit('PLU060 geometric reference identity differs')
        expected = p.references(ARCHIVE.read_bytes(), 999, 'plu060_merged')
        if [v[0] for v in expected] != [v+2451545 for v in HORIZONS_TDB]:
            raise SystemExit('PLU060 geometric reference selection differs')
        for row, (jd, position, velocity) in zip(saved['horizonsRows'], expected):
            if row != dict(tdb=jd-2451545, positionKm=[x*g.AU_KM for x in position], velocityKmPerTDBDay=[x*g.AU_KM for x in velocity]):
                raise SystemExit('PLU060 parsed geometric references differ')
        if len(saved['horizonsRows']) != len(expected):
            raise SystemExit('PLU060 geometric reference count differs')
        for blend in saved['blends']:
            if not 0 <= blend['angularBoundArcminutes'] < 1:
                raise SystemExit('PLU060 blend direction bound misses acceptance')
        print('PLU060 qualification source bindings and geometric archive verified; use --kernel and --cache for full enclosure replay')
        return
    if args.kernel is None or args.cache is None:
        parser.error('--kernel and --cache are required for full qualification')
    if args.capture:
        raw=r.download(r.horizons_url(query()))
        p.references(raw,999,'plu060_merged')
        ARCHIVE.write_bytes(raw)
    result=qualify(args.kernel,args.cache)
    path=DATA/'plu060-qualification.json'
    encoded=(json.dumps(result,indent=2,sort_keys=True)+'\n').encode()
    if args.check:
        if path.read_bytes()!=encoded: raise SystemExit('PLU060 qualification differs')
    else: path.write_bytes(encoded)
    print(json.dumps({k:result[k] for k in ['centerOffsetPositionBoundKm','centerOffsetRateBoundKmPerTDBDay','coefficientConversionBounds']}))
    print('Blend bounds:',[(v['positionBoundKm'],v['rateBoundKmPerTDBDay']) for v in result['blends']])

if __name__=='__main__':
    main()
