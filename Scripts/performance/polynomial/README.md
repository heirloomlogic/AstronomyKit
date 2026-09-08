# Polynomial planetary evaluation

The shipping evaluator uses immutable degree-12 Cartesian polynomials fitted to
the complete VSOP87B model. Position and analytic heliocentric velocity come from
one representation; heliocentric distance is the norm of that position before the
existing fixed rotation. Apparent-coordinate and light-time calculations retain
their existing definitions. Public APIs are unchanged; `ephemerisVersion` advances
to identify the new numerical implementation for persisted caches.

## Coverage and qualification

The coefficient archive was recovered from `860a674` without refitting. It covers
1900-01-01 through the end of 2100 TT. Mercury and Earth use eight-day segments,
Neptune uses sixteen days, and the other planets use thirty-two days. The runtime
falls back to the complete VSOP series outside coverage and in disabled segments;
the existing thread-local full-model cache remains active.

The older coefficient screen allowed 1e-11 AU component residuals. The current
production regression budget is stricter: max(1e-12, abs(reference)*1e-12) for
position/velocity components and distance. Qualification against native-math
baseline `53f5c5c` samples 53 epochs in each of 34,418 segments, including interior
points and adjacent-representable endpoints. It disables 10,060 segments and
retains 24,358. Downstream qualification excludes nine more segments after
angular-strength fields exceed their unchanged 1e-12 regression budget. Those
planet and Earth segments use the full evaluator throughout their intervals;
24,349 segments remain enabled. The original failed measurements and offending
samples are retained under `results/initial-campaign/` and
`results/integration-exclusions.json`. This is sampled evidence, not a formal
interpolation-error bound.
The original coefficients, goldens, and independent references are unchanged.

The segment selector corrects subtraction rounding at boundaries, so a timestamp
immediately before a boundary cannot accidentally select the next validity mask.
Independent quadratic tests exercise that case, analytic derivatives, invalid
segments, and nonfinite dates. All 34,426 segment/coverage seams are checked at the
boundary and both adjacent floating-point dates, with four finite-difference
widths crossing each seam. The same component budgets apply.

Historical 0.05-second station displacement remains a reported diagnostic under
[the approved incremental acceptance policy](../native-math/POLICY.md). Independent
station/event limits remain 60 seconds. Coverage, event counts, grouping,
provenance, cancellation, and exhaustion remain acceptance checks.

## Measured performance

Measured 2026-09-08 on Apple M1 Max, macOS 26.6.2, Swift 6.4 / Xcode 27 beta 5.
Each row is the median of five alternating fresh-process Release trials against
native full-model commit `53f5c5c`. All builds, numerical checks, and trace runs
finished before timing. This was a shared desktop, not an isolated benchmark host.
External Node/workerd jobs overlapped the initial week-scan campaign; those week
and Reykjavik trials are retained under `results/contended-scans/` and replaced
with a later five-trial campaign after the jobs stopped. Raw timings and process
snapshots are retained. Local speedups are not platform-wide latency guarantees.

| Workload | Native full model | Polynomial + fallback | Speedup |
| --- | ---: | ---: | ---: |
| nyc-day | 3.206838 s | 2.348599 s | 1.37× |
| nyc-week | 20.096265 s | 14.510853 s | 1.38× |
| reykjavik-day | 3.244399 s | 2.209463 s | 1.47× |
| scoring | 15.398284 s | 2.651833 s | 5.81× |

Scoring excludes chart preparation; scan timing includes preparation. Process
latency and peak resident memory are retained for every trial. The final native
library is 11,924,576 bytes versus 1,059,008 bytes for the baseline, a 10,865,568-byte
increase in this arm64 diagnostic build. Application packaging may differ.

All scoring checksums remain -81888. Scores, window boundaries, peak times, and
discrete window fields match; floating geometry and angular-strength differences
pass their unchanged regression budgets. Scoring passes the 30-second cap in all five trials. The historical two-times product target remains
unmet and is reported separately under the approved incremental-delivery policy.

### Position workloads

Each trial requests 1,600 geocentric positions after one warmup traversal. The
native C loops avoid Python per-position overhead; the Swift probe uses public
APIs with matching bodies and epochs.

