#!/usr/bin/env python3
"""Fresh finite lunar candidate holdout with native TT/frame/event evaluation."""
import argparse
import importlib.util
import json
import math
import random
import statistics
import subprocess
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('geometry',Path(__file__).with_name('qualify-geometric-events.py'))
G=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(G)
Q=G.Q;ROOT=Q.ROOT
PLAN=ROOT/'Documentation/Migration/lunar-candidate-holdout-plan.json'
REPORT=ROOT/'Documentation/Migration/lunar-candidate-holdout-assessment.json'
RAW=ROOT/'Scripts/reference-data/sources/lunar-candidate-holdout'
BUILD=ROOT/'.context/accuracy-qualification/integrated-lunar'
BINARY=BUILD/'probe'
PAYLOAD=ROOT/'.context/accuracy-qualification/folded-moon-earth.bin'
KERNEL=ROOT/'.context/accuracy-qualification/de440s.bsp'
AU_KM=149597870.7


def validate_plan(plan):
    if plan['policySHA256']!=Q.digest(Q.POLICY.read_bytes()): raise ValueError('holdout owner policy drift')
    if plan['candidateKernelSHA256']!=Q.digest(KERNEL.read_bytes()) or plan['candidatePayloadSHA256']!=Q.digest(PAYLOAD.read_bytes()): raise ValueError('holdout candidate drift')
    if plan['domain']!={'startInclusiveJulianDateTT':2415020.5,'stopExclusiveJulianDateTT':2499391.5,'timeScale':'TT'}: raise ValueError('holdout domain mismatch')
    if plan['reference']!={'target':'301','center':'399','frame':'ICRF','correction':'NONE','units':'AU-D','timeScale':'TT'}: raise ValueError('holdout reference convention mismatch')
    if plan['coarseStepDays']!=1/24 or plan['referenceNumericalAllowanceSeconds']!=1. or plan['nativeRootMaximumBracketWidthSeconds']!=.0005: raise ValueError('holdout controls drift')
    for name,expected in plan['excludedSourcesSHA256'].items():
        if Q.digest((ROOT/name).read_bytes())!=expected: raise ValueError('holdout exclusion source drift')
    expected_sources={'Documentation/Migration/'+name for name in ['approved-accuracy-targets.json','position-event-sampling-plan.json','geometric-event-sampling-plan.json','position-event-assessment.json','geometric-event-assessment.json','distance-characterization.json','distance-acceptance.json','approved-distance-retrospective.json','polar-reference-comparison.json']}
    if set(plan['excludedSourcesSHA256'])!=expected_sources: raise ValueError('holdout exclusion source population drift')
    known=set()
    def collect(value):
        if isinstance(value,dict):
            for key,item in value.items():
                if key=='julianDateTT' and isinstance(item,(int,float)): known.add(round(item,8))
                elif key=='julianDatesTT' and isinstance(item,list): known.update(round(x,8) for x in item)
                else: collect(item)
        elif isinstance(value,list):
            for item in value: collect(item)
    for name in expected_sources: collect(json.loads((ROOT/name).read_bytes()))
    if plan['excludedIndependentEpochsJulianDateTT']!=sorted(known) or plan['excludedLunarWindows']!=Q.load_plan()['eventWindows']:
        raise ValueError('holdout exclusion catalog detached from source content')
    old=[(w['startJulianDateTT'],w['startJulianDateTT']+w['durationDays']) for w in plan['excludedLunarWindows']]
    excluded=set(plan['excludedIndependentEpochsJulianDateTT']);dates=plan['positionJulianDatesTT'];windows=plan['eventWindows']
    if len(dates)!=128 or len(set(dates))!=128 or dates!=sorted(dates) or len(windows)!=12 or len({w['id'] for w in windows})!=12: raise ValueError('holdout population mismatch')
    seen=[]
    for w in windows:
        a=w['startJulianDateTT'];b=a+w['durationDays']
        if w['durationDays']!=31 or not 2415020.5<=a<b<2499391.5 or any(a<y and b>x for x,y in old+seen) or any(a<=x<=b for x in excluded): raise ValueError('holdout window is not fresh/disjoint')
        seen.append((a,b))
    if any(not 2415020.5<=jd<2499391.5 or jd in excluded or any(a<=jd<=b for a,b in old+seen) for jd in dates): raise ValueError('holdout epochs are not fresh/disjoint')
    if plan['positionSeed']!=823001 or plan['windowSeed']!=823002: raise ValueError('holdout seed drift')
    start,stop=2415020.5,2499391.5;rng=random.Random(plan['windowSeed']);expected_windows=[]
    for i in range(12):
        a=start+i*(stop-start)/12;b=start+(i+1)*(stop-start)/12
        for _ in range(10000):
            candidate=round(rng.uniform(a,b-31),8)
            if any(candidate<y and candidate+31>x for x,y in old) or any(candidate<=x<=candidate+31 for x in excluded): continue
            expected_windows.append({'id':f'fresh-{i:02d}','startJulianDateTT':candidate,'durationDays':31});break
        else: raise ValueError('holdout window generation exhausted')
    rng=random.Random(plan['positionSeed']);expected_dates=[]
    for i in range(128):
        for _ in range(10000):
            jd=round(start+(i+rng.random())*(stop-start)/128,8)
            if jd in excluded or any(x<=jd<=y for x,y in old+seen): continue
            expected_dates.append(jd);break
        else: raise ValueError('holdout date generation exhausted')
    if windows!=expected_windows or dates!=sorted(expected_dates): raise ValueError('holdout population detached from frozen seeded selection')
    return plan


