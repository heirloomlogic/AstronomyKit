# Performance checks

Native Swift tests now own cache work-avoidance and state-ownership evidence. The retired C probes only exercised implementation patches in `astronomy.c`; the public C-backed JPL, distance, audit, reproducibility, polynomial, ecliptic-state, and event suites remain until the public engine cutover.

| Retired check | Native replacement |
|---|---|
| `VsopCacheTests`, `test-vsop-cache.sh`, `vsop_cache_probe.c` | `EngineVSOP87BCacheTests` counts work across position, state, and distance callers, checks exact keys, nonfinite bypass, FIFO eviction, reset, concurrent callers, and a zero-capacity negative control. |
| `NutationCacheTests`, `test-nutation-cache.sh`, `nutation_cache_probe.c`, `nutation_output_probe.c` | `EngineNutationCacheTests` counts work across angle, rate, tilt, and sidereal-time callers and checks a zero-capacity negative control, exact keys, nonfinite bypass, FIFO eviction, reset, concurrent callers, and series equality. |
| `MoonCacheTests`, `test-moon-cache.sh`, `moon_cache_probe.c`, `moon_output_probe.c` | `EngineMoonCacheTests` counts work in the DE441 series, DE440 table, and blend; checks a zero-capacity negative control, exact keys, nonfinite bypass, FIFO eviction, caller time, and concurrent callers. |

`EngineCacheTests` covers the shared exact-key, bounded-cache, registry, eviction, reset, weak-lifetime, and nested-contention behavior. `EnginePlutoCacheTests` covers Pluto's segment cache, disabled control, reset, eviction, and public fixture contention. `EngineStateOwnershipTests` combines JPL, distance, and independent audit fixtures with Moon, Pluto, nutation, star, and independent gravity-simulation work in varied orders, after resets, and under contention.

Run the integrated evidence with:

```sh
swift test --filter 'EngineStateOwnershipTests|EngineVSOP87BCacheTests|EngineNutationCacheTests|EngineMoonCacheTests|EnginePlutoCacheTests|EngineCacheTests|DeltaTThreadSafetyTests|EngineStarConcurrencyTests|EngineGravitySimulationTests'
```

The optional Release diagnostic records elapsed serial and contended workload time plus process peak resident bytes. The serial pass runs first from cold caches and warms them for the larger contended pass, so the two elapsed times do not establish a speedup. Peak resident bytes are a finite observation from one process, not a leak test. The diagnostic has no pass/fail resource threshold because scheduler, runner, and allocator differences are not correctness failures.

```sh
CACHE_OWNERSHIP_MEASUREMENT_OUTPUT=.context/cache-ownership-release.json swift test -c release --filter EngineStateOwnershipTests.measurement
```

To observe a cold Release test build separately, use a new scratch directory, retain the complete build log, and record `/usr/bin/time -p` output. Afterward, `stat -f %z <scratch>/out/Products/Release/AstronomyKitTests.xctest/Contents/MacOS/AstronomyKitTests` records the linked test executable size on macOS. The elapsed build time and executable size include the package's tests and do not describe the library alone.
