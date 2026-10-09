#!/usr/bin/env python3
"""Replay pinned observer-event primary responses; network retrieval is explicit."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/observer-event-data'
FIXTURE = DATA / 'reference-fixtures.json'
EPOCHS = [2415020.5, 2451545., 2459545., 2499391.5]
CASES = [('sun', 10, [-82.55, 35.6, 0.]), ('moon', 301, [-82.55, 35.6, 0.]),
         ('mars', 499, [151.21, -33.87, .058]), ('jupiter', 599, [0., 51.48, .046])]


def read_source(path):
    recipe = json.loads(path.with_suffix('.query.json').read_bytes())
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if recipe['_responseSHA256'] != digest:
        raise ValueError(f'response digest differs: {path}')
    return json.loads(data), recipe


def finite(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError('nonfinite source value')
    return result


def parse_horizons(document, recipe, body, target, site):
    text = document['result']
    if document.get('error') or not re.search(rf'Target body name: .*\({target}\) +\{{source:', text):
        raise ValueError('wrong target or failed response')
    for required in ['Center body name: Earth (399)', 'Center-site name: (user defined site below)',
                     'Atmos refraction: NO (AIRLESS)', 'Center pole/equ : ITRF93']:
        if required not in text:
            raise ValueError('changed observer semantics')
    for key, expected in {'COMMAND': str(target), 'CENTER': 'coord@399', 'TIME_TYPE': 'TT',
                          'QUANTITIES': '2,4,7,20,30,42,45,49', 'APPARENT': 'AIRLESS'}.items():
        if recipe[key] != "'" + expected + "'":
            raise ValueError('changed query convention')
    if [finite(v) for v in recipe['SITE_COORD'].strip("'").split(',')] != site:
        raise ValueError('changed site')
    header = next(line for line in text.splitlines() if line.startswith('Date_'))
    columns = [c.strip() for c in next(csv.reader([header]))]
    expected_header = ['Date_________JDTT', '', '', 'R.A.__(a-app)', 'DEC___(a-app)', 'Azimuth_(a-app)',
                       'Elevation_(a-app)', 'L_Ap_Sid_Time', 'delta', 'deldot', 'TDB-UT',
                       'L_Ap_Hour_Ang', 'RA_(ICRF-a-app)', 'DEC_(ICRF-a-app)', 'UT1-UTC', '']
    if columns != expected_header:
        raise ValueError('changed source column layout')
    rows = list(csv.reader(text.split('$$SOE\n')[1].split('$$EOE')[0].splitlines()))
    if len(rows) != len(EPOCHS):
        raise ValueError('changed source sample count')
    result = []
    for epoch, row in zip(EPOCHS, rows):
        if len(row) != 16 or finite(row[0]) != epoch:
            raise ValueError('changed source epoch or layout')
        values = [finite(row[i]) for i in range(3, 14)]
        dut1 = None if row[14].strip() == 'n.a.' else finite(row[14])
        if (epoch < 2437665.5) != (dut1 is None):
            raise ValueError('unexpected pre-1962 UT1 convention')
        if not (0 <= values[2] < 360 and -90 <= values[3] <= 90 and values[5] > 0 and -12 <= values[8] <= 12):
            raise ValueError('invalid angle or distance')
        result.append(dict(body=body, target=target, tt=epoch-2451545., observer=site,
                           apparentEQDDeg=values[:2], azimuthDegrees=values[2], altitudeDegrees=values[3],
                           localSiderealHours=values[4], distanceAU=values[5], tdbMinusUTSeconds=values[7],
                           hourAngleHours=values[8] % 24, apparentICRFDeg=values[9:11], dut1Seconds=dut1))
    return result


def polar_rows():
    document, recipe = read_source(DATA/'sources/horizons/polar-primary.json')
    text = document['result']
    if recipe['TIME_TYPE'] != "'TT'" or recipe['SITE_COORD'] != "'0,-90,0'" or recipe['COMMAND'] != "'10'":
        raise ValueError('changed polar query')
    if 'Target body name: Sun (10)' not in text or 'Atmos refraction: NO (AIRLESS)' not in text:
        raise ValueError('changed polar source')
    expected = [finite(v) for v in recipe['TLIST'].strip("'").split(',')]
    rows = list(csv.reader(text.split('$$SOE\n')[1].split('$$EOE')[0].splitlines()))
    if len(rows) != 4:
        raise ValueError('changed polar count')
    result = []
    for epoch, row in zip(expected, rows):
        if len(row) != 19 or abs(finite(row[1])-epoch) > 0.0005 / 86400 + math.ulp(epoch):
            raise ValueError('changed polar epoch or columns')
        result.append(dict(tt=finite(row[1])-2451545., altitudeDegrees=finite(row[7]),
                           distanceAU=finite(row[11]), apparentICRFDeg=[finite(row[15]), finite(row[16])]))
    return result


def fixture():
    sources = []
    for path in sorted((DATA/'sources').rglob('*.json')):
        if path.name.endswith('.query.json'):
            continue
        read_source(path)
        sources.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            queryPath=str(path.with_suffix('.query.json').relative_to(ROOT)),
                            querySHA256=hashlib.sha256(path.with_suffix('.query.json').read_bytes()).hexdigest()))
    rows = []
    for body, target, site in CASES:
        document, recipe = read_source(DATA/'sources/horizons'/f'{body}.json')
        rows += parse_horizons(document, recipe, body, target, site)
    semidiameters = []
    for date in ['2000-01-03', '2022-07-04', '2022-09-20']:
        document, _ = read_source(DATA/'sources/usno'/f'usno-sd-{date}.json')
        sun = next(row for row in document['properties']['data'] if row['object'] == 'Sun')
        sd = finite(sun['altitude_corrections']['sd'])
        document, _ = read_source(DATA/'sources/horizons'/f'horizons-sd-{date}.json')
        row = next(csv.reader(document['result'].split('$$SOE\n')[1].split('$$EOE')[0].splitlines()))
        distance = finite(row[3])
        semidiameters.append(dict(date=date, universalTime=date+'T12:00Z', semidiameterDegrees=sd,
                                 distanceAU=distance, inferredRadiusKM=round(math.sin(math.radians(sd))*distance*149597870.7, 6)))
    return dict(schemaVersion=1, angularToleranceArcminutes=1,
                selection='Sixteen frozen source epochs: four bodies, four TT epochs, three geodetic sites. Separate four-point polar diagnostic and three USNO/Horizons semidiameter pairs.',
                timeSemantics='JD TT input. Before 1962 Horizons UT means UT1; later it means UTC and quantity 49 supplies UT1 minus UTC. TT minus UT1 equals quantity 30 minus TDB minus TT minus DUT1. Derived native times retain their captured Delta T model.',
                solarRiseSetRadiusKM=696000, semidiameterComparisonDegrees=0.000001,
                radiusScope='Apparent optical limb in native rise/set only; independent USNO navigation semidiameters support the convention but do not disclose the rise/set service implementation.',
                sources=sources, rows=rows, semidiameters=semidiameters, polar=polar_rows())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args()
    if args.download:
        for path in sorted((DATA/'sources').rglob('*.query.json')):
            recipe = json.loads(path.read_bytes())
            if 'url' in recipe:
                url = recipe['url']
            else:
                url = 'https://ssd.jpl.nasa.gov/api/horizons.api?' + urllib.parse.urlencode(
                    {'format': 'json', **{k: v for k, v in recipe.items() if not k.startswith('_')}})
            data = urllib.request.urlopen(url, timeout=120).read()
            json.loads(data)
            path.with_name(path.name.replace('.query.json', '.json')).write_bytes(data)
            recipe['_responseSHA256'] = hashlib.sha256(data).hexdigest()
            path.write_text(json.dumps(recipe, indent=2)+'\n')
    encoded = (json.dumps(fixture(), indent=2, sort_keys=True, allow_nan=False)+'\n').encode()
    if args.check:
        if FIXTURE.read_bytes() != encoded:
            raise SystemExit('observer-event fixture differs')
    else:
        FIXTURE.write_bytes(encoded)
    print('observer-event primary fixtures verified')


if __name__ == '__main__':
    main()
