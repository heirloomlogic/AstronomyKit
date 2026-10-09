#!/usr/bin/env python3
"""Replay bounded primary local circumstances, preserving publisher UT and fixed Delta T."""
import argparse
import hashlib
import importlib.util
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('global_solar_archive', ROOT/'Scripts/capture-global-solar.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
SOURCE = ROOT/'Scripts/reference-data/sources/local-solar'
OUTPUT = ROOT/'Scripts/eclipse-data/local-references.json'
SOURCES = {
    'rp1301-table8.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/tables/table.8', 'f91dee05f8bd8df4057882897a34698ca1a2d3252f3be6b70aa7517320ebf630'),
    'rp1301-table10.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/tables/table.10', '3a3387559ec9b8a4664c09c1eb62f9d1927018f528ab1fcca388f9d82d7acbdc'),
    'nasa-washington.html': ('https://eclipse.gsfc.nasa.gov/SEcirc/SEcircNA/WashingtonDC1%2B21.html', '27ec610561a7868209b688176ede483dadac543d8d507202f3b6209b1a22af6b'),
    'nasa-local-key.html': ('https://eclipse.gsfc.nasa.gov/SEcirc/SEcirckey.html', 'fbcc4a0e6a17c861791b48aa94b5437e91d29d4c444a0d8132a28b8bba464fff'),
    'nasa-local-model.html': ('https://eclipse.gsfc.nasa.gov/SEcirc/SEpredictions.html', '0b806de9945ae29a8e6217cb59240b36b956a4592a08a3fc24deffc9110ff7f9'),
    'rp1301-footnotes.html': ('https://eclipse.gsfc.nasa.gov/SEpubs/19940510/text/footnotes.html', '2a0e129f092b984d9eadbb96418c2a0a7d62db64f92a71ac932148878d0393dd'),
}
SELECTION = [('rp1301-table8.html', 'MEXICO', 'Acapulco', 16, 51.0, -99, 55.0, 3), ('rp1301-table10.html', 'ILLINOIS', 'Springfield', 39, 48.0, -89, 39.0, 200)]


def recipe(name):
    url, digest = SOURCES[name]
    if name.startswith('nasa-'):
        return {'url':url,'sha256':digest,'method':'GET','publisher':'NASA GSFC','timeScale':'local standard GMT-5','subject':'Washington DC consecutive visible solar eclipses; historical j=2 ephemerides'}
    return {'url': url, 'sha256': digest, 'method': 'GET', 'publisher': 'NASA GSFC', 'report': 'RP1301', 'timeScale': 'UT', 'deltaTSeconds': 59.5, 'ephemeris': 'DE200/LE200', 'date': '1994-05-10'}


