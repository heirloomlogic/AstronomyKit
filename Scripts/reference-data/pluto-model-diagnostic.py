#!/usr/bin/env python3
"""Reproduce frozen Pluto diagnostics; no acceptance or production model changes."""
import argparse
import concurrent.futures
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request
import source_archive

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'Scripts/reference-data/sources/distance/model-diagnostics/pluto'
WORK = ROOT / '.context/pluto-model'
AU = 149597870.7


def sha(path):
    return source_archive.sha256(ROOT, path)


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True,allow_nan=False) + '\n')


def validate_finite(value):
    if isinstance(value,float) and not math.isfinite(value):
        raise ValueError('nonfinite diagnostic value')
    if isinstance(value,dict):
        for child in value.values(): validate_finite(child)
    if isinstance(value,list):
        for child in value: validate_finite(child)


def parse_response(data, epochs, name):
    if data.get('signature') != {'source':'NASA/JPL Horizons API','version':'1.2'}:
        raise ValueError('unexpected Horizons API signature')
    result = data['result']
    target,solution=('Pluto Barycenter (9)','DE441') if name=='barycenter' else ('Pluto (999)','plu060_merged')
    required={
        'Target body name': target + ' {source: '+solution+'}',
        'Center body name': 'Sun (10) {source: '+solution+'}',
        'Output units': 'AU-D', 'Output type':'GEOMETRIC cartesian states',
        'Reference frame':'ICRF', 'Output format':'2 (position and velocity)',
    }
    for field,value in required.items():
        match=re.search(r'^'+re.escape(field)+r'\s*:\s*(.+)$',result,re.M)
        if not match or ' '.join(match[1].split())!=value:
            raise ValueError('reference convention mismatch: '+field)
    if 'JDTT ,' not in result or 'Calendar Date (TT )' not in result:
        raise ValueError('reference time scale is not TT')
    rows = result.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines()
    parsed = []
    for row in rows:
        fields = row.split(',')
        jd = float(fields[0])
        state = [float(v) for v in fields[2:8]]
        if len(state)!=6 or not all(math.isfinite(v) for v in state):
            raise ValueError('nonfinite reference')
        parsed.append({'ttDays': jd - 2451545, 'position': state[:3], 'velocity': state[3:]})
    if [r['ttDays'] for r in parsed] != epochs:
        raise ValueError('reference epoch mismatch')
    return parsed


def query_parameters(plan,target):
    return {k: "'"+v+"'" for k,v in {
        'COMMAND':target, 'CENTER':'500@10', 'EPHEM_TYPE':'VECTORS', 'MAKE_EPHEM':'YES',
        'OBJ_DATA':'NO', 'OUT_UNITS':'AU-D', 'REF_PLANE':'FRAME', 'REF_SYSTEM':'ICRF',
        'TIME_TYPE':'TT', 'TLIST_TYPE':'JD', 'VEC_CORR':'NONE', 'VEC_TABLE':'2',
        'CSV_FORMAT':'YES', 'CAL_TYPE':'GREGORIAN',
        'TLIST':','.join(str(2451545+t) for t in plan['epochsTTDays'])}.items()}


def acquire(plan, name, target):
    parameters=query_parameters(plan,target)
    url = 'https://ssd.jpl.nasa.gov/api/horizons.api?' + urllib.parse.urlencode(parameters)
    raw = urllib.request.urlopen(url, timeout=120).read()
    parse_response(json.loads(raw), plan['epochsTTDays'],name)
    response = EVIDENCE / (name+'.json')
    response.write_bytes(raw)
    write(EVIDENCE/(name+'.query.json'), {'endpoint': 'https://ssd.jpl.nasa.gov/api/horizons.api', 'parameters':parameters, 'responseSHA256':sha(response)})


