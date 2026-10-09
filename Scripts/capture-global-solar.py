#!/usr/bin/env python3
"""Build pinned global-solar references; stage and validate all downloads before publication."""
import argparse
import datetime
import hashlib
import html
import json
import os
import shutil
import tempfile
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/eclipse-data'
SOURCE = ROOT / 'Scripts/reference-data/sources/global-solar'
OUTPUT = DATA / 'global-references.json'
SOURCES = {
    'rp1301-table1.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/tables/table.1', 'a9952d45c37aea7207fffbc60a799e3f9488830f754fc72fb0b869c0a7fe6213', 'TDT'),
    'rp1301-table4.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/tables/table.4', '0b6c2c938b181a85c457bafd7bd442115ef93a620021589f76a8f12a94ae9e28', 'UT'),
    'rp1301-parameters.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/text/ephemerides.html', '2d34652d03f95e0ec8c4d0fff292f0b8ab3527044005acbadac70a0b0f0eb7c5', 'TDT'),
    'rp1301-lunar-radius.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/text/mean-lunar-radius.html', 'feb45fb0f1951dd587e72060d1d4bf0998816ab4b0c7ca8013d6f44ccad1b956', 'geometry'),
    'nasa-solar-1901.html': ('https://eclipse.gsfc.nasa.gov/SEcat5/SE1901-2000.html', '1daf90d8b3f1763a09b45cc0d838150fc09edbef711fe1be80f2e0c0d8f6d5ff', 'TD'),
    'nasa-jsex-program.js': ('https://eclipse.gsfc.nasa.gov/JSEX/program.js', '9676f7922ced83c47fc088af5b8f53f7f51cc13563e527ee53910c54ed61c881', 'algorithm'),
    'COPYING.GPL-2.0': ('https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt', 'edaef632cbb643e4e7a221717a6c441a4c1a7c918e6e4d56debc3d8739b233f6', 'not applicable'),
}
CATALOG = ROOT / 'Scripts/reference-data/sources/solar_2001.html'
CATALOG_HASH = '820b7a9e4a04881ff212ee59603f03fb3ebdcb72e340414494b1fb84271efc9d'


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()


def recipe(name):
    url, sha, scale = SOURCES[name]
    publisher, subject = ('Free Software Foundation', 'GNU General Public License version 2') if name == 'COPYING.GPL-2.0' else ('NASA GSFC', 'solar eclipses')
    return {'url': url, 'sha256': sha, 'timeScale': scale, 'publisher': publisher, 'subject': subject, 'method': 'GET'}


def text(data):
    return html.unescape(re.sub('<[^>]+>', '', data.decode('latin1')))


def tt(date):
    return (datetime.datetime.fromisoformat(date) - datetime.datetime(2000, 1, 1, 12)).total_seconds() / 86400