| Workload | Native full model | Polynomial + fallback | Speedup |
| --- | ---: | ---: | ---: |
| native/new | 0.213750 s | 0.009867 s | 21.66× |
| native/random | 0.230805 s | 0.011576 s | 19.94× |
| native/refinement | 0.212192 s | 0.000604 s | 351.31× |
| native/repeated | 0.000413 s | 0.000589 s | 0.70× |
| swift/new | 0.215033 s | 0.010163 s | 21.16× |
| swift/random | 0.229386 s | 0.011157 s | 20.56× |
| swift/refinement | 0.213203 s | 0.000593 s | 359.81× |
| swift/repeated | 0.000413 s | 0.000587 s | 0.70× |

The already-warm repeated-epoch case regresses from roughly 0.41 ms to 0.59 ms
per 1,600 positions because eligible calls evaluate their polynomials. New-date
and refinement workloads benefit much more. The published scan gains include the
nine integration exclusions; the faster rejected configuration is archived and
is not the shipping result.

## Validation evidence

- 596 Swift tests in 178 suites pass in debug, Release, and ThreadSanitizer.
- Three independent analytic evaluator tests and all ten diagnostic Python tests
  pass, including the compiled ERFA nutation reference. Both existing generators,
  the polynomial embed check, and the recovered frozen generator build pass.
- 1,824,154 component qualification samples select the initial validity mask;
  103,278 boundary/adjacent-date checks cover every segment and coverage seam.
- All 24,120 independent positions and 2,462 frozen station comparisons pass.
  Maximum independent station error is 40.789318 seconds;
  maximum historical station shift is 0.036049 seconds.

- All 36 independent event-query pairs pass, including overlapping queries,
  convergence, coverage, provenance, and motion/group coherence.
  Maximum independent event error is 59.472942 seconds;
  maximum historical event shift is 0.072957 seconds.

- All 14,458 complete downstream search records retain query/event counts,
  coverage and unresolved reasons, chronology grouping, provenance, and
  cancellation/exhaustion flags. Local station roots alone do not certify search
  discovery; these complete records provide separate downstream evidence.
- 448 additional state/vector/distance checks preserve caller metadata and exact
  replay, including wide epochs and signed zero. The native work-count probe
  observes zero trig calls for 64 fresh qualified position/state/distance queries
  and rejects a full-series negative control. A separate out-of-range probe proves
  full-model cache reuse and rejects an uncached negative control.
- iOS, tvOS, and watchOS builds, strict Swift lint, and native-math guards pass.
  Linux debug/Release/sanitizer execution is required in the PR's CI matrix;
  no local Linux runtime was available.

[Build inputs](results/build.json), [downstream inputs](results/downstream-build.json),
[qualification](results/qualification.json), [seams](results/seams.json),
[event results](results/events-summary.json), [full trace comparison](results/trace-summary.json),
[checks](results/checks.json), and the raw payloads are retained in `results/`.

## Reproduce

Run from the repository root with the native baseline and archived generator
revision available in git. Python 3, Clang, and Swift are required. The frozen
coefficient generator uses its own recovered deterministic engine dependencies;
it does not fit against the shipping native-math engine.

```sh
python3 Scripts/performance/polynomial/embed.py --check
python3 -m unittest discover -s Scripts/performance/polynomial -p 'test_*.py' -v
python3 Scripts/performance/polynomial/experiment.py prepare --output .build/polynomial-generator-check
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
sh Scripts/performance/test-vsop-cache.sh
python3 Scripts/performance/polynomial/run.py build
python3 Scripts/performance/polynomial/qualify.py
python3 Scripts/performance/polynomial/seams.py
python3 Scripts/performance/polynomial/run.py validate
python3 Scripts/performance/polynomial/downstream.py build
python3 Scripts/performance/polynomial/downstream.py events
python3 Scripts/performance/polynomial/traces.py
python3 Scripts/performance/polynomial/verify.py
# Complete all builds, qualification and profiling before timing.
python3 Scripts/performance/polynomial/run.py benchmark
python3 Scripts/performance/polynomial/downstream.py benchmark
```

Regeneration is optional: the verified archive is the shipping source of truth.
The original `experiment.py screen` and `generate` commands retain the historical
fit protocol and limits; they do not update the shipping validity mask or qualify
a release. Re-running `qualify.py` reports current platform results without
rewriting that mask. Its archived hash is specific to this qualification campaign.

Native qualification supports macOS/Linux. Public Swift and downstream timing
probes currently require macOS. Downstream reproduction also requires the archived
AstrologyKit objects listed in the [input manifest](../native-math/results/downstream-inputs.json).
The harness verifies their hashes and links identical Swift objects against each
native evaluator. All chronology experiment modes are disabled. Full traces run
separately from timing; the downstream production dependency pin is unchanged.
