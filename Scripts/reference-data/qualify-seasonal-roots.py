#!/usr/bin/env python3
"""Bounded nominal seasonal roots; physical apparent-source uncertainty is unqualified."""
import argparse
import datetime
import gzip
import importlib.util
import json
import math
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('geometric',Path(__file__).with_name('qualify-geometric-events.py'))
G=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(G)
Q=G.Q
PLAN=ROOT/'Documentation/Migration/seasonal-root-sampling-plan.json'
REPORT=ROOT/'Documentation/Migration/seasonal-root-assessment.json'
REPLAY_RECEIPT=ROOT/'Documentation/Migration/seasonal-root-replay-provenance.json'
REPLAY_TIME_TOLERANCE_DAYS=1e-7
RAW=ROOT/'Scripts/reference-data/sources/seasonal-roots'
KINDS=['marchEquinox','juneSolstice','septemberEquinox','decemberSolstice']


def load_plan():
    plan=json.loads(PLAN.read_bytes())
    if plan['policySHA256']!=Q.digest(Q.POLICY.read_bytes()): raise ValueError('frozen accuracy policy changed')
    if plan['baseRevision']!='f64f6920672cc53c39bbc74076eb2f13bf7e1365': raise ValueError('wrong frozen baseline')
    if G.erfa is None or G.erfa.__version__!=plan['pyerfaVersion'] or G.numpy.__version__!=plan['numpyVersion']: raise ValueError('install frozen isolated reference dependencies')
    G.validate_reference_paths({'erfa':G.erfa.__file__,'numpy':G.numpy.__file__,'erfaUfunc':G.erfa.ufunc.__file__})
    return plan


