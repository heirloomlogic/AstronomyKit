#!/usr/bin/env python3
"""Native folded lunar coefficient feasibility, without shipping integration."""
import argparse
import importlib.util
import json
import math
import platform
import statistics
import struct
import subprocess
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('candidate',Path(__file__).with_name('probe-lunar-ephemeris-candidate.py'))
C=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(C)
Q=C.Q;G=C.G;ROOT=C.ROOT
PLAN=ROOT/'Documentation/Migration/native-lunar-probe-plan.json'
REPORT=ROOT/'Documentation/Migration/native-lunar-candidate-probe.json'
SOURCE=ROOT/'Tools/Migration/NativeLunarProbe/main.swift'
BINARY=ROOT/'.context/accuracy-qualification/native-lunar-probe'
PAYLOAD=ROOT/'.context/accuracy-qualification/folded-moon-earth.bin'


def export_payload():
    kernel=C.SPK.open(str(C.EXCERPT))
    moon,earth=kernel[3,301],kernel[3,399]
    try:
        a,interval,m=moon.load_array();b,other,e=earth.load_array()
        if (moon.frame,earth.frame,moon.data_type,earth.data_type)!=(1,1,2,2) or a!=b or interval!=other or m.shape!=e.shape:
            raise ValueError('cannot fold detached coefficient grids/frame/type')
        if m.shape[0]!=3: raise ValueError('unexpected coefficient axes')
        lower=max(moon.start_jd,earth.start_jd);upper=min(moon.end_jd,earth.end_jd)
        values=(m-e).transpose(1,0,2).astype('<f8')
        if not G.numpy.isfinite(values).all(): raise ValueError('nonfinite coefficient')
        header=struct.pack('<8sQQdddd',b'MOONDEV1',m.shape[1],m.shape[2],a,interval,lower,upper)
        return header+values.tobytes(),{'startJulianDateTDB':a,'intervalDays':interval,'recordCount':m.shape[1],'coefficientCountPerAxis':m.shape[2],
                                     'lowerJulianDateTDB':lower,'upperJulianDateTDB':upper,'coefficientOrder':'record,axis,ascending degree; little-endian Float64; geometric Moon minus Earth ICRF km'}
    finally: kernel.close()


def parity(metadata,plan):
    requests=[];groups=[]
    def add(a,b,group): requests.append({'tdb1':float(a),'tdb2':float(b)});groups.append(group)
    assessment=json.loads(Q.REPORT.read_bytes());geometry=json.loads(G.REPORT.read_bytes())
    tt=[p['reference']['julianDateTT'] for p in assessment['positions'] if p['body']=='Moon' and p['mode']=='geocentric-none']
    tt += [e['reference']['julianDateTT'] for e in assessment['lunarApsides']]
    tt += [e['reference']['julianDateTT'] for e in geometry['events'] if e['family']=='node']
    for jd in tt:
        offset=jd-2451545.;correction=C.erfa.dtdb(2451545.,offset,0,0,0,0);a,b=C.erfa.tttdb(2451545.,offset,correction)
        add(a,b,'archived lunar case')
    for i in range(metadata['recordCount']+1):
        for fraction,group in [(0,'record boundary'),(.5,'record midpoint')]:
            jd=metadata['startJulianDateTDB']+(i+fraction)*metadata['intervalDays']
            if metadata['lowerJulianDateTDB']<=jd<=metadata['upperJulianDateTDB']: add(2451545.,jd-2451545.,group)
    for key in ['lowerJulianDateTDB','upperJulianDateTDB']: add(2451545.,metadata[key]-2451545.,'excerpt guard')
    encoded=''.join(json.dumps(r,sort_keys=True)+'\n' for r in requests)
    result=subprocess.run([str(BINARY),'states',str(PAYLOAD)],input=encoded,text=True,capture_output=True,check=True)
    rows=[json.loads(line) for line in result.stdout.splitlines()]
    if len(rows)!=len(requests): raise ValueError('native output count detached from requests')
    kernel=C.SPK.open(str(C.KERNEL))
    try:
        first=G.numpy.asarray([r['tdb1'] for r in requests]);second=G.numpy.asarray([r['tdb2'] for r in requests])
        mp,mv=kernel[3,301].compute_and_differentiate(first,second);ep,ev=kernel[3,399].compute_and_differentiate(first,second)
        expected_p=(mp-ep).T;expected_v=(mv-ev).T
    finally: kernel.close()
    summaries={group:{'count':0,'maximumPositionComponentDifferenceKm':0.,'maximumVelocityComponentDifferenceKmPerDay':0.} for group in sorted(set(groups))}
    for request,row,group,p,v in zip(requests,rows,groups,expected_p,expected_v):
        if row.get('request')!=request or 'error' in row: raise ValueError('native request identity/evaluation failed')
        native_p=row.get('positionKm',[]);native_v=row.get('velocityKmPerDay',[])
        if len(native_p)!=3 or len(native_v)!=3 or not all(math.isfinite(x) for x in native_p+native_v): raise ValueError('invalid native state')
        pd=max(abs(float(a)-b) for a,b in zip(p,native_p));vd=max(abs(float(a)-b) for a,b in zip(v,native_v))
        if pd>plan['positionComponentParityLimitKm'] or vd>plan['velocityComponentParityLimitKmPerDay']: raise ValueError(f'native state parity exceeded fixed limit: {pd} km, {vd} km/day')
        summary=summaries[group];summary['count']+=1
        summary['maximumPositionComponentDifferenceKm']=max(summary['maximumPositionComponentDifferenceKm'],pd)
        summary['maximumVelocityComponentDifferenceKmPerDay']=max(summary['maximumVelocityComponentDifferenceKmPerDay'],vd)
    return {'stateCount':len(rows),'groups':summaries,'requestsSHA256':Q.digest(encoded.encode()),'nativeResponsesSHA256':Q.digest(result.stdout.encode()),
            'independentStatesSHA256':Q.digest(expected_p.astype('<f8').tobytes()+expected_v.astype('<f8').tobytes())}


