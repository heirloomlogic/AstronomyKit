#!/usr/bin/env python3
"""Check and archive the final polynomial qualification campaign."""
import gzip
import json
import shutil
from run import HERE, ROOT, OUT, NAMES, read, sha

assert read('verification.json')['passed']
accuracy=read('accuracy-summary.json')
downstream=read('downstream-timings.json')
timings=read('timings.json')
assert len(timings)==8 and len(downstream)==4
assert all(len(row['trials'][n])==5 for report in [timings,downstream] for row in report.values() for n in NAMES)
window_checks = {}
for name, row in downstream.items():
    diff = row['completeWindowDifferences']
    if diff is None: continue
    assert not diff['discrete'], row
    # Integers and timestamps are numeric in JSON too. Require behavioral fields
    # (scores, weights, counts, boundaries and peak times) to remain exact; only
    # the following floating geometry fields may differ within numerical budgets.
    for field, delta in diff['numeric'].items():
        if field.startswith(('[]' + '.peakChartState.positions.', '[]' + '.peakChartState.declinations.',
                             '[]' + '.peakChartState.speeds.')) or field in (
                '[].peakChartState.aspects[].orb', '[].peakFlagInstances[].separation',
                '[].peakFlagInstances[].distanceToSun'):
            limit = 1e-8
        elif field == '[].peakFlagInstances[].angularStrength':
            limit = 1e-12
        else:
            raise AssertionError(f'Changed behavioral window field: {name} {field}: {delta}')
        assert delta['maxAbsoluteDifference'] <= limit, (name, field, delta)
    window_checks[name] = {'passed':True, 'behavioralNumericFieldsExact':True,
                          'floatingGeometryDifferencesWithinBudgets':True}
assert len({r['checksum'] for n in NAMES for r in downstream['scoring']['trials'][n]})==1
for n in NAMES:
    assert sha(read('build.json')['libraries'][n]['path'])==accuracy['libraries'][n]['binarySHA256']
for name,digest in read('downstream-build.json')['executables'].items():
    assert sha(OUT/name)==digest


results=HERE/'results';results.mkdir(exist_ok=True)
for path in OUT.iterdir():
    if path.suffix in ['.json','.log','.jsonl']:
        if path.suffix in ['.log','.jsonl'] or path.name.endswith('-windows.json') or (path.name.startswith('events-') and path.name!='events-summary.json'):
            with path.open('rb') as source, (results/(path.name+'.gz')).open('wb') as destination:
                with gzip.GzipFile(fileobj=destination,mode='wb',mtime=0) as compressed:
                    shutil.copyfileobj(source,compressed)
        else:
            name=path.name
            key={'qualification.json':'qualificationSHA256','replay.json':'replaySHA256'}.get(name)
            if key:
                validity=json.loads((HERE/'data/shipping-validity.json').read_text())
                if sha(path)!=validity.get(key): name=name.replace('.json','-current.json')
            shutil.copy2(path,results/name)
    elif path.name=='accuracy.json.gz': shutil.copy2(path,results/path.name)
for archive in ['initial-campaign','contended-scans']:
    if (OUT/archive).exists(): shutil.copytree(OUT/archive,results/archive,dirs_exist_ok=True)
checks={}
for name in ['debug','release','tsan','python','accuracy-python','lint','iOS','tvOS','watchOS','cache','guard-debug','guard-release','generator']:
    path=ROOT/'.context'/f'polynomial-{name}.log'
    content=path.read_text()
    if name in ['debug','release','tsan']: assert '596 tests in 178 suites passed' in content,name
    if name in ['iOS','tvOS','watchOS']: assert '** BUILD SUCCEEDED **' in content,name
    if name in ['python','accuracy-python']: assert 'OK' in content and 'skipped=' not in content,name
    if name=='lint': assert not content.strip()
    if name.startswith('guard-'): assert 'Native math guard passed' in content
    if name=='cache': assert 'Polynomial probe rejected the full-series negative control.' in content
    if name=='generator': assert 'Verified iau2000b_full.h' in content and 'Traceback' not in content
    checks[name]={'passed':True,'logSHA256':sha(path)}
    (results/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
checks['windowSemantics']=window_checks
checks['linux']={'executedLocally':False,'requiredInCI':True}
(results/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
print('Archived passing qualification, complete traces, windows, raw trials and build checks')
