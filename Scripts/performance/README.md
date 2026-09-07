# Exact planetary calculation cache

AstronomyKit retains full VSOP87B series results at exact calculation times in a bounded thread-local cache. Position, analytic derivative, and radial-distance requests share entries. Every cache miss evaluates the complete original series in its original order. Caller timestamps, civil UTC conversion, mutable engine settings, and public APIs remain unchanged.

## Throughput

Measured on an Apple M1 Max, macOS 26.6.2, Apple Swift 6.4 / Xcode 27 beta 5. Values are median seconds for 1,600 positions over five trials. Baseline is `8e88bb4`, restored is `c0322c2`, and candidate is identified by its source hashes in [the native measurement record](results/native.json). Native models alternate between trials. The [quiet Swift run](results/swift.json) measured five trials in sequential model blocks. The committed harness now compiles every model first and alternates them between trials to reduce time drift.

| Workload | Before #32 | Restored full model | Cached candidate | Restored / candidate |
| --- | ---: | ---: | ---: | ---: |
| Native diagnostic, new epochs | 0.008873 | 0.561916 | 0.506667 | 1.11× |
| Native diagnostic, repeated epoch | 0.008913 | 0.561456 | 0.006460 | 86.92× |
| Public Swift, new epochs | 0.004769 | 0.544247 | 0.518613 | 1.05× |
| Public Swift, repeated epoch | 0.005018 | 0.552637 | 0.000553 | 998.82× |

Each trial requests Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune, and Sun. New epochs use `UT = 9000 + i × 0.125` for 200 values. The repeated workload requests all eight bodies 200 times at UT 9000 after warmup; it measures a working set that fits in the cache. Native timing uses the issue's `measure.Model.position` diagnostic, including ctypes overhead. The Swift probe compiles the shipping Swift sources with `-O -whole-module-optimization` and calls `CelestialBody.geocentricPosition(at:)`. Its work differs from the native ecliptic diagnostic, so compare models within each row.

The repeated workload benefits most. New-epoch calculations still evaluate the full model and remain much slower than the truncated pre-#32 baseline. This candidate does not establish the shared release gate: AstrologyKit scoring and representative Edict scans must separately finish within 2× their measured pre-change baselines. AstrologyKit owns those downstream measurements. CI caps and accuracy tolerances are unchanged.

A three-second sample of the optimized restored Swift executable recorded 2,250 main-thread samples, about 97% in deterministic trigonometry and argument reduction beneath VSOP evaluation. [The captured profile](results/swift-restored.sample.txt.gz) preserves the call tree. The [cache-size experiment](results/cache-sizes.json) found 32 entries per body sufficient for the repeated workload; 16 entries evicted needed Earth evaluations. The selected cache uses 16,416 bytes per thread on arm64. Entries expire by bounded replacement or thread exit; there is no shared lock or heap allocation.

A later run of the alternating harness overlapped an external `swiftpm-testing-helper` process observed at 442% CPU. Its [raw measurements](results/contended-benchmark.json) are retained and excluded from the table. These local timings establish reuse benefits, but do not supply an isolated-machine release baseline. The archived probe used for each measurement is included with its hashes.

## Verification

- Serial debug, release, and ThreadSanitizer each passed 595 tests in 177 suites, including unchanged JPL/Audit accuracy references and bit-exact snapshots. The new Swift tests cover timestamp metadata, model/time isolation, eviction, signed zero, and concurrent call order.
- The [equivalence check](results/equivalence.json) matched the restored engine bit-for-bit at 24,120 archived monthly TT positions, their 24,120 repeated requests, and 448 state/vector/distance requests. It compares computed results and caller metadata without refreshing snapshots or references.
- The native reuse test counts deterministic trig calls. Twelve warm position/state/radius requests use 48/96/0 calls; the uncached restored source uses 76,848/213,204/17,220 and fails the test. CI runs this hardware-independent check on macOS and Linux.
- Both offline generators pass. All ten Python diagnostic tests pass, including the independent ERFA nutation reference. Strict Swift lint and the host-libm symbol guard pass. Compressed test logs and source/artifact hashes are under `results/`.

Local qualification uses the compiler above. Linux and other Apple platform checks run in the PR's existing CI matrix; downstream release qualification remains separate.

## Reproduce

From the repository root, on an otherwise idle machine:

```sh
python3 Scripts/performance/benchmark.py --output .build/performance
python3 Scripts/performance/verify-equivalence.py --reference .build/performance/restored.dylib --candidate .build/performance/candidate.dylib --output .build/performance/equivalence.json
sh Scripts/performance/test-vsop-cache.sh
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
```

The native benchmark and reuse test support macOS/Linux; use `.so` for the equivalence libraries on Linux. The optimized public-Swift probe currently requires macOS. The benchmark needs the two historical commits locally, checks generated tables, records compilers and source hashes, and fails on changed native sample bits or Swift checksums. The equivalence checker uses the frozen common-TT population and no external oracle package. Timing is diagnostic evidence; the reuse test enforces work avoided without a machine-dependent wall-clock threshold.