def provenance():
    paths=[PLAN,SOURCE,Path(__file__),C.PLAN,C.REPORT,C.EXCERPT,C.KERNEL,Q.REPORT,G.REPORT]+[Path(module.__file__) for module in (C,G,Q)]
    return {'inputsSHA256':{str(p.relative_to(ROOT)):Q.digest(p.read_bytes()) for p in paths},'executableSHA256':Q.digest(BINARY.read_bytes()),
            'swiftVersion':subprocess.check_output(['swift','--version'],text=True).strip(),'buildCommand':['swiftc','-O',str(SOURCE.relative_to(ROOT)),'-o',str(BINARY.relative_to(ROOT))],
            'platform':platform.platform(),'referenceEnvironment':G.environment(),'jplephemVersion':C.jplephem.__version__}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['report','check']);args=parser.parse_args()
    G.load_plan();G.validate_reference_paths({'jplephem':C.jplephem.__file__})
    if C.jplephem.__version__!='2.24': raise ValueError('unexpected candidate evaluator')
    parent=json.loads(C.REPORT.read_bytes())
    if parent['kernel']['sha256']!=Q.digest(C.KERNEL.read_bytes()) or parent['developmentExcerpt']['sha256']!=Q.digest(C.EXCERPT.read_bytes()):
        raise ValueError('native source kernel/excerpt detached from candidate probe')
    if parent['planSHA256']!=Q.digest(C.PLAN.read_bytes()) or parent['scriptSHA256']!=Q.digest(Path(C.__file__).read_bytes()):
        raise ValueError('native parent probe source/plan drift')
    for name,expected in parent['helperSourceSHA256'].items():
        if Q.digest((ROOT/name).read_bytes())!=expected: raise ValueError('native parent helper source drift')
    if parent['jplephem']['sourceSHA256']!={p.name:Q.digest(p.read_bytes()) for p in sorted(Path(C.jplephem.__file__).parent.glob('*.py'))}:
        raise ValueError('native jplephem source differs from candidate probe')
    plan=json.loads(PLAN.read_bytes());payload,metadata=export_payload()
    if args.action=='report':
        if REPORT.exists(): raise ValueError('native probe report already frozen')
        PAYLOAD.write_bytes(payload)
        subprocess.run(['swiftc','-O',str(SOURCE),'-o',str(BINARY)],check=True)
    elif PAYLOAD.read_bytes()!=payload: raise ValueError('folded coefficient payload drift')
    deterministic={'classification':plan['classification'],'provenance':provenance(),'payload':{'bytes':len(payload),'sha256':Q.digest(payload),**metadata},'parity':parity(metadata,plan)}
    if args.action=='check':
        frozen=json.loads(REPORT.read_bytes())
        if any(frozen.get(k)!=v for k,v in deterministic.items()): raise ValueError('native candidate replay drift')
        print('Native candidate parity replay matched: '+json.dumps(deterministic['parity']['groups'],sort_keys=True));return
    if platform.system()!='Darwin': raise ValueError('frozen performance plan is Darwin-only')
    trials=[]
    for _ in range(plan['performanceTrials']):
        baseline=json.loads(subprocess.check_output([str(BINARY),'baseline'],text=True))
        measured=json.loads(subprocess.check_output([str(BINARY),'benchmark',str(PAYLOAD),str(plan['evaluationsPerTrial'])],text=True))
        if measured['count']!=plan['evaluationsPerTrial'] or not math.isfinite(measured['checksum']): raise ValueError('invalid benchmark output')
        trials.append({'baseline':baseline,'mappedEvaluation':measured,'separateProcessPeakRSSDifferenceBytes':measured['peakRSSBytes']-baseline['peakRSSBytes']})
    report={**deterministic,'performanceTrials':trials,'performanceSummary':{'medianNanosecondsPerState':statistics.median(t['mappedEvaluation']['evaluationNanoseconds']/t['mappedEvaluation']['count'] for t in trials),
            'medianLoadMilliseconds':statistics.median(t['mappedEvaluation']['loadNanoseconds']/1e6 for t in trials),'mappedProcessPeakRSSRangeBytes':[min(t['mappedEvaluation']['peakRSSBytes'] for t in trials),max(t['mappedEvaluation']['peakRSSBytes'] for t in trials)],
            'baselineProcessPeakRSSRangeBytes':[min(t['baseline']['peakRSSBytes'] for t in trials),max(t['baseline']['peakRSSBytes'] for t in trials)],'medianSeparateProcessPeakRSSDifferenceBytes':statistics.median(t['separateProcessPeakRSSDifferenceBytes'] for t in trials)},'limitations':plan['limits']}
    REPORT.write_bytes(Q.encoded(report));print(json.dumps({'payloadBytes':len(payload),'parity':report['parity']['groups'],'performanceSummary':report['performanceSummary']},sort_keys=True))

if __name__=='__main__': main()
