#!/usr/bin/env python3
"""Finite geometric lunar-node and heliocentric-alignment reference evidence."""
import argparse
import importlib.util
import json
import math
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
REFERENCE_ENV=ROOT/'.context/accuracy-qualification/python-reference'
if REFERENCE_ENV.exists(): sys.path.insert(0,str(REFERENCE_ENV))
try:
    import erfa
    import numpy
except ImportError:
    erfa=None
    numpy=None
SPEC=importlib.util.spec_from_file_location('position_events',Path(__file__).with_name('qualify-position-events.py'))
Q=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(Q)
PLAN=ROOT/'Documentation/Migration/geometric-event-sampling-plan.json'
REPORT=ROOT/'Documentation/Migration/geometric-event-assessment.json'
RAW=ROOT/'Scripts/reference-data/sources/geometric-events'


def validate_reference_paths(paths):
    for name,path in paths.items():
        if not Path(path).resolve().is_relative_to(REFERENCE_ENV.resolve()): raise ValueError('reference dependency loaded outside pinned environment: '+name)


def load_plan():
    plan=json.loads(PLAN.read_bytes())
    if plan['parentSamplingPlanSHA256']!=Q.digest(Q.PLAN.read_bytes()) or plan['policySHA256']!=Q.digest(Q.POLICY.read_bytes()): raise ValueError('geometric event plan detached from parent/policy')
    if erfa is None or erfa.__version__!=plan['pyerfaVersion']: raise ValueError('install pinned independent reference dependencies in .context/accuracy-qualification/python-reference')
    validate_reference_paths({'erfa':erfa.__file__,'erfaUfunc':erfa.ufunc.__file__,'numpy':numpy.__file__})
    return plan


def pair(name,recipe,acquire=False):
    file=RAW/(name+'.json');query=RAW/(name+'.query.json')
    if acquire and not file.exists() and not query.exists():
        data=Q.download(recipe);RAW.mkdir(parents=True,exist_ok=True)
        file.write_bytes(data);query.write_bytes(Q.encoded({'parameters':recipe,'responseSHA256':Q.digest(data),'planSHA256':Q.digest(PLAN.read_bytes())}))
    saved=json.loads(query.read_bytes());data=file.read_bytes()
    if saved['parameters']!=recipe or saved['responseSHA256']!=Q.digest(data) or saved['planSHA256']!=Q.digest(PLAN.read_bytes()): raise ValueError('detached geometric response/query/plan')
    return Q.parse_response(data,recipe)


def date_plane(jd):
    if erfa is None: raise ValueError('independent ERFA reference dependency unavailable')
    return erfa.ecm06(2451545.0,jd-2451545.0)


def event_kind(family,direction_kind):
    mapping={'node':{'pericenter':'ascending','apocenter':'descending'},'alignment':{'pericenter':'relative-0','apocenter':'relative-180'}}
    if family not in mapping or direction_kind not in mapping[family]: raise ValueError('unknown geometric event identity')
    return mapping[family][direction_kind]


def scalar_rows(targets,earths,family,body):
    if family not in ('node','alignment'): raise ValueError('unknown reference residual')
    if family=='alignment' and (len(targets)!=len(earths) or any(t['julianDateTT']!=e['julianDateTT'] for t,e in zip(targets,earths))): raise ValueError('unpaired reference vector epochs')
    rows=[]
    for i,row in enumerate(targets):
        matrix=date_plane(row['julianDateTT']);vector=matrix@numpy.array(row['positionAU'])
        if family=='node': value=float(vector[2]/math.hypot(*vector))
        else:
            earth=matrix@numpy.array(earths[i]['positionAU']);denominator=math.hypot(earth[0],earth[1])*math.hypot(vector[0],vector[1])
            if denominator==0: raise ValueError('undefined longitude at coordinate pole')
            direction=-1 if body in ('Mercury','Venus') else 1
            value=float(direction*(earth[1]*vector[0]-earth[0]*vector[1])/denominator)
        # Adapter to the already-tested generic polynomial/crossing algorithm;
        # this internal field contains a dimensionless residual, not a range rate.
        rows.append({'julianDateTT':row['julianDateTT'],'rangeRateAUPerDay':value})
    return rows


def roots_from_scalars(rows,family):
    return [{**root,'kind':event_kind(family,root['kind'])} for root in Q.coarse_roots(rows)]