def references(plan, name, directory=None):
    directory=directory or EVIDENCE
    path = directory/(name+'.json')
    query=json.loads((directory/(name+'.query.json')).read_text())
    if query['endpoint']!='https://ssd.jpl.nasa.gov/api/horizons.api' or query['parameters']!=query_parameters(plan,'9' if name=='barycenter' else '999'):
        raise ValueError('reference query mismatch')
    if sha(path) != query['responseSHA256']:
        raise ValueError('reference hash mismatch')
    return parse_response(json.loads(path.read_bytes()),plan['epochsTTDays'],name)


def residual(actual, reference):
    return {'radialKm':(math.hypot(*actual)-math.hypot(*reference))*AU, 'vectorKm':math.dist(actual,reference)*AU}


def variant_source(source, step, modern=None):
    source, count = re.subn(r'#define PLUTO_DT\s+146\b',f'#define PLUTO_DT {step}',source)
    if count != 1:
        raise ValueError('unexpected step declaration')
    source, count = re.subn(r'#define PLUTO_NSTEPS\s+201\b',f'#define PLUTO_NSTEPS {round(29200/step)+1}',source)
    if count != 1:
        raise ValueError('unexpected step count declaration')
    if modern:
        for row in modern:
            epoch = row['ttDays']
            replacement = '{ '+str(epoch)+', {'+', '.join(format(v,'.17g') for v in row['position'])+'}, {'+', '.join(format(v,'.17g') for v in row['velocity'])+'} }'
            pattern = r'\{\s*'+re.escape(f'{epoch:.1f}')+r',\s*\{[^}]+\},\s*\{[^}]+\}\s*\}'
            source,count = re.subn(pattern,replacement,source)
            if count != 1:
                raise ValueError('seed replacement failed '+str(epoch))
    return source


def relative_force_source(source, inner=False):
    """Prescribe heliocentric perturbators with explicit indirect accelerations."""
    major='static void MajorBodyBary(major_bodies_t *bary, double tt)\n{\n'
    major+='    bary->Sun.tt=tt; bary->Sun.r=VecZero; bary->Sun.v=VecZero;\n'
    for title,body in [('Jupiter','JUPITER'),('Saturn','SATURN'),('Uranus','URANUS'),('Neptune','NEPTUNE')]:
        major+=f'    bary->{title}=CalcVsopPosVel(&vsop[BODY_{body}],tt);\n'
    major+='}\n\n'
    source,count=re.subn(r'static void MajorBodyBary\(major_bodies_t \*bary, double tt\).*?(?=static void AddAcceleration)',major,source,flags=re.S)
    if count!=1: raise ValueError('force source anchor mismatch')
    anchor='    return acc;\n}\n\n\nbody_grav_calc_t GravSim('
    addition=''
    for title,body in [('Jupiter','JUPITER'),('Saturn','SATURN'),('Uranus','URANUS'),('Neptune','NEPTUNE')]:
        addition+=f'    AddAcceleration(&acc,bary->{title}.r,{body}_GM,VecZero);\n'
    if inner:
        for body in ['MERCURY','VENUS','EARTH','MARS']:
            gm='(EARTH_GM+MOON_GM)' if body=='EARTH' else body+'_GM'
            addition+=f'    {{ body_state_t p=CalcVsopPosVel(&vsop[BODY_{body}],bary->Sun.tt); AddAcceleration(&acc,small_pos,{gm},p.r); AddAcceleration(&acc,p.r,{gm},VecZero); }}\n'
    if source.count(anchor)!=1: raise ValueError('acceleration source anchor mismatch')
    return source.replace(anchor,addition+anchor)


