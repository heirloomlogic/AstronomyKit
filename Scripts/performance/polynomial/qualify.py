#!/usr/bin/env python3
"""Qualify all archived segments under the current component regression budgets."""
import ctypes as C
import json
import subprocess
import sys
from run import ROOT, HERE, OUT, sha, save, read

croot=ROOT/'Sources/CLibAstronomy'
lib=OUT/('qualification.dylib' if sys.platform=='darwin' else 'qualification.so')
cmd=['clang','-O2','-shared','-fPIC','-pthread','-I',str(OUT),'-I',str(croot),'-I',str(croot/'include'),
     str(HERE/'qualify.c'),'-lm','-o',str(lib)]


def compile_library():
    """Build the qualification library against the stubbed baseline and the original masks."""
    (OUT/'qualify-runtime.h').write_text('#undef PolynomialPosition\n'+(croot/'polynomial.h').read_text().replace(
        'if (!model->valid[segment]) return 0;', '/* Qualify the original coefficients, including disabled segments. */'))
    subprocess.run(cmd,check=True)
    return lib


def qualify():
    compile_library()
    fn=C.CDLL(str(lib)).ak_qualify_segment
    fn.argtypes=[C.c_int,C.c_int,C.POINTER(C.c_double)];fn.restype=C.c_double
    manifest=json.loads((HERE/'data/generation.json').read_text())
    report={'reference':read('build.json')['baselineRevision'],'command':cmd,'binarySHA256':sha(lib),
            'budget':'max(1e-12, abs(reference)*1e-12) for each position/velocity component and radius',
            'samplesPerSegment':53,'bodies':[]}
    for body,row in enumerate(manifest['bodies']):
        failures=[];largest=0.;dates=[]
        for segment in range(row['segments']):
            tt=C.c_double()
            ratio=fn(body,segment,C.byref(tt))
            if ratio<0: raise ValueError('Qualification requires original validity masks')
            if ratio>1: failures.append(segment)
            largest=max(largest,ratio)
            if ratio>1: dates.append([segment,tt.value,ratio])
        report['bodies'].append({'body':row['body'],'segments':row['segments'],'invalid':failures,
                                'maxBudgetRatio':largest,'failures':dates})
        save('qualification.json',report)
        print(row['body'],len(failures),'/',row['segments'],'fallbacks; max ratio',largest,flush=True)
    return report


def write_mask(report):
    (HERE/'data/shipping-validity.json').write_text(json.dumps(
        {'qualificationSHA256':sha(OUT/'qualification.json'),
         'invalid':{r['body']:r['invalid'] for r in report['bodies']}},indent=2,sort_keys=True)+'\n')


if __name__=='__main__':
    result=qualify()
    if '--write-mask' in sys.argv[1:]: write_mask(result)