def load_plan(): return validate_plan(json.loads(PLAN.read_bytes()))


def pair(name,recipe,acquire=False):
    file=RAW/(name+'.json');query=RAW/(name+'.query.json')
    if acquire and not file.exists() and not query.exists():
        data=Q.download(recipe);RAW.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
        query.write_bytes(Q.encoded({'parameters':recipe,'responseSHA256':Q.digest(data),'planSHA256':Q.digest(PLAN.read_bytes())}))
    saved=json.loads(query.read_bytes());data=file.read_bytes()
    if saved['parameters']!=recipe or saved['responseSHA256']!=Q.digest(data) or saved['planSHA256']!=Q.digest(PLAN.read_bytes()): raise ValueError('detached holdout response/query/plan')
    return Q.parse_response(data,recipe)


def references(window,plan,acquire=False):
    prefix=window['id'];dates=[round(window['startJulianDateTT']+i*plan['coarseStepDays'],8) for i in range(31*24+1)]
    rows,meta=pair(prefix+'-coarse',Q.parameters('301','399','NONE',dates),acquire);output={};provenance={'coarse':meta}
    for family in ['apsis','node']:
        scalar=rows if family=='apsis' else G.scalar_rows(rows,None,'node','Moon')
        candidates=Q.coarse_roots(scalar)
        if not candidates: raise ValueError('no independently enumerated event in 31-day window')
        offsets=plan['fineOffsetsSeconds'][family]
        fine_dates=sorted({round(r['julianDateTT']+s/86400,8) for r in candidates for s in offsets})
        fine,fine_meta=pair(prefix+'-'+family+'-fine',Q.parameters('301','399','NONE',fine_dates),acquire);provenance[family+'Fine']=fine_meta
        scalars=fine if family=='apsis' else G.scalar_rows(fine,None,'node','Moon');by_date={round(r['julianDateTT'],8):r for r in scalars};roots=[]
        for candidate in candidates:
            local=[by_date[round(candidate['julianDateTT']+s/86400,8)] for s in offsets]
            root,kind=Q.interpolated_root(local,3);quadratic,qkind=Q.interpolated_root(local,2)
            convergence=abs(root-quadratic)*86400;shift=abs(root-candidate['julianDateTT'])*86400
            if kind!=candidate['kind'] or qkind!=kind or convergence>plan['interpolationConvergenceLimitSeconds'] or shift>plan['coarseFineMaximumDifferenceSeconds']: raise ValueError('holdout interpolation refinement failed')
            if not window['startJulianDateTT']<=root<window['startJulianDateTT']+31: raise ValueError('holdout refined root outside window')
            if family=='node': kind=G.event_kind('node',kind)
            roots.append({'julianDateTT':root,'kind':kind,'quadraticDifferenceSeconds':convergence,'coarseRefinementDifferenceSeconds':shift})
        output[family]=roots
    return output,provenance


