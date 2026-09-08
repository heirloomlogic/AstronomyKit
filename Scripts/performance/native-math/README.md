# Native math: first production performance increment

The shipping engine uses system math on Apple and Linux. Full model tables,
FP contraction policy, exact-epoch caching, time semantics and concurrency
protections remain intact. Existing `ak_*` entry points forward to native math.
The revised [acceptance policy](POLICY.md) permits independently validated
improvements without waiting for the historical end-to-end performance target.

## Measured performance

Measured 2026-09-08 on arm64,
macOS-26.6.2-arm64-arm-64bit-Mach-O. Compiler:
`Apple Swift version 6.4 (swiftlang-6.4.0.30.4 clang-2100.3.30.1); Target: arm64-apple-macosx26.0`.
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

| Workload | Baseline | Native math | Speedup |
| --- | ---: | ---: | ---: |
| native/new | 0.493722 s | 0.208179 s | 2.37× |
| native/random | 0.495627 s | 0.220270 s | 2.25× |
| native/refinement | 0.511201 s | 0.209721 s | 2.44× |
| native/repeated | 0.000508 s | 0.000456 s | 1.11× |
| swift/new | 0.490986 s | 0.209232 s | 2.35× |
| swift/random | 0.495735 s | 0.221284 s | 2.24× |
| swift/refinement | 0.531747 s | 0.222965 s | 2.38× |
| swift/repeated | 0.000515 s | 0.000417 s | 1.24× |


### Downstream workloads

Both arms link identical archived AstrologyKit Release objects with the freshly
built shipping AstronomyKit Swift object. Only C/math differs. All chronology
experiment modes and trace encoding are disabled. This tests the actual event
service and scanning/scoring implementation; it does not update a consumer's
production dependency pin. Commands and input hashes are retained in
[downstream-build.json](results/downstream-build.json).

| Workload | Baseline | Native math | Speedup |
| --- | ---: | ---: | ---: |
| nyc-day | 8.168896 s | 3.780528 s | 2.16× |
| nyc-week | 45.640230 s | 19.667197 s | 2.32× |
| reykjavik-day | 6.794981 s | 2.958957 s | 2.30× |
| scoring | 39.731222 s | 16.053018 s | 2.48× |


Scoring excludes chart preparation; process latency, which includes preparation,
is retained in every raw trial. Scan timing includes preparation. Full Codable
window payloads are written after the scan timer and retained for every trial.
Scores, counts, window boundaries and peak times match exactly, as do discrete
fields. Floating geometry differences pass the numerical comparison budgets and
are reported separately in [downstream-timings.json](results/downstream-timings.json). Random
UUIDs and dictionary/set ordering are normalized by the existing comparison tool.
Both arms retain scoring checksum -81888.

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
  is 1.14e-13 degrees.
  The sampler returns longitude, latitude and TT; it does not measure distance.
- All 2,462 frozen stations pass the independent 60-second limit. Maximum
  independent error is 40.799618 seconds;
  maximum historical timestamp shift is 0.005150 seconds.
  These local-root checks do not establish complete station discovery.
- 448 additional state/vector/distance checks pass,
  including wide epochs, signed zero, exact metadata and exact repeated calls.
- All 36 original downstream event-query pairs pass accuracy, convergence,
  covered/unresolved interval, cancellation/exhaustion, provenance and coherence
  checks. Maximum independent event error is
  59.477234 seconds; event timestamps
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