def references(family,window,body='Moon',acquire=False):
    plan=load_plan();prefix=family+'-'+window['id']+'-'+body.lower();earth=None;metadata={}
    if family=='node':
        target,meta=Q.pair(Q.RAW/'events',window['id']+'-coarse',Q.parameters('301','399','NONE',Q.coarse_dates(window)))
    else:
        dates=[window['startJulianDateTT']+i for i in range(int(window['stopJulianDateTT']-window['startJulianDateTT'])+1)]
        earth,earth_meta=pair('alignment-'+window['id']+'-earth-coarse',Q.parameters('399','10','NONE',dates),acquire)
        target,meta=pair(prefix+'-coarse',Q.parameters(plan['alignmentBodies'][body],'10','NONE',dates),acquire)
        metadata['earthCoarse']=earth_meta
    metadata['targetCoarse']=meta
    candidates=roots_from_scalars(scalar_rows(target,earth,family,body),family)
    if not candidates: return [],metadata
    dates=sorted({round(root['julianDateTT']+offset/86400,8) for root in candidates for offset in plan['fineOffsetsSeconds']})
    code='301' if family=='node' else plan['alignmentBodies'][body];center='399' if family=='node' else '10'
    fine,fine_meta=pair(prefix+'-fine',Q.parameters(code,center,'NONE',dates),acquire);metadata['targetFine']=fine_meta
    if family=='alignment':
        earth,earth_meta=pair(prefix+'-earth-fine',Q.parameters('399','10','NONE',dates),acquire);metadata['earthFine']=earth_meta
    scalars=scalar_rows(fine,earth,family,body);by_date={round(r['julianDateTT'],8):r for r in scalars};roots=[]
    for candidate in candidates:
        local=[by_date[round(candidate['julianDateTT']+offset/86400,8)] for offset in plan['fineOffsetsSeconds']]
        cubic,kind=Q.interpolated_root(local,3);quadratic,qkind=Q.interpolated_root(local,2);kind=event_kind(family,kind)
        convergence=abs(cubic-quadratic)*86400;coarse_difference=abs(cubic-candidate['julianDateTT'])*86400
        if kind!=candidate['kind'] or kind!=event_kind(family,qkind) or convergence>plan['interpolationConvergenceLimitSeconds'] or coarse_difference>plan['coarseFineMaximumDifferenceSeconds']: raise ValueError('geometric root refinement failed')
        roots.append({'julianDateTT':cubic,'kind':kind,'quadraticDifferenceSeconds':convergence,'coarseRefinementDifferenceSeconds':coarse_difference})
    return roots,metadata


def cases():
    for window in Q.load_plan()['eventWindows']: yield 'node',window,'Moon'
    for window in load_plan()['alignmentWindows']:
        for body in load_plan()['alignmentBodies']: yield 'alignment',window,body


def acquire():
    for family,window,body in cases():
        roots,_=references(family,window,body,True);print(f"archived {family}/{window['id']}/{body}: {len(roots)} events",flush=True)


def environment():
    wheels=ROOT/'.context/accuracy-qualification/reference-wheels'
    files=sorted(wheels.glob('*.whl'))
    installed=sorted(REFERENCE_ENV.rglob('*.so'))+sorted(REFERENCE_ENV.glob('*.dist-info/METADATA'))
    modules={'erfa':erfa.__file__,'erfaUfunc':erfa.ufunc.__file__,'numpy':numpy.__file__}
    validate_reference_paths(modules)
    linkage=subprocess.check_output(['otool','-L',erfa.ufunc.__file__],text=True) if platform.system()=='Darwin' and shutil.which('otool') else 'not inspected on this platform'
    mode='externally linked ERFA' if 'liberfa' in linkage.lower() else 'bundled ERFA in wheel' if linkage!='not inspected on this platform' else 'not inspected'
    return {'python':platform.python_version(),'platform':platform.platform(),'loadedModulePaths':{k:str(Path(v).resolve().relative_to(ROOT)) for k,v in modules.items()},'erfaLinkageMode':mode,'erfaLinkedLibraries':linkage.replace(str(ROOT),'<workspace>'),'pyerfa':erfa.__version__,'erfa':erfa.version.erfa_version,'numpy':numpy.__version__,
            'wheelSHA256':{p.name:Q.digest(p.read_bytes()) for p in files},'installedBinaryMetadataSHA256':{str(p.relative_to(REFERENCE_ENV)):Q.digest(p.read_bytes()) for p in installed},
            'frameDefinition':'ERFA ecm06: ICRS -> IAU2006 mean ecliptic/equinox date; two-part TT'}