def build(blobs, recipes):
    if set(blobs) != set(SOURCES) or set(recipes) != set(SOURCES): raise ValueError('source set')
    for name in SOURCES:
        if recipes[name] != recipe(name) or hashlib.sha256(blobs[name]).hexdigest() != SOURCES[name][1]: raise ValueError('source provenance')
        if name.startswith('nasa-') or name=='rp1301-footnotes.html': continue
        text = shared.text(blobs[name])
        for marker in ['ANNULAR SOLAR ECLIPSE OF 10 MAY 1994', 'U.T.', 'Obs.', 'Latitude Longitude', 'First Contact', 'Fourth Contact']:
            if marker not in text: raise ValueError('local source semantics: '+marker)
    # The already pinned report supplies the time model and both lunar-radius conventions.
    report = shared.build({n:(shared.SOURCE/n).read_bytes() for n in shared.SOURCES}, {n:json.loads((shared.SOURCE/(n+'.query.json')).read_bytes()) for n in shared.SOURCES}, shared.CATALOG.read_bytes())['rp1301']
    rows = []
    for filename, wanted_region, city, latd, latm, lond, lonm, height in SELECTION:
        region = None; maxima = []; contacts = []
        for line in shared.text(blobs[filename]).splitlines():
            stripped = line.strip()
            if re.fullmatch('[A-Z ]+', stripped): region = stripped
            if region != wanted_region or not line.startswith(city+' '): continue
            rest = line[len(city):].strip()
            if re.match(r'\d\d:\d\d:', rest): contacts.append(rest)
            else: maxima.append(rest)
        if len(maxima) != 1 or len(contacts) != 1: raise ValueError('missing/duplicate selected location')
        match = re.fullmatch(r'(\d+)\s+([\d.]+)\s+(-\d+)-([\d.]+)\s+(\d+)\s+(\d\d:\d\d:\d\d\.\d)\s+(.+)', maxima[0])
        if not match: raise ValueError('maximum row')
        fields = match.groups()
        if tuple(map(float, fields[:5])) != (latd, latm, lond, lonm, height): raise ValueError('site identity')
        tail = fields[6].split()
        if len(tail) not in (6,9): raise ValueError('maximum columns')
        groups = re.findall(r'(\d\d:\d\d:\d\d\.\d)\s+(-?\d+)\s+\d+\s+\d+', contacts[0])
        if len(groups) not in (2,4) or (len(groups)==4) != (len(tail)==9): raise ValueError('contact/central relation')
        names = ['partialBegin','partialEnd'] if len(groups)==2 else ['partialBegin','totalBegin','totalEnd','partialEnd']
        def epoch(clock):
            return shared.tt('1994-05-10T'+clock)
        values = [{'name':name, 'ut':epoch(clock), 'tt':epoch(clock)+report['deltaTSeconds']/86400, 'altitude':float(alt)} for name,(clock,alt) in zip(names,groups)]
        peak = epoch(fields[5]); altitude = float(tail[-6])
        values.append({'name':'peak','ut':peak,'tt':peak+report['deltaTSeconds']/86400,'altitude':altitude})
        values.sort(key=lambda r:r['ut'])
        area=float(tail[-1]); magnitude=float(tail[-2])
        if not 0 < area < 1 or not 0 < magnitude < 1: raise ValueError('area/diameter fraction')
        rows.append({'id':city+', '+wanted_region, 'source':filename,'latitude':latd+latm/60,'longitude':lond-lonm/60,'heightMeters':height,'kind':'annular' if len(groups)==4 else 'partial','contacts':values,'obscuration':area,'lower':area-0.0005,'upper':area+0.0005,'diameterMagnitude':magnitude,'timeToleranceSeconds':60,'altitudeToleranceDegrees':0.5})
    footnotes=re.sub(r'-\s+', '-', ' '.join(shared.text(blobs['rp1301-footnotes.html']).split()))
    if "For partial eclipses, maximum eclipse is the instant when the greatest fraction of the Sun's diameter is occulted." not in footnotes or 'maximum eclipse is the instant of mid-totality or mid-annularity.' not in footnotes:raise ValueError('local maximum definition')
    catalog=shared.text(blobs['nasa-washington.html'])
    normalized=' '.join(catalog.split())
    for marker in ["38°53.0'N", "077°02.0'W", 'every solar eclipse visible from', '(= GMT - 5.0)', 'Local Standard Time']:
        if marker not in normalized: raise ValueError('sequence convention: '+marker)
    model=shared.text(blobs['nasa-local-model.html'])
    for marker in ['Newcomb, 1895', 'Brown, 1919', 'Eckert, Jones and Clark, 1954', '0.272281']:
        if marker not in model: raise ValueError('sequence model')
    key=shared.text(blobs['nasa-local-key.html'])
    for marker in ['partial', 'obscuration']:
        if marker not in key: raise ValueError('sequence key')
    lines=[line.split() for line in catalog.splitlines() if re.match(r'\s*\d{4}\s+\w{3}\s+\d{2}\s+[PATH]:',line)]
    first=[i for i,row in enumerate(lines) if row[:3]==['2026','Aug','12']]
    if len(first)!=1: raise ValueError('sequence first identity')
    pair=lines[first[0]:first[0]+2]
    if len(pair)!=2 or pair[1][:3]!=['2028','Jan','26']: raise ValueError('sequence adjacency')
    sequence=[]
    for fields,date,path in zip(pair,['2026-08-12','2028-01-26'],['T:p','A:p']):
        if fields[3]!=path or fields[-1]!='partial' or any(not re.fullmatch(r'\d\d:\d\d',v) for v in fields[4:7]): raise ValueError('sequence local type/visibility')
        contacts={name:shared.tt(date+'T'+clock+':00')+5/24 for name,clock in zip(['partialBegin','peak','partialEnd'],fields[4:7])}
        sequence.append({'date':date,'pathType':path,'localKind':'partial','gmtCalendarDays':contacts,'sourceLocalClocks':fields[4:7],'altitude':float(fields[7]),'obscuration':float(fields[10])})
    return {'maximumDefinition':{'source':'rp1301-footnotes.html','partial':'greatest occulted solar diameter fraction','central':'mid-totality or mid-annularity'},'sequence':{'latitude':38+53/60,'longitude':-77-2/60,'heightMeters':None,'localStandardOffsetHours':-5,'events':sequence,'scope':'Consecutive visible-event identities only. Historical model and minute/GMT labels; no row-specific Delta T, elevation, refraction or timing uncertainty supplied. Tests use zero elevation explicitly, not as a source assertion.'},'schemaVersion':1, 'events':rows,'timeScale':'UT','deltaTSeconds':report['deltaTSeconds'],'ephemeris':report['model'],'k1':report['k1'],'k2':report['k2'],'rounding':'Area intervals conditionally assume nearest 0.001 printing; no publisher rounding rule or uncertainty is asserted. They are source-print intervals, not an implementation tolerance.','sourceHashes':{n:SOURCES[n][1] for n in SOURCES}}


def refresh(download=urllib.request.urlopen, source=SOURCE, output=OUTPUT):
    blobs={n:download(url,timeout=60).read() for n,(url,_) in SOURCES.items()}
    recipes={n:recipe(n) for n in SOURCES}
    result=build(blobs,recipes)
    files={source/n:b for n,b in blobs.items()}
    files.update({source/(n+'.query.json'):shared.encoded(r) for n,r in recipes.items()})
    files[output]=shared.encoded(result)
    shared.publish(files)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--download',action='store_true');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if args.download:
        if args.check:parser.error('download and check are exclusive')
        refresh()
    else:
        result=shared.encoded(build({n:(SOURCE/n).read_bytes() for n in SOURCES},{n:json.loads((SOURCE/(n+'.query.json')).read_bytes()) for n in SOURCES}))
        if args.check:
            if OUTPUT.read_bytes()!=result:raise SystemExit('local references stale')
        else:shared.publish({OUTPUT:result})
    print('local solar archives and references match')

if __name__=='__main__': main()
