# Polynomial planetary evaluation

The shipping evaluator uses immutable degree-12 Cartesian polynomials fitted to the complete VSOP87B model. Position and analytic heliocentric velocity come from one representation; heliocentric distance is the norm of that position before the existing fixed rotation. Apparent-coordinate and light-time calculations retain their existing definitions. Public APIs are unchanged. `ephemerisVersion` is `3.0.0-candidate.4+vsop87b-comp.poly-v2.iau2000b.utc-c72.native-libm`, so persisted caches are not reused across the numerics change.

This archive replaces the one at `7dd8f01`, which disabled 10,069 of its 34,418 segments. Those segments were not failing on fit error. `VsopCoords`, `VsopDeriv` and `VsopHelioDistance` accumulated hundreds of series terms with plain addition, and the t^1 longitude series begins with the mean-motion constant (26088 rad/millennium for Mercury, whose ulp is 3.6e-12), so every later term rounded at that ulp and the accumulated loss was multiplied by t. The qualification budget max(1e-12, abs(reference)*1e-12) was measuring the full model's own arithmetic. The error is systematic and linear in |t|: at the coverage edges it reaches 4.45e-12 AU for Mercury, 1.47e-12 Venus, 1.20e-12 Earth, 1.68e-12 Mars, 1.19e-12 Jupiter and 6e-13 to 8e-13 AU for the outer planets. Fit degree could not close that gap; Mercury width 2 screened at 4.148e-12 at degree 12 and again at degree 24.

Commit `8a1680535d7f4afc523dbe9e9041435dca9ddc10` replaces every accumulation with Neumaier compensated addition, same terms in the same order, and matches a Python `math.fsum` evaluation of the same tables bit for bit. Measured per call with a noinline harness, compensation costs 6% to 13% on coordinate evaluation for Mercury through Mars and 30% to 39% for Saturn through Neptune, whose series are short. That path now serves only the 413 disabled segments, dates outside 1900-2100, and the reference arm.

## Coverage and qualification

Coverage is TT [-36524.5, 36889.5), 1900-01-01 through the end of 2100. The runtime falls back to the complete VSOP series outside coverage and in disabled segments; the existing thread-local full-model cache remains active.

`experiment.py` pins fit and qualification to `8a16805`. A fit must target the numerics it is qualified against, so the pin tracks the shipping evaluator instead of a frozen historical revision; `PROTOCOL.md` records why the v1 archive cannot be kept. Screening limits tightened from 1e-11 to 2.5e-13 AU and AU/day, four times inside the production budget of max(1e-12, abs(reference)*1e-12). A 1e-13 limit was rejected because no configuration reaches it for the inner planets even with compensation.

Screening selected the previous shipping grid unchanged except Saturn, which moved from 32-day to 16-day segments. All bodies are degree 12. Screen margins against the 1e-12 production budget are Mercury 4.2x, Venus 4.6x, Earth 5.3x, Mars 7.6x, Jupiter 11.9x, Saturn 17.1x, Uranus 15.2x and Neptune 23.5x.

Full-range generation fits 36,712 segments and validates 51 samples in each: Mercury and Earth 9,177 segments at eight days, Saturn and Neptune 4,589 at sixteen, Venus, Mars, Jupiter and Uranus 2,295 at thirty-two. 413 segments miss the 2.5e-13 screening limit and stay on the full model: Mercury 409, clustered in 1900-1920 and 2060-2100 where |t| is largest, Venus 4, and none for the other six bodies. Full-range position and velocity maxima are Mercury 4.16e-13 AU and 1.70e-13 AU/day, Venus 3.02e-13 and 3.25e-14, Earth 2.40e-13 and 3.54e-14, Mars 1.78e-13 and 2.34e-14, Jupiter 1.11e-13 and 8.54e-15, Saturn 7.24e-14 and 1.40e-16, Uranus 9.41e-14 and 3.10e-14, Neptune 9.59e-14 and 2.82e-14. Coefficient data is 11,454,144 bytes, against 10.74 MB in the previous archive.

Qualification builds the same revision with the polynomial path stubbed out (`#define PolynomialPosition(b,t,p,v) 0`), so every reference sample takes the full compensated series. It samples 53 epochs, including interior points and adjacent-representable endpoints, in every one of the 36,712 segments, including the 413 already on the full model. There are no failures. Maximum budget ratios are Mercury 0.411, Venus 0.313, Earth 0.239, Mars 0.193, Jupiter 0.102, Saturn 0.069, Uranus 0.068 and Neptune 0.061. The validity mask contributed by qualification is empty: the only disabled segments are the 413 from the screening limit.