def validate_native(requests,rows):
    if len(requests)!=len(rows): raise ValueError('native response count mismatch')
    for request,row in zip(requests,rows):
        if row.get('status')!='success' or row.get('request')!=request: raise ValueError('native response request/status mismatch')
        if request['operation']=='state':
            if row.get('julianDateTT')!=request['julianDateTT']: raise ValueError('native state epoch mismatch')
            for key in ['positionKm','velocityKmPerTDBDay']:
                vector=row.get(key,[])
                if len(vector)!=3 or not all(math.isfinite(x) for x in vector): raise ValueError('invalid native state vector')
            Q.angle_arcminutes(row['positionKm'],row['positionKm'])
        elif request['operation']=='events':
            previous=None;kinds={'apsis':('pericenter','apocenter'),'node':('ascending','descending')}[request['family']]
            for event in row['events']:
                jd=event['julianDateTT'];width=event['finalBracketWidthSeconds']
                if not math.isfinite(jd) or not request['startJulianDateTT']<=jd<request['stopJulianDateTT'] or event['kind'] not in kinds or not 0<=width<=.0005: raise ValueError('native event kind/window/root width mismatch')
                if previous is not None and (jd<=previous['julianDateTT'] or event['kind']==previous['kind']): raise ValueError('native event order/direction mismatch')
                previous=event
        else: raise ValueError('unknown native operation')


def native(requests):
    data=''.join(json.dumps(r)+'\n' for r in requests)
    output=subprocess.check_output([str(BINARY),'batch',str(PAYLOAD)],input=data,text=True)
    rows=[json.loads(line) for line in output.splitlines()];validate_native(requests,rows);return rows


def event_result(error_seconds,allowance):
    return {'signedTimeErrorSeconds':error_seconds,'nominalWithinTarget':abs(error_seconds)<60.,'numericalEnvelopeClassification':Q.event_classification(error_seconds,allowance)}