def archive_pair(directory,name,recipe,data):
    directory.mkdir(parents=True,exist_ok=True)
    compressed=gzip.compress(data,mtime=0)
    (directory/(name+'.json.gz')).write_bytes(compressed)
    (directory/(name+'.query.json')).write_bytes(Q.encoded({'parameters':recipe,'responseSHA256':Q.digest(data),'compressedSHA256':Q.digest(compressed),'planSHA256':Q.digest(PLAN.read_bytes()),'acquisitionRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}))


def bound_bytes(directory,name,recipe):
    saved=json.loads((directory/(name+'.query.json')).read_bytes())
    compressed=(directory/(name+'.json.gz')).read_bytes()
    if saved['parameters']!=recipe or saved['planSHA256']!=Q.digest(PLAN.read_bytes()) or saved['compressedSHA256']!=Q.digest(compressed): raise ValueError('detached seasonal query/response/plan')
    data=gzip.decompress(compressed)
    if saved['responseSHA256']!=Q.digest(data): raise ValueError('detached decompressed seasonal response')
    return data


def vector_batches(mode,stage,dates,acquire=False):
    plan=load_plan();definition=plan['nominalReference'] if mode=='nominal' else plan['matchedDiagnostic']
    delay=0 if mode=='nominal' else definition['fixedDelayDays'];rows=[];metadata=[]
    size=plan['numericalControls']['batchSize']
    for offset in range(0,len(dates),size):
        chunk=dates[offset:offset+size];query_dates=[round(jd-delay,8) for jd in chunk]
        recipe=Q.parameters(definition['target'],definition['center'],definition['vectorCorrection'],query_dates)
        name=f'{mode}-{stage}-{offset//size:03d}'
        response=RAW/(name+'.json.gz');query=RAW/(name+'.query.json')
        if acquire and not response.exists() and not query.exists(): archive_pair(RAW,name,recipe,Q.download(recipe))
        data=bound_bytes(RAW,name,recipe);parsed,meta=Q.parse_response(data,recipe)
        for jd,row in zip(chunk,parsed):
            rows.append({**row,'receptionJulianDateTT':jd})
        metadata.append({'pair':name,**meta})
        if acquire: print(f'archived {name}: {len(parsed)} rows',flush=True)
    return rows,metadata


def archived_dates(mode,stage,count):
    plan=load_plan();definition=plan['nominalReference'] if mode=='nominal' else plan['matchedDiagnostic']
    delay=0 if mode=='nominal' else definition['fixedDelayDays'];size=plan['numericalControls']['batchSize']
    paths=sorted(RAW.glob(f'{mode}-{stage}-*.query.json'))
    expected=[RAW/f'{mode}-{stage}-{i:03d}.query.json' for i in range(math.ceil(count/size))]
    if paths!=expected: raise ValueError('archived seasonal batch selection changed')
    dates=[]
    for index,path in enumerate(paths):
        recipe=json.loads(path.read_bytes())['parameters']
        query_dates=[float(value) for value in recipe['TLIST'].strip("'").split(',')]
        if len(query_dates)!=min(size,count-index*size) or any(not math.isfinite(jd) for jd in query_dates): raise ValueError('archived seasonal batch count/epochs changed')
        if recipe!=Q.parameters(definition['target'],definition['center'],definition['vectorCorrection'],query_dates): raise ValueError('archived seasonal conventions changed')
        name=path.name.removesuffix('.query.json');Q.parse_response(bound_bytes(RAW,name,recipe),recipe)
        reception=[round(jd+delay,plan['numericalControls']['queryDecimalPlaces']) for jd in query_dates]
        if any(round(jd-delay,plan['numericalControls']['queryDecimalPlaces'])!=query for jd,query in zip(reception,query_dates)): raise ValueError('archived fixed-delay epochs do not round-trip')
        dates+=reception
    if dates!=sorted(set(dates)): raise ValueError('archived seasonal epochs are not strictly ordered')
    return dates


def validate_sample_epochs(dates,seeds,offsets):
    precision=load_plan()['numericalControls']['queryDecimalPlaces'];offsets=sorted(offsets)
    if len(dates)!=len(seeds)*len(offsets) or dates!=sorted(set(dates)): raise ValueError('seasonal sample selection/count/order changed')
    groups=[]
    for index,seed in enumerate(seeds):
        epoch=seed['julianDateTT'];group=dates[index*len(offsets):(index+1)*len(offsets)]
        for jd,offset in zip(group,offsets):
            if not math.isfinite(jd) or not math.isfinite(epoch) or round(jd,precision)!=jd: raise ValueError('invalid archived seasonal sample epoch')
            # Quantized acquisition inputs are immutable; this bound only validates
            # their relation to independently recomputed roots, including JD ulps.
            rounding_bound=10**(-precision)+4*max(math.ulp(epoch),math.ulp(jd))
            if abs(jd-(epoch+offset/86400))>rounding_bound: raise ValueError('archived seasonal refinement spacing/selection drift')
        groups.append(dict(zip(offsets,group)))
    return groups


def date_frame(jd):
    ob=G.erfa.obl06(2451545.0,jd-2451545.0);_,deps=G.erfa.nut06a(2451545.0,jd-2451545.0)
    c,s=math.cos(ob+deps),math.sin(ob+deps)
    return G.numpy.array([[1,0,0],[0,c,s],[0,-s,c]])@G.erfa.pnm06a(2451545.0,jd-2451545.0)


def longitude(row,mode):
    vector=G.numpy.array(row['positionAU'])
    if mode=='matched': vector=-vector
    ecliptic=date_frame(row['julianDateTT'])@vector
    return math.degrees(math.atan2(ecliptic[1],ecliptic[0]))%360


def scalar_rows(rows,mode,target):
    return [{'julianDateTT':r['receptionJulianDateTT'],'rangeRateAUPerDay':(longitude(r,mode)-target+180)%360-180} for r in rows]


def coarse_candidates(rows,mode):
    plan=load_plan();angles=[];previous=None
    for row in rows:
        value=longitude(row,mode)
        if previous is not None:
            step=(value-previous)%360
            if not 0<step<plan['numericalControls']['maximumCoarseAdvanceDegrees']: raise ValueError('coarse longitude advance outside frozen envelope')
            angles.append(angles[-1]+step)
        else: angles.append(value)
        previous=value
    roots=[]
    for i,(a,b) in enumerate(zip(angles,angles[1:])):
        for quarter in range(math.floor(a/90)+1,math.floor(b/90)+1):
            target=quarter*90;lo=max(0,min(i-1,len(rows)-4))
            local=[{'julianDateTT':rows[j]['receptionJulianDateTT'],'rangeRateAUPerDay':angles[j]-target} for j in range(lo,lo+4)]
            root,direction=Q.interpolated_root(local,3)
            if direction!='pericenter': raise ValueError('seasonal crossing is not ascending')
            roots.append({'julianDateTT':root,'kind':KINDS[quarter%4],'targetDegrees':target%360})
    validate_identities(roots)
    return roots


def year_start(year):
    return 2451544.5+(datetime.datetime(year,1,1)-datetime.datetime(2000,1,1)).days


def validate_identities(roots):
    plan=load_plan();selection=plan['selection']
    if len(roots)!=selection['expectedEvents']: raise ValueError('wrong full seasonal event count')
    for i,root in enumerate(roots):
        year=selection['firstYear']+i//4
        if root['kind']!=KINDS[i%4] or not year_start(year)<=root['julianDateTT']<year_start(year+1): raise ValueError('seasonal identity/order/year mismatch')
        if i and roots[i-1]['julianDateTT']>=root['julianDateTT']: raise ValueError('nonascending seasonal epochs')


def references(mode,acquire=False):
    plan=load_plan();selection=plan['selection'];control=plan['numericalControls']
    start,stop=selection['startJulianDateTT'],selection['stopJulianDateTT'];step=selection['coarseStepDays']
    dates=[start+i*step for i in range(math.ceil((stop-start)/step))]+[stop]
    coarse,meta=vector_batches(mode,'coarse',dates,acquire);candidates=coarse_candidates(coarse,mode)
    offsets=control['fineOffsetsSeconds']+control['halfFineOffsetsSeconds']
    dates=sorted({round(root['julianDateTT']+offset/86400,8) for root in candidates for offset in offsets}) if acquire else archived_dates(mode,'fine',len(candidates)*len(offsets))
    groups=validate_sample_epochs(dates,candidates,offsets)
    fine,fine_meta=vector_batches(mode,'fine',dates,acquire);meta+=fine_meta;by_date={r['receptionJulianDateTT']:r for r in fine};roots=[]
    for candidate,group in zip(candidates,groups):
        results=[]
        for key in ['fineOffsetsSeconds','halfFineOffsetsSeconds']:
            local=[by_date[group[offset]] for offset in control[key]]
            scalars=scalar_rows(local,mode,candidate['targetDegrees']);root,direction=Q.interpolated_root(scalars,3);quadratic,qdirection=Q.interpolated_root(scalars,2)
            results.append((root,abs(root-quadratic)*86400,direction==qdirection=='pericenter'))
        coarse_diff=abs(results[0][0]-candidate['julianDateTT'])*86400;half_diff=abs(results[0][0]-results[1][0])*86400
        failures=[]
        if any(r[1]>control['maximumQuadraticCubicDifferenceSeconds'] or not r[2] for r in results): failures.append('quadratic/cubic convergence or direction')
        if coarse_diff>control['maximumCoarseFineDifferenceSeconds']: failures.append('coarse/fine convergence')
        if half_diff>control['maximumHalfGridDifferenceSeconds']: failures.append('half-grid convergence')
        roots.append({**candidate,'julianDateTT':results[1][0],'coarseJulianDateTT':candidate['julianDateTT'],'coarseFineDifferenceSeconds':coarse_diff,'halfGridDifferenceSeconds':half_diff,'quadraticCubicDifferenceSeconds':[r[1] for r in results],'numericalFailures':failures})
    offsets=control['directBracketOffsetsSeconds']
    dates=sorted({round(root['julianDateTT']+offset/86400,8) for root in roots for offset in offsets}) if acquire else archived_dates(mode,'direct',len(roots)*len(offsets))
    groups=validate_sample_epochs(dates,roots,offsets)
    direct,direct_meta=vector_batches(mode,'direct',dates,acquire);meta+=direct_meta;by_date={r['receptionJulianDateTT']:r for r in direct}
    for root,group in zip(roots,groups):
        local=[by_date[group[offset]] for offset in offsets]
        values=[r['rangeRateAUPerDay'] for r in scalar_rows(local,mode,root['targetDegrees'])]
        root['directBracketResidualDegrees']=values
        if not values[0]<0<values[1]: root['numericalFailures'].append('direct ascending bracket')
    validate_identities(roots)
    return roots,meta


def validate_public(request,result):
    if result.get('request')!=request or result.get('status')!='success': raise ValueError('public result detached from request or unsuccessful')
    events=result.get('events');year=request['year']
    if not isinstance(events,list) or len(events)!=4 or [e.get('kind') for e in events]!=KINDS: raise ValueError('public seasonal count/identity/order mismatch')
    dates=[e.get('julianDateTT') for e in events]
    if any(not isinstance(jd,(int,float)) or not math.isfinite(jd) or not year_start(year)<=jd<year_start(year+1) for jd in dates) or dates!=sorted(set(dates)): raise ValueError('public seasonal epoch/year/order mismatch')


def public_results(binary):
    plan=load_plan();requests=[{'operation':'seasonal-roots','year':year,'deltaTModel':model} for model in plan['publicDeltaTModels'] for year in range(plan['selection']['firstYear'],plan['selection']['lastYear']+1)]
    text=''.join(json.dumps(request)+'\n' for request in requests)
    process=subprocess.run([str(binary),'accuracy-batch'],input=text,text=True,capture_output=True,check=True)
    results=[json.loads(line) for line in process.stdout.splitlines()]
    if len(results)!=len(requests): raise ValueError('public batch request count mismatch')
    for request,result in zip(requests,results): validate_public(request,result)
    return requests,results


def source_hashes():
    paths=[PLAN,Q.POLICY,Path(__file__),Path(G.__file__),Path(Q.__file__),ROOT/'Scripts/reference-data/build-accuracy-runner.py',ROOT/'Tools/Migration/AccuracyQualificationRunner/main.swift']
    paths+=list((ROOT/'Sources/AstronomyKit').rglob('*.swift'))+list((ROOT/'Sources/CLibAstronomy').rglob('*.c'))+list((ROOT/'Sources/CLibAstronomy').rglob('*.h'))
    paths+=list(RAW.glob('*'))
    return {str(p.relative_to(ROOT)):Q.digest(p.read_bytes()) for p in sorted(set(paths)) if p.is_file()}


def assess(binary):
    plan=load_plan();references_by_mode={};provenance={}
    for mode in ['nominal','matched']: references_by_mode[mode],provenance[mode]=references(mode)
    requests,results=public_results(binary);events=[];summary={}
    for request,result in zip(requests,results):
        index=(request['year']-plan['selection']['firstYear'])*4
        for mode in references_by_mode:
            key=mode+'/'+request['deltaTModel'];entry=summary.setdefault(key,{'count':0,'nominalExceedances':0,'numericalEnvelopeExceedances':0,'inconclusiveNumericalEnvelopes':0,'referenceControlFailures':0,'maximumAbsoluteTimeErrorSeconds':0})
            for reference,actual in zip(references_by_mode[mode][index:index+4],result['events']):
                error=(actual['julianDateTT']-reference['julianDateTT'])*86400
                classification='unresolved-reference-controls' if reference['numericalFailures'] else Q.event_classification(error,plan['numericalControls']['referenceNumericalAllowanceSeconds'])
                events.append({'mode':mode,'deltaTModel':request['deltaTModel'],'year':request['year'],'reference':reference,'actual':actual,'signedTimeErrorSeconds':error,'nominalWithinStrictTarget':abs(error)<plan['strictMaximumTimeErrorSeconds'],'numericalEnvelopeClassification':classification})
                entry['count']+=1;entry['nominalExceedances']+=int(abs(error)>=60);entry['numericalEnvelopeExceedances']+=int(classification=='exceeded');entry['inconclusiveNumericalEnvelopes']+=int(classification=='inconclusive-numerical-envelope');entry['referenceControlFailures']+=int(bool(reference['numericalFailures']));entry['maximumAbsoluteTimeErrorSeconds']=max(entry['maximumAbsoluteTimeErrorSeconds'],abs(error))
    environment=G.environment();environment['frameDefinition']=plan['nominalReference']['frame']
    return {'schemaVersion':1,'classification':'finite-nominal-seasonal-evidence-physical-apparent-qualification-incomplete','inputSHA256':source_hashes(),'referenceEnvironment':environment,'publicRunner':{'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'executableSHA256':Q.digest(binary.read_bytes()),'compiler':subprocess.check_output(['swift','--version'],text=True).strip(),'isolatedManifestSHA256':Q.digest((ROOT/'.context/accuracy-qualification/runner-package/Package.swift').read_bytes())},'provenance':provenance,'summary':summary,'events':events,'limitations':plan['limitations'],'physicalApparentQualification':'unsupported: '+plan['nominalReference']['physicalQualification']}


def require_finite_payload(value):
    if isinstance(value,float) and not math.isfinite(value): raise ValueError('nonfinite seasonal payload value')
    if isinstance(value,dict):
        for item in value.values(): require_finite_payload(item)
    elif isinstance(value,list):
        for item in value: require_finite_payload(item)


def validate_report_semantics(payload):
    require_finite_payload(payload);plan=load_plan();summary={}
    expected_count=plan['selection']['expectedEvents']*2*len(plan['publicDeltaTModels'])
    if len(payload['events'])!=expected_count: raise ValueError('seasonal report population changed')
    for index,event in enumerate(payload['events']):
        model=plan['publicDeltaTModels'][index//(plan['selection']['expectedEvents']*2)]
        year=plan['selection']['firstYear']+(index%(plan['selection']['expectedEvents']*2))//8
        mode='nominal' if index%8<4 else 'matched';kind=KINDS[index%4]
        if event['deltaTModel']!=model or event['year']!=year or event['mode']!=mode: raise ValueError('seasonal report event selection changed')
        actual,reference=event['actual'],event['reference']
        for row in (actual,reference):
            jd=row['julianDateTT']
            if type(jd) not in (int,float) or not math.isfinite(jd) or not year_start(year)<=jd<year_start(year+1) or row['kind']!=kind: raise ValueError('invalid seasonal report epoch/identity')
        if reference['targetDegrees']!=plan['targetAnglesDegrees'][index%4]: raise ValueError('seasonal report target changed')
        error=(actual['julianDateTT']-reference['julianDateTT'])*86400
        if type(event['signedTimeErrorSeconds']) not in (int,float) or event['signedTimeErrorSeconds']!=error: raise ValueError('saved seasonal residual inconsistent with epochs')
        nominal=abs(error)<plan['strictMaximumTimeErrorSeconds']
        classification='unresolved-reference-controls' if reference['numericalFailures'] else Q.event_classification(error,plan['numericalControls']['referenceNumericalAllowanceSeconds'])
        if type(event['nominalWithinStrictTarget']) is not bool or event['nominalWithinStrictTarget']!=nominal or event['numericalEnvelopeClassification']!=classification: raise ValueError('seasonal report classification inconsistent with residual')
        key=mode+'/'+model;entry=summary.setdefault(key,{'count':0,'nominalExceedances':0,'numericalEnvelopeExceedances':0,'inconclusiveNumericalEnvelopes':0,'referenceControlFailures':0,'maximumAbsoluteTimeErrorSeconds':0})
        entry['count']+=1;entry['nominalExceedances']+=int(not nominal);entry['numericalEnvelopeExceedances']+=int(classification=='exceeded');entry['inconclusiveNumericalEnvelopes']+=int(classification=='inconclusive-numerical-envelope');entry['referenceControlFailures']+=int(bool(reference['numericalFailures']));entry['maximumAbsoluteTimeErrorSeconds']=max(entry['maximumAbsoluteTimeErrorSeconds'],abs(error))
    if payload['summary']!=summary: raise ValueError('seasonal report summary inconsistent with events')


def validate_replay(saved,current):
    validate_report_semantics(saved);validate_report_semantics(current)
    left=json.loads(json.dumps(saved));right=json.loads(json.dumps(current));time_bound=REPLAY_TIME_TOLERANCE_DAYS*86400
    for old,new in zip(left['events'],right['events']):
        for field in ['actual','reference']:
            if abs(old[field]['julianDateTT']-new[field]['julianDateTT'])>REPLAY_TIME_TOLERANCE_DAYS: raise ValueError('rebuilt seasonal epoch changed')
            if old[field]['kind']!=new[field]['kind']: raise ValueError('rebuilt seasonal identity changed')
        # Validate both residuals first; normalization cannot conceal invalid saved evidence.
        if abs(old['signedTimeErrorSeconds']-new['signedTimeErrorSeconds'])>2*time_bound: raise ValueError('rebuilt seasonal residual changed')
        for field in ['coarseJulianDateTT','coarseFineDifferenceSeconds','halfGridDifferenceSeconds']:
            scale=86400 if field=='coarseJulianDateTT' else 1
            if abs(old['reference'][field]-new['reference'][field])*scale>2*time_bound: raise ValueError('rebuilt seasonal refinement changed')
        for field in ['quadraticCubicDifferenceSeconds','directBracketResidualDegrees']:
            bound=2*time_bound if field=='quadraticCubicDifferenceSeconds' else 1e-12
            if len(old['reference'][field])!=len(new['reference'][field]) or any(abs(a-b)>bound for a,b in zip(old['reference'][field],new['reference'][field])): raise ValueError('rebuilt seasonal reference control changed')
        reference=dict(new['reference'])
        for field in ['julianDateTT','coarseJulianDateTT','coarseFineDifferenceSeconds','halfGridDifferenceSeconds','quadraticCubicDifferenceSeconds','directBracketResidualDegrees']: reference[field]=old['reference'][field]
        new['reference']=reference;new['actual']=old['actual'];new['signedTimeErrorSeconds']=old['signedTimeErrorSeconds']
    if left['summary'].keys()!=right['summary'].keys(): raise ValueError('replay summary groups changed')
    for key in left['summary']:
        name='maximumAbsoluteTimeErrorSeconds'
        if abs(left['summary'][key][name]-right['summary'][key][name])>2*time_bound: raise ValueError('rebuilt summary timing changed')
        right['summary'][key][name]=left['summary'][key][name]
    for value in (left,right): value.pop('publicRunner');value.pop('referenceEnvironment')
    if left!=right: raise ValueError('offline scientific seasonal replay changed')


def validate_source_provenance(saved,current,receipt):
    require_finite_payload(receipt)
    if receipt['originalAssessmentSHA256']!=Q.digest(REPORT.read_bytes()) or receipt['replayInputSHA256']!=current['inputSHA256']: raise ValueError('seasonal replay provenance detached from original assessment/current inputs')
    original=saved['inputSHA256'];updated=current['inputSHA256'];changed={key for key in original.keys()|updated.keys() if original.get(key)!=updated.get(key)}
    if changed!=set(receipt['changedValidatorPaths']) or changed!={'Scripts/reference-data/qualify-seasonal-roots.py'}: raise ValueError('original scientific inputs changed outside replay validator')
    if receipt['originalValidatorSHA256']!=original['Scripts/reference-data/qualify-seasonal-roots.py']: raise ValueError('original validator identity changed')
    if receipt['planSHA256']!=Q.digest(PLAN.read_bytes()): raise ValueError('replay plan changed')


def check(binary):
    saved=json.loads(REPORT.read_bytes());current=assess(binary);receipt=json.loads(REPLAY_RECEIPT.read_bytes())
    validate_source_provenance(saved,current,receipt)
    current['inputSHA256']=saved['inputSHA256']
    validate_replay(saved,current)
    print('Offline replay validated archived epochs, residual semantics, finite payloads, source bindings and strict classifications; original measurements retained.',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['acquire','report','check']);parser.add_argument('--binary',type=Path,default=Q.BINARY);args=parser.parse_args();load_plan()
    if args.action=='acquire':
        for mode in ['nominal','matched']:
            roots,_=references(mode,True);print(f'{mode}: {len(roots)} roots; {sum(bool(r["numericalFailures"]) for r in roots)} failed controls',flush=True)
    elif args.action=='report':
        if REPORT.exists(): raise ValueError('seasonal report already archived')
        report=assess(args.binary);REPORT.write_bytes(Q.encoded(report));print(json.dumps(report['summary'],sort_keys=True))
    else:check(args.binary)

if __name__=='__main__':main()
