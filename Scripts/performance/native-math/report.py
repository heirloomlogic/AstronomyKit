#!/usr/bin/env python3
"""Archive the completed native-math campaign and generate its measured report."""
import gzip
import json
from pathlib import Path
import shutil
from run import HERE, ROOT, OUT, NAMES, read, sha

accuracy=read('accuracy-summary.json')
verified=read('verification.json')
events=read('events-summary.json')
timings=read('timings.json')
downstream=read('downstream-timings.json')
assert verified['passed'] and not accuracy['failures'] and not events['failures']
assert len(timings)==8 and len(downstream)==4
for report in [timings,downstream]:
    assert all(len(r['trials'][n])==5 for r in report.values() for n in NAMES)
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
    if path.suffix in ['.json','.log']:
        if path.name.endswith('-windows.json') or path.name.startswith('events-') and path.name!='events-summary.json' or path.suffix=='.log':
            (results/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
        else: shutil.copy2(path,results/path.name)
    elif path.name=='accuracy.json.gz': shutil.copy2(path,results/path.name)
checks={}
for name in ['debug','release','tsan','python','lint','iOS','tvOS','watchOS','cache','guard','backend-guard']:
    path=ROOT/'.context'/f'native-{name}.log'
    assert path.exists(),path
    text=path.read_text()
    if name in ['debug','release','tsan']: assert '595 tests in 177 suites passed' in text
    if name in ['iOS','tvOS','watchOS']: assert '** BUILD SUCCEEDED **' in text
    if name=='python': assert 'OK' in text and 'skipped=' not in text
    if name=='lint': assert not text.strip()
    if name=='backend-guard': assert 'Native math guard passed (release)' in text
    if name=='guard': assert 'Negative control passed' in text
    if name=='cache': assert 'Cache probe rejected the uncached negative control.' in text
    checks[name]={'passed':True,'logSHA256':sha(path)}
    (results/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
checks['linux']={'executedLocally':False,'requiredInCI':True}
checks['githubActions']={'executed':False,'note':'Local implementation; no PR or remote CI run created.'}
checks['windowSemantics'] = window_checks
(results/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')

def table(report):
    text='| Workload | Baseline | Native math | Speedup |\n| --- | ---: | ---: | ---: |\n'
    for name,row in report.items():
        med=row['medians'];text+=f"| {name} | {med['baseline']:.6f} s | {med['candidate']:.6f} s | {row['speedup']:.2f}× |\n"
    return text

readme=f'''# Native math: first production performance increment

The shipping engine uses system math on Apple and Linux. Full model tables,
FP contraction policy, exact-epoch caching, time semantics and concurrency
protections remain intact. Existing `ak_*` entry points forward to native math.
The revised [acceptance policy](POLICY.md) permits independently validated
improvements without waiting for the historical end-to-end performance target.

## Measured performance

Measured 2026-09-08 on {read('build.json')['machine']},
{read('build.json')['platform']}. Compiler:
`{read('build.json')['compiler'].strip().replace(chr(10), '; ')}`.
Baseline is cached full-model commit `989828d`; candidate sources and binaries
are identified in [build.json](results/build.json). Each cell is the median
of five alternating fresh-process Release trials. Builds, numerical checks and
profiling did not overlap the timing campaign. This was a shared desktop, not an isolated
benchmark machine; the measurements are local evidence, not platform-wide guarantees.

Each component trial requests 1,600 geocentric positions. Native and public
Swift probes use matching bodies and epochs, with one warmup traversal per
process. New/random/refinement workloads cover new epochs; repeated epochs
measure an already cache-friendly working set. Native C loops avoid Python/ctypes
per-position overhead. Raw trials include native CPU times and checksums.

{table(timings)}

### Downstream workloads

Both arms link identical archived AstrologyKit Release objects with the freshly
built shipping AstronomyKit Swift object. Only C/math differs. All chronology
experiment modes and trace encoding are disabled. This tests the actual event
service and scanning/scoring implementation; it does not update a consumer's
production dependency pin. Commands and input hashes are retained in
[downstream-build.json](results/downstream-build.json).

{table(downstream)}

Scoring excludes chart preparation; process latency, which includes preparation,
is retained in every raw trial. Scan timing includes preparation. Full Codable
window payloads are written after the scan timer and retained for every trial.
Scores, counts, window boundaries and peak times match exactly, as do discrete
fields. Floating geometry differences pass the numerical comparison budgets and
are reported separately in [downstream-timings.json](results/downstream-timings.json). Random
UUIDs and dictionary/set ordering are normalized by the existing comparison tool.
Both arms retain scoring checksum {downstream['scoring']['trials']['candidate'][0]['checksum']}.

The candidate passes the 30-second scoring cap in all five trials. The historical
2× scoring/day/week target remains unmet and remains an overall objective.
These local results qualify the increment under the revised performance and
accuracy policy. Linux CI remains required before release; the broader downstream
optimization is still outstanding.

## Numerical and build validation

- 595 Swift tests in 177 suites passed in debug, Release and ThreadSanitizer.
  All original golden reference constants are retained with the approved shared
  tolerances. Cache replay and caller metadata remain exact.
- All 24,120 monthly common-TT positions pass the unchanged independent
  60-arcsecond position limit. Maximum native-versus-baseline longitude change
  is {max(v[0] for v in accuracy['maxAngularChangeDegreesByBody'].values()):.3g} degrees.
  The sampler returns longitude, latitude and TT; it does not measure distance.
- All 2,462 frozen stations pass the independent 60-second limit. Maximum
  independent error is {accuracy['maxStationErrorSeconds']['candidate']:.6f} seconds;
  maximum historical timestamp shift is {accuracy['maxStationShiftSeconds']:.6f} seconds.
  These local-root checks do not establish complete station discovery.
- {verified['stateVectorDistanceChecks']} additional state/vector/distance checks pass,
  including wide epochs, signed zero, exact metadata and exact repeated calls.
- All 36 original downstream event-query pairs pass accuracy, convergence,
  covered/unresolved interval, cancellation/exhaustion, provenance and coherence
  checks. Maximum independent event error is
  {events['maxIndependentErrorSeconds']['candidate']:.6f} seconds; event timestamps
  match the baseline in these fixtures. The probe reconstructs chronology groups,
  point samples and motion values to verify coherent results in both query windows.
  Complete numerical field differences are retained in
  [events-summary.json](results/events-summary.json).
- The native cache probe reports 48/96/0 trig calls for twelve repeated
  position/state/distance calls. Its uncached negative control reports
  76,848/213,204/17,220 calls and is correctly rejected.
- Both generators, all ten Python diagnostic tests (including the compiled
  ERFA nutation check), strict Swift lint, shipping native-math guards for both Swift build backends and
  iOS/tvOS/watchOS builds pass. Logs are archived under `results/`.
- Linux debug/Release/sanitizer CI remains required. No Linux runtime is installed
  locally, and no remote CI run or release is claimed.

Historical experiment reports and accuracy references are unchanged. Source,
artifact and log hashes are retained with the results.

## Reproduce

From the repository root, with the baseline commit available:

```sh
python3 Scripts/performance/native-math/run.py build
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
sh Scripts/performance/test-vsop-cache.sh
python3 Scripts/check-native-math.py --configuration debug
python3 Scripts/check-native-math.py --configuration release
python3 Scripts/performance/native-math/downstream.py build
python3 Scripts/performance/native-math/run.py validate
python3 Scripts/performance/native-math/downstream.py events
python3 Scripts/performance/native-math/verify.py
# Finish all builds/checks before these uninstrumented timing runs.
python3 Scripts/performance/native-math/run.py benchmark
python3 Scripts/performance/native-math/downstream.py benchmark
```

Component native builds/validation support macOS and Linux; Swift and downstream
probes currently require macOS. Downstream reproduction additionally needs the
archived AstrologyKit build inputs listed in
[downstream-inputs.json](results/downstream-inputs.json). These external Swift
objects/modules are prerequisites, not rebuilt by this harness. The bundled
probes and comparison helper need no files from the earlier investigation.
The downstream builder verifies the original object hashes and leaves their
checkout unchanged.
Full event/scan payloads, raw timings and independent numerical samples are
compressed in `results/`. The archive/report helper expects the local validation
logs named in `report.py`; it never changes references or tolerance budgets.
'''
(HERE/'README.md').write_text(readme)
manifest={str(p.relative_to(HERE)):sha(p) for p in HERE.rglob('*') if p.is_file() and p.name!='sha256.json' and '__pycache__' not in str(p)}
(results/'sha256.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('Archived',len(manifest),'files and wrote README.md')
