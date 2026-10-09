#!/usr/bin/env python3
"""Archive independent body-center range-rate windows around the native event candidates."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DATA=ROOT/'Scripts/reference-data/sources/planetary-apsides'
OUTPUT=ROOT/'Scripts/reference-data/planetary-apsis-evidence.json'
SPEC=importlib.util.spec_from_file_location('references',Path(__file__).with_name('build-fixtures.py'))
f=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(f)
# Native predictions from a fixed 2025-01-01 start, frozen before publisher retrieval.
CASES=[('mercury',199,2460695.0845825057,'apocenter'),('venus',299,2460726.3289744984,'pericenter'),
       ('earth',399,2460680.0618358366,'pericenter'),('mars',499,2460782.4260232407,'apocenter'),
       ('jupiter',599,2462133.6140703936,'apocenter'),('uranus',799,2470035.695252181,'pericenter'),
       ('neptune',899,2467133.4450413701,'pericenter'),('pluto',999,2493228.9711945844,'apocenter')]

SOURCES = {199: 'DE441', 299: 'DE441', 399: 'DE441', 499: 'mar099', 599: 'jup365_merged', 799: 'ura184_merged', 899: 'nep098_merged', 999: 'plu060_merged'}


def query(target,epoch):
    q=f.vector_query(str(target),'500@10',[round(epoch-4+i/8,9) for i in range(65)])
    q.update({k:f.quoted(v) for k,v in dict(TIME_TYPE='TT',TLIST_TYPE='JD',VEC_TABLE='3').items()})
    return q


def parse_vectors(target,dates,raw):
    f.validate_horizons_response(str(target),raw)
    text=json.loads(raw)['result']
    header=next(line for line in text.splitlines() if line.startswith('Target body name:'))
    required=['Center body name: Sun (10)','Output units    : AU-D','Reference frame : ICRF','JDTT','Output type     : GEOMETRIC cartesian states']
    if f'({target})' not in header or f'{{source: {SOURCES[target]}}}' not in header or any(value not in text for value in required):raise ValueError('unexpected planetary vector semantics')
    lines=text.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines()
    if len(lines)!=len(dates):raise ValueError('missing planetary samples')
    rows=[]
    for expected,line in zip(dates,lines):
        fields=line.split(',');jd=float(fields[0]);rate=float(fields[10])
        if not math.isfinite(rate) or abs(jd-expected)>1e-9:raise ValueError('changed epoch or nonfinite rate')
        rows.append(dict(jdtt=jd,rateAUPerDay=rate))
    return header,rows


def parse(target,epoch,raw):
    header,rows=parse_vectors(target,[round(epoch-4+i/8,9) for i in range(65)],raw)
    crossings=[]
    for a,b in zip(rows,rows[1:]):
        if a['rateAUPerDay']*b['rateAUPerDay']<0:
            crossings.append(dict(lowerJDTT=a['jdtt'],upperJDTT=b['jdtt'],kind='pericenter' if a['rateAUPerDay']<0 else 'apocenter'))
    return header,rows,crossings


def refine(body,target,epoch,crossings,capture):
    path=DATA/f'{body}-refinement.json'
    transcript=[] if capture else json.loads(path.read_bytes())
    brackets=[dict(row) for row in crossings]
    used=0
    while any((r['upperJDTT']-r['lowerJDTT'])*86400>1 for r in brackets):
        if used>=15:raise ValueError('source refinement did not converge')
        dates=[round((r['lowerJDTT']+r['upperJDTT'])/2,9) for r in brackets]
        q=query(target,epoch);q['TLIST']=f.quoted(','.join(str(d) for d in dates))
        if capture:
            raw=f.download(f.horizons_url(q))
            transcript.append(dict(query=q,response=raw.decode('utf-8'),sha256=hashlib.sha256(raw).hexdigest()))
        else:
            item=transcript[used]
            if item['query']!=q:raise ValueError('refinement query changed')
            raw=item['response'].encode('utf-8')
            if hashlib.sha256(raw).hexdigest()!=item['sha256']:raise ValueError('refinement source digest changed')
        _,rows=parse_vectors(target,dates,raw)
        for bracket,row in zip(brackets,rows):
            if (row['rateAUPerDay']<0)==(bracket['kind']=='pericenter'):
                bracket['lowerJDTT']=row['jdtt']
            else:bracket['upperJDTT']=row['jdtt']
        used+=1
    if used!=len(transcript):raise ValueError('extra refinement response')
    if capture:path.write_text(json.dumps(transcript,indent=2,sort_keys=True)+'\n')
    return brackets,hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--capture',action='store_true');parser.add_argument('--check',action='store_true');parser.add_argument('--refine',action='store_true');args=parser.parse_args()
    if sum([args.capture,args.check,args.refine])>1:parser.error('capture, refine and check are mutually exclusive')
    DATA.mkdir(parents=True,exist_ok=True)
    def one(case):
        body,target,epoch,kind=case;q=query(target,epoch);path=DATA/f'{body}.json'
        if args.capture:path.write_bytes(f.download(f.horizons_url(q)))
        raw=path.read_bytes();header,rows,crossings=parse(target,epoch,raw)
        roots,refinement_sha=refine(body,target,epoch,crossings,args.capture or args.refine)
        return dict(body=body,target=target,nativeCandidateJDTT=epoch,nativeKind=kind,targetHeader=header,query=q,url=f.horizons_url(q),responseSHA256=hashlib.sha256(raw).hexdigest(),samples=rows,crossings=crossings,roots=roots,refinementSHA256=refinement_sha)
    with ThreadPoolExecutor(max_workers=2) as pool:cases=list(pool.map(one,CASES))
    result=dict(schemaVersion=1,selection='Diagnostic windows centered on frozen native candidates from 2025-01-01; independent source values, not independent epoch selection or a complete event census.',definition='Geometric physical planet center relative to Sun center; JD TT, ICRF, AU/day range rate.',cases=cases)
    encoded=json.dumps(result,indent=2,sort_keys=True)+'\n'
    if args.check:
        if OUTPUT.read_text()!=encoded:raise SystemExit('planetary identity evidence differs')
    else:OUTPUT.write_text(encoded)
    print([(c['body'],len(c['crossings'])) for c in cases])

if __name__=='__main__':main()
