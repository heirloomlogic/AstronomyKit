#!/usr/bin/env python3
"""Frozen finite independent position and lunar-apsis evidence, not a sky certificate."""
import argparse
import csv
import hashlib
import json
import math
import re
import subprocess
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'Documentation/Migration'
PLAN = DOCS / 'position-event-sampling-plan.json'
POLICY = DOCS / 'approved-accuracy-targets.json'
RAW = ROOT / 'Scripts/reference-data/sources/position-events'
REPORT = DOCS / 'position-event-assessment.json'
BINARY = ROOT / '.context/accuracy-qualification/build-runner/debug/AccuracyQualificationRunner'
API = 'https://ssd.jpl.nasa.gov/api/horizons_file.api'
BODY_CODES = {'Mercury':0,'Venus':1,'Earth':2,'Mars':3,'Jupiter':4,'Saturn':5,'Uranus':6,'Neptune':7,'Pluto':8,'Sun':9,'Moon':10}


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+'\n').encode()


def digest(data): return hashlib.sha256(data).hexdigest()


def load_plan():
    plan=json.loads(PLAN.read_bytes())
    if plan['policySHA256'] != digest(POLICY.read_bytes()): raise ValueError('owner policy changed after plan freezing')
    phases=plan['positionPhases']
    a=phases['characterization']['julianDatesTT']; b=phases['holdout']['julianDatesTT']
    if len(a)!=131 or len(b)!=128 or set(a)&set(b): raise ValueError('invalid frozen phase population')
    for dates in (a,b):
        if len(set(dates))!=len(dates) or dates!=sorted(dates) or not all(2415020.5<=jd<2499391.5 for jd in dates): raise ValueError('invalid frozen epochs')
    if len(plan['positionSeries'])!=29 or len(plan['eventWindows'])!=16: raise ValueError('invalid plan coverage')
    return plan


def parameters(target,center,correction,dates):
    values={'COMMAND':target,'OBJ_DATA':'NO','MAKE_EPHEM':'YES','EPHEM_TYPE':'VECTORS','CENTER':'500@'+center,
            'TLIST':','.join(format(jd,'.8f') for jd in dates),'TLIST_TYPE':'JD','TIME_TYPE':'TT','REF_SYSTEM':'ICRF',
            'REF_PLANE':'FRAME','OUT_UNITS':'AU-D','VEC_TABLE':'3','VEC_CORR':correction,'CSV_FORMAT':'YES','CAL_TYPE':'GREGORIAN'}
    return {k:f"'{v}'" for k,v in values.items()}


