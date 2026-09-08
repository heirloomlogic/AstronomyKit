#!/usr/bin/env python3
"""Qualify the frozen downstream request populations at the exact TT the product consumed."""
import ctypes as C
import gzip
import json
from pathlib import Path
import struct
import sys
from run import ROOT, HERE, OUT, sha, save, read
from embed import BODIES
from qualify import compile_library, lib

FILES=['scoring','nyc-day','nyc-week','reykjavik-day']
RECORD='<IiiId'
SIZE=24
CAPACITY=1<<20


def load_requests(path):
    """Return (record count, deduplicated packed records, unique count)."""
    data=gzip.decompress(Path(path).read_bytes())
    if len(data)%SIZE: raise ValueError(f'{path}: partial record')
    unique={}
    for thread,kind,body,active,tt in struct.iter_unpack(RECORD,data):
        # Compare the exact bits: identical (kind, body, TT) repeats the same evaluation.
        unique.setdefault((kind,body,struct.pack('<d',tt)),(thread,kind,body,active,tt))
    return len(data)//SIZE, b''.join(struct.pack(RECORD,*r) for r in unique.values()), len(unique)


def replay():
    if not lib.exists(): compile_library()
    fn=C.CDLL(str(lib)).ak_qualify_requests
    fn.argtypes=[C.c_char_p,C.c_long,C.POINTER(C.c_double),C.POINTER(C.c_long),C.POINTER(C.c_double),C.c_long]
    fn.restype=C.c_long
    report={'reference':read('build.json')['baselineRevision'],'binarySHA256':sha(lib),
            'budget':'max(1e-12, abs(reference)*1e-12) for each requested component and radius','files':{}}
    invalid={name:set() for name in BODIES}
    for name in FILES:
        path=HERE/f'data/requests/{name}-requests.bin.gz'
        count,packed,unique=load_requests(path)
        maxima=(C.c_double*8)()
        segments=(C.c_long*CAPACITY)(*([-1]*CAPACITY))
        ratios=(C.c_double*CAPACITY)()
        evaluated=fn(packed,unique,maxima,segments,ratios,CAPACITY)
        worst={};raw=0
        for i in range(CAPACITY):
            if segments[i]<0: break
            key=(BODIES[segments[i]//1000000],segments[i]%1000000)
            worst[key]=max(worst.get(key,0.),ratios[i]);raw+=1
        failing={}
        for (body,segment),ratio in worst.items():
            failing.setdefault(body,set()).add(segment)
            invalid[body].add(segment)
        report['files'][name]={'sourceSHA256':sha(path),'records':count,'unique':unique,'evaluated':evaluated,
            'maxBudgetRatio':{b:maxima[i] for i,b in enumerate(BODIES)},
            'invalid':{b:sorted(s) for b,s in sorted(failing.items())},
            'failingRecords':raw,'saturated':raw>=CAPACITY,
            'failures':sorted([b,s,r] for (b,s),r in worst.items())}
        save('replay.json',{**report,'invalid':{b:sorted(invalid[b]) for b in BODIES}})
        print(name,count,'records;',unique,'unique;',evaluated,'evaluated; max ratio',
              max(maxima),'; failing segments',sum(len(s) for s in failing.values()),flush=True)
    report['invalid']={b:sorted(invalid[b]) for b in BODIES}
    save('replay.json',report)
    return report


def write_mask(report):
    path=HERE/'data/shipping-validity.json'
    mask=json.loads(path.read_text())
    for name in BODIES:
        mask['invalid'][name]=sorted(set(mask['invalid'][name])|set(report['invalid'][name]))
    mask['replaySHA256']=sha(OUT/'replay.json')
    path.write_text(json.dumps(mask,indent=2,sort_keys=True)+'\n')


if __name__=='__main__':
    result=replay()
    if '--write-mask' in sys.argv[1:]: write_mask(result)
