#!/usr/bin/env python3
"""Pair unchanged downstream Swift against baseline/native C and retain full payloads."""
import argparse
import gzip
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

from run import HERE, ROOT, OUT, NAMES, sha, save, read, env, invoke
from comparison import canonical, differences, spans, utc


def build():
    frozen=json.loads((HERE/'results/downstream-inputs.json').read_text())
    for p,h in frozen['objects'].items():
        assert sha(p)==h, f'Archived downstream object changed: {p}'
    # Use the freshly built shipping AstronomyKit Swift object for both arms.
    # Only native math differs; downstream event/search experiment modes stay off.
    astronomy=ROOT/'.build/release/AstronomyKit.o'
    assert astronomy.exists()
    records={'objects':{**frozen['objects'],str(astronomy):sha(astronomy)},'commands':{},'executables':{}}
    for kind in ['scoring','scan','events']:
        original=frozen['commands'][kind]
        original_probe=next(Path(p) for p in original if p.endswith('.swift'))
        probe=HERE/(kind+'-probe.swift')
        assert probe.exists(), f"Missing bundled probe: {probe}"
        records.setdefault('probes',{})[str(probe)]=sha(probe)
        for name in NAMES:
            lib=Path(read('build.json')['libraries'][name]['path'])
            cmd=[str(probe) if p==str(original_probe) else
                 str(astronomy) if p.endswith('/AstronomyKit.o') else
                 str(lib) if p.endswith('.dylib') else p for p in original]
            key=kind+'-'+name
            cmd[-1]=str(OUT/key)
            invoke(cmd)
            records['commands'][key]=cmd
            records['executables'][key]=sha(OUT/key)
    save('downstream-build.json',records)


def events():
    rows={}
    for name in NAMES:
        path=OUT/f'events-{name}.json'
        p=subprocess.run([str(OUT/('events-'+name)),str(ROOT/'Scripts/accuracy/fixtures'),str(path)],
                         env=env(),text=True,capture_output=True)
        (OUT/f'events-{name}.log').write_text(p.stdout+p.stderr)
        assert p.returncode==0,p.stderr
        rows[name]=json.loads(path.read_text())
        print(name,p.stdout.strip(),flush=True)
    failures=[]; shifts=[]; errors={n:[] for n in NAMES}; detail=None
    assert len(rows['baseline'])==len(rows['candidate'])==36
    for a,b in zip(rows['baseline'],rows['candidate']):
        identity=b['identity']
        if a['identity']!=identity: failures.append([identity,'identity'])
        for name,r in [('baseline',a),('candidate',b)]:
            if not r['coherent']: failures.append([identity,name,'coherence'])
        for field in ['result','overlapping']:
            x,y=a[field],b[field]
            detail=differences(x,y,out=detail)
            for key in ['query','ephemerisID','ephemerisVersion','numericalPolicy','cancelled','exhausted']:
                if x[key]!=y[key]: failures.append([identity,key])
            for key in ['covered','unresolved']:
                if spans(x,key)!=spans(y,key): failures.append([identity,key])
            if len(x['events'])!=1 or len(y['events'])!=1:
                failures.append([identity,'event count']);continue
            for n,r in [('baseline',a),('candidate',b)]:
                e=r[field]['events'][0]
                error=abs(utc(e['instant'])/1e6-r['referenceDate']);errors[n].append(error)
                limit=1e-6 if e['residualUnit']=='degreesPerDay' else 1e-4
                if not math.isfinite(e['residual']) or abs(e['residual'])>limit:
                    failures.append([identity,n,'residual'])
                if error>60 or utc(e['bracket']['end'])-utc(e['bracket']['start'])>1000:
                    failures.append([identity,n,'accuracy/convergence'])
            e,f=x['events'][0],y['events'][0]
            if e['target']!=f['target']: failures.append([identity,'target'])
            shifts.append(abs(utc(e['instant'])-utc(f['instant']))/1e6)
    save('events-summary.json',{'queryPairs':36,'failures':failures,'maxHistoricalShiftSeconds':max(shifts),
         'maxIndependentErrorSeconds':{n:max(v) for n,v in errors.items()},'completeRecordDifferences':detail,
         'groupingValidation':'Probe recomputes groups and exact point samples from every returned event in each arm.'})
    print('Event comparison failures:',failures,flush=True)
    assert not failures


def benchmark():
    report={}
    historical={'scoring':.130250958,'nyc-day':.038368666,'nyc-week':.166827083,'reykjavik-day':.036499125}
    for scenario in historical:
        rows={n:[] for n in NAMES};payloads={n:[] for n in NAMES}
        for trial in range(5):
            for name in NAMES[::(-1 if trial%2 else 1)]:
                key=f'{scenario}-{name}-{trial+1}'
                windows=OUT/(key+'-windows.json')
                started=time.perf_counter()
                p=subprocess.run([str(OUT/(('scoring-' if scenario=='scoring' else 'scan-')+name)),scenario],
                    env={**env(),'CHRONOLOGY_WINDOWS_PATH':str(windows)},text=True,capture_output=True,timeout=300)
                elapsed=time.perf_counter()-started
                (OUT/(key+'.log')).write_text(p.stdout+p.stderr)
                # The baseline can exceed its downstream 30-second cap. Preserve it as
                # a separate result rather than aborting this incremental comparison.
                if scenario=='scoring':
                    m=re.search(r'320 scorings in ([\d.]+) seconds.*checksum (-?\d+)',p.stdout)
                    assert m,p.stdout+p.stderr
                    data={'seconds':float(m[1]),'checksum':int(m[2]),'scoringCapPassed':float(m[1])<=30}
                else:
                    assert p.returncode==0,p.stdout+p.stderr
                    value=json.loads(next(l for l in p.stdout.splitlines() if l.startswith('{') and 'windows' in l))
                    data={'seconds':value['seconds'],'windowCount':len(value['windows'])}
                    payloads[name].append(canonical(json.loads(windows.read_text())))
                data.update(processSeconds=elapsed,exitCode=p.returncode)
                rows[name].append(data)
                print(key,round(data['seconds'],3),flush=True)
        med={n:statistics.median(r['seconds'] for r in rr) for n,rr in rows.items()}
        diffs=None
        for a,b in zip(payloads['baseline'],payloads['candidate']): diffs=differences(a,b,out=diffs)
        report[scenario]={'trials':rows,'medians':med,'speedup':med['baseline']/med['candidate'],
                          'historicalTargetSeconds':2*historical[scenario],
                          'historicalTargetPassed':med['candidate']<=2*historical[scenario],
                          'completeWindowDifferences':diffs}
        save('downstream-timings.json',report)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['build','events','benchmark']);a=p.parse_args()
    globals()[a.mode]()