def build(blobs, recipes, catalog):
    if set(blobs) != set(SOURCES) or set(recipes) != set(SOURCES):
        raise ValueError('incomplete source set')
    for name in SOURCES:
        if recipes[name] != recipe(name) or hashlib.sha256(blobs[name]).hexdigest() != SOURCES[name][1]:
            raise ValueError('source recipe or digest mismatch: ' + name)
    if hashlib.sha256(catalog).hexdigest() != CATALOG_HASH:
        raise ValueError('catalog digest mismatch')
    table1, table4 = text(blobs['rp1301-table1.html']), text(blobs['rp1301-table4.html'])
    method = blobs['nasa-jsex-program.js'].decode('utf-8')
    method_markers = ['GNU General Public License', 'either version 2', 'any later version.', 'circumstances[28] = circumstances[8] - circumstances[21] * elements[26+index]', 'circumstances[29] = circumstances[9] - circumstances[21] * elements[27+index]', 'mid[38] = (mid[28] - mid[29]) / (mid[28] + mid[29])', 'tmp=Math.atan(0.99664719*Math.tan(obsvconst[0]))']
    if any(marker not in method for marker in method_markers):
        raise ValueError('NASA JSEX method semantics missing')
    license_text = blobs['COPYING.GPL-2.0'].decode('utf-8')
    license_markers = ['GNU GENERAL PUBLIC LICENSE', 'Version 2, June 1991', 'Everyone is permitted to copy and distribute verbatim copies', 'changing it is not allowed.', 'END OF TERMS AND CONDITIONS']
    if any(marker not in license_text for marker in license_markers):
        raise ValueError('GNU GPL version 2 license text missing')
    for marker in ['2449483.216973', '0.94314', '0.2725076', '0.2722810', '59.5', 'DE200/LE200', 'Terrestrial Dynamical Time']:
        if marker not in table1:
            raise ValueError('RP1301 semantics missing: ' + marker)
    greatest = re.findall(r'Instant of\s+(\d+):(\d+):([\d.]+) TDT', table1)
    origin = re.findall(r'Polynomial Besselian Elements for:.*?(\d+):(\d+):([\d.]+) TDT', table1)
    slopes = re.findall(r'Tan \S*1 = ([\d.]+)\s+Tan \S*2 = ([\d.]+)', table1)
    source_magnitude = re.findall(r'(Eclipse Magnitude) = ([\d.]+)', table1)
    if len(greatest) != 1 or len(origin) != 1 or len(slopes) != 1 or source_magnitude != [('Eclipse Magnitude','0.94314')]:
        raise ValueError('RP1301 greatest-eclipse metadata missing or duplicated')
    decimal_hour = lambda clock: int(clock[0])+int(clock[1])/60+float(clock[2])/3600
    element_rows = re.findall(r'^\s*([0-3])\s+([\-\d.]+)\s+([\-\d.]+)(?:\s+([\-\d.]+)\s+([\-\d.]+)\s+([\-\d.]+)\s+([\-\d.]+))?\s*$', table1, re.M)
    if len(element_rows) != 4:
        raise ValueError('RP1301 Besselian element rows missing or duplicated')
    besselian = {'t0TDT': decimal_hour(origin[0]), 'greatestTDT': decimal_hour(greatest[0]), 'tanF1': float(slopes[0][0]), 'tanF2': float(slopes[0][1]),
                 'coefficients': {key: [] for key in ['x','y','d','l1','l2']}}
    for row in element_rows:
        values = [float(value) for value in row[1:] if value]
        for key, value in zip(['x','y','d','l1','l2'], values):
            besselian['coefficients'][key].append(value)
    if [len(besselian['coefficients'][key]) for key in ['x','y','d','l1','l2']] != [4,4,3,3,3]:
        raise ValueError('unexpected RP1301 Besselian polynomial degrees')
    wanted = {'2014-04-29': 'annular', '2043-04-09': 'total', '2023-04-20': 'total', '2025-03-29': 'partial'}
    months = dict(zip('Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(), range(1, 13)))
    rows = []
    pattern = re.compile(r'^\s*\d+\s+(\d{4})\s+(\w{3})\s+(\d{2})\s+(\d\d:\d\d:\d\d)\s+(-?\d+)\s+\S+\s+\d+\s+([PATH][+\-]?)\s+([\-+\d.]+)\s+(\d+\.\d+)\s+([\d.]+)([NS])\s+([\d.]+)([EW])')
    for line in text(catalog).splitlines():
        match = pattern.match(line)
        if not match: continue
        year, month, day, clock, delta, path, gamma, magnitude, lat, ns, lon, ew = match.groups()
        date = f'{year}-{months[month]:02d}-{day}'
        if date not in wanted: continue
        rows.append({'date': date, 'tt': tt(date+'T'+clock), 'pathType': path, 'kindAtPeak': wanted[date], 'gammaEarthRadii': float(gamma), 'magnitude': float(magnitude), 'latitude': float(lat)*(1 if ns=='N' else -1), 'longitude': float(lon)*(1 if ew=='E' else -1), 'catalogDeltaTSeconds': int(delta), 'timeToleranceSeconds': 453.6, 'locationToleranceDegrees': 0.247})
    if len(rows) != len(wanted) or {x['date'] for x in rows} != set(wanted):
        raise ValueError('missing or duplicate catalog event')
    if next(x for x in rows if x['date']=='2023-04-20')['magnitude'] <= 1:
        raise ValueError('hybrid peak kind not supported')
    area = []
    for minute in [10, 15]:
        matches = re.findall(rf'^\s*17:{minute}\s+(.+)$', table4, re.M)
        if len(matches) != 1: raise ValueError('missing/duplicate Table 4 sample')
        fields = matches[0].split()
        ratio, fraction = float(fields[3]), float(fields[4])
        if ratio != 0.9431 or fraction != 0.8895: raise ValueError('unexpected Table 4 source fields')
        epoch = tt(f'1994-05-10T17:{minute}:00')
        area.append({'ut': epoch, 'tt': epoch+59.5/86400, 'diameterRatio': ratio, 'obscuration': fraction, 'lower': fraction-0.00005, 'upper': fraction+0.00005})
    boundary_lines = [line for line in text(blobs['nasa-solar-1901.html']).splitlines()
                      if re.match(r'^\s*\d+\s+1986\s+Oct\s+03\s+', line)]
    if len(boundary_lines) != 1: raise ValueError('missing or duplicate 1986 catalog row')
    fields = boundary_lines[0].split()
    if len(fields) != 17 or fields[4] != '19:06:15' or fields[8] != 'H' or fields[11] != '1.0000':
        raise ValueError('1986 catalog semantics')
    prose = ' '.join(text(blobs['rp1301-lunar-radius.html']).split())
    claims = re.findall(r'eclipse of 3 October 1986\. The Astronomical Almanac identified this event as a total eclipse of 3 seconds duration when in it was in fact a (beaded annular) eclipse\.', prose)
    if claims != ['beaded annular']: raise ValueError('1986 observed limb semantics')
    boundary = {'date': '1986-10-03', 'tt': tt('1986-10-03T'+fields[4]), 'timeScale': 'TD',
                'catalogSource': 'nasa-solar-1901.html', 'pathType': fields[8],
                'printedMagnitude': fields[11], 'magnitude': float(fields[11]),
                'observedLimbKind': claims[0], 'limbSource': 'rp1301-lunar-radius.html'}
    method_source = {'source': 'nasa-jsex-program.js', 'url': SOURCES['nasa-jsex-program.js'][0], 'sha256': SOURCES['nasa-jsex-program.js'][1], 'license': 'GNU GPL version 2 or later', 'licenseSource': 'COPYING.GPL-2.0', 'licenseURL': SOURCES['COPYING.GPL-2.0'][0], 'licenseSHA256': SOURCES['COPYING.GPL-2.0'][1], 'earthPolarToEquatorialRatio': 0.99664719, 'relation': "L'=l-zeta*tan(f); central Moon/Sun ratio=(L1'-L2')/(L1'+L2')"}
    return {'schemaVersion': 1, 'boundary1986': boundary, 'events': rows, 'rp1301': {'greatestTT': 2449483.216973-2451545, 'deltaTSeconds': 59.5, 'model': 'DE200/LE200', 'k1': 0.2725076, 'k2': 0.272281, 'greatestLabel': source_magnitude[0][0], 'greatestMagnitude': float(source_magnitude[0][1]), 'ratioLower': 0.943135, 'ratioUpper': 0.943145, 'sunGeocentricSemidiameterArcseconds': 950.22, 'moonK1GeocentricSemidiameterArcseconds': 884.08, 'moonParallaxArcseconds': 3244.35, 'besselian': besselian, 'methodSource': method_source, 'samples': area}, 'rounding': 'conditional nearest-print intervals; no publisher rounding rule or uncertainty asserted', 'sourceHashes': {**{name: SOURCES[name][1] for name in SOURCES}, 'solar_2001.html': CATALOG_HASH}}


def publish(files):
    """Stage a complete set and restore prior files after an ordinary publication error.

    This is not cross-file crash atomicity. If rollback itself fails, retain the
    staged backups and report their directory for recovery.
    """
    files = {Path(path): data for path, data in files.items()}
    for path in files: path.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.global-solar-publish-', dir=os.path.commonpath([p.parent for p in files])))
    previous = {}; pending = {}; published = []; retain = False
    try:
        for index, (path, data) in enumerate(files.items()):
            pending[path] = stage/f'new-{index}'
            pending[path].write_bytes(data)
            previous[path] = stage/f'old-{index}' if path.exists() else None
            if previous[path] is not None: previous[path].write_bytes(path.read_bytes())
        try:
            for path in files:
                os.replace(pending[path], path)
                published.append(path)
        except Exception as error:
            failures = []
            for path in reversed(published):
                try:
                    if previous[path] is None: path.unlink()
                    else: os.replace(previous[path], path)
                except Exception as rollback_error: failures.append(str(rollback_error))
            if failures:
                retain = True
                raise RuntimeError(f'publication failed; rollback incomplete; backups retained at {stage}: {failures}') from error
            raise
    finally:
        if not retain: shutil.rmtree(stage)


def refresh(download=urllib.request.urlopen, source=SOURCE, output=OUTPUT):
    # Complete retrieval and semantic validation precede any canonical write.
    blobs = {name: download(url, timeout=60).read() for name, (url, _, _) in SOURCES.items()}
    recipes = {name: recipe(name) for name in SOURCES}
    result = build(blobs, recipes, CATALOG.read_bytes())
    files = {source/name: data for name, data in blobs.items()}
    files.update({source/(name+'.query.json'): encoded(value) for name,value in recipes.items()})
    files[output] = encoded(result)
    publish(files)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.download:
        if args.check: parser.error('download and check are exclusive')
        refresh()
    else:
        blobs = {name: (SOURCE/name).read_bytes() for name in SOURCES}
        recipes = {name: json.loads((SOURCE/(name+'.query.json')).read_bytes()) for name in SOURCES}
        result = encoded(build(blobs, recipes, CATALOG.read_bytes()))
        if args.check:
            if OUTPUT.read_bytes()!=result: raise SystemExit('global references are stale')
        else: publish({OUTPUT: result})
    print('global solar archives and references match')

if __name__ == '__main__': main()