def assess(binary):
    plan=load_plan();requests=[];data=[];provenance={}
    for family,window,body in cases():
        roots,meta=references(family,window,body);name=family+'/'+window['id']+'/'+body;provenance[name]=meta
        stop=window['stopJulianDateTT'] if family=='alignment' else window['startJulianDateTT']+window['durationDays']
        request={'operation':'heliocentric-alignments' if family=='alignment' else 'lunar-nodes','startJulianDateTT':window['startJulianDateTT'],'stopJulianDateTT':stop}
        if family=='alignment': request['body']=Q.BODY_CODES[body]
        requests.append(request);data.append((name,family,body,roots))
    actuals=Q.public_batch(requests,binary);events=[];identity_failures=[];summary={}
    for (name,family,body,roots),actual in zip(data,actuals):
        public=actual['events'];key=family+'/'+body
        if len(public)!=len(roots) or [r['kind'] for r in public]!=[r['kind'] for r in roots]:
            identity_failures.append({'case':name,'reference':roots,'actual':public});continue
        for reference,result in zip(roots,public):
            difference=(result['julianDateTT']-reference['julianDateTT'])*86400;classification=Q.event_classification(difference,plan['referenceNumericalAllowanceSeconds'])
            event={'case':name,'family':family,'body':body,'reference':reference,'actual':result,'signedTimeErrorSeconds':difference,'nominalWithinTarget':abs(difference)<60,'numericalEnvelopeClassification':classification};events.append(event)
            entry=summary.setdefault(key,{'count':0,'nominalExceedances':0,'numericalEnvelopeExceedances':0,'inconclusiveNumericalEnvelopes':0,'maximumAbsoluteTimeErrorSeconds':0})
            entry['count']+=1;entry['nominalExceedances']+=int(abs(difference)>=60);entry['numericalEnvelopeExceedances']+=int(classification=='exceeded');entry['inconclusiveNumericalEnvelopes']+=int(classification=='inconclusive-numerical-envelope')
            if abs(difference)>entry['maximumAbsoluteTimeErrorSeconds']: entry['maximumAbsoluteTimeErrorSeconds']=abs(difference);entry['worstReferenceJulianDateTT']=reference['julianDateTT']
    paths=[PLAN,Path(__file__),Path(Q.__file__)]+list(RAW.glob('*.json'))+list((Q.RAW/'events').glob('*.json'))
    inputs=Q.input_hashes();inputs.update({str(p.relative_to(ROOT)):Q.digest(p.read_bytes()) for p in paths})
    return {'classification':'finite-geometric-public-api-evidence-not-continuous-or-physical-uncertainty-qualification','inputSHA256':inputs,'referenceEnvironment':environment(),
            'executableSHA256':Q.digest(binary.read_bytes()),'executablePath':str(binary.resolve()),'provenance':provenance,'summary':summary,'events':events,'identityFailures':identity_failures,
            'totals':{'cases':len(data),'matchedEvents':len(events),'identityFailures':len(identity_failures),'nominalTimingExceedances':sum(not e['nominalWithinTarget'] for e in events),'numericalEnvelopeExceedances':sum(e['numericalEnvelopeClassification']=='exceeded' for e in events),'inconclusiveNumericalEnvelopes':sum(e['numericalEnvelopeClassification']=='inconclusive-numerical-envelope' for e in events)},
            'limitations':plan['limitations'],'uncoveredEventFamilies':plan['excludedFamilies']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['acquire','report','check']);parser.add_argument('--binary',type=Path,default=Q.BINARY);args=parser.parse_args()
    if args.action=='acquire': acquire()
    else:
        report=assess(args.binary);data=Q.encoded(report)
        if args.action=='check':
            if REPORT.read_bytes()!=data: raise ValueError('geometric event report drift')
            print('Offline geometric event replay matched: '+json.dumps(report['totals'],sort_keys=True))
        else:
            if REPORT.exists(): raise ValueError('geometric report already frozen')
            REPORT.write_bytes(data);print(json.dumps(report['summary'],sort_keys=True))

if __name__=='__main__': main()