def parse_response(data,recipe):
    envelope=json.loads(data); text=envelope.get('result','')
    required={'EPHEM_TYPE':"'VECTORS'",'TIME_TYPE':"'TT'",'REF_SYSTEM':"'ICRF'",'REF_PLANE':"'FRAME'",'OUT_UNITS':"'AU-D'",'VEC_TABLE':"'3'",'TLIST_TYPE':"'JD'",'CSV_FORMAT':"'YES'"}
    if any(recipe.get(k)!=v for k,v in required.items()): raise ValueError('unsupported recipe conventions')
    if 'error' in envelope or '$$SOE' not in text or '$$EOE' not in text: raise ValueError('incomplete Horizons response')
    if envelope.get('signature')!={'source':'NASA/JPL Horizons API','version':'1.0'}: raise ValueError('unknown service signature')
    target=re.search(r'Target body name:\s*(.*?)\s+\{source:\s*([^}]+)\}',text)
    center=re.search(r'Center body name:\s*(.*?)\s+\{source:\s*([^}]+)\}',text)
    if not target or not center or '('+recipe['COMMAND'].strip("'")+')' not in target[1] or '('+recipe['CENTER'].strip("'").split('@')[-1]+')' not in center[1]: raise ValueError('wrong target/center')
    if not re.search(r'^Center-site name:\s*BODY CENTER\s*$',text,re.M): raise ValueError('origin is not the requested body center')
    site=re.search(r'^Center geodetic\s*:\s*([^{}]+)',text,re.M)
    if not site or any(float(x.strip())!=0 for x in site[1].split(',')): raise ValueError('nonzero or missing body-center site')
    if 'JDTT' not in text or 'Reference frame : ICRF' not in text or 'Output units    : AU-D' not in text: raise ValueError('wrong time/frame/units')
    correction=recipe['VEC_CORR'].strip("'")
    expected={'NONE':'GEOMETRIC','LT':'LT CORRECTED','LT+S':'LT+S CORRECTED'}.get(correction)
    if expected is None or not re.search(r'Output type\s*:\s*'+re.escape(expected)+r' cartesian states\s*$',text,re.M): raise ValueError('wrong vector correction')
    rows=[]
    for fields in csv.reader(text.split('$$SOE',1)[1].split('$$EOE',1)[0].strip().splitlines()):
        values=[float(fields[0])]+[float(value) for value in fields[2:11]]
        if len(values)!=10 or not all(math.isfinite(v) for v in values) or values[8]<=0: raise ValueError('invalid vector row')
        if abs(math.hypot(*values[1:4])-values[8])>1e-11: raise ValueError('inconsistent vector/range')
        rows.append({'julianDateTT':values[0],'positionAU':values[1:4],'velocityAUPerDay':values[4:7],'lightTimeDays':values[7],'rangeAU':values[8],'rangeRateAUPerDay':values[9]})
    dates=sorted(float(x) for x in recipe['TLIST'].strip("'").split(','))
    if len(rows)!=len(dates) or any(abs(row['julianDateTT']-jd)>1e-8 for row,jd in zip(rows,dates)): raise ValueError('wrong epoch coverage')
    return rows,{'target':target[1],'targetEphemeris':target[2],'center':center[1],'centerEphemeris':center[2],'frame':'ICRF','timeScale':'TT','correction':correction,'service':envelope['signature'],'url':API}


def download(recipe):
    lines=['!$$SOF']
    for key,value in recipe.items():
        lines.append('TLIST='+'\n'.join(f"'{jd}'" for jd in value.strip("'").split(',')) if key=='TLIST' else f'{key}={value}')
    query='\n'.join(lines)+'\n';boundary='AstronomyKitPositionEventBoundary'
    payload=(f'--{boundary}\r\nContent-Disposition: form-data; name="format"\r\n\r\njson\r\n--{boundary}\r\nContent-Disposition: form-data; name="input"; filename="query.txt"\r\nContent-Type: text/plain\r\n\r\n{query}\r\n--{boundary}--\r\n').encode()
    for attempt in range(3):
        try:
            request=urllib.request.Request(API,data=payload,headers={'User-Agent':'AstronomyKit independent qualification','Content-Type':f'multipart/form-data; boundary={boundary}'})
            with urllib.request.urlopen(request,timeout=45) as response: data=response.read()
            parse_response(data,recipe);return data
        except (OSError,ValueError) as error:
            if attempt==2: raise RuntimeError(f'Horizons acquisition failed: {error}') from error
            time.sleep(1<<attempt)


def pair(directory,name,recipe,acquire=False):
    file=directory/(name+'.json');query=directory/(name+'.query.json')
    if acquire and not file.exists() and not query.exists():
        data=download(recipe); directory.mkdir(parents=True,exist_ok=True)
        file.write_bytes(data);query.write_bytes(encoded({'parameters':recipe,'responseSHA256':digest(data),'planSHA256':digest(PLAN.read_bytes())}))
    saved=json.loads(query.read_bytes());data=file.read_bytes()
    if saved['parameters']!=recipe or saved['responseSHA256']!=digest(data) or saved['planSHA256']!=digest(PLAN.read_bytes()): raise ValueError('detached response, query, or frozen plan')
    return parse_response(data,recipe)


