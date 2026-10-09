#!/usr/bin/env python3
"""Measure full-range Pluto barycenter representations and the available center offset."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import struct
import time

SPEC = importlib.util.spec_from_file_location('moon_qualification', Path(__file__).with_name('qualify-moon-de441.py'))
shared = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shared)
direct = shared.direct
ROOT = direct.ROOT
OUTPUT = ROOT / 'Scripts/pluto-data/de441-evidence.json'
PLU060_SHA = 'dfbb102491a26ed41ae08ca3f8963f22f0219df1d8f265ab87b9ad825a826fc6'
PLU060_URL = 'https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.bsp'
TT_LIMIT = 766525.
CANDIDATES = ('direct-float64', 'direct-float32', 'cubic-float64', 'cubic-float32')
up, down = shared.up, shared.down
norm = direct.norm


def subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def add_interval(a, b):
    return down(a[0] + b[0]), up(a[1] + b[1])


def sub_interval(a, b):
    return down(a[0] - b[1]), up(a[1] - b[0])


def scale_interval(a, positive):
    return down(a[0] * positive), up(a[1] * positive)


def cubic(left, right, days):
    result = []
    for axis in range(3):
        pl, pr = left[axis], right[axis]
        dl, dr = left[axis + 3] * days / 2, right[axis + 3] * days / 2
        even, odd = (pr + pl) / 2, (pr - pl) / 2
        c2, c3 = (dr - dl) / 8, (dr + dl - 2 * odd) / 16
        result.append((even - c2, odd - c3, c2, c3))
    return result


def cubic_intervals(left, right, days):
    """Enclose exact real coefficients defined by encoded shared nodes."""
    result = []
    for axis in range(3):
        pl, pr = (left[axis],) * 2, (right[axis],) * 2
        dl = scale_interval((left[axis + 3],) * 2, days / 2)
        dr = scale_interval((right[axis + 3],) * 2, days / 2)
        even = scale_interval(add_interval(pr, pl), .5)
        odd = scale_interval(sub_interval(pr, pl), .5)
        c2 = scale_interval(sub_interval(dr, dl), .125)
        c3 = scale_interval(sub_interval(add_interval(dr, dl), scale_interval(odd, 2)), .0625)
        result.append((sub_interval(even, c2), sub_interval(odd, c3), c2, c3))
    return result


def evaluate(axes, x, days):
    state = [direct.chebyshev_value_and_rate(axis, x, days) for axis in axes]
    return [v[0] for v in state], [v[1] for v in state]


def nodes(axes, days):
    return [list(p) + list(v) for p, v in (evaluate(axes, x, days) for x in (-1., 1.))]


def error_bounds(source, intervals, days):
    position, rate = [], []
    for original, decoded in zip(source, intervals):
        errors = []
        for index, coefficient in enumerate(original):
            interval = decoded[index] if index < len(decoded) else (0., 0.)
            errors.append(up(max(abs(coefficient - interval[0]), abs(coefficient - interval[1]))))
        position.append(up(math.fsum(errors)))
        rate.append(up(math.fsum(up(up(error * (degree * degree)) * (2 / days)) for degree, error in enumerate(errors))))
    return shared.norm_upper(position), shared.norm_upper(rate)


def windows(segments, target, start, end, center=0):
    """Require contiguous source coverage; later SPK segments own shared endpoints."""
    selected = sorted(((s, m) for s, m in segments if (s.target, s.center) == (target, center)), key=lambda pair: pair[0].start_seconds_tdb)
    result, cursor = [], start
    for segment, metadata in selected:
        low = direct.J2000 + segment.start_seconds_tdb / 86400
        high = direct.J2000 + segment.end_seconds_tdb / 86400
        if high <= cursor or low >= end:
            continue
        if low > cursor:
            raise ValueError('source coverage gap')
        stop = min(high, end)
        first, count = direct.record_window(metadata, cursor, stop)
        result.append((segment, metadata, first, count))
        cursor = stop
    if cursor != end:
        raise ValueError('source coverage incomplete')
    return result


def load_records(reader, layout):
    jobs = []
    for segment, metadata, first, count in layout:
        for offset in range(0, count, 8192):
            index, size = first + offset, min(8192, count - offset)
            jobs.append((segment, metadata, index, size))
    def read(job):
        s, m, first, count = job
        raw = reader.read((s.first_word - 1 + first * m.record_words) * 8, count * m.record_words * 8)
        return job, raw
    result = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for (segment, metadata, first, count), raw in pool.map(read, jobs):
            degree_count = (metadata.record_words - 2) // 3
            if degree_count * 3 + 2 != metadata.record_words:
                raise ValueError('invalid coefficient count')
            for offset in range(count):
                values = struct.unpack_from(f'<{metadata.record_words}d', raw, offset * metadata.record_words * 8)
                start = metadata.start_jd_tdb + (first + offset) * metadata.record_days
                if values[:2] != ((start - direct.J2000 + metadata.record_days / 2) * 86400, metadata.record_days * 43200):
                    raise ValueError('record midpoint/radius mismatch')
                if not all(math.isfinite(v) for v in values):
                    raise ValueError('nonfinite coefficient')
                if result and start != result[-1][0] + result[-1][1]:
                    raise ValueError('record grid is not contiguous')
                axes = tuple(tuple(values[2 + a * degree_count:2 + (a + 1) * degree_count]) for a in range(3))
                result.append((start, metadata.record_days, axes))
    return result


def references(data, target, solution):
    result = json.loads(data)['result']
    required = (f'({target})', f'{{source: {solution}}}', 'Center body name: Sun (10)', 'Output units    : AU-D', 'JDTDB', 'Output type     : GEOMETRIC cartesian states', 'Reference frame : ICRF')
    target_line = next((line for line in result.splitlines() if line.startswith('Target body name:')), '')
    if f'({target})' not in target_line or f'{{source: {solution}}}' not in target_line or not all(text in result for text in required):
        raise ValueError('unexpected Horizons target, center, source, frame, units, or time')
    body = result.split('$$SOE')[1].split('$$EOE')[0]
    rows = []
    for line in body.strip().splitlines():
        fields = line.split(',')
        if len(fields) < 8:
            raise ValueError('malformed Horizons vector')
        numbers = [float(fields[0]), *map(float, fields[2:8])]
        if not all(math.isfinite(n) for n in numbers):
            raise ValueError('nonfinite Horizons vector')
        rows.append((numbers[0], numbers[1:4], numbers[4:7]))
    if not rows:
        raise ValueError('no Horizons vectors')
    return rows


def record_at(records, jd):
    index = min(len(records) - 1, math.floor((jd - records[0][0]) / records[0][1]))
    if index < 0 or not records[index][0] <= jd <= records[index][0] + records[index][1]:
        raise ValueError('evaluation outside table coverage')
    start, days, axes = records[index]
    return evaluate(axes, 2 * (jd - start) / days - 1, days)


def angular_arcseconds(a, b):
    cross = [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
    return math.atan2(norm(cross), math.fsum(x*y for x, y in zip(a, b))) * (180 / math.pi) * 3600


def scan(records, name, output):
    fmt = 'd' if name.endswith('64') else 'f'
    encoded = bytearray()
    decoded, maxima, worst = [], [0., 0.], [None, None]
    previous_right = None
    minimum_radius, maximum_radius = math.inf, 0.
    source_seams, decoded_seams = [0., 0.], [0., 0.]
    last_source_right = last_decoded_right = None
    for index, (start, days, axes) in enumerate(records):
        left, right = nodes(axes, days)
        if last_source_right is not None:
            for k in (0, 1):
                source_seams[k] = max(source_seams[k], norm(subtract(left[3*k:3*k+3], last_source_right[3*k:3*k+3])))
        last_source_right = right
        if name.startswith('cubic'):
            if previous_right is None:
                raw = struct.pack(f'<6{fmt}', *left)
                encoded.extend(raw)
                previous_right = struct.unpack(f'<6{fmt}', raw)
            raw = struct.pack(f'<6{fmt}', *right)
            encoded.extend(raw)
            right = struct.unpack(f'<6{fmt}', raw)
            intervals = cubic_intervals(previous_right, right, days)
            compact = cubic(previous_right, right, days)
            previous_right = right
        else:
            flat = [v for axis in axes for v in axis]
            raw = struct.pack(f'<{len(flat)}{fmt}', *flat)
            encoded.extend(raw)
            values = struct.unpack(f'<{len(flat)}{fmt}', raw)
            n = len(axes[0])
            compact = [values[a*n:(a+1)*n] for a in range(3)]
            intervals = [[(v, v) for v in axis] for axis in compact]
        decoded_left, decoded_right = nodes(compact, days)
        if last_decoded_right is not None:
            for k in (0, 1):
                decoded_seams[k] = max(decoded_seams[k], norm(subtract(decoded_left[3*k:3*k+3], last_decoded_right[3*k:3*k+3])))
        last_decoded_right = decoded_right
        bounds = error_bounds(axes, intervals, days)
        for k in (0, 1):
            if bounds[k] > maxima[k]:
                maxima[k], worst[k] = bounds[k], index
        center = [abs(axis[0]) for axis in axes]
        tail = [up(math.fsum(abs(v) for v in axis[1:])) for axis in axes]
        minimum_radius = min(minimum_radius, down(shared.norm_lower(center) - shared.norm_upper(tail)))
        maximum_radius = max(maximum_radius, up(shared.norm_upper(center) + shared.norm_upper(tail)))
        decoded.append((start, days, compact))
    output.write_bytes(encoded)
    return decoded, {'recordCount': len(records), 'recordDays': records[0][1], 'startJDTDB': records[0][0], 'endJDTDB': records[-1][0] + records[-1][1], 'encodedBytes': len(encoded), 'sha256': hashlib.sha256(encoded).hexdigest(), 'positionBoundKm': maxima[0], 'analyticRateBoundKmPerTDBDay': maxima[1], 'worstRecordIndices': worst, 'minimumSourceRadiusKm': minimum_radius, 'maximumSourceRadiusKm': maximum_radius, 'sourceBoundaryCount': len(records)-1, 'maximumSourceBoundaryPositionJumpKm': source_seams[0], 'maximumSourceBoundaryRateJumpKmPerTDBDay': source_seams[1], 'maximumDecodedBoundaryPositionJumpKm': decoded_seams[0], 'maximumDecodedBoundaryRateJumpKmPerTDBDay': decoded_seams[1]}


def heliocentric(tables, jd):
    pluto, sun = record_at(tables[9], jd), record_at(tables[10], jd)
    return tuple(subtract(pluto[k], sun[k]) for k in (0, 1))


def packed_state(raw, metadata, name, jd):
    """Include byte decoding and cubic reconstruction in evaluation measurements."""
    start, days, count, coefficients = metadata
    index = min(count - 1, math.floor((jd - start) / days))
    if index < 0 or jd > start + days * count:
        raise ValueError('evaluation outside packed coverage')
    fmt, width = ('d', 8) if name.endswith('64') else ('f', 4)
    if name.startswith('cubic'):
        left = struct.unpack_from(f'<6{fmt}', raw, index * 6 * width)
        right = struct.unpack_from(f'<6{fmt}', raw, (index + 1) * 6 * width)
        axes = cubic(left, right, days)
    else:
        values = struct.unpack_from(f'<{3*coefficients}{fmt}', raw, index * 3 * coefficients * width)
        axes = [values[a*coefficients:(a+1)*coefficients] for a in range(3)]
    return evaluate(axes, 2 * (jd - (start + index * days)) / days - 1, days)


def compare(actual, reference):
    return {'positionDifferenceKm': norm(subtract(actual[0], reference[0])), 'velocityDifferenceKmPerSecond': norm(subtract(actual[1], reference[1])) / 86400, 'angularDifferenceArcseconds': angular_arcseconds(actual[0], reference[0])}


def build(cache, plu060, output_dir):
    started = time.perf_counter()
    saved = json.loads(OUTPUT.read_text()) if OUTPUT.exists() else {}
    reader = shared.CachedReader(cache, saved.get('source', {}).get('retrievedByteRangesSHA256'))
    segments = [(s, direct.read_metadata(reader, s)) for s in direct.read_segments(reader) if (s.target, s.center) in ((9, 0), (10, 0))]
    margin = direct.TDB_TT_MARGIN_DAYS
    start, end = direct.J2000 - TT_LIMIT - margin, direct.J2000 + TT_LIMIT + margin
    layouts = {target: windows(segments, target, start, end) for target in (9, 10)}
    source = {target: load_records(reader, layout) for target, layout in layouts.items()}
    print('DE441 records retrieved: ' + str({k: len(v) for k, v in source.items()}), flush=True)
    if hashlib.sha256(plu060.read_bytes()).hexdigest() != PLU060_SHA:
        raise ValueError('PLU060 whole-file digest differs')
    center_reader = direct.RangeReader(plu060)
    center_segments = [(s, direct.read_metadata(center_reader, s)) for s in direct.read_segments(center_reader) if (s.target, s.center) == (999, 9)]
    center_start = min(direct.J2000 + s.start_seconds_tdb / 86400 for s, _ in center_segments)
    center_end = max(direct.J2000 + s.end_seconds_tdb / 86400 for s, _ in center_segments)
    center = load_records(center_reader, windows(center_segments, 999, center_start, center_end, center=9))
    center_max = max(shared.norm_upper([up(math.fsum(abs(v) for v in axis)) for axis in axes]) for _, _, axes in center)
    print(f'PLU060 center records scanned: {len(center)}', flush=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    results, tables = {}, {}
    scan_seconds = {}
    for name in CANDIDATES:
        before = time.perf_counter()
        tables[name], bodies = {}, {}
        for target, records in source.items():
            tables[name][target], bodies[str(target)] = scan(records, name, output_dir / f'{name}-{target}.bin')
        minimum = down(bodies['9']['minimumSourceRadiusKm'] - bodies['10']['maximumSourceRadiusKm'])
        bound = up(bodies['9']['positionBoundKm'] + bodies['10']['positionBoundKm'])
        rate = up(bodies['9']['analyticRateBoundKmPerTDBDay'] + bodies['10']['analyticRateBoundKmPerTDBDay'])
        if minimum <= 0 or bound >= minimum:
            raise ValueError('invalid angular bound geometry')
        results[name] = {'bodies': bodies, 'encodedBytes': sum(b['encodedBytes'] for b in bodies.values()), 'minimumHeliocentricDistanceKm': minimum, 'positionBoundKm': bound, 'analyticRateBoundKmPerTDBDay': rate, 'angularRepresentationBoundArcminutes': up(math.asin(up(bound/minimum)) * (180/math.pi) * 60), 'centerOffsetBudgetKmAtOneArcminute': down(minimum * math.sin(math.pi / 10800) - bound)}
        scan_seconds[name] = time.perf_counter() - before
        print(f'{name}: {results[name]["encodedBytes"]} bytes, {bound:.6g} km, {rate:.6g} km/day', flush=True)
    archived = []
    archives = {}
    for filename, target, solution in [('pluto-vector.json', 999, 'plu060_merged'), ('pluto-barycenter-vector.json', 9, 'DE441')]:
        path = ROOT / 'Scripts/reference-data/sources/horizons' / filename
        raw = path.read_bytes()
        archives[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
        for jd, p, v in references(raw, target, solution):
            reference = ([n * direct.AU_KM for n in p], [n * direct.AU_KM for n in v])
            offset = record_at(center, jd) if target == 999 else ([0.]*3, [0.]*3)
            row = {'julianDateTDB': jd, 'target': target, 'candidates': {}}
            for name in CANDIDATES:
                state = heliocentric(tables[name], jd)
                corrected = tuple([state[k][a] + offset[k][a] for a in range(3)] for k in (0, 1))
                row['candidates'][name] = {'barycenterProxy': compare(state, reference), 'withAvailableCenterOffset': compare(corrected, reference)}
            archived.append(row)
    # Freeze regular full-span, accepted endpoints, source join, central/blend, and integrator-grid samples.
    epochs = sorted(set([-TT_LIMIT, TT_LIMIT, *[float(t) for t in range(-730000, 730001, 29200)], -11112.5, *[edge + delta for edge in (-36524.5, 47846.5) for delta in (-32., -24., -16., -8., 0., 8., 16., 24., 32.)]]))
    samples = [{'tdbDaysFromJ2000': epoch, 'candidates': {name: compare(heliocentric(tables[name], direct.J2000 + epoch), heliocentric(source, direct.J2000 + epoch)) for name in CANDIDATES}} for epoch in epochs]
    runtime = {}
    for name in CANDIDATES:
        packed = {target: (output_dir / f'{name}-{target}.bin').read_bytes() for target in (9, 10)}
        metadata = {target: (rows[0][0], rows[0][1], len(rows), len(rows[0][2][0])) for target, rows in source.items()}
        before, checksum = time.perf_counter(), 0.
        for i in range(10000):
            jd = direct.J2000 + epochs[i % len(epochs)]
            states = [packed_state(packed[t], metadata[t], name, jd) for t in (9, 10)]
            checksum += states[0][0][0] - states[1][0][0]
        elapsed = time.perf_counter() - before
        runtime[name] = {'iterations': 10000, 'seconds': elapsed, 'evaluationsPerSecond': 10000/elapsed, 'checksum': checksum, 'scanAndEncodingSeconds': scan_seconds[name]}
    provenance_paths = [Path(__file__), ROOT/'Scripts/qualify-moon-de441.py', ROOT/'Scripts/assess-moon-de441.py']
    return {'schemaVersion': 1, 'source': {'url': direct.SOURCE_URL, 'identity': shared.identity(), 'retrievedByteRangesSHA256': dict(sorted(reader.ranges.items())), 'globalDigestVerified': False, 'state': 'Pluto barycenter (9) minus Sun (10), each relative to SSB (0); geometric ICRF; km and km/TDB day', 'segments': {str(t): [{'segment': s._asdict(), 'metadata': m._asdict(), 'firstRecord': first, 'recordCount': count} for s, m, first, count in layout] for t, layout in layouts.items()}}, 'acceptedRange': {'ttDaysFromJ2000Inclusive': [-TT_LIMIT, TT_LIMIT], 'tdbMarginDays': margin}, 'candidates': results, 'centerOffset': {'url': PLU060_URL, 'sha256': PLU060_SHA, 'wholeFileDigestVerified': True, 'startJDTDB': center_start, 'endJDTDB': center_end, 'recordCount': len(center), 'positionNormBoundKmOverAvailableCoverage': center_max, 'fullAcceptedRangeQualified': False, 'treatment': 'Barycenter proxy outside retained central model; measured PLU060 center correction is available only over 1800–2199. No extrapolation or full-range center-offset bound is asserted.'}, 'referenceArchivesSHA256': archives, 'archivedReferences': archived, 'fixedSamples': samples, 'sourceCodeSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in provenance_paths}, 'runtimeObservation': {'evaluator': 'Packed little-endian bytes, index, decode, cubic reconstruction where applicable, and analytic Chebyshev value/rate for both bodies', 'python': platform.python_version(), 'platform': platform.platform(), 'totalSeconds': time.perf_counter()-started, 'candidates': runtime, 'productionRepresentative': False}, 'assessment': {'barycenterRepresentationFullRangeScanned': True, 'absoluteFullRangeAccuracyQualified': False, 'productionIntegrated': False, 'choiceForNextExperiment': 'cubic-float64', 'remaining': 'Validate Swift decoding, TT/TDB and frame transformations, retained central model and blends, and actual state consumers. DE441 representation bounds do not certify source ephemeris accuracy or the unavailable full-range Pluto-center correction; #92/#96 public paths remain separate.'}}


def deterministic(value):
    value = dict(value)
    value.pop('runtimeObservation', None)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / '.context/issue-184/compact/ranges')
    parser.add_argument('--plu060', type=Path, default=ROOT / '.context/issue-190/plu060.bsp')
    parser.add_argument('--artifacts', type=Path, default=ROOT / '.context/issue-190/candidates')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    evidence = build(args.cache, args.plu060, args.artifacts)
    if args.check:
        if deterministic(evidence) != deterministic(json.loads(OUTPUT.read_text())):
            raise SystemExit('Pluto DE441 evidence differs')
        print('Verified Pluto DE441 evidence')
    else:
        OUTPUT.write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
        print(f'Wrote {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
