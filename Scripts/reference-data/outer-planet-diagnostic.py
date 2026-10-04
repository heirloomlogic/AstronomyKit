#!/usr/bin/env python3
"""Independent, frozen-epoch model diagnostics; never reads acceptance samples/budgets."""
import argparse
import sys
import csv
import hashlib
import json
import math
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path
import source_archive

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'Scripts/reference-data/sources/distance/model-diagnostics/outer-planets'
CACHE = ROOT / '.context/outer-planet-diagnostic'
REPORT = RAW / 'report.json'
AU_KM = 149597870.7
API = 'https://ssd.jpl.nasa.gov/api/horizons_file.api'
BODIES = {'Uranus': ('ura', '7', '799'), 'Neptune': ('nep', '8', '899')}
KERNEL_HASH = '4b1021ceb01033f7d512b15dbe63b7b2421f118104e127374a85537ad0d336f9'
DE200_AU_KM = 149597870.66  # JPL DE200 ASCII header GROUP 1041, AU constant.
EPOCH_HASH = 'aa87d839bbbfc60f758ee82c4f3444adb92099f4c2dc4985f60acf731c85fe98'
# Published BDL VSOP87 documentation: dynamical ecliptic -> FK5 equator J2000.
ROTATION = ((1., .000000440360, -.000000190919), (-.000000479966, .917482137087, -.397776982902), (0., .397776982902, .917482137087))