def run_variant(plan, step, name, modern, force=None):
    epoch_key=hashlib.sha256(json.dumps(plan['epochsTTDays']).encode()).hexdigest()[:12]
    directory = WORK/epoch_key/(name+'-'+str(step)); directory.mkdir(parents=True,exist_ok=True)
    original = ROOT/'Sources/CLibAstronomy/astronomy.c'
    source = directory/'astronomy.c'
    contents=variant_source(source_archive.read_bytes(ROOT, original).decode(),step,modern)
    if force: contents=relative_force_source(contents,inner=force=='relative-eight-planets')
    source.write_text(contents)
    # Source includes generated coefficient files beside the production source.
    binary = directory/'probe'
    subprocess.run(['cc','-O2','-std=c11','-pthread','-I',str(original.parent),'-I',str(original.parent/'include'),
                    '-DPLUTO_DIAGNOSTIC_SOURCE="'+str(source)+'"',str(ROOT/'Scripts/reference-data/pluto-diagnostic-probe.c'),'-lm','-o',str(binary)],check=True)
    raw = subprocess.check_output([str(binary)],input=''.join(str(t)+'\n' for t in plan['epochsTTDays']).encode())
    rows = [json.loads(line) for line in raw.splitlines()]
    if [r['ttDays'] for r in rows] != plan['epochsTTDays']:
        raise ValueError('probe epochs changed')
    return {'seedModel':name,'stepDays':step,'forceModel':force or 'production-barycentric','sourceSHA256':sha(source),'rows':rows}


def decorate(variant,bary,center):
    for row,b,c in zip(variant['rows'],bary,center):
        row['residuals']={key:{'barycenter':residual(row[key],b['position']),'bodyCenter':residual(row[key],c['position'])} for key in ['cached','forward','backward','directBlend']}
        row['interpolationVersusDirectBlend']=residual(row['cached'],row['directBlend'])


def force_diagnostic(plan, stem='force'):
    forceplan=json.loads((EVIDENCE/(stem+'-plan.json')).read_text())
    bary=references(plan,'barycenter');center=references(plan,'body-center')
    seeds=[r for r in bary if r['ttDays'] in plan['seedTTDays']]
    variants=[]
    for force in forceplan['forceVariants']:
        for step in forceplan['stepsDays']:
            print('Evaluating',force,step,flush=True)
            variant=run_variant(plan,step,force,seeds,force)
            decorate(variant,bary,center);variants.append(variant)
    write(EVIDENCE/(stem+'-report.json'),{'forcePlanSHA256':sha(EVIDENCE/(stem+'-plan.json')),'variants':variants})


