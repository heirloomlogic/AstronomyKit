#!/usr/bin/env python3
"""Compare complete downstream event searches separately from uninstrumented timing."""
import collections
from pathlib import Path
import json
import subprocess
import sys
from run import ROOT, OUT, NAMES, env, save
sys.path.append(str(ROOT/'Scripts/performance/native-math'))
from comparison import differences, spans, utc


def key(r): return json.dumps(r['query'],sort_keys=True,separators=(',',':'))
def events(r):
    groups=collections.defaultdict(list)
    for e in r['events']: groups[json.dumps(e['target'],sort_keys=True)].append(e)
    return {k:sorted(v,key=lambda e:utc(e['instant'])) for k,v in groups.items()}
def groups(r):
    return [sorted(json.dumps(e['target'],sort_keys=True) for e in g['events']) for g in r['chronologicalGroups']]

summary={}
for scenario in ['scoring','nyc-day','nyc-week','reykjavik-day']:
    records={}
    for name in NAMES:
        path=OUT/f'{scenario}-{name}-trace.json'
        command=[str(OUT/(('scoring-' if scenario=='scoring' else 'scan-')+name)),scenario]
        result=subprocess.run(command,env={**env(),'CHRONOLOGY_TRACE':'1','CHRONOLOGY_TRACE_PATH':str(path)},
                              text=True,capture_output=True,timeout=600)
        (OUT/f'{scenario}-{name}-trace.log').write_text(result.stdout+result.stderr)
        assert result.returncode==0,result.stdout+result.stderr
        with Path(str(path)+'.jsonl').open() as f: rows=[json.loads(line) for line in f]
        count=json.loads(path.read_text())['counters']['queries']
        assert len(rows)==count
        records[name]=rows
    reference={key(r):r for r in records['baseline']}
    data={'queries':{n:len(v) for n,v in records.items()},'failures':[],'differences':None,'maxRootShiftSeconds':0}
    seen=set()
    for result in records['candidate']:
        k=key(result); seen.add(k)
        if k not in reference: data['failures'].append({'kind':'query identity','query':result['query']});continue
        full=reference[k]
        data['differences']=differences(full,result,out=data['differences'])
        for field in ['ephemerisID','ephemerisVersion','numericalPolicy','cancelled','exhausted']:
            if full[field]!=result[field]:data['failures'].append({'kind':field,'query':result['query']})
        for field in ['covered','unresolved']:
            if spans(full,field)!=spans(result,field):data['failures'].append({'kind':field,'query':result['query']})
        if groups(full)!=groups(result):data['failures'].append({'kind':'grouping','query':result['query']})
        a,b=events(full),events(result)
        if {k:len(v) for k,v in a.items()}!={k:len(v) for k,v in b.items()}:
            data['failures'].append({'kind':'event identity/count','query':result['query']})
        for target in a.keys()&b.keys():
            for x,y in zip(a[target],b[target]):
                data['maxRootShiftSeconds']=max(data['maxRootShiftSeconds'],abs(utc(x['instant'])-utc(y['instant']))/1e6)
                if x['provenance']!=y['provenance']:
                    data['failures'].append({'kind':'provenance','query':result['query']})
                limit=1e-6 if y['residualUnit']=='degreesPerDay' else 1e-4
                if abs(y['residual'])>limit:
                    data['failures'].append({'kind':'residual','query':result['query']})
    if seen!=reference.keys():data['failures'].append({'kind':'missing queries'})
    summary[scenario]=data;save('trace-summary.json',summary)
    print(scenario,len(records['candidate']),'queries;',len(data['failures']),'failures',flush=True)
assert not any(r['failures'] for r in summary.values())