def encoded(v):
    return (json.dumps(v, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_verified(name):
    data = (RAW / name).read_bytes()
    recipe = json.loads((RAW / (name + '.recipe.json')).read_bytes())
    if sha(data) != recipe['sha256']:
        raise ValueError(f'{name}: hash mismatch')
    return data, recipe


def archive(name, data, recipe):
    (RAW / name).write_bytes(data)
    (RAW / (name + '.recipe.json')).write_bytes(encoded({**recipe, 'sha256': sha(data)}))


def dates():
    data = (RAW / 'epochs.json').read_bytes()
    if sha(data) != EPOCH_HASH:
        raise ValueError('predetermined epochs changed')
    return json.loads(data)['julianDatesTT']


def coefficients(body):
    suffix = BODIES[body][0]
    path = ROOT / f'Scripts/model-data/VSOP87B.{suffix}'
    manifest = json.loads((ROOT / 'Scripts/model-data/manifest.json').read_bytes())
    data = path.read_bytes()
    if sha(data) != manifest['files'][path.name]['sha256']:
        raise ValueError(f'{body}: coefficient hash differs from frozen manifest')
    lines = data.decode().splitlines()
    result = {}
    i = 0
    while i < len(lines):
        header = lines[i]
        if int(header[17]) != 2 or header[22:29].strip().upper() != body.upper():
            raise ValueError('wrong VSOP version/body')
        coord, power, count = int(header[41]), int(header[59]), int(header[60:67])
        if (coord, power) in result or coord not in (1, 2, 3):
            raise ValueError('duplicate/invalid coordinate series')
        terms = []
        for n, line in enumerate(lines[i + 1:i + 1 + count], 1):
            if int(line[1]) != 2 or int(line[3]) != coord or int(line[4]) != power or int(line[5:10]) != n:
                raise ValueError('term numbering/coordinate/power mismatch')
            terms.append((line[79:97].strip(), line[97:111].strip(), line[111:131].strip()))
        if len(terms) != count:
            raise ValueError('truncated coefficient series')
        result[coord, power] = terms
        i += count + 1
    return result


def spherical(terms, jd):
    t = (jd - 2451545.) / 365250.
    return [math.fsum(t ** p * math.fsum(float(a) * math.cos(float(b) + float(c) * t) for a, b, c in rows)
                      for (coord, p), rows in terms.items() if coord == k) for k in (1, 2, 3)]


def fk5_vector(lbr):
    l, b, r = lbr
    ecl = (r * math.cos(b) * math.cos(l), r * math.cos(b) * math.sin(l), r * math.sin(b))
    return [math.fsum(a * b for a, b in zip(row, ecl)) for row in ROTATION]


def native_de200_vector(lbr):
    # Bretagnon & Francou (1988), eq. (1): gamma_DE200 gamma_VSOP = -0.0930 arcsec,
    # reckoned in the equator; inertial dynamical obliquity = 23d26m21.4091s.
    l, b, r = lbr
    eps = math.radians(23 + 26/60 + 21.4091/3600)
    delta = math.radians(-.0930/3600)
    x, y, z = r*math.cos(b)*math.cos(l), r*math.cos(b)*math.sin(l), r*math.sin(b)
    equy = math.cos(eps)*y - math.sin(eps)*z
    return [math.cos(delta)*x-math.sin(delta)*equy, math.sin(delta)*x+math.cos(delta)*equy, math.sin(eps)*y+math.cos(eps)*z]


def parameters(code):
    values = {'COMMAND': code, 'OBJ_DATA': 'NO', 'MAKE_EPHEM': 'YES', 'EPHEM_TYPE': 'VECTORS', 'CENTER': '500@10',
              'TLIST': ','.join(format(jd, '.8f') for jd in dates()), 'TLIST_TYPE': 'JD', 'TIME_TYPE': 'TT',
              'REF_SYSTEM': 'ICRF', 'REF_PLANE': 'FRAME', 'OUT_UNITS': 'AU-D', 'VEC_TABLE': '3', 'VEC_CORR': 'NONE', 'CSV_FORMAT': 'YES'}
    return {k: f"'{v}'" for k, v in values.items()}


def parse_horizons(data, params, source):
    envelope = json.loads(data)
    text = envelope.get('result', '')
    if envelope.get('signature') != {'source': 'NASA/JPL Horizons API', 'version': '1.0'} or 'error' in envelope:
        raise ValueError('unexpected Horizons service/error')
    target = re.search(r'Target body name:\s*(.*?)\s+\{source:\s*([^}]+)\}', text)
    center = re.search(r'Center body name:\s*(.*?)\s+\{source:\s*([^}]+)\}', text)
    if not target or not center or f"({params['COMMAND'].strip(chr(39))})" not in target[1] or '(10)' not in center[1]:
        raise ValueError('Horizons target/center mismatch')
    if target[2] != source or (source == 'DE441' and center[2] != 'DE441'):
        raise ValueError('reference solution differs from recipe')
    for required in ('JDTT', 'Reference frame : ICRF', 'Output units    : AU-D', '$$SOE', '$$EOE'):
        if required not in text:
            raise ValueError(f'missing {required}')
    if not re.search(r'Output type\s*:\s*GEOMETRIC', text):
        raise ValueError('not geometric')
    rows = []
    for f in csv.reader(text.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines()):
        vals = [float(f[0])] + [float(v) for v in f[2:11]]
        if len(vals) != 10 or not all(map(math.isfinite, vals)):
            raise ValueError('invalid Horizons state')
        jd, x, y, z, vx, vy, vz, lt, r, vr = vals
        if abs(math.hypot(x, y, z) - r) > 1e-11:
            raise ValueError('inconsistent Horizons radius')
        rows.append({'jdTT': jd, 'positionAU': [x, y, z], 'velocityAUPerDay': [vx, vy, vz]})
    if [r['jdTT'] for r in rows] != dates():
        raise ValueError('Horizons epoch coverage mismatch')
    return rows, {'target': target[1], 'targetSource': target[2], 'center': center[1], 'centerSource': center[2]}


def acquire_horizons():
    for body, (_, bary, center) in BODIES.items():
        for label, code, source in [('barycenter', bary, 'DE441'), ('center', center, 'ura184_merged' if body == 'Uranus' else 'nep098_merged')]:
            params = parameters(code)
            lines = ['!$$SOF']
            for key, value in params.items():
                lines.append('TLIST=' + '\n'.join(f"'{jd}'" for jd in value.strip("'").split(',')) if key == 'TLIST' else f'{key}={value}')
            file_data = '\n'.join(lines) + '\n'
            boundary = 'AstronomyKitOuterPlanetDiagnostic'
            payload = (f'--{boundary}\r\nContent-Disposition: form-data; name="format"\r\n\r\njson\r\n'
                       f'--{boundary}\r\nContent-Disposition: form-data; name="input"; filename="query.txt"\r\nContent-Type: text/plain\r\n\r\n{file_data}\r\n--{boundary}--\r\n').encode()
            request = urllib.request.Request(API, data=payload, headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
            data = urllib.request.urlopen(request, timeout=60).read()
            _, metadata = parse_horizons(data, params, source)
            archive(f'{body.lower()}-{label}.horizons.json', data, {'url': API, 'parameters': params, 'metadata': metadata, 'epochsSHA256': EPOCH_HASH})
            print('archived', body, label, flush=True)


def extract_de200():
    import spiceypy as spice
    path = CACHE / 'de200.bsp'
    if sha(path.read_bytes()) != KERNEL_HASH:
        raise ValueError('unexpected DE200 SPK hash')
    tls, recipe = read_verified('naif0012.tls')
    spice.kclear()
    spice.furnsh(str(path)); spice.furnsh(str(RAW / 'naif0012.tls'))
    segments = []
    h = spice.dafopr(str(path)); spice.dafbfs(h)
    while spice.daffna():
        dc, ic = spice.dafus(spice.dafgs(), 2, 6)
        segments.append({'target': int(ic[0]), 'center': int(ic[1]), 'frame': int(ic[2]), 'type': int(ic[3]), 'startET': float(dc[0]), 'stopET': float(dc[1])})
    _, comments, _ = spice.dafec(h, 200, 1000)
    spice.dafcls(h)
    rows = []
    for body, (_, code, _) in BODIES.items():
        segment = next(s for s in segments if s['target'] == int(code))
        if segment['frame'] != 14 or segment['center'] != 0:
            raise ValueError('unexpected DE200 native frame/origin')
        for jd in dates():
            ttsec = (jd - 2451545.) * 86400.
            et = float(spice.unitim(ttsec, 'TDT', 'TDB'))
            native, _ = spice.spkgeo(int(code), et, 'DE-200', 10)
            icrf, _ = spice.spkgeo(int(code), et, 'J2000', 10)
            wrong, _ = spice.spkgeo(int(code), ttsec, 'DE-200', 10)
            rows.append({'body': body, 'jdTT': jd, 'tdbMinusTTSeconds': et-ttsec, 'positionAU': [float(v)/AU_KM for v in icrf[:3]],
                         'nativePositionAU': [float(v)/AU_KM for v in native[:3]], 'velocityAUPerDay': [float(v)*86400/AU_KM for v in icrf[3:]],
                         'usingTTAsTDBVectorDifferenceKm': math.dist(native[:3], wrong[:3])})
    archive('de200-states.json', encoded({'rows': rows, 'segments': segments, 'comments': [s for s in comments if s]}),
            {'kernelURL': 'https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/a_old_versions/de200.bsp', 'kernelSHA256': KERNEL_HASH,
             'epochsSHA256': EPOCH_HASH, 'nativeFrame': 'DE-200 (14)', 'outputFrame': 'SPICE J2000 (1); DE-200 built-in identity alias, not independently aligned ICRF',
             'physicalFrameCaveat': 'SPICE DE-200-to-J2000 is identity; this does not measure or remove the physical DE200-to-ICRF orientation bias.',
             'targetCodes': [7, 8], 'centerCode': 10, 'correction': 'NONE', 'inputTimeScale': 'TT', 'kernelTimeScale': 'TDB',
             'timeConversion': "unitim((jdTT-2451545)*86400, 'TDT', 'TDB'), using naif0012.tls",
             'spiceypyVersion': spice.__version__, 'cspiceVersion': spice.tkvrsn('TOOLKIT'), 'timeKernelSHA256': recipe['sha256'],
             'de200ToJ2000Rotation': spice.pxform('DE-200', 'J2000', 0).tolist()})
    spice.kclear()


def high_precision():
    import mpmath as mp
    mp.mp.dps = 60
    rows = []
    for body in BODIES:
        terms = coefficients(body)
        for jd in dates():
            t = (mp.mpf(str(jd)) - 2451545) / 365250
            values = [mp.fsum(t**p * mp.fsum(mp.mpf(a)*mp.cos(mp.mpf(b)+mp.mpf(c)*t) for a,b,c in ts)
                             for (coord,p),ts in terms.items() if coord == k) for k in (1,2,3)]
            rows.append({'body': body, 'jdTT': jd, 'spherical': [str(v) for v in values]})
    archive('high-precision.json', encoded(rows), {'method': '60 decimal digits; decimal coefficients from original fixed columns; mpmath cos/fsum; direct power series', 'mpmathVersion': mp.__version__, 'epochsSHA256': EPOCH_HASH})


def published_checks():
    data, _ = read_verified('vsop87.chk')
    result = {}
    for body in BODIES:
        pattern = rf'VSOP87B\s+{body.upper()}\s+JD([0-9.]+)[^\n]*\n\s*l\s+([-0-9.]+)\s+rad\s+b\s+([-0-9.]+)\s+rad\s+r\s+([-0-9.]+)\s+au'
        rows = re.findall(pattern, data.decode())
        if len(rows) != 10:
            raise ValueError('published-check coverage mismatch')
        differences = []
        for jd, l, b, r in rows:
            actual = spherical(coefficients(body), float(jd))
            differences.append([abs(math.remainder(actual[0] - float(l), 2*math.pi)), abs(actual[1]-float(b)), abs(actual[2]-float(r))])
        maxima = [max(d[k] for d in differences) for k in range(3)]
        if max(maxima) > 5.1e-11:
            raise ValueError('published VSOP87 check mismatch exceeds printed rounding')
        result[body] = {'sampleCount': len(rows), 'maxLongitudeDifferenceRad': maxima[0], 'maxLatitudeDifferenceRad': maxima[1], 'maxRadiusDifferenceAU': maxima[2]}
    return result


def references():
    de, dr = read_verified('de200-states.json')
    data = json.loads(de)
    if dr['kernelSHA256'] != KERNEL_HASH or dr['epochsSHA256'] != EPOCH_HASH or dr['centerCode'] != 10 or dr['targetCodes'] != [7,8] or dr['nativeFrame'] != 'DE-200 (14)':
        raise ValueError('DE200 reference recipe mismatch')
    if [(r['body'],r['jdTT']) for r in data['rows']] != [(b,jd) for b in BODIES for jd in dates()]:
        raise ValueError('DE200 epoch coverage mismatch')
    result = {b: {'de200': [r for r in data['rows'] if r['body'] == b]} for b in BODIES}
    for body, (_, bary, center) in BODIES.items():
        for label, code, source in [('barycenter', bary, 'DE441'), ('center', center, 'ura184_merged' if body=='Uranus' else 'nep098_merged')]:
            raw, recipe = read_verified(f'{body.lower()}-{label}.horizons.json')
            if recipe['parameters'] != parameters(code) or recipe['epochsSHA256'] != EPOCH_HASH:
                raise ValueError('Horizons recipe mismatch')
            rows, metadata = parse_horizons(raw, recipe['parameters'], source)
            if metadata != recipe['metadata']:
                raise ValueError('Horizons metadata mismatch')
            result[body][label] = rows
    return result


def measure():
    refs = references()
    _, de_recipe = read_verified('de200-states.json')
    de_rotation = de_recipe['de200ToJ2000Rotation']
    header, _ = read_verified('de200-header.txt')
    # Validate the archive's native astronomical unit, not an assumed modern value.
    names = header.decode().split('GROUP   1040')[1].split('GROUP   1041')[0].split()[1:]
    values = header.decode().split('GROUP   1041')[1].split('GROUP   1050')[0].split()[1:]
    if float(values[names.index('AU')].replace('D','E')) != DE200_AU_KM:
        raise ValueError('unexpected DE200 astronomical unit')
    hp, recipe = read_verified('high-precision.json')
    hp_rows = json.loads(hp)
    if recipe['epochsSHA256'] != EPOCH_HASH or [(r['body'],r['jdTT']) for r in hp_rows] != [(b,jd) for b in BODIES for jd in dates()]:
        raise ValueError('high-precision coverage mismatch')
    hp_by = {(r['body'],r['jdTT']): list(map(float,r['spherical'])) for r in hp_rows}
    input_rows = [(b,jd) for b in BODIES for jd in dates()]
    with tempfile.TemporaryDirectory(prefix='outer-planet-local-probe-') as temp:
        binary = Path(temp)/'probe'
        subprocess.run(['cc','-O2','-std=c11','-pthread','-I',str(ROOT/'Sources/CLibAstronomy/include'),str(ROOT/'Scripts/reference-data/distance-probe.c'),*map(str, sorted(p for p in (ROOT/'Sources/CLibAstronomy').rglob('*.c') if p.name != 'astronomy.c')),'-lm','-o',str(binary)],check=True)
        actual = [json.loads(line) for line in subprocess.check_output([str(binary)], input=''.join(f'{b} heliocentric {jd-2451545:.17g}\n' for b,jd in input_rows),text=True).splitlines()]
    if len(actual) != len(input_rows):
        raise ValueError('local probe coverage mismatch')
    local = dict(zip(input_rows,actual))
    rows = []
    for body in BODIES:
        terms = coefficients(body)
        for i,jd in enumerate(dates()):
            raw = spherical(terms,jd)
            p = fk5_vector(raw)
            native = native_de200_vector(raw)
            aligned = [math.fsum(a*b for a,b in zip(matrix_row,native)) for matrix_row in de_rotation]
            old, modern, center = (refs[body][label][i] for label in ('de200','barycenter','center'))
            oldr, modernr, centerr = [math.hypot(*v['positionAU']) for v in (old,modern,center)]
            residual = (raw[2]-modernr)*AU_KM
            model = (raw[2]-oldr)*AU_KM
            evolution = (oldr-modernr)*AU_KM
            rows.append({'body': body, 'jdTT': jd, 'rawRadiusAU': raw[2], 'rawMinusDE200RadiusKm': model,
                         'de200MinusDE441RadiusKm': evolution, 'rawMinusDE441RadiusKm': residual,
                         'radialDecompositionRoundingKm': residual-model-evolution,
                         'rawMinusDE200NativeAURadiusKm': raw[2]*DE200_AU_KM-oldr*AU_KM,
                         'legacyAUScaleContributionKm': raw[2]*(AU_KM-DE200_AU_KM),
                         'rawMinusDE200VectorKm': math.dist(native,old['nativePositionAU'])*AU_KM,
                         'rawDE200AxesMinusDE441ICRFVectorKm': math.dist(aligned,modern['positionAU'])*AU_KM,
                         'rawFK5MinusRawDE200AxesVectorDifferenceKm': math.dist(p,aligned)*AU_KM,
                         'de200AxesMinusDE441ICRFVectorKm': math.dist(old['positionAU'], modern['positionAU'])*AU_KM,
                         'rawFK5MinusDE441ICRFVectorKm': math.dist(p,modern['positionAU'])*AU_KM,
                         'centerSolutionMinusBarycenterRadiusKm': (centerr-modernr)*AU_KM,
                         'centerSolutionMinusBarycenterVectorKm': math.dist(center['positionAU'],modern['positionAU'])*AU_KM,
                         'rawMinusCenterSolutionRadiusKm': (raw[2]-centerr)*AU_KM,
                         'rawMinusLocalRadiusKm': (raw[2]-local[body,jd]['rangeAU'])*AU_KM,
                         'rawFK5MinusLocalVectorKm': math.dist(p,local[body,jd]['positionAU'])*AU_KM,
                         'binary64Minus60DigitRadiusKm': (raw[2]-hp_by[body,jd][2])*AU_KM,
                         'binary64Minus60DigitLongitudeRad': raw[0]-hp_by[body,jd][0],
                         'binary64Minus60DigitLatitudeRad': raw[1]-hp_by[body,jd][1],
                         'de200TDBMinusTTSeconds': old['tdbMinusTTSeconds'],
                         'de200UsingTTAsTDBVectorDifferenceKm': old['usingTTAsTDBVectorDifferenceKm']})
    summaries = {}
    for body in BODIES:
        values = [r for r in rows if r['body']==body]
        summaries[body] = {key: {'maxAbsolute': max(abs(r[key]) for r in values), 'jdTT': max(values,key=lambda r:abs(r[key]))['jdTT']}
                           for key in values[0] if key not in ('body','jdTT','rawRadiusAU')}
    paths = sorted(RAW.glob('*.json')) + [RAW/'de200-header.txt'] + [RAW/'vsop87.chk',RAW/'naif0012.tls',Path(__file__),ROOT/'Scripts/model-data/manifest.json',ROOT/'Scripts/model-data/vsop87.txt',ROOT/'Scripts/reference-data/distance-probe.c']
    paths += [ROOT/f'Scripts/model-data/VSOP87B.{v[0]}' for v in BODIES.values()]
    paths += sorted((ROOT/'Sources/CLibAstronomy').rglob('*.c')) + sorted((ROOT/'Sources/CLibAstronomy').rglob('*.h')) + sorted((ROOT/'Sources/CLibAstronomy').rglob('*.inc'))
    hashes = {str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in paths if p != REPORT}
    return {'schemaVersion':1,'sampleCountPerBody':len(dates()),'purpose':'Model diagnosis only; no acceptance policy or product error limits.',
            'vectorFrameCaveat':'rawMinusDE200VectorKm uses Bretagnon-Francou (1988) eq.1 obliquity and -0.0930 arcsec equinox relation; rawDE200AxesMinusDE441ICRFVectorKm and de200AxesMinusDE441ICRFVectorKm use SPICE DE-200-to-J2000, which is identity and does not establish physical ICRF alignment. These are numerical differences in mixed physical axes, not frame-resolved vector causal attribution. Constants have published finite precision. rawFK5MinusDE441ICRFVectorKm exposes another frame convention. Radial decomposition is rotation invariant.',
            'centerCaveat':'Center and barycenter Horizons requests use separate planetary/satellite fits; returned differences are not isolated satellite-center displacements.',
            'inputSHA256':hashes,'publishedChecks':published_checks(),'summaries':summaries,'rows':rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['fetch-de200','acquire-horizons','extract-de200','high-precision','report','check'])
    args = parser.parse_args()
    if __name__ == "__main__" and args.action == "check":
        source_archive.replay(ROOT, Path(__file__), sys.argv[1:])
        return
    if args.action == 'fetch-de200':
        CACHE.mkdir(parents=True, exist_ok=True)
        url = json.loads((RAW / 'de200.bsp.download.json').read_bytes())['url']
        data = urllib.request.urlopen(url, timeout=120).read()
        if sha(data) != KERNEL_HASH: raise ValueError('downloaded DE200 kernel hash mismatch')
        (CACHE / 'de200.bsp').write_bytes(data)
        print('verified DE200 kernel', KERNEL_HASH)
    elif args.action == 'acquire-horizons': acquire_horizons()
    elif args.action == 'extract-de200': extract_de200()
    elif args.action == 'high-precision': high_precision()
    else:
        report = measure()
        if args.action == 'report': REPORT.write_bytes(encoded(report))
        else:
            previous = json.loads(REPORT.read_bytes())
            if previous['inputSHA256'] != report['inputSHA256']:
                raise ValueError('diagnostic input hashes changed')
            # libm/compiler details can differ; this is a reproduction allowance, not an accuracy budget.
            def compare(old, new, key=''):
                if type(old) is not type(new):
                    raise ValueError(f'diagnostic type changed: {key}')
                if isinstance(old, dict):
                    if old.keys() != new.keys(): raise ValueError(f'diagnostic keys changed: {key}')
                    for k in old: compare(old[k], new[k], f'{key}.{k}')
                elif isinstance(old, list):
                    if len(old) != len(new): raise ValueError(f'diagnostic coverage changed: {key}')
                    for a,b in zip(old,new): compare(a,b,key)
                elif isinstance(old, float):
                    allowance = 2e-12 if any(part.endswith(('Rad','AU')) for part in key.split('.')) else .0001
                    if key.endswith('.jdTT'): allowance = 0.
                    if not math.isfinite(old) or not math.isfinite(new) or abs(old-new) > allowance:
                        raise ValueError(f'nonreproducible diagnostic {key}')
                elif old != new:
                    raise ValueError(f'diagnostic metadata changed: {key}')
            compare(previous,report)
        print(json.dumps(report['summaries'],indent=2,sort_keys=True))
        print('diagnostic',args.action,'complete')


if __name__ == '__main__': main()