def top2013(plan):
    """Compile the official Fortran subroutines with its own rotation matrix."""
    import erfa
    manifest=json.loads((EVIDENCE/'top2013-sources.json').read_text())
    for name, entry in manifest.items():
        path=WORK/name
        if not path.exists() or sha(path) != entry['sha256']:
            raise ValueError('TOP2013 source missing or hash mismatch: '+str(path))
    text=(WORK/'TOP2013.f').read_text()
    prefix=text.split('      do ip = 5,9')[0].replace("      open (20,file='TOP2013.out')",'')
    body='''      ip=9
      do
         read (*,*,iostat=ierr) tj
         if (ierr.ne.0) exit
         call TOP2013 (tj,ip,fich,nul,el,ierr)
         if (ierr.ne.0) stop 1
         call ELLXYZ (ip,el,r1,ierr)
         if (ierr.ne.0) stop 2
         do i=1,3
            r2(i)=0.d0
            r2(i+3)=0.d0
            do j=1,3
               r2(i)=r2(i)+rot(i,j)*r1(j)
               r2(i+3)=r2(i+3)+rot(i,j)*r1(j+3)
            enddo
         enddo
         write (*,'(6ES25.17)') r2
      enddo
      end
'''
    driver=WORK/'top-driver.f'
    driver.write_text(prefix+body+'      subroutine TOP2013'+text.split('      subroutine TOP2013',1)[1])
    binary=WORK/'top-driver'
    subprocess.run(['gfortran','-std=legacy','-O2',str(driver),'-o',str(binary)],check=True)
    offsets=[float(erfa.dtdb(2451545.,float(t),0.,0.,0.,0.)) for t in plan['epochsTTDays']]
    times=[t+d/86400 for t,d in zip(plan['epochsTTDays'],offsets)]
    # Also evaluate numeric TT-as-TDB to reproduce historical seed generation.
    inputs=times+plan['epochsTTDays']
    raw=subprocess.check_output([str(binary)],cwd=WORK,input=''.join(format(t,'.17g')+'\n' for t in inputs).encode())
    states=[[float(v) for v in line.split()] for line in raw.splitlines()]
    if len(states)!=2*len(times): raise ValueError('TOP2013 row count')
    bary=references(plan,'barycenter')
    rows=[]
    for i,(t,d,state,b) in enumerate(zip(plan['epochsTTDays'],offsets,states,bary)):
        rows.append({'ttDays':t,'tdbMinusTTSeconds':d,'position':state[:3],'velocity':state[3:],
                     'numericTTAsTDBPosition':states[i+len(times)][:3],
                     'numericTTAsTDBVelocity':states[i+len(times)][3:],
                     'modernBarycenterResidual':residual(state[:3],b['position'])})
    report={'sources':manifest,'driverSHA256':sha(driver),'erfaVersion':erfa.__version__,
            'timeConversion':'ERFA dtdb geocenter (u=v=0), date supplied as TT per ERFA approximation; UT irrelevant at geocenter',
            'rows':rows}
    official=WORK/'official-top'
    subprocess.run(['gfortran','-std=legacy','-O2',str(WORK/'TOP2013.f'),'-o',str(official)],check=True)
    subprocess.run([str(official)],cwd=WORK,check=True)
    expected=[float(v) for v in re.findall(r'[-+]?\d+\.\d+',(WORK/'TOP2013.ctl').read_text())]
    actual=[float(v) for v in re.findall(r'[-+]?\d+\.\d+',(WORK/'TOP2013.out').read_text())]
    if len(expected)!=1045 or len(actual)!=len(expected) or max(abs(x-y) for x,y in zip(actual,expected))>1.01e-10:
        raise ValueError('official TOP2013 control reproduction mismatch')
    report['officialControl']={'numericFieldCount':len(expected),'maximumAbsoluteDifference':max(abs(x-y) for x,y in zip(actual,expected)),
                               'outputSHA256':sha(WORK/'TOP2013.out'),'compiler':subprocess.check_output(['gfortran','--version']).decode().splitlines()[0]}
    write(EVIDENCE/'top2013-report.json',report)


def source_paths():
    return [ROOT/'Scripts/reference-data/pluto-model-diagnostic.py',ROOT/'Scripts/reference-data/pluto-diagnostic-probe.c',
            ROOT/'Scripts/reference-data/test_pluto_model_diagnostic.py',
            ROOT/'Sources/CLibAstronomy/astronomy.c',ROOT/'Sources/CLibAstronomy/include/astronomy.h',
            ROOT/'Sources/CLibAstronomy/generated/vsop87b_full.h',ROOT/'Sources/CLibAstronomy/generated/iau2000b_full.h',
            ROOT/'Sources/CLibAstronomy/polynomial.h',ROOT/'Sources/CLibAstronomy/generated/polynomial-data.h']


def offgrid(acquire_data=False, stem='offgrid'):
    global EVIDENCE
    saved=EVIDENCE
    try:
        EVIDENCE=saved/stem
        plan=json.loads((EVIDENCE/'plan.json').read_text())
        if acquire_data:
            for name,target in [('barycenter','9'),('body-center','999')]: acquire(plan,name,target)
        bary=references(plan,'barycenter');center=references(plan,'body-center')
        seeds=[r for r in bary if r['ttDays'] in plan['seedTTDays']]
        variants=[]
        for step in plan['stepsDays']:
            print('Evaluating offgrid original',step,flush=True)
            variant=run_variant(plan,step,'original',None)
            decorate(variant,bary,center);variants.append(variant)
        variant=run_variant(plan,plan['additionalModernEightPlanetStepDays'],'relative-eight-planets',seeds,'relative-eight-planets')
        decorate(variant,bary,center);variants.append(variant)
        write(EVIDENCE/'report.json',{'planSHA256':sha(EVIDENCE/'plan.json'),'variants':variants})
    finally:
        EVIDENCE=saved