def angle_arcminutes(a,b):
    units=[]
    for vector in (a,b):
        if len(vector)!=3 or not all(math.isfinite(x) for x in vector): raise ValueError('invalid vector')
        length=math.hypot(*vector)
        if not math.isfinite(length) or length==0: raise ValueError('zero/invalid vector norm')
        units.append([x/length for x in vector])
    x,y=units
    cross=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]]
    return math.atan2(math.hypot(*cross),sum(u*v for u,v in zip(x,y)))*10800/math.pi


def event_classification(error_seconds,numerical_allowance):
    if not math.isfinite(error_seconds) or not math.isfinite(numerical_allowance) or numerical_allowance<0: raise ValueError('invalid event comparison')
    error=abs(error_seconds)
    if error+numerical_allowance<60: return 'within-target-numerical-envelope'
    if max(0,error-numerical_allowance)>=60: return 'exceeded'
    return 'inconclusive-numerical-envelope'


def brackets(rows):
    found=[]
    for i,(a,b) in enumerate(zip(rows,rows[1:])):
        x,y=a['rangeRateAUPerDay'],b['rangeRateAUPerDay']
        if x==0:
            if i and rows[i-1]['rangeRateAUPerDay']*y<0: found.append((i-1,i+1))
        elif y!=0 and x*y<0: found.append((i,i+1))
    return found


def polynomial(rows,jd):
    origin=rows[0]['julianDateTT'];x=jd-origin
    result=0
    for i,row in enumerate(rows):
        xi=row['julianDateTT']-origin;term=row['rangeRateAUPerDay']
        for j,other in enumerate(rows):
            if i!=j: term *= (x-(other['julianDateTT']-origin))/(xi-(other['julianDateTT']-origin))
        result += term
    return result


def require_monotonic_interpolant(rows,lo,hi,kind):
    # A single sampled sign change does not prove a cubic has one root.
    # Construct Lagrange coefficients in a scaled local coordinate and check
    # every extremum of its derivative over the selected bracket.
    origin=rows[0]['julianDateTT'];scale=rows[-1]['julianDateTT']-origin
    coefficients=[0.0]*len(rows)
    for i,row in enumerate(rows):
        xi=(row['julianDateTT']-origin)/scale;basis=[row['rangeRateAUPerDay']]
        for j,other in enumerate(rows):
            if i==j: continue
            xj=(other['julianDateTT']-origin)/scale;factor=xi-xj;product=[0.0]*(len(basis)+1)
            for k,value in enumerate(basis): product[k]-=value*xj/factor;product[k+1]+=value/factor
            basis=product
        for k,value in enumerate(basis): coefficients[k]+=value
    lower=(lo-origin)/scale;upper=(hi-origin)/scale;points=[lower,upper]
    if len(coefficients)==4 and coefficients[3]!=0:
        vertex=-coefficients[2]/(3*coefficients[3])
        if lower<vertex<upper: points.append(vertex)
    direction=1 if kind=='pericenter' else -1
    for point in points:
        derivative=sum(k*c*point**(k-1) for k,c in enumerate(coefficients) if k)
        if derivative*direction<=0: raise ValueError('interpolant is not strictly monotonic in root bracket')


def interpolated_root(rows,degree):
    if degree not in (2,3) or len(rows)<degree+1: raise ValueError('insufficient interpolation data')
    if any(not math.isfinite(r['julianDateTT']) or not math.isfinite(r['rangeRateAUPerDay']) for r in rows) or any(a['julianDateTT']>=b['julianDateTT'] for a,b in zip(rows,rows[1:])): raise ValueError('invalid interpolation epochs/values')
    intervals=brackets(rows)
    if len(intervals)!=1: raise ValueError('expected unique directed range-rate crossing')
    i,j=intervals[0];offset=max(0,min(i-1,len(rows)-degree-1));selected=rows[offset:offset+degree+1]
    lo,hi=rows[i]['julianDateTT'],rows[j]['julianDateTT'];left=polynomial(selected,lo)
    kind='pericenter' if rows[i]['rangeRateAUPerDay']<rows[j]['rangeRateAUPerDay'] else 'apocenter'
    if left*polynomial(selected,hi)>=0: raise ValueError('interpolant lost bracket')
    require_monotonic_interpolant(selected,lo,hi,kind)
    for _ in range(60):
        mid=(lo+hi)/2
        if mid==lo or mid==hi: break
        value=polynomial(selected,mid)
        if value==0: return mid,kind
        if (value<0)==(left<0): lo=mid;left=value
        else: hi=mid
    return (lo+hi)/2,kind


