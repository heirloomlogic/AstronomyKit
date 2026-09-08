# Maintaining AstronomyKit

This document is for maintainers. It describes how AstronomyKit vendors the [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library and how to update that vendored copy. Day-to-day contribution guidance lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## What is vendored

AstronomyKit wraps a single-file C library. Two files are copied from upstream, with the local patches listed below:

- `Sources/CLibAstronomy/astronomy.c` — the implementation
- `Sources/CLibAstronomy/include/astronomy.h` — the public C header

Everything else under `Sources/CLibAstronomy/` is ours: `polynomial.h` (the polynomial evaluator) and the generated coefficient tables under `generated/`. The Swift layer in `Sources/AstronomyKit/` is ours and is not part of the vendored code.

The top of `astronomy.c` carries a **vendoring note** recording the exact upstream commit and the local patches. That note is the source of truth; keep it current when you update.

## Version & tag scheme

Release tags embed the bundled engine version:

```
X.Y.Z+upstream-A.B.C
```

- `X.Y.Z` is AstronomyKit's own [semantic version](https://semver.org).
- `+upstream-A.B.C` is the Astronomy Engine release the vendored `astronomy.c` corresponds to (see its `ASTRONOMY_ENGINE_VERSION` / upstream release notes).

Bumping the vendored library changes only the `+upstream-` suffix unless it also changes AstronomyKit's public API or behavior, in which case bump `X.Y.Z` per semver as usual.

## Local patches (must survive every update)

The vendored `astronomy.c` includes the patches below. Preserve them after every upstream sync, or verify that upstream adopted an equivalent implementation.

1. **Pluto orbit cache mutex.** A `pthread` mutex (`pluto_cache_mutex`) guards the Pluto segment cache. `CalcPluto` holds the lock across both the segment lookup and its use; `Astronomy_Reset` takes it before freeing the cache. Prevents a use-after-free between concurrent calculation and reset.

2. **Atomic Delta T function pointer.** `DeltaTFunc` is a C11 `_Atomic` (`stdatomic.h`). `Astronomy_SetDeltaTFunction` stores with release ordering; `TerrestrialTime` loads with acquire ordering. Lets the Delta T model be swapped safely while calculations run on other threads.

3. **Atomic performance counters.** The undocumented counters `_CalcMoonCount`, `_AltitudeDiffCallCount`, and `_FindAscentMaxRecursionDepth` are C11 `_Atomic`, since concurrent Moon and rise/set calculations increment them.

4. **Constellation lazy-init `pthread_once`.** `Astronomy_Constellation` lazily builds a J2000→B1875 rotation matrix on first use. The state was function-local `static`s, so concurrent first calls raced. Initialization is now hoisted to file scope (`constel_init_once`, `constel_epoch2000`, `constel_rot`) behind a `pthread_once`.

5. **Pluto compute denial-of-service guard.** `CalcPluto`'s uncached `CalcPlutoOneWay` crawl for times outside the `PlutoStateTable` range costs time proportional to the distance from the table, so a far-off time could hang. It now returns `ASTRO_BAD_TIME` for times more than `PLUTO_MAX_CRAWL_DAYS` (~100 years) beyond the table.

6. **FP contraction disabled.** Keep `#pragma STDC FP_CONTRACT OFF` immediately after `#include "astronomy.h"`. The engine calls the host libm directly; do not introduce `unsafeFlags` or fast-math settings.

7. **Full VSOP87B and IAU2000B tables.** Upstream truncates the VSOP87B series and the nutation model. The vendored copy includes every retained VSOP87B term and all 77 IAU2000B terms, generated offline into `generated/` from pinned upstream data. Do not reintroduce the truncation when resyncing.

8. **Exact VSOP cache.** A bounded thread-local cache retains spherical coordinates, derivatives, and radius for each of the eight planetary models. Keys use the exact bits of scaled TT, including signed zero; nonfinite inputs bypass the cache. Entries contain no caller time metadata or mutable engine settings. Keep the cache below time conversion so Delta T changes cannot reuse a result for a different TT. Each body retains 32 entries. Storage lasts for the thread's lifetime and needs no cleanup in `Astronomy_Reset`.

9. **Polynomial planetary evaluation.** `CalcVsop`, `CalcVsopPosVel`, and `VsopHelioDistance` first try `PolynomialPosition` from `polynomial.h`, which evaluates degree-12 Chebyshev fits of the full VSOP87B model for qualified segments from 1900 through 2100 TT. Anything outside coverage, or in a segment that failed qualification, falls through to the full series and the cache above.

10. **Bounded TT inverse.** The native TT-to-UT inverse checks for finite input, representational precision, and Delta T discontinuity gaps, so nonconvergent input returns an invalid time instead of looping forever.

11. **Compensated VSOP summation.** `VsopCoords`, `VsopDeriv`, and `VsopHelioDistance` accumulate every series through the `VSOP_COMPENSATED_ADD` macro (Neumaier compensated addition), keeping the same terms in the same order. Plain accumulation lost low bits systematically because the t^1 longitude series starts with the mean-motion constant, and the loss grows linearly with |t|: up to 4.45e-12 AU for Mercury at the coverage edges, above the 1e-12 component budget the polynomial tables are qualified against. The compensated result matches an exactly summed evaluation of the same tables bit for bit. Patch 6 (FP contraction off) is what keeps the compensation from being fused away; do not reorder the terms or hoist the `+= *_c` finalization.

## Updating from upstream

1. **Pick the target upstream commit.** Note its full hash and date, and the corresponding `+upstream-A.B.C` engine version.

2. **Diff, don't blind-copy.** Fetch upstream `source/c/astronomy.c` and `astronomy.h` at the target commit and diff against the current vendored files so you can see exactly what changed and re-apply the local patches cleanly:

   ```sh
   # from a checkout of the upstream repo at the target commit
   diff -u path/to/upstream/source/c/astronomy.c \
           Sources/CLibAstronomy/astronomy.c
   ```

3. **Apply the upstream changes**, then **re-apply the local patches** above (or, if upstream has adopted equivalent fixes, confirm that and note it). The patch sites are marked in context by the vendoring note; search for `pluto_cache_mutex`, `DeltaTFunc`, `VsopCache`, `PolynomialPosition`, and the counter names.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Changelog & tag.** Add a `CHANGELOG.md` entry, then tag `X.Y.Z+upstream-A.B.C`.

## Numerical compatibility

AstronomyKit uses the platform's native libm. There is no bit-identity promise between platforms, architectures, OS releases, toolchains, or optimization levels. Small rounding differences can be amplified by finite differences and event searches.

`AstronomyConfig.ephemerisVersion` identifies the numerical implementation. Persisted numerical caches should include that version and the platform, architecture, OS, and toolchain identity, and regenerate derived data when those identities change.

## Verification

```sh
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
python3 Scripts/generate-models.py --check
python3 Scripts/generate-time-table.py --check
python3 Scripts/performance/polynomial/embed.py --check
python3 -m unittest discover -s Scripts/performance/polynomial -p 'test_*.py'
sh Scripts/performance/test-vsop-cache.sh
```

Keep whole-suite runs nonparallel: the Delta T thread-safety test intentionally swaps the process-global model. Swift Testing's `.serialized` trait orders tests inside that suite only and does not isolate unrelated suites from those swaps.

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against JPL Horizons and audit reference positions to roughly ±1 arcminute; a regression there requires investigation before release. `ReproducibilityTests` holds tight numerical regression budgets against frozen reference bits; tolerance failures also require investigation. Do not widen budgets or regenerate independent reference data to make a change pass.

CI runs all of these on every pull request, plus release-configuration tests and iOS/tvOS/watchOS builds.

## Generated tables

Three generators produce checked-in sources from pinned, checksummed inputs. Consumers never run them; CI runs each with `--check` to confirm the committed output is current.

- `Scripts/generate-models.py` reads `Scripts/model-data/` (full VSOP87B and IAU2000B source tables pinned to the vendored upstream revision) and writes `Sources/CLibAstronomy/generated/vsop87b_full.h` and `iau2000b_full.h`.
- `Scripts/generate-time-table.py` reads `Scripts/time-data/` (archived USNO TAI-UTC and IERS Bulletin C records) and writes `Sources/AstronomyKit/UTCOffsetTable.swift`. Updating time standards requires a new snapshot, hash manifest, a new `ephemerisVersion`, and transition tests.
- `Scripts/performance/polynomial/embed.py` reads the frozen coefficient archive in `Scripts/performance/polynomial/data/` and writes `Sources/CLibAstronomy/generated/polynomial-data.h`. See [that directory's README](Scripts/performance/polynomial/README.md) for coverage and provenance.