def seal():
    write(EVIDENCE/'manifest.json',{'files':{str(p.relative_to(ROOT)):sha(p) for p in sorted(EVIDENCE.rglob('*')) if p.is_file() and p.name!='manifest.json'},
          'sourceFiles':{str(p.relative_to(ROOT)):sha(p) for p in source_paths()},
          'compiler':subprocess.check_output(['cc','--version']).decode().splitlines()[0],
          'compileFlags':['-O2','-std=c11','-pthread','-lm'],
          'purpose':'offline integrity and arithmetic reproduction; not product acceptance or portable output bit identity'})


def check():
    manifest=json.loads((EVIDENCE/'manifest.json').read_text())
    expected={str(p.relative_to(ROOT)) for p in EVIDENCE.rglob('*') if p.is_file() and p.name!='manifest.json'}
    if set(manifest['files'])!=expected or set(manifest['sourceFiles'])!={str(p.relative_to(ROOT)) for p in source_paths()}:
        raise ValueError('manifest membership mismatch')
    for path,digest in (manifest['files']|manifest['sourceFiles']).items():
        if sha(ROOT/path)!=digest: raise ValueError('manifest hash mismatch: '+path)
    plan=json.loads((EVIDENCE/'plan.json').read_text())
    if sha(EVIDENCE/'plan.json')!='174c391f03156b779d87f6e2b9ba7efe6e0f73b32be8408bd3c1d579e4f767a2':
        raise ValueError('initial frozen plan changed')
    bary=references(plan,'barycenter');center=references(plan,'body-center')
    seeds=[r for r in bary if r['ttDays'] in plan['seedTTDays']]
    original=source_archive.read_bytes(ROOT, ROOT/'Sources/CLibAstronomy/astronomy.c').decode()
    for stem in ['integration','force','convergence','omission','offgrid','phasegrid']:
        grid=stem in ['offgrid','phasegrid']
        dp=json.loads((EVIDENCE/stem/'plan.json').read_text()) if grid else plan
        db=references(dp,'barycenter',EVIDENCE/stem) if grid else bary
        dc=references(dp,'body-center',EVIDENCE/stem) if grid else center
        ds=[r for r in db if r['ttDays'] in dp['seedTTDays']]
        report=json.loads((EVIDENCE/stem/'report.json' if grid else EVIDENCE/(stem+'-report.json')).read_text())
        validate_finite(report)
        if stem=='integration':
            expected=[(n,s,'production-barycentric') for n in ['original','modern-barycenter'] for s in plan['integrationStepsDays']]
            if report['planSHA256']!=sha(EVIDENCE/'plan.json') or report['productionSourceSHA256']!=sha(ROOT/'Sources/CLibAstronomy/astronomy.c') or report['probeSHA256']!=sha(ROOT/'Scripts/reference-data/pluto-diagnostic-probe.c'):
                raise ValueError('integration source binding mismatch')
        elif grid:
            expected=[('original',s,'production-barycentric') for s in dp['stepsDays']]+[('relative-eight-planets',dp['additionalModernEightPlanetStepDays'],'relative-eight-planets')]
            if report['planSHA256']!=sha(EVIDENCE/stem/'plan.json'): raise ValueError('grid plan binding mismatch')
        else:
            fp=json.loads((EVIDENCE/(stem+'-plan.json')).read_text())
            expected=[(n,s,n) for n in fp['forceVariants'] for s in fp['stepsDays']]
            if report['forcePlanSHA256']!=sha(EVIDENCE/(stem+'-plan.json')): raise ValueError('force plan binding mismatch')
        variants=report['variants']
        if [(v['seedModel'],v['stepDays'],v['forceModel']) for v in variants]!=expected: raise ValueError('variant membership mismatch')
        for v in variants:
            src=variant_source(original,v['stepDays'],None if v['seedModel']=='original' else ds)
            if v['forceModel']!='production-barycentric': src=relative_force_source(src,v['forceModel']=='relative-eight-planets')
            if hashlib.sha256(src.encode()).hexdigest()!=v['sourceSHA256']: raise ValueError('variant source mismatch')
            if [r['ttDays'] for r in v['rows']]!=dp['epochsTTDays']: raise ValueError('variant epochs mismatch')
            for r,b,c in zip(v['rows'],db,dc):
                for key in ['cached','forward','backward','directBlend']:
                    if len(r[key])!=3 or not all(math.isfinite(x) for x in r[key]): raise ValueError('invalid probe vector')
                    for name,ref in [('barycenter',b),('bodyCenter',c)]:
                        recomputed=residual(r[key],ref['position'])
                        if any(abs(recomputed[k]-r['residuals'][key][name][k])>1e-7 for k in recomputed): raise ValueError('residual arithmetic mismatch')
                rr=residual(r['cached'],r['directBlend'])
                if any(abs(rr[k]-r['interpolationVersusDirectBlend'][k])>1e-7 for k in rr): raise ValueError('interpolation arithmetic mismatch')
    top=json.loads((EVIDENCE/'top2013-report.json').read_text())
    validate_finite(top)
    if [r['ttDays'] for r in top['rows']]!=plan['epochsTTDays']: raise ValueError('TOP2013 epochs mismatch')
    for r,b in zip(top['rows'],bary):
        computed=residual(r['position'],b['position'])
        if any(abs(computed[k]-r['modernBarycenterResidual'][k])>1e-7 for k in computed): raise ValueError('TOP2013 residual mismatch')
    print('Pluto diagnostic archive, exact source variants, conventions, epochs, and residual arithmetic verified.')