def assess():
    plan=load_plan();G.load_plan();policy=json.loads(Q.POLICY.read_bytes())
    rows,position_meta=pair('positions',Q.parameters('301','399','NONE',plan['positionJulianDatesTT']))
    actual=native([{'operation':'state','julianDateTT':r['julianDateTT']} for r in rows]);positions=[]
    for ref,result in zip(rows,actual):
        vector=[x/AU_KM for x in result['positionKm']];angle=Q.angle_arcminutes(vector,ref['positionAU']);range_error=(math.hypot(*vector)-ref['rangeAU'])/ref['rangeAU']*1e6
        correction=float(G.erfa.dtdb(2451545.,ref['julianDateTT']-2451545.,0,0,0,0));matrix=G.date_plane(ref['julianDateTT'])
        if abs(result['tdbMinusTTSeconds']-correction)>1e-12 or max(abs(result['datePlane'][i][j]-float(matrix[i][j])) for i in range(3) for j in range(3))>1e-14: raise ValueError('native time/frame convention parity failed')
        positions.append({'reference':ref,'actual':result,'angleErrorArcminutes':angle,'signedRangeErrorPPM':range_error,'angleWithinTarget':angle<=policy['angularPosition']['maximumArcminutes'],
                          'distanceWithinTarget':abs(range_error)<=policy['distance']['maximumRelativeErrorByBody']['Moon']*1e6})
    cases=[];requests=[];provenance={'positions':position_meta}
    for window in plan['eventWindows']:
        roots,meta=references(window,plan);provenance[window['id']]=meta
        for family in ['apsis','node']:
            cases.append({'window':window,'family':family,'references':roots[family]})
            requests.append({'operation':'events','family':family,'startJulianDateTT':window['startJulianDateTT'],'stopJulianDateTT':window['startJulianDateTT']+31})
    results=native(requests);events=[];failures=[]
    for case,result in zip(cases,results):
        refs=case['references'];found=result['events']
        if len(refs)!=len(found) or [e['kind'] for e in refs]!=[e['kind'] for e in found]: failures.append({'case':case,'actual':result});continue
        for ref,event in zip(refs,found):
            difference=(event['julianDateTT']-ref['julianDateTT'])*86400
            events.append({'case':case['window']['id'],'family':case['family'],'reference':ref,'actual':event,**event_result(difference,plan['referenceNumericalAllowanceSeconds'])})
    manifest=BUILD/'build-manifest.json';build=json.loads(manifest.read_bytes())
    if build['erfaCommit']!=plan['erfaCommit']: raise ValueError('native ERFA commit mismatch')
    for name,sha in build['filesSHA256'].items():
        if Q.digest((ROOT/name).read_bytes())!=sha: raise ValueError('native build/source binding drift')
    paths=[PLAN,Path(__file__),Path(G.__file__),Path(Q.__file__),Q.POLICY,manifest,ROOT/'Scripts/reference-data/test_integrated_lunar_probe.py',ROOT/'Scripts/reference-data/test_lunar_candidate_holdout.py']+list(RAW.glob('*.json'))
    summaries={}
    for family in ['apsis','node']:
        selected=[e for e in events if e['family']==family]
        summaries[family]={'count':len(selected),'maximumAbsoluteTimeErrorSeconds':max((abs(e['signedTimeErrorSeconds']) for e in selected),default=None),
            'nominalExceedances':sum(not e['nominalWithinTarget'] for e in selected),'numericalEnvelopeExceedances':sum(e['numericalEnvelopeClassification']=='exceeded' for e in selected),
            'inconclusiveNumericalEnvelopes':sum(e['numericalEnvelopeClassification']=='inconclusive-numerical-envelope' for e in selected)}
    return {'classification':plan['classification'],'inputSHA256':{str(p.relative_to(ROOT)):Q.digest(p.read_bytes()) for p in sorted(set(paths))},
            'nativeBuildManifest':build,'referenceEnvironment':G.environment(),'provenance':provenance,'positions':positions,'events':events,'identityFailures':failures,
            'summary':{'positionCount':len(positions),'maximumAngleErrorArcminutes':max(p['angleErrorArcminutes'] for p in positions),'maximumAbsoluteRangeErrorPPM':max(abs(p['signedRangeErrorPPM']) for p in positions),
                'angularExceedances':sum(not p['angleWithinTarget'] for p in positions),'distanceExceedances':sum(not p['distanceWithinTarget'] for p in positions),'eventCaseCount':len(cases),'identityFailures':len(failures),'events':summaries},'limitations':plan['limitations']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['acquire','report','check']);args=parser.parse_args();plan=load_plan();G.load_plan()
    if args.action=='acquire':
        pair('positions',Q.parameters('301','399','NONE',plan['positionJulianDatesTT']),True);print('Archived 128 fresh positions',flush=True)
        for window in plan['eventWindows']:
            roots,_=references(window,plan,True);print('Archived '+window['id']+': '+str({k:len(v) for k,v in roots.items()}),flush=True)
        return
    report=assess()
    if args.action=='check':
        stored=json.loads(REPORT.read_bytes())
        if any(stored.get(k)!=v for k,v in report.items()): raise ValueError('candidate holdout replay drift')
        print('Fresh candidate holdout replay matched: '+json.dumps(report['summary'],sort_keys=True));return
    if REPORT.exists(): raise ValueError('holdout report already frozen')
    trials=[]
    for _ in range(plan['performanceTrials']):
        trial=json.loads(subprocess.check_output([str(BINARY),'benchmark',str(PAYLOAD),str(plan['evaluationsPerTrial'])],text=True))
        if trial['count']!=plan['evaluationsPerTrial'] or not math.isfinite(trial['checksum']): raise ValueError('invalid integrated cost observation')
        trials.append(trial)
    report['localCostTrials']=trials;report['localCostSummary']={'medianNanosecondsPerTTFrameState':statistics.median(t['evaluationNanoseconds']/t['count'] for t in trials),
        'medianLoadMilliseconds':statistics.median(t['loadNanoseconds']/1e6 for t in trials),'totalProcessPeakRSSRangeBytes':[min(t['peakRSSBytes'] for t in trials),max(t['peakRSSBytes'] for t in trials)],'scope':plan['performanceScope']}
    REPORT.write_bytes(Q.encoded(report));print(json.dumps({'summary':report['summary'],'localCostSummary':report['localCostSummary']},sort_keys=True))

if __name__=='__main__': main()
