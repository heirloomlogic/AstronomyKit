# Performance checks

Two hardware-independent checks guard the engine's work-avoidance paths. CI runs both on macOS and Linux.

- `test-vsop-cache.sh` compiles `astronomy.c` with counting wrappers around `sin` and `cos`, then runs two probes. `vsop_cache_probe.c` shows that repeated position, state, and distance requests at one epoch outside polynomial coverage reuse the thread-local VSOP cache instead of re-summing the series. `polynomial/work_probe.c` shows that fresh epochs inside qualified polynomial coverage never enter the series at all. Each probe is also run against a negative-control build with the path disabled, which must fail.
- `polynomial/` holds the polynomial coefficient archive, its generator, and its unit tests. See [its README](polynomial/README.md).

```sh
sh Scripts/performance/test-vsop-cache.sh
```

The benchmark harnesses and raw timings from the cache (PR #34), native-math (PR #35), and polynomial (PR #36) campaigns were removed once those decisions shipped; they remain in git history at each PR's merge commit. Timing is diagnostic evidence gathered per change, not a checked-in threshold.
