#!/usr/bin/env python3
"""Validate every shipping seam with unchanged component budgets."""
import ctypes as C
import json
import subprocess
import sys
from run import ROOT, HERE, OUT, sha, save
from embed import BODIES
croot=ROOT/'Sources/CLibAstronomy'
lib=OUT/('seams.dylib' if sys.platform=='darwin' else 'seams.so')
cmd=['clang','-O2','-shared','-fPIC','-pthread','-I',str(OUT),'-I',str(croot),'-I',str(croot/'include'),str(HERE/'seams.c'),'-lm','-o',str(lib)]
subprocess.run(cmd,check=True)
fn=C.CDLL(str(lib)).ak_check_seams;fn.argtypes=[C.c_int,C.POINTER(C.c_double),C.POINTER(C.c_ubyte)];fn.restype=None
report={'command':cmd,'binarySHA256':sha(lib),'sources':{str(p):sha(p) for p in [HERE/'seams.c',croot/'polynomial.h',croot/'generated/polynomial-data.h',OUT/'baseline.c']},'bodies':[]}
for body,name in enumerate(BODIES):
    out=(C.c_double*3)(); invalid=(C.c_ubyte*10000)();fn(body,out,invalid)
    report['bodies'].append({'body':name,'positions':int(out[0]),'componentBudgetRatio':out[1],'stencilBudgetRatio':out[2],'passed':out[1]<=1 and out[2]<=1,'invalid':[i for i,v in enumerate(invalid) if v]})
    save('seams.json',report);print(name,list(out),flush=True)
assert all(r['passed'] for r in report['bodies'])
