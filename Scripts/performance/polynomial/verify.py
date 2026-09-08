#!/usr/bin/env python3
"""Verify archived accuracy, exact metadata, and native state/distance regressions."""
import ctypes as C
import gzip
import json
import math
import struct
import sys
from run import ROOT, OUT, NAMES, load, read, save, sha
sys.path.insert(0,str(ROOT/'Scripts/performance'))
import importlib.util
spec = importlib.util.spec_from_file_location("equivalence", ROOT/'Scripts/performance/verify-equivalence.py')
equivalence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(equivalence)
Time, Vector, State, Distance = equivalence.Time, equivalence.Vector, equivalence.State, equivalence.Distance

models = {n:load(n) for n in NAMES}
checks = 0
maxima = {}
for name, result_type, fields in (
    ('Astronomy_HelioDistance', Distance, ('value',)),
    ('Astronomy_HelioVector', Vector, ('x','y','z')),
    ('Astronomy_HelioState', State, ('x','y','z','vx','vy','vz')),
    ('Astronomy_BaryState', State, ('x','y','z','vx','vy','vz')),
):
    functions = [getattr(models[n].library,name) for n in NAMES]
    for fn in functions:
        fn.argtypes=[C.c_int,Time];fn.restype=result_type
    largest=0
    for body in range(8):
        for tt in (-730500.,-36525.,-0.,0.,9000.125,36525.,730500.):
            for ut in (tt,tt+.25):
                at=Time(ut,tt,.125,-.25,3.)
                expected, actual = [fn(body,at) for fn in functions]
                assert actual.status == expected.status == 0
                for field in fields:
                    a,b=getattr(expected,field),getattr(actual,field)
                    assert math.isfinite(a) and math.isfinite(b)
                    assert abs(a-b)<=max(1e-12,abs(a)*1e-12), (name,body,tt,field,a,b)
                    largest=max(largest,abs(a-b))
                replay=functions[1](body,at)
                assert struct.pack(f'{len(fields)}d',*[getattr(actual,f) for f in fields]) == struct.pack(
                    f'{len(fields)}d',*[getattr(replay,f) for f in fields]), 'cache replay'
                if hasattr(actual,'t'):
                    assert struct.pack(f'{len(Time._fields_)}d',*[getattr(actual.t,f) for f,_ in Time._fields_]) == struct.pack(
                        f'{len(Time._fields_)}d',*[getattr(at,f) for f,_ in Time._fields_]), 'caller metadata'
                checks+=1
    maxima[name]=largest

accuracy=read('accuracy-summary.json')
assert accuracy['referenceSHA256']==sha(ROOT/'Scripts/accuracy/results/production/range-references.json.gz')
for n in NAMES:
    assert accuracy['libraries'][n]['binarySHA256']==read('build.json')['libraries'][n]['binarySHA256']
assert accuracy['positions']==24120 and accuracy['stations']==2462 and not accuracy['failures']
assert max(accuracy['maxStationErrorSeconds'].values())<=60
assert all(abs(v)<=60 for values in accuracy['independentPositionMaxArcseconds']['candidate'].values() for v in values)
assert not read('events-summary.json')['failures']
# The broad sampler's third component is TT; retain this exact check separately.
details=json.loads(gzip.decompress((OUT/'accuracy.json.gz').read_bytes()))
assert all(len(r[2])==2 or r[2][2]==0 for r in details['positions'])
seams=read('seams.json')
assert all(r['passed'] for r in seams['bodies'])
assert seams['sources'][str(ROOT/'Sources/CLibAstronomy/generated/polynomial-data.h')]==sha(ROOT/'Sources/CLibAstronomy/generated/polynomial-data.h')
traces=read('trace-summary.json')
assert len(traces)==4 and not any(r['failures'] for r in traces.values())
validity=json.loads((ROOT/'Scripts/performance/polynomial/data/shipping-validity.json').read_text())
archived=ROOT/'Scripts/performance/polynomial/results/qualification.json'
assert validity['qualificationSHA256']==sha(archived if archived.exists() else OUT/'qualification.json')
if 'replaySHA256' in validity:
    replayed=ROOT/'Scripts/performance/polynomial/results/replay.json'
    assert validity['replaySHA256']==sha(replayed if replayed.exists() else OUT/'replay.json')
integration=json.loads((ROOT/'Scripts/performance/polynomial/data/integration-validity.json').read_text())
assert integration['evidenceSHA256']==sha(OUT/'integration-exclusions.json')
assert integration['invalid']==read('integration-exclusions.json')['invalid']
for row in read('qualification.json')['bodies']:
    disabled=set(validity['invalid'][row['body']]+integration['invalid'][row['body']])
    assert set(row['invalid'])<=disabled, ('New unqualified segments',row['body'])
save('verification.json',{'passed':True,'stateVectorDistanceChecks':checks,'maxAbsoluteChanges':maxima,
     'positionCount':24120,'independentPositionLimitArcseconds':60,'stationCount':2462,
     'scope':'Native regression and frozen accuracy populations; actual search coverage uses events-summary.json',
     'scriptSHA256':sha(__file__)})
print('Verified:',checks,'state/vector/distance checks, exact metadata/cache replay, and frozen position/event results')