def coarse_dates(window):
    return [round(window['startJulianDateTT']+i/24,8) for i in range(31*24+1)]


def coarse_roots(rows):
    roots=[]
    for i,j in brackets(rows):
        offset=max(0,min(i-1,len(rows)-4));root,kind=interpolated_root(rows[offset:offset+4],3)
        roots.append({'julianDateTT':root,'kind':kind})
    return roots


def event_references(window,acquire=False):
    plan=load_plan();directory=RAW/'events';name=window['id']
    rows,meta=pair(directory,name+'-coarse',parameters('301','399','NONE',coarse_dates(window)),acquire)
    candidates=coarse_roots(rows)
    if not candidates: raise ValueError('no independently found lunar events in 31-day window')
    fine_dates=sorted({round(r['julianDateTT']+s/86400,8) for r in candidates for s in plan['eventFineOffsetsSeconds']})
    fine,fine_meta=pair(directory,name+'-fine',parameters('301','399','NONE',fine_dates),acquire)
    by_date={round(row['julianDateTT'],8):row for row in fine}; roots=[]
    for candidate in candidates:
        local=[by_date[round(candidate['julianDateTT']+s/86400,8)] for s in plan['eventFineOffsetsSeconds']]
        cubic,kind=interpolated_root(local,3);quadratic,qkind=interpolated_root(local,2)
        convergence=abs(cubic-quadratic)*86400
        if kind!=candidate['kind'] or kind!=qkind or convergence>.05 or abs(cubic-candidate['julianDateTT'])*86400>30: raise ValueError('independent interpolation refinement failed')
        roots.append({'julianDateTT':cubic,'kind':kind,'quadraticDifferenceSeconds':convergence,'coarseRefinementDifferenceSeconds':abs(cubic-candidate['julianDateTT'])*86400})
    return roots,{'coarse':meta,'fine':fine_meta}


def acquire_positions():
    plan=load_plan()
    for phase,settings in plan['positionPhases'].items():
        for series in plan['positionSeries']:
            name=series['body'].lower()+'-'+series['mode']
            pair(RAW/phase,name,parameters(series['targetID'],series['centerID'],series['correction'],settings['julianDatesTT']),True)
            print('archived '+phase+'/'+name,flush=True)


def acquire_events():
    for window in load_plan()['eventWindows']:
        roots,_=event_references(window,True); print(f"archived {window['id']}: {len(roots)} directed apsides",flush=True)


def validate_public_results(requests,actuals):
    if len(actuals)!=len(requests): raise ValueError('public API response count differs from requests')
    for request,actual in zip(requests,actuals):
        if actual.get('status')!='success' or actual.get('request')!=request: raise ValueError('public API status/request identity mismatch')
        if request['operation']=='position':
            jd=actual.get('julianDateTT',math.nan)
            if not math.isfinite(jd) or abs(jd-request['julianDateTT'])>1e-8: raise ValueError('public vector epoch differs from request')
            angle_arcminutes(actual['positionAU'],actual['positionAU'])
        elif request['operation'] in ('lunar-apsides','lunar-nodes','heliocentric-alignments'):
            previous=None
            for event in actual['events']:
                jd=event['julianDateTT']
                if not math.isfinite(jd) or not request['startJulianDateTT']<=jd<request['stopJulianDateTT']: raise ValueError('public event outside requested window')
                kinds={'lunar-apsides':('pericenter','apocenter'),'lunar-nodes':('ascending','descending'),'heliocentric-alignments':('relative-0','relative-180')}[request['operation']]
                if event['kind'] not in kinds: raise ValueError('invalid public event kind')
                if request['operation']=='lunar-apsides' and (not math.isfinite(event['distanceAU']) or event['distanceAU']<=0): raise ValueError('invalid public apsis range')
                if previous and (jd<=previous['julianDateTT'] or event['kind']==previous['kind']): raise ValueError('public apsides not ordered and alternating')
                previous=event
        else: raise ValueError('unknown public operation')


