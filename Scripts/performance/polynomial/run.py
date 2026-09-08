#!/usr/bin/env python3
"""Build, validate and benchmark shipping polynomials against native full VSOP."""
import argparse
import ctypes as C
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import struct
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / '.build/polynomial-shipping'
BASELINE = '53f5c5c'
NAMES = ['baseline', 'candidate']
WORKLOADS = ['new', 'random', 'refinement', 'repeated']
sys.path.insert(0, str(ROOT / 'Scripts/accuracy'))
from measure import Model, signed


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(name, value): (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+'\n')
def read(name): return json.loads((OUT / name).read_text())
def invoke(cmd): subprocess.run(list(map(str, cmd)), check=True)
def env(): return {**{k:v for k,v in os.environ.items() if not k.startswith('CHRONOLOGY_')}, 'CHRONOLOGY_MODE':'reference', 'CHRONOLOGY_TRACE':'0'}


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    croot = ROOT/'Sources/CLibAstronomy'
    baseline = OUT/'baseline.c'
    baseline.write_bytes(subprocess.check_output(['git','show',f'{BASELINE}:Sources/CLibAstronomy/astronomy.c']))
    records = {'baselineRevision':subprocess.check_output(['git','rev-parse',BASELINE],text=True).strip(),
               'platform':platform.platform(), 'machine':platform.machine(),
               'compiler':subprocess.check_output(['swiftc','--version'],text=True), 'libraries':{}, 'swift':{},
               'sources':{str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'Sources').rglob('*') if p.is_file()}}
    for name in NAMES:
        source = baseline if name=='baseline' else croot/'astronomy.c'
        math_sources = [croot/'ak_math.c']
        lib = OUT/(name+('.dylib' if sys.platform=='darwin' else '.so'))
        cmd = ['clang','-O2','-dynamiclib' if sys.platform=='darwin' else '-shared','-fPIC','-pthread',
               '-I',croot/'include','-I',croot,source,*math_sources,
               ROOT/'Scripts/accuracy/sample.c',ROOT/'Scripts/performance/native-math/probe.c','-lm','-o',lib]
        invoke(cmd)
        records['libraries'][name] = {'path':str(lib),'command':list(map(str,cmd)), 'binarySHA256':sha(lib), 'binaryBytes':lib.stat().st_size, 'sourceSHA256':sha(source)}
        if sys.platform=='darwin':
            module = croot/'module.modulemap'
            cmd = ['swiftc','-O','-whole-module-optimization','-I',croot,'-Xcc',f'-fmodule-map-file={module}',
                   *sorted((ROOT/'Sources/AstronomyKit').glob('*.swift')), ROOT/'Scripts/performance/native-math/swift-probe.swift',lib,'-o',OUT/('swift-'+name)]
            invoke(cmd)
            records['swift'][name] = {'command':list(map(str,cmd)), 'binarySHA256':sha(OUT/('swift-'+name))}
    records['harness'] = {p.name:sha(p) for p in HERE.iterdir() if p.is_file()}
    save('build.json',records)


def load(name):
    record = read('build.json')['libraries'][name]
    assert sha(record['path']) == record['binarySHA256']
    model = Model(Path(record['path']))
    model.sample = model.library.ak_sample_tt
    model.sample.argtypes = [C.c_int,C.c_double,C.c_int,C.POINTER(C.c_double)]
    model.sample.restype = C.c_int
    return model


def speed(model, body, tt): return signed(model.position(body,tt+.01)[0]-model.position(body,tt-.01)[0])/.02

def root(model, body, at):
    lo, hi = at-.5, at+.5
    low, high = speed(model,body,lo), speed(model,body,hi)
    assert math.isfinite(low) and math.isfinite(high) and low*high <= 0
    while (hi-lo)*86400 > .01:
        mid=(lo+hi)/2; value=speed(model,body,mid)
        assert math.isfinite(value)
        if low*value <= 0: hi=mid
        else: lo,low=mid,value
    return (lo+hi)/2


