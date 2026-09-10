# Performance checks

Four hardware-independent checks guard the engine's work-avoidance paths. CI runs them on macOS and Linux.

- `test-vsop-cache.sh` compiles `astronomy.c` with counting wrappers around `sin` and `cos`, then runs two probes. `vsop_cache_probe.c` shows that repeated position, state, and distance requests at one epoch outside polynomial coverage reuse the thread-local VSOP cache instead of re-summing the series. `polynomial/work_probe.c` shows that fresh epochs inside qualified polynomial coverage never enter the series at all. Each probe is also run against a negative-control build with the path disabled, which must fail.
- `test-nutation-cache.sh` instruments `iau2000b_eval` in a temporary build. `nutation_cache_probe.c` shows that repeated ecliptic-state requests at one epoch share one nutation evaluation, angle-only calls warm the rate cache, exact signed-zero keys stay distinct, nonfinite keys bypass storage, and the 32-slot FIFO evicts old entries. A negative-control build with the cache bypassed must fail.
- `test-moon-cache.sh` instruments `CalcMoonRaw` in a temporary build. `moon_cache_probe.c` shows that repeated lunar state requests share exactly three series evaluations, exact signed-zero keys stay distinct, nonfinite keys bypass storage, the 32-slot FIFO evicts old entries, and separate threads keep separate entries. It also compares cached and bypassed builds from the same compiler for bit-identical lunar positions, rates, and caller time metadata. A negative-control build with the cache bypassed must fail.
- `polynomial/` holds the polynomial coefficient archive, its generator, and its unit tests. See [its README](polynomial/README.md).

```sh
sh Scripts/performance/test-vsop-cache.sh
sh Scripts/performance/test-nutation-cache.sh
sh Scripts/performance/test-moon-cache.sh
```

The benchmark harnesses and raw timings from the cache (PR #34), native-math (PR #35), and polynomial (PR #36) campaigns were removed once those decisions shipped; they remain in git history at each PR's merge commit. Timing is diagnostic evidence gathered per change, not a checked-in threshold.