def public_batch(requests,binary):
    output=subprocess.check_output([str(binary),'accuracy-batch'],input=''.join(json.dumps(r)+'\n' for r in requests),text=True)
    actual=[json.loads(line) for line in output.splitlines()]
    validate_public_results(requests,actual)
    return actual


def input_hashes():
    paths=[PLAN,POLICY,Path(__file__),ROOT/'Scripts/reference-data/build-accuracy-runner.py']
    for directory,patterns in [(RAW,['*.json']),(ROOT/'Sources/CLibAstronomy',['*.c','*.h']),(ROOT/'Sources/AstronomyKit',['*.swift']),(ROOT/'Tools/Migration/AccuracyQualificationRunner',['*.swift'])]:
        for pattern in patterns: paths+=sorted(directory.rglob(pattern))
    paths.append(ROOT/'Package.swift')
    return {str(p.relative_to(ROOT)):digest(p.read_bytes()) for p in sorted(set(paths))}


def assess(binary):
    plan=load_plan();policy=json.loads(POLICY.read_bytes());positions=[];provenance={};requests=[]
    for phase,settings in plan['positionPhases'].items():
        for series in plan['positionSeries']:
            name=series['body'].lower()+'-'+series['mode']
            rows,metadata=pair(RAW/phase,name,parameters(series['targetID'],series['centerID'],series['correction'],settings['julianDatesTT']))
            provenance[phase+'/'+name]=metadata
            for row in rows:
                positions.append({'phase':phase,'body':series['body'],'mode':series['mode'],'reference':row})
                requests.append({'operation':'position','body':BODY_CODES[series['body']],'mode':series['mode'],'julianDateTT':row['julianDateTT']})
    actuals=public_batch(requests,binary);summaries={}
    for row,actual in zip(positions,actuals):
        vector=actual['positionAU'];reference=row['reference'];angle=angle_arcminutes(vector,reference['positionAU'])
        relative=(math.hypot(*vector)-reference['rangeAU'])/reference['rangeAU'];limit=policy['distance']['maximumRelativeErrorByBody'][row['body']]
        row.update({'actualPositionAU':vector,'angleErrorArcminutes':angle,'nominalAngularWithinTarget':angle<=1,'signedRangeErrorPPM':relative*1e6,'nominalSecondaryDistanceWithinTarget':abs(relative)<=limit})
        key=row['phase']+'/'+row['body']+'/'+row['mode']
        summary=summaries.setdefault(key,{'count':0,'angularExceedanceCount':0,'secondaryDistanceExceedanceCount':0,'maximumAngleErrorArcminutes':-1,'maximumAbsoluteRangeErrorPPM':0})
        summary['count']+=1;summary['angularExceedanceCount']+=int(angle>1);summary['secondaryDistanceExceedanceCount']+=int(abs(relative)>limit)
        if angle>summary['maximumAngleErrorArcminutes']: summary['maximumAngleErrorArcminutes']=angle;summary['worstAngleJulianDateTT']=reference['julianDateTT']
        summary['maximumAbsoluteRangeErrorPPM']=max(summary['maximumAbsoluteRangeErrorPPM'],abs(relative)*1e6)
    event_requests=[];event_references_by_window=[]
    for window in plan['eventWindows']:
        roots,metadata=event_references(window);provenance['events/'+window['id']]=metadata;event_references_by_window.append(roots)
        event_requests.append({'operation':'lunar-apsides','startJulianDateTT':window['startJulianDateTT'],'stopJulianDateTT':window['startJulianDateTT']+window['durationDays']})
    event_actuals=public_batch(event_requests,binary);events=[];identity_failures=[]
    for window,references,actual in zip(plan['eventWindows'],event_references_by_window,event_actuals):
        public=actual['events']
        if len(public)!=len(references) or [r['kind'] for r in public]!=[r['kind'] for r in references]:
            identity_failures.append({'window':window['id'],'references':references,'actuals':public});continue
        for reference,result in zip(references,public):
            difference=(result['julianDateTT']-reference['julianDateTT'])*86400
            events.append({'window':window['id'],'reference':reference,'actual':result,'signedTimeErrorSeconds':difference,'nominalWithinTarget':abs(difference)<60,'numericalEnvelopeClassification':event_classification(difference,plan['eventReferenceNumericalAllowanceSeconds'])})
    return {'schemaVersion':1,'classification':'finite-public-api-evidence-not-continuous-or-physical-uncertainty-qualification','inputSHA256':input_hashes(),'executableProvenance':{'path':str(binary.resolve().relative_to(ROOT)) if binary.resolve().is_relative_to(ROOT) else str(binary.resolve()),'sha256':digest(binary.read_bytes()),'swiftVersion':subprocess.check_output(['swift','--version'],text=True).strip(),'buildManifestSHA256':digest((ROOT/'.context/accuracy-qualification/runner-package/Package.swift').read_bytes()),'expectedBuildCommand':'python3 Scripts/reference-data/build-accuracy-runner.py','attribution':'executable and source hashes are both retained; replay requires this exact executable; tool cannot prove a user-supplied alternate binary was built from these sources'},'provenance':provenance,'positionSummary':summaries,'positions':positions,'lunarApsides':events,'eventIdentityFailures':identity_failures,
            'totals':{'positions':len(positions),'nominalAngularExceedances':sum(not r['nominalAngularWithinTarget'] for r in positions),'nominalSecondaryDistanceExceedances':sum(not r['nominalSecondaryDistanceWithinTarget'] for r in positions),'matchedLunarApsides':len(events),'lunarWindowIdentityFailures':len(identity_failures),'nominalLunarTimingExceedances':sum(not r['nominalWithinTarget'] for r in events),'lunarTimingNumericalEnvelopeExceedances':sum(r['numericalEnvelopeClassification']=='exceeded' for r in events),'lunarTimingInconclusiveNumericalEnvelopes':sum(r['numericalEnvelopeClassification']=='inconclusive-numerical-envelope' for r in events)},
            'limitations':['finite samples do not establish continuous domain accuracy','J2000/FK5 versus ICRF orientation is retained in raw angular residuals','body-center and outer-planet satellite offsets are model limitations retained in residuals','NO_ABERRATION uses a fixed heliocentric Sun unlike barycentric Horizons LT','default aberration backdates the observer and differs from Horizons LT+S; Moon uses geometric NONE for both modes','distance results here have different correction conventions from the approved distance retrospective; default ranges are diagnostic','lunar root interpolation convergence is numerical evidence, not an ephemeris physical uncertainty bound','future TT accuracy does not qualify future UTC conversion or Earth-rotation-dependent circumstances'],'uncoveredEventFamilies':plan['uncoveredEventFamilies']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['acquire-positions','acquire-events','report','check']);parser.add_argument('--binary',type=Path,default=BINARY);args=parser.parse_args()
    if args.action=='acquire-positions': acquire_positions()
    elif args.action=='acquire-events': acquire_events()
    else:
        report=assess(args.binary);data=encoded(report)
        if args.action=='check':
            if REPORT.read_bytes()!=data: raise ValueError('position/event report drift: do not erase frozen evidence with regeneration')
            print('Offline public API replay matched report: '+json.dumps(report['totals'],sort_keys=True))
        else:
            if REPORT.exists(): raise ValueError('report already frozen; preserve it before any separate candidate assessment')
            REPORT.write_bytes(data);print(json.dumps(report['totals'],sort_keys=True))

if __name__=='__main__': main()
