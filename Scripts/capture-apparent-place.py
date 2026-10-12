#!/usr/bin/env python3
"""Capture and replay independent Horizons apparent geocentric/topocentric places."""
import argparse
import concurrent.futures
import csv
import hashlib
import json
import math
from pathlib import Path
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'Scripts/apparent-place-data/horizons'
OUTPUT=ROOT/'Scripts/apparent-place-data/horizons-fixtures.json'
EPOCHS=[2451545.125,2455197.625,2461280.676452762762]
BODIES={'sun':10,'moon':301,'mercury':199,'venus':299,'mars':499,'jupiter':599,
        'saturn':699,'uranus':799,'neptune':899,'pluto':999}
SITE=[-82.55,35.6,0.0]
DISTANCES=ROOT/'Tests/AstronomyKitTests/Fixtures/IndependentReferences/distance-fixtures.json'
RANGE_LIMITS={body:min(row['allowedErrorKm'] for row in json.loads(DISTANCES.read_bytes())['references'] if row['body'].lower()==body and row['mode']=='geocentric') for body in BODIES}


def recipe(body,topocentric):
    parameters={'COMMAND':str(BODIES[body]),'CENTER':'coord@399' if topocentric else '500@399',
                'EPHEM_TYPE':'OBSERVER','MAKE_EPHEM':'YES','OBJ_DATA':'NO','TIME_TYPE':'TT',
                'TLIST':','.join(repr(t) for t in EPOCHS),'TLIST_TYPE':'JD','CAL_FORMAT':'JD',
                'CAL_TYPE':'GREGORIAN','CSV_FORMAT':'YES','ANG_FORMAT':'DEG','EXTRA_PREC':'YES',
                'APPARENT':'AIRLESS','RANGE_UNITS':'AU','QUANTITIES':'1,2,20,30,45'}
    if topocentric:
        parameters.update(COORD_TYPE='GEODETIC',SITE_COORD=','.join(map(str,SITE)))
    return {key:"'"+value+"'" for key,value in parameters.items()}


def case(body,topocentric,fetch):
    key=body+('-topocentric' if topocentric else '-geocentric')
    path=DATA/(key+'.json')
    query=DATA/(key+'.query.json')
    parameters=recipe(body,topocentric)
    if fetch:
        url='https://ssd.jpl.nasa.gov/api/horizons.api?'+urllib.parse.urlencode({'format':'json',**parameters})
        data=urllib.request.urlopen(url,timeout=120).read()
        document=json.loads(data)
        if document.get('error') or '$$SOE' not in document.get('result',''):
            raise ValueError(document)
        path.write_bytes(data)
        query.write_text(json.dumps({'parameters':parameters,'responseSHA256':hashlib.sha256(data).hexdigest()},indent=2,sort_keys=True)+'\n')
    data=path.read_bytes()
    stored=json.loads(query.read_bytes())
    if stored!={'parameters':parameters,'responseSHA256':hashlib.sha256(data).hexdigest()}:
        raise ValueError('Recipe or response changed: '+key)
    text=json.loads(data)['result']
    if f'({BODIES[body]})' not in text.split('Center body name:')[0] or 'Center body name: Earth (399)' not in text:
        raise ValueError('Target or origin changed: '+key)
    if 'Atmos refraction: NO (AIRLESS)' not in text:
        raise ValueError('Apparent convention changed')
    header=next(csv.reader([next(line for line in text.splitlines() if line.startswith('Date_'))]))
    header=[field.strip() for field in header]
    expected=['Date_________JDTT','','','R.A.___(ICRF)','DEC____(ICRF)','R.A.__(a-app)','DEC___(a-app)','delta','deldot','TDB-UT','RA_(ICRF-a-app)','DEC_(ICRF-a-app)','']
    if header!=expected:
        raise ValueError('Unexpected column layout: '+repr(header))
    rows=list(csv.reader(text.split('$$SOE\n')[1].split('$$EOE')[0].splitlines()))
    if len(rows)!=len(EPOCHS):
        raise ValueError('Unexpected epoch count')
    result=[]
    for epoch,row in zip(EPOCHS,rows):
        if not all(math.isfinite(float(row[i])) for i in [0,3,4,5,6,7,8,9,10,11]):
            raise ValueError('Nonfinite source row')
        if abs(float(row[0])-epoch)>1e-8:
            raise ValueError('Epoch changed')
        result.append({'body':body,'target':BODIES[body],'tt':float(row[0])-2451545.,
                       'observer':SITE if topocentric else None,'astrometricICRFDeg':list(map(float,row[3:5])), 'apparentEQDDeg':list(map(float,row[5:7])),
                       'distanceAU':float(row[7]),'tdbMinusUTSeconds':float(row[9]),
                       'apparentICRFDeg':list(map(float,row[10:12])),'angularToleranceArcseconds':2.0 if body in ['uranus','neptune'] else 0.25,
                       'correctionToleranceArcseconds':0.0002, 'rangeToleranceKm':RANGE_LIMITS[body]})
    return key,stored,result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch',action='store_true')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    DATA.mkdir(parents=True,exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(case,body,topocentric,args.fetch) for body in BODIES for topocentric in [False,True]]
        results=[future.result() for future in futures]
    artifact={'schemaVersion':1,'source':'NASA/JPL Horizons observer tables; apparent airless ICRF/EQD; TT input; source TDB-UT retained',
              'scope':'60 fixed modern epochs/sites; this is not an unsampled or full-range accuracy bound',
              'qualification':'Quarter-arcsecond direction gate except Uranus/Neptune at two arcseconds; their selected VSOP astrometric source errors reach 1.45454 arcseconds. A separate 0.0002-arcsecond apparent-minus-astrometric displacement gate isolates angular corrections.',
              'rangeAllowanceSourceSHA256':hashlib.sha256(DISTANCES.read_bytes()).hexdigest(),
              'recipes':{key:stored for key,stored,rows in results},'rows':[row for key,stored,rows in results for row in rows]}
    content=json.dumps(artifact,indent=2,sort_keys=True)+'\n'
    if args.check:
        if OUTPUT.read_text()!=content:
            raise SystemExit('Apparent-place fixtures differ from source replay')
        print('60 apparent-place rows and all response hashes verified')
    else:
        OUTPUT.write_text(content)
        print(OUTPUT)


if __name__=='__main__':
    main()