def main():
    parser=argparse.ArgumentParser()
    for flag in ['acquire','top2013','forces','convergence','omission','check','seal','offgrid','phasegrid']:
        parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if args.check: check();return
    if args.seal: seal();return
    if args.offgrid or args.phasegrid: offgrid(args.acquire,'phasegrid' if args.phasegrid else 'offgrid');return
    WORK.mkdir(parents=True,exist_ok=True)
    plan=json.loads((EVIDENCE/'plan.json').read_text())
    if args.top2013:
        top2013(plan)
        return
    if args.forces or args.convergence or args.omission:
        force_diagnostic(plan,'convergence' if args.convergence else 'omission' if args.omission else 'force')
        return
    if args.acquire:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda pair:acquire(plan,*pair), [('barycenter','9'),('body-center','999')]))
    bary=references(plan,'barycenter'); center=references(plan,'body-center')
    modern=[r for r in bary if r['ttDays'] in plan['seedTTDays']]
    variants=[]
    for name,seeds in [('original',None),('modern-barycenter',modern)]:
        for step in plan['integrationStepsDays']:
            print('Evaluating',name,step,flush=True)
            variant=run_variant(plan,step,name,seeds)
            decorate(variant,bary,center)
            variants.append(variant)
    report={'planSHA256':sha(EVIDENCE/'plan.json'),'productionSourceSHA256':sha(ROOT/'Sources/CLibAstronomy/astronomy.c'),
            'probeSHA256':sha(ROOT/'Scripts/reference-data/pluto-diagnostic-probe.c'),'references':{p.name:sha(p) for p in sorted(EVIDENCE.glob('*.query.json'))},'variants':variants}
    write(EVIDENCE/'integration-report.json',report)


if __name__ == '__main__':
    main()
