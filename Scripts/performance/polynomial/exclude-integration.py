#!/usr/bin/env python3
"""Record full-model fallback segments for failing downstream angular-strength samples."""
import gzip
import json
import math
import shutil
from run import HERE, ROOT, OUT, sha
from embed import BODIES, START, STOP

archive=OUT/'initial-campaign';archive.mkdir(exist_ok=True)
for path in OUT.iterdir():
    if path.is_file() and (path.name in ['build.json','downstream-build.json','downstream-timings.json','timings.json'] or path.name.endswith('-windows.json')):
        (archive/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
manifest=json.loads((HERE/'data/generation.json').read_text())
invalid={b:set() for b in BODIES};failures=[]
for scenario in ['nyc-day','nyc-week','reykjavik-day']:
    paths=[OUT/f'{scenario}-{n}-1-windows.json' for n in ['baseline','candidate']]
    a,b=[json.loads(p.read_text()) for p in paths]
    for x,y in zip(a,b):
        assert x['peakTimestamp']==y['peakTimestamp']
        for f,g in zip(x['peakFlagInstances'],y['peakFlagInstances']):
            error=abs(f.get('angularStrength',0)-g.get('angularStrength',0))
            if error<=1e-12:continue
            planet=f['planet'];assert g['planet']==planet
            # Swift Date's reference epoch is 2001-01-01, 365.5 days after J2000.
            # A one-day envelope includes TT conversion and planetary light time.
            ut=x['peakTimestamp']/86400+365.5
            bodies={'Earth'}
            if planet.capitalize() in BODIES:bodies.add(planet.capitalize())
            elif planet not in ['sun','moon']:raise ValueError(planet)
            segments={}
            for body in sorted(bodies):
                width=manifest['bodies'][BODIES.index(body)]['width']
                indexes=list(range(math.floor((ut-1-START)/width),math.floor((ut+1-START)/width)+1))
                invalid[body].update(indexes);segments[body]=indexes
            failures.append({'scenario':scenario,'peakTimestamp':x['peakTimestamp'],'planet':planet,
                             'flag':f['flag'],'baseline':f['angularStrength'],'candidate':g['angularStrength'],
                             'absoluteDifference':error,'segments':segments})
report={'budget':1e-12,'failures':failures,'invalid':{b:sorted(v) for b,v in invalid.items()},
        'inputSHA256':{p.name:sha(p) for p in OUT.glob('*-1-windows.json')},
        'method':'Exclude the planet and Earth segments within one day of each failing sample; retain unchanged coefficients and budgets.'}
p=OUT/'integration-exclusions.json';p.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
(HERE/'data/integration-validity.json').write_text(json.dumps({'evidenceSHA256':sha(p),'invalid':report['invalid']},indent=2)+'\n')
print('Additional integration exclusions:',report['invalid'])