def validate():
    models = {name:load(name) for name in NAMES}
    path=ROOT/'Scripts/accuracy/results/production/range-references.json.gz'
    frozen=json.loads(gzip.decompress(path.read_bytes()))
    assert frozen['protocolSHA256'] == sha(ROOT/'Scripts/accuracy/RANGE-PROTOCOL.md')
    positions=[]; stations=[]; maxima={}; failures=[]
    for body,tt,lon,lat in frozen['positions']:
        values={name:model.position(body,tt) for name,model in models.items()}
        assert all(math.isfinite(x) for v in values.values() for x in v)
        a,b=values['baseline'],values['candidate']
        # sample.c returns longitude, latitude, and caller TT (not distance).
        assert struct.pack('d',a[2]) == struct.pack('d',b[2]), 'TT metadata'
        delta=[signed(b[0]-a[0]), b[1]-a[1]]
        if abs(delta[0])>1e-8 or abs(delta[1])>1e-8:
            failures.append(['position regression',body,tt,delta])
        assert struct.pack('3d',*models['candidate'].position(body,tt))==struct.pack('3d',*b), 'cache replay'
        errors={n:[signed(v[0]-lon)*3600,(v[1]-lat)*3600] for n,v in values.items()}
        if max(map(abs, errors['candidate'])) > 60:
            failures.append(['independent position accuracy',body,tt,errors['candidate']])
        positions.append([body,tt,delta,errors])
        maxima[body]=[max(x,abs(y)) for x,y in zip(maxima.get(body,[0,0]),delta)]
    print('Validated',len(positions),'monthly positions',flush=True)
    for i,row in enumerate(frozen['stations']):
        roots={name:root(model,row['body'],row['tt']) for name,model in models.items()}
        errors={name:(at-row['tt'])*86400 for name,at in roots.items()}
        shift=(roots['candidate']-roots['baseline'])*86400
        stations.append({**row,'roots':roots,'errorSeconds':errors,'shiftSeconds':shift})
        if abs(errors['candidate'])>60: failures.append(['station accuracy',i,errors])
        if i%250==0: print('Validated stations',i,flush=True)
    details={'positions':positions,'stations':stations}
    (OUT/'accuracy.json.gz').write_bytes(gzip.compress(json.dumps(details,allow_nan=False).encode(),mtime=0))
    save('accuracy-summary.json',{'referenceSHA256':sha(path),'libraries':read('build.json')['libraries'],
         'positions':len(positions),'stations':len(stations),'independentPositionLimitArcseconds':60,
         'maxAngularChangeDegreesByBody':maxima,
         'maxStationErrorSeconds':{n:max(abs(r['errorSeconds'][n]) for r in stations) for n in NAMES},
         'maxStationShiftSeconds':max(abs(r['shiftSeconds']) for r in stations),'failures':failures,
         'independentPositionMaxArcseconds':{n:{b:[max(abs(r[3][n][k]) for r in positions if r[0]==b) for k in range(2)] for b in maxima} for n in NAMES}})
    assert not failures, failures[:5]
    print('Accuracy passed',flush=True)


def benchmark():
    report={}
    for api in ['native','swift']:
        if api=='swift' and sys.platform!='darwin': continue
        for i,work in enumerate(WORKLOADS):
            rows={n:[] for n in NAMES}
            for trial in range(5):
                for name in NAMES[::(-1 if trial%2 else 1)]:
                    if api=='native':
                        # Fresh process, warmup + timed traversal, matching Swift.
                        output=subprocess.check_output([sys.executable,__file__,'native-trial','--name',name,'--workload',str(i)],text=True)
                        data=json.loads(output)
                    else:
                        data=json.loads(subprocess.check_output([str(OUT/('swift-'+name)),work,'1'],text=True))[work]
                        data={'seconds':data['trialsSeconds'][0],'checksum':data['checksums'][0]}
                    rows[name].append(data)
            med={n:statistics.median(r['seconds'] for r in rr) for n,rr in rows.items()}
            report[api+'/'+work]={'trials':rows,'medians':med,'speedup':med['baseline']/med['candidate']}
            save('timings.json',report)
            print(api,work,med,flush=True)


def native_trial(name, work):
    lib=load(name).library
    fn=lib.ak_native_trial;fn.argtypes=[C.c_int,C.POINTER(C.c_double)];fn.restype=C.c_int
    values=(C.c_double*3)()
    assert fn(work,values)==0
    assert fn(work,values)==0
    print(json.dumps(dict(zip(['seconds','cpuSeconds','checksum'],values))))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=['build','validate','benchmark','native-trial'])
    p.add_argument('--name',choices=NAMES);p.add_argument('--workload',type=int)
    a=p.parse_args()
    if a.mode=='native-trial': native_trial(a.name,a.workload)
    else: globals()[a.mode]()