`replay.py` evaluates the four frozen request populations in `data/requests/`, every ephemeris request the workloads actually made, at their exact TT under the production budget. Scoring is 678,903 records over 95,936 unique (kind, body, TT) triples, New York day 940,669 over 644,568, New York week 5,295,748 over 1,636,249, Reykjavik day 830,690 over 597,438. Every unique request was evaluated, none failed, and the maximum budget ratio is 0.154 for scoring and 0.073 to 0.075 for the three scans. Downstream integration contributes no exclusions; the nine angular-strength exclusions carried by the previous archive all clear.

Seam checks cover 110,160 boundary and adjacent-date positions across every segment and coverage seam, with four central-difference widths crossing each seam. Maximum component ratio is 0.246 and maximum stencil ratio 0.218; all bodies pass. The segment selector corrects subtraction rounding at boundaries, so a timestamp immediately before a boundary cannot select the next segment's mask. Independent quadratic tests exercise that case along with analytic derivatives, invalid segments and nonfinite dates. This is sampled evidence, not a formal interpolation-error bound.

Historical station and event displacement remains a reported diagnostic under [the approved incremental acceptance policy](../native-math/POLICY.md). Independent station and event limits remain 60 seconds. Coverage, event counts, grouping, provenance, cancellation and exhaustion remain acceptance checks.

## Measured performance

Measured 2026-09-08 on Apple M1 Max, macOS 26.6.2, Swift 6.4 / Xcode 27 beta 5. Each row is the median of five alternating fresh-process Release trials. The baseline arm is the compensated full model with the polynomial path stubbed out; the candidate is this archive. All builds, numerical checks and trace runs finished before timing. This was a shared desktop, not an isolated benchmark host. Raw timings and process snapshots are retained for every trial. Local speedups are not platform-wide latency guarantees.

| Workload | Compensated full model | Polynomial + fallback | Speedup |
| --- | ---: | ---: | ---: |
| nyc-day | 4.063303 s | 0.416684 s | 9.75x |
| nyc-week | 22.068531 s | 2.896673 s | 7.62x |
| reykjavik-day | 3.757700 s | 0.470095 s | 7.99x |
| scoring | 19.654002 s | 1.369029 s | 14.36x |

These ratios are not comparable to the 1.37x to 5.81x reported at `7dd8f01`. That campaign used the plain-summation native baseline at `53f5c5c`, which ran nyc-day in 3.206838 s; this baseline arm is slower because it carries compensation on every evaluation and because the host was shared. Against the previous shipping archive (nyc-day 2.348599 s, nyc-week 14.510853 s, reykjavik-day 2.209463 s, scoring 2.651833 s) the candidate is 5.6x, 5.0x, 4.7x and 1.9x faster.

Scoring excludes chart preparation; scan timing includes preparation. The candidate native library is 12,651,104 bytes against 1,059,008 for the baseline in this arm64 diagnostic build. Application packaging may differ.

All scoring checksums are -81888 in every trial of both arms. Scores, window boundaries, peak times and discrete window fields match; floating geometry and angular-strength differences pass their unchanged regression budgets. Scoring passes the 30-second cap in all five trials. The historical two-times product targets (0.076737 s day, 0.333654 s week, 0.072998 s Reykjavik, 0.260502 s scoring) remain unmet by 5.4x, 8.7x, 6.4x and 5.3x. The remaining time is AstrologyKit query discovery and refinement rather than ephemeris evaluation, and is reported separately under the incremental-delivery policy.

### Position workloads

Each trial requests 1,600 geocentric positions after one warmup traversal. The native C loops avoid Python per-position overhead; the Swift probe uses public APIs with matching bodies and epochs.

| Workload | Compensated full model | Polynomial + fallback | Speedup |
| --- | ---: | ---: | ---: |
| native/new | 0.251621 s | 0.000604 s | 416.6x |
| native/random | 0.263168 s | 0.000591 s | 445.3x |
| native/refinement | 0.262116 s | 0.000623 s | 420.7x |
| native/repeated | 0.000443 s | 0.000620 s | 0.71x |
| swift/new | 0.251726 s | 0.000574 s | 438.9x |
| swift/random | 0.264323 s | 0.000608 s | 434.6x |
| swift/refinement | 0.248992 s | 0.000595 s | 418.3x |
| swift/repeated | 0.000415 s | 0.000586 s | 0.71x |

The already-warm repeated-epoch case still regresses, from roughly 0.42 ms to 0.59 ms per 1,600 positions, because eligible calls evaluate the polynomial instead of hitting the full-model cache. New-date, random and refinement traversals no longer fall back at all, which is why they gain more than they did in the previous archive.

