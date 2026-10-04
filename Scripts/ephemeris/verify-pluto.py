#!/usr/bin/env python3
"""Checkout-only Pluto artifact integrity; standard library, no kernels/network."""
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DATA = ROOT / 'Sources/CLibAstronomy/EphemerisData'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inspect_component(content, component, guards):
    if len(content) != component['bytes'] or sha(content) != component['sha256']:
        raise ValueError('C artifact size/hash drift')
    text = content.decode('ascii')
    prefix = component['prefix']
    expected = {
        'START_TDB': component['startJulianDateTDB'],
        'END_TDB': guards[1], 'LOWER_TDB': guards[0],
        'STEP_DAYS': component['intervalDays'],
        'RECORD_COUNT': component['recordCount'],
        'COEFFICIENT_COUNT': component['coefficientCountPerAxis'],
    }
    for key, value in expected.items():
        match = re.search(r'^#define ' + prefix.upper() + '_' + key + r' (\S+)$', text, re.M)
        if not match:
            raise ValueError('missing metadata macro')
        actual = int(match[1]) if key.endswith('COUNT') else float.fromhex(match[1])
        if actual != value:
            raise ValueError('C metadata differs from manifest')
    start, step, count = expected['START_TDB'], expected['STEP_DAYS'], expected['RECORD_COUNT']
    degree_count = expected['COEFFICIENT_COUNT']
    if step <= 0 or not 2 <= degree_count <= 64 or not start <= guards[0] < guards[1] <= start + step * count:
        raise ValueError('invalid coefficient grid support')
    array = re.search(r'static const double ' + prefix + r'_coefficients\[\] = \{\n(.*?)\n\};\n\Z', text, re.S)
    if not array:
        raise ValueError('missing or malformed immutable C array')
    entries = array[1].replace('\n', '').split(',')
    if entries[-1].strip():
        raise ValueError('missing final array delimiter')
    entries.pop()
    if len(entries) != count * 3 * degree_count:
        raise ValueError('coefficient dimensions mismatch')
    if any(not math.isfinite(float.fromhex(value.strip())) for value in entries):
        raise ValueError('nonfinite coefficient')
    return len(entries)


def check():
    plan_data = (HERE / 'pluto-plan.json').read_bytes()
    plan = json.loads(plan_data)
    manifest_data = (DATA / 'pluto-manifest.json').read_bytes()
    manifest = json.loads(manifest_data)
    if manifest['planSHA256'] != sha(plan_data) or manifest['generatorSHA256'] != sha((HERE / 'generate-pluto.py').read_bytes()):
        raise ValueError('manifest detached from source/plan')
    if manifest['sources'] != plan['sources'] or manifest['publicTTDomain'] != [2415020.5, 2499391.5] or not manifest['domainUpperExclusive']:
        raise ValueError('source identity or approved domain drift')
    components = manifest['components']
    if [(c['center'], c['target'], c['sign']) for c in components] != [(0, 9, 1), (0, 10, -1), (9, 999, 1)]:
        raise ValueError('Pluto body-center composition changed')
    total = 0
    for component, planned in zip(components, plan['components']):
        if any(component[key] != value for key, value in planned.items()):
            raise ValueError('component differs from plan')
        details = {**component, **manifest['productionCFiles'][component['cFilename']], 'prefix': component['cPrefix']}
        total += inspect_component((DATA / component['cFilename']).read_bytes(), details, plan['payloadTDBGuards'])
    report = json.loads((HERE / 'pluto-evidence.json').read_bytes())
    if report['manifestSHA256'] != sha(manifest_data) or report['planSHA256'] != sha(plan_data):
        raise ValueError('evidence detached from manifest/plan')
    for name, expected in report['inputSHA256'].items():
        if sha((ROOT / name).read_bytes()) != expected:
            raise ValueError('reference evidence input drift: ' + name)
    return {'components': len(components), 'coefficientCount': total, 'compiledDataBytes': total * 8,
            'freshReferenceCount': report['positionSummary']['fresh-predetermined']['count']}


if __name__ == '__main__':
    print('Pluto checkout integrity verified: ' + json.dumps(check(), sort_keys=True))
