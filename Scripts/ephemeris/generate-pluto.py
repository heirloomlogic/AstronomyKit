#!/usr/bin/env python3
"""Deterministic signed SPK coefficient excerpts for geometric Pluto center 999.

Python reference dependencies are development-only. Never fits or resamples data.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / '.context/accuracy-qualification/python-reference'
sys.path.insert(0, str(ENV))
import erfa
import jplephem
import numpy as np
from jplephem.spk import SPK

HERE = Path(__file__).resolve().parent
PLAN = HERE / 'pluto-plan.json'
OUT = ROOT / '.context/pluto-integration'
COUT = ROOT / 'Sources/CLibAstronomy/EphemerisData'
MANIFEST = COUT / 'pluto-manifest.json'
REPORT = HERE / 'pluto-evidence.json'
RAW = HERE / 'pluto-reference'
KERNELS = {'de440s.bsp': ROOT / '.context/accuracy-qualification/de440s.bsp',
           'plu060.bsp': ROOT / '.context/pluto-integration/plu060.bsp'}
AU = 149597870.7
HEADER = struct.Struct('<8sQQdddd')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()


def helpers():
    spec = importlib.util.spec_from_file_location('pluto_geometric_reference', ROOT / 'Scripts/reference-data/qualify-geometric-events.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_plan():
    plan = json.loads(PLAN.read_bytes())
    expected = plan['referenceDependencies']
    if (jplephem.__version__, erfa.__version__, np.__version__) != (expected['jplephem'], expected['pyerfa'], expected['numpy']):
        raise ValueError('reference dependency version drift')
    for module in (jplephem, erfa, np):
        if not Path(module.__file__).resolve().is_relative_to(ENV.resolve()):
            raise ValueError('reference dependency outside pinned environment')
    for name, source in plan['sources'].items():
        content = KERNELS[name].read_bytes()
        if len(content) != source['bytes'] or digest(content) != source['sha256']:
            raise ValueError('source kernel identity drift: ' + name)
    return plan


def source_segments(kernel, center, target):
    segments = sorted((s for s in kernel.segments if (s.center, s.target) == (center, target)), key=lambda s: s.start_jd)
    if not segments or any((s.frame, s.data_type) != (1, 2) for s in segments):
        raise ValueError('missing or unsupported frame/type/center/target')
    for a, b in zip(segments, segments[1:]):
        if a.end_jd != b.start_jd:
            raise ValueError('source segment overlap/gap requires explicit priority policy')
    return segments


def component_payload(plan, component, kernel):
    lower, upper = plan['payloadTDBGuards']
    segments = source_segments(kernel, component['center'], component['target'])
    if segments[0].start_jd > lower or segments[-1].end_jd < upper:
        raise ValueError('source fails requested full date coverage')
    arrays, metadata = [], []
    grid_start = grid_stop = interval = degree_count = None
    for segment in segments:
        if segment.end_jd <= lower or segment.start_jd >= upper:
            continue
        start, step, array = segment.load_array()
        if array.shape[0] != 3 or start != segment.start_jd or start + step * array.shape[1] != segment.end_jd:
            raise ValueError('noncanonical SPK record support')
        first = max(0, math.floor((lower - start) / step))
        stop = min(array.shape[1], math.ceil((upper - start) / step))
        local_start, local_stop = start + first * step, start + stop * step
        if grid_start is None:
            grid_start, interval, degree_count = local_start, step, array.shape[2]
        elif (step, array.shape[2], local_start) != (interval, degree_count, grid_stop):
            raise ValueError('cannot concatenate unequal or disconnected source grids')
        grid_stop = local_stop
        arrays.append(component['sign'] * array[:, first:stop, :].transpose(1, 0, 2))
        metadata.append({'center': segment.center, 'target': segment.target, 'frame': segment.frame,
                         'type': segment.data_type, 'sourceSegmentStartTDB': segment.start_jd,
                         'sourceSegmentEndTDB': segment.end_jd, 'firstRecord': first,
                         'stopRecordExclusive': stop, 'sourceLabel': segment.source.decode('ascii')})
    values = np.concatenate(arrays, axis=0).astype('<f8')
    if not np.isfinite(values).all():
        raise ValueError('nonfinite source coefficient')
    header = HEADER.pack(b'MOONDEV1', len(values), degree_count, grid_start, interval, lower, upper)
    payload = header + values.tobytes()
    return payload, {**component, 'bytes': len(payload), 'sha256': digest(payload),
                     'recordCount': len(values), 'coefficientCountPerAxis': degree_count,
                     'startJulianDateTDB': grid_start, 'intervalDays': interval,
                     'lowerJulianDateTDB': lower, 'upperJulianDateTDB': upper,
                     'sourceSegments': metadata}


def products(plan):
    payloads, components = {}, []
    for component in plan['components']:
        with SPK.open(str(KERNELS[component['kernel']])) as kernel:
            payload, metadata = component_payload(plan, component, kernel)
        payloads[component['filename']] = payload
        components.append(metadata)
    manifest = {'schemaVersion': 1, 'producer': 'Heirloom Logic / AstronomyKit',
                'derivativeProduct': 'Renamed native coefficient excerpts; not original NASA/JPL SPK kernels',
                'originalDataAcknowledgement': 'NASA/JPL Solar System Dynamics DE440 and PLU060; NASA/JPL NAIF distribution',
                'rulesURL': 'https://naif.jpl.nasa.gov/naif/rules.html',
                'creditURL': 'https://naif.jpl.nasa.gov/naif/credit.html',
                'sourceCommentsURL': 'https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.cmt',
                'planSHA256': digest(PLAN.read_bytes()), 'generatorSHA256': digest(Path(__file__).read_bytes()),
                'sources': plan['sources'], 'coordinateContract': plan['coordinateContract'],
                'publicTTDomain': plan['publicTTDomain'], 'domainUpperExclusive': True,
                'representation': plan['representation'], 'components': components,
                'productionRepresentation': plan['productionRepresentation'],
                'totalPayloadBytes': sum(len(p) for p in payloads.values())}
    return payloads, manifest


def c_source(component, payload):
    start, interval, lower, upper, values = decode(payload)
    prefix = component['cPrefix']
    macro = prefix.upper()
    lines = ['/* Generated by Heirloom Logic / AstronomyKit from NASA/JPL DE440 and PLU060.',
             ' * Renamed derivative coefficient product, not an original JPL kernel.',
             ' * Signed AU; record/axis/ascending Chebyshev degree. See pluto-manifest.json.',
             ' * Sources and conditions: https://naif.jpl.nasa.gov/naif/rules.html',
             ' */',
             f'#define {macro}_START_TDB {start.hex()}',
             f'#define {macro}_END_TDB {upper.hex()}',
             f'#define {macro}_LOWER_TDB {lower.hex()}',
             f'#define {macro}_STEP_DAYS {interval.hex()}',
             f'#define {macro}_RECORD_COUNT {len(values)}',
             f'#define {macro}_COEFFICIENT_COUNT {values.shape[2]}',
             f'static const double {prefix}_coefficients[] = {{']
    lines.extend('    ' + ', '.join(float(x / AU).hex() for x in row) + ',' for row in values.reshape(-1, values.shape[2]))
    lines.append('};')
    return ('\n'.join(lines) + '\n').encode()


def decode(payload):
    if len(payload) < HEADER.size:
        raise ValueError('truncated header')
    magic, count, degree_count, start, interval, lower, upper = HEADER.unpack_from(payload)
    if magic != b'MOONDEV1' or not count or not 2 <= degree_count <= 64:
        raise ValueError('invalid payload identity/dimensions')
    if len(payload) != HEADER.size + count * 3 * degree_count * 8:
        raise ValueError('payload size mismatch')
    if not all(math.isfinite(x) for x in (start, interval, lower, upper)) or interval <= 0 or not start <= lower < upper <= start + count * interval:
        raise ValueError('invalid payload support')
    values = np.frombuffer(payload, '<f8', offset=HEADER.size).reshape(count, 3, degree_count)
    if not np.isfinite(values).all():
        raise ValueError('nonfinite payload')
    return (start, interval, lower, upper, values)


def evaluate(decoded, first, second=0.0):
    start, interval, lower, upper, values = decoded
    first, second = np.broadcast_arrays(np.asarray(first), np.asarray(second))
    offset = (first - start) + second
    if np.any(~np.isfinite(offset)) or np.any(offset < lower - start) or np.any(offset > upper - start):
        raise ValueError('epoch outside payload support')
    index = np.floor(offset / interval).astype(int)
    index = np.minimum(index, len(values) - 1)
    x = 2 * (offset - index * interval) / interval - 1
    coefficients = values[index].transpose(2, 1, 0) if index.ndim else values[index].T
    # NumPy Chebyshev implementation is separate from jplephem's recurrence.
    p = np.polynomial.chebyshev.chebval(x, coefficients, tensor=False)
    d = np.polynomial.chebyshev.chebder(coefficients, axis=0)
    v = np.polynomial.chebyshev.chebval(x, d, tensor=False) * (2 / interval)
    return p, v


def tdb(jdtt):
    offset = jdtt - 2451545.0
    correction = erfa.dtdb(2451545.0, offset, 0, 0, 0, 0)
    return erfa.tttdb(2451545.0, offset, correction)


def reference_state(kernel, component, first, second):
    segments = source_segments(kernel, component['center'], component['target'])
    p, v = np.empty((3, len(second))), np.empty((3, len(second)))
    # Right-hand segment at shared endpoints; unlike SPK.__getitem__, covers both.
    for i, segment in enumerate(segments):
        offsets = (first - segment.start_jd) + second
        mask = (offsets >= 0) & ((offsets < segment.end_jd - segment.start_jd) if i + 1 < len(segments) else (offsets <= segment.end_jd - segment.start_jd))
        if mask.any():
            p[:, mask], v[:, mask] = segment.compute_and_differentiate(first, second[mask])
    return p * component['sign'], v * component['sign']


def parity(plan, payloads):
    summaries = []
    for component in plan['components']:
        decoded = decode(payloads[component['filename']])
        start, step, lower, upper, values = decoded
        dates = [start + i * step / 2 for i in range(2 * len(values) + 1)]
        dates += [lower, upper, 2456293.5 - 1e-8, 2456293.5, 2456293.5 + 1e-8]
        dates = sorted(set(jd for jd in dates if lower <= jd <= upper))
        second = np.asarray(dates) - 2451545.0
        p, v = evaluate(decoded, 2451545.0, second)
        production_decoded = (*decoded[:4], decoded[4] / AU)
        cp, cv = evaluate(production_decoded, 2451545.0, second)
        with SPK.open(str(KERNELS[component['kernel']])) as kernel:
            rp, rv = reference_state(kernel, component, 2451545.0, second)
        pd, vd = float(np.max(np.abs(p - rp))), float(np.max(np.abs(v - rv)))
        cpd, cvd = float(np.max(np.abs(cp * AU - rp))), float(np.max(np.abs(cv * AU - rv)))
        if max(pd, cpd) > plan['parityLimits']['positionComponentKm'] or max(vd, cvd) > plan['parityLimits']['velocityComponentKmPerDay']:
            raise ValueError(f'fixed parity limit exceeded: {pd}, {vd}')
        summaries.append({'component': component['filename'], 'stateCount': len(dates),
                          'maximumPositionComponentDifferenceKm': pd,
                          'maximumVelocityComponentDifferenceKmPerDay': vd,
                          'productionAUScaledPositionDifferenceKm': cpd,
                          'productionAUScaledVelocityDifferenceKmPerDay': cvd})
    return summaries


def fresh_reference(plan, acquire=False):
    g = helpers()
    recipe = g.Q.parameters('999', '10', 'NONE', plan['freshPositionSampling']['julianDatesTT'])
    raw, query = RAW / 'pluto-heliocentric.json', RAW / 'pluto-heliocentric.query.json'
    if acquire and not raw.exists() and not query.exists():
        data = g.Q.download(recipe)
        RAW.mkdir(parents=True, exist_ok=True)
        raw.write_bytes(data)
        query.write_bytes(encoded({'parameters': recipe, 'responseSHA256': digest(data), 'planSHA256': digest(PLAN.read_bytes())}))
    data, saved = raw.read_bytes(), json.loads(query.read_bytes())
    if saved != {'parameters': recipe, 'responseSHA256': digest(data), 'planSHA256': digest(PLAN.read_bytes())}:
        raise ValueError('detached fresh reference/query/plan')
    rows, metadata = g.Q.parse_response(data, recipe)
    if metadata['targetEphemeris'] != 'plu060_merged' or metadata['centerEphemeris'] != 'plu060_merged':
        raise ValueError('fresh Horizons source identity differs from frozen plan')
    return rows, metadata


def evidence(plan, payloads, manifest):
    g = helpers()
    raw_decoded = [decode(payloads[c['filename']]) for c in plan['components']]
    decoded = [(*d[:4], d[4] / AU) for d in raw_decoded]
    def state(jd):
        a, b = tdb(jd)
        states = [evaluate(d, a, b) for d in decoded]
        return sum(s[0] for s in states) * AU, sum(s[1] for s in states) * AU
    refs, metadata = fresh_reference(plan)
    old = json.loads(g.Q.REPORT.read_bytes())
    old_positions = [r for r in old['positions'] if r['body'] == 'Pluto' and r['mode'] == 'heliocentric']
    positions = []
    for classification, rows in [('fresh-predetermined', refs), ('retrospective', [r['reference'] for r in old_positions])]:
        for row in rows:
            p, v = state(row['julianDateTT'])
            positions.append({'classification': classification, 'julianDateTT': row['julianDateTT'],
                              'angleErrorArcminutes': g.Q.angle_arcminutes(p / AU, row['positionAU']),
                              'signedRangeErrorPPM': (float(np.linalg.norm(p)) / AU - row['rangeAU']) / row['rangeAU'] * 1e6,
                              'maximumVelocityComponentErrorKmPerDay': float(np.max(np.abs(v - np.array(row['velocityAUPerDay']) * AU)))})
    geometry = json.loads(g.REPORT.read_bytes())
    events, event_inputs = [], set()
    for event in geometry['events']:
        if event['body'] != 'Pluto':
            continue
        window = event['case'].split('/')[1]
        path = g.RAW / f'alignment-{window}-pluto-earth-fine'
        event_inputs.update([path.with_suffix('.query.json'), path.with_suffix('.json')])
        recipe = json.loads(path.with_suffix('.query.json').read_bytes())['parameters']
        rows, _ = g.Q.parse_response(path.with_suffix('.json').read_bytes(), recipe)
        center = event['reference']['julianDateTT']
        rows = sorted(rows, key=lambda r: abs(r['julianDateTT'] - center))[:5]
        rows.sort(key=lambda r: r['julianDateTT'])
        def scalar(seconds):
            jd = center + seconds / 86400
            earth = np.array([g.Q.polynomial([{'julianDateTT': r['julianDateTT'], 'rangeRateAUPerDay': r['positionAU'][axis]} for r in rows], jd) for axis in range(3)])
            matrix = g.date_plane(jd)
            e, p = matrix @ earth, matrix @ state(jd)[0]
            return float(e[1] * p[0] - e[0] * p[1])
        lo, hi = -60., 60.
        left, right = scalar(lo), scalar(hi)
        direction = 1 if event['reference']['kind'] == 'relative-0' else -1
        if left * right >= 0 or (right - left) * direction <= 0:
            raise ValueError('retrospective candidate root fails frozen directed bracket')
        for _ in range(20):
            mid = (lo + hi) / 2
            value = scalar(mid)
            if (value < 0) == (left < 0):
                lo, left = mid, value
            else:
                hi = mid
        events.append({'classification': 'retrospective', 'case': event['case'], 'kind': event['reference']['kind'],
                       'referenceJulianDateTT': center, 'oldAPIErrorSeconds': event['signedTimeErrorSeconds'],
                       'candidatePlutoWithArchivedEarthErrorSeconds': (lo + hi) / 2, 'finalBracketWidthSeconds': hi - lo})
    summaries = {}
    for classification in ('fresh-predetermined', 'retrospective'):
        rows = [r for r in positions if r['classification'] == classification]
        summaries[classification] = {'count': len(rows), 'maximumAngleErrorArcminutes': max(r['angleErrorArcminutes'] for r in rows),
                                     'maximumAbsoluteRangeErrorPPM': max(abs(r['signedRangeErrorPPM']) for r in rows),
                                     'maximumVelocityComponentErrorKmPerDay': max(r['maximumVelocityComponentErrorKmPerDay'] for r in rows)}
    if len(events) != 18 or summaries['fresh-predetermined']['count'] != 128:
        raise ValueError('case count drift')
    if any(r['angleErrorArcminutes'] > plan['targets']['angleArcminutes'] or abs(r['signedRangeErrorPPM']) > plan['targets']['distancePPM'] for r in positions):
        raise ValueError('fixed position/distance target exceeded')
    return {'classification': 'finite-source-parity-and-candidate-evidence-not-continuous-public-API-qualification',
            'planSHA256': digest(PLAN.read_bytes()), 'generatorSHA256': digest(Path(__file__).read_bytes()),
            'manifestSHA256': digest(encoded(manifest)), 'parity': parity(plan, payloads),
            'freshReference': metadata, 'positions': positions, 'positionSummary': summaries,
            'events': events, 'eventSummary': {'count': len(events), 'oldAPIMaximumErrorSeconds': max(abs(e['oldAPIErrorSeconds']) for e in events),
                                            'candidateMaximumErrorSeconds': max(abs(e['candidatePlutoWithArchivedEarthErrorSeconds']) for e in events)},
            'inputSHA256': {str(p.relative_to(ROOT)): digest(p.read_bytes()) for p in [g.REPORT, g.Q.REPORT, Path(g.__file__), Path(g.Q.__file__), *sorted(RAW.glob('*')), *sorted(event_inputs)]},
            'limitations': plan['limitations']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['generate', 'acquire', 'report', 'check'])
    args = parser.parse_args()
    plan = load_plan()
    if args.action == 'acquire':
        rows, metadata = fresh_reference(plan, acquire=True)
        print(json.dumps({'freshReferenceCount': len(rows), 'metadata': metadata}, sort_keys=True))
        return
    payloads, manifest = products(plan)
    cfiles = {c['cFilename']: c_source(c, payloads[c['filename']]) for c in plan['components']}
    manifest['productionCFiles'] = {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in cfiles.items()}
    if args.action == 'generate':
        OUT.mkdir(parents=True, exist_ok=True)
        COUT.mkdir(parents=True, exist_ok=True)
        for name, data in payloads.items():
            (OUT / name).write_bytes(data)
        for name, data in cfiles.items():
            (COUT / name).write_bytes(data)
        MANIFEST.write_bytes(encoded(manifest))
        print(json.dumps({'payloadBytes': manifest['totalPayloadBytes'], 'parity': parity(plan, payloads)}, sort_keys=True))
        return
    if MANIFEST.read_bytes() != encoded(manifest) or any((OUT / name).read_bytes() != data for name, data in payloads.items()) or any((COUT / name).read_bytes() != data for name, data in cfiles.items()):
        raise ValueError('bundled payload or manifest differs from deterministic generation')
    report = evidence(plan, payloads, manifest)
    if args.action == 'report':
        if REPORT.exists():
            raise ValueError('report already frozen')
        REPORT.write_bytes(encoded(report))
    elif REPORT.read_bytes() != encoded(report):
        raise ValueError('frozen evidence replay drift')
    print(json.dumps({'positions': report['positionSummary'], 'events': report['eventSummary'], 'parity': report['parity']}, sort_keys=True))


if __name__ == '__main__':
    main()