## Validation evidence

- 596 Swift tests in 178 suites pass in debug, Release and ThreadSanitizer builds.
- Nine polynomial Python tests pass, three for the evaluator and six for request replay, along with the ten accuracy diagnostics including the compiled ERFA nutation reference. Both existing generators, the polynomial embed check, native-math guards in debug and Release, the cache probe and strict Swift lint pass.
- All 24,120 independent monthly positions and 2,462 frozen station comparisons pass. Maximum independent station error is 40.789318 seconds; maximum historical station shift is 0.005150 seconds, down from 0.036049.
- All 36 independent event-query pairs pass, including overlapping queries, convergence, coverage, provenance and motion/group coherence. Maximum independent event error is 59.472942 seconds; maximum historical event shift is 0.021458 seconds, down from 0.072957.
- All 14,458 complete downstream search records (scoring 1,403, nyc-day 1,463, nyc-week 10,128, reykjavik-day 1,464) retain query and event counts, coverage and unresolved reasons, chronology grouping, provenance, and cancellation and exhaustion flags. Maximum root shift is 1e-6 seconds in the week scan and zero elsewhere. Local station roots alone do not certify search discovery; these complete records provide separate downstream evidence.
- 448 additional state, vector and distance checks preserve caller metadata and exact replay, including wide epochs and signed zero. Maximum absolute change against the compensated model is 9.53e-14 AU for `HelioVector`, `HelioState` and `BaryState`, and 1.42e-14 AU for `HelioDistance`. The native work-count probe observes zero trig calls for fresh qualified position, state and distance queries and rejects a full-series negative control; a separate out-of-range probe proves full-model cache reuse and rejects an uncached negative control.
- iOS, tvOS and watchOS builds pass. Linux debug, Release and sanitizer execution runs in the PR's CI matrix; no local Linux runtime was available.

The failed chronology, fallback-investigation, motion-investigation and regression-audit harnesses have been removed. The one measurement from them that bears on this change, that compensated summation alone moved the Mars station at TT -33748.35542866588 from +0.079098 s to -0.000402 s relative to the smooth motion root, is preserved in the compensation commit message.

[Build inputs](results/build.json), [downstream inputs](results/downstream-build.json), [qualification](results/qualification.json), [request replay](results/replay.json), [seams](results/seams.json), [event results](results/events-summary.json), [full trace comparison](results/trace-summary.json), [checks](results/checks.json), and the raw payloads are retained in `results/`.

## Reproduce

Run from the repository root. Python 3, Clang and Swift are required. `experiment.py` fetches the pinned full-model sources from git, so the fit and qualification reference need not be checked out.

```sh
python3 Scripts/performance/polynomial/embed.py --check
python3 -m unittest discover -s Scripts/performance/polynomial -p 'test_*.py' -v
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
sh Scripts/performance/test-vsop-cache.sh
python3 Scripts/performance/polynomial/experiment.py screen --output .build/polynomial-regeneration
python3 Scripts/performance/polynomial/experiment.py generate --output .build/polynomial-regeneration
# Copy the generated coefficients (gzipped *.bin), *.valid, generation.json and selection.json into data/.
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/run.py build
python3 Scripts/performance/polynomial/qualify.py --write-mask
python3 Scripts/performance/polynomial/replay.py --write-mask
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/seams.py
python3 Scripts/performance/polynomial/run.py validate
swift build -c release
python3 Scripts/performance/polynomial/downstream.py build
python3 Scripts/performance/polynomial/downstream.py events
python3 Scripts/performance/polynomial/traces.py
# Complete every build, mask update and trace run before timing.
python3 Scripts/performance/polynomial/downstream.py benchmark
python3 Scripts/performance/polynomial/exclude-integration.py
python3 Scripts/performance/polynomial/verify.py
python3 Scripts/performance/polynomial/run.py benchmark
python3 Scripts/performance/polynomial/report.py
```

`embed.py` runs twice because the compiled header combines the coefficients with the masks that `qualify.py --write-mask` and `replay.py --write-mask` produce. The ERFA nutation diagnostic needs a compiled full-model library: run the accuracy suite with `ASTRONOMY_ACCURACY_LIBRARY=.build/polynomial-shipping/candidate.dylib`, otherwise that test is skipped.

Native qualification supports macOS and Linux. The public Swift and downstream timing probes require macOS. Downstream reproduction also requires the archived AstrologyKit objects listed in the [input manifest](../native-math/results/downstream-inputs.json); the harness verifies their hashes and links identical Swift objects against each native evaluator. Full traces run separately from timing, and the downstream production dependency pin is unchanged.
