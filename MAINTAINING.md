# Maintaining AstronomyKit

This document is for maintainers. It describes how AstronomyKit vendors the
[Astronomy Engine](https://github.com/cosinekitty/astronomy) C library and how
to update that vendored copy. Day-to-day contribution guidance lives in
[CONTRIBUTING.md](CONTRIBUTING.md).

## What is vendored

AstronomyKit wraps a single-file C library. Two files are copied verbatim from
upstream (aside from the local patches listed below):

- `Sources/CLibAstronomy/astronomy.c` — the implementation
- `Sources/CLibAstronomy/include/astronomy.h` — the public C header

The historical musl subset in `Sources/CLibAstronomy/detmath/` and its private
`ak_detmath.h` redirect header are retained for archived experiments only.
They are excluded from the shipping target. `ak_math.c` supplies the existing
public `ak_*` symbols as native-math forwarding functions.

The Swift layer in `Sources/AstronomyKit/` is ours and is not part of the
vendored code.

The top of `astronomy.c` carries a **vendoring note** recording the exact
upstream commit and the local patches. That note is the source of truth; keep it
current when you update.

## Version & tag scheme

Release tags embed the bundled engine version:

```
X.Y.Z+upstream-A.B.C
```

- `X.Y.Z` is AstronomyKit's own [semantic version](https://semver.org).
- `+upstream-A.B.C` is the Astronomy Engine release the vendored `astronomy.c`
  corresponds to (see its `ASTRONOMY_ENGINE_VERSION` / upstream release notes).

Bumping the vendored library changes only the `+upstream-` suffix unless it also
changes AstronomyKit's public API or behavior, in which case bump `X.Y.Z` per
semver as usual.

## Local patches (must survive every update)

The vendored `astronomy.c` includes the runtime patches below. AstronomyKit preserves thread safety and validates numerical accuracy; preserve these patches after every upstream sync, or verify that upstream adopted an equivalent implementation. The complete coefficient tables and civil time integration are documented at the end of this file.

1. **Pluto orbit cache mutex.** A `pthread` mutex (`pluto_cache_mutex`) guards
   the Pluto segment cache. `CalcPluto` holds the lock across both the segment
   lookup and its use; `Astronomy_Reset` takes it before freeing the cache.
   Prevents a use-after-free between concurrent calculation and reset.

2. **Atomic Delta T function pointer.** `DeltaTFunc` is a C11 `_Atomic`
   (`stdatomic.h`). `Astronomy_SetDeltaTFunction` stores with release ordering;
   `TerrestrialTime` loads with acquire ordering. Lets the Delta T model be
   swapped safely while calculations run on other threads.

3. **Atomic performance counters.** The undocumented counters `_CalcMoonCount`,
   `_AltitudeDiffCallCount`, and `_FindAscentMaxRecursionDepth` are C11
   `_Atomic`, since concurrent Moon and rise/set calculations increment them.

4. **Constellation lazy-init `pthread_once`.** `Astronomy_Constellation` lazily
   builds a J2000→B1875 rotation matrix on first use. The state was
   function-local `static`s, so concurrent first calls raced. Initialization is
   now hoisted to file scope (`constel_init_once`, `constel_epoch2000`,
   `constel_rot`) behind a `pthread_once`.

5. **Pluto compute denial-of-service guard.** `CalcPluto`'s uncached
   `CalcPlutoOneWay` crawl for times outside the `PlutoStateTable` range costs
   time proportional to the distance from the table, so a far-off time could
   hang. It now returns `ASTRO_BAD_TIME` for times more than
   `PLUTO_MAX_CRAWL_DAYS` (~100 years) beyond the table.

6. **Native math with contraction disabled.** Keep
   `#pragma STDC FP_CONTRACT OFF` immediately after `astronomy.h`. The engine
   calls host math directly; `ak_math.c` retains compatibility entry points.
   Do not restore `ak_detmath.h` or compile `detmath/` into the shipping target.

7. **Exact VSOP cache.** A bounded thread-local cache retains spherical coordinates, derivatives, and radius for each of the eight immutable planetary models. Keys use the exact bits of scaled TT, including signed zero; nonfinite inputs bypass the cache. Entries contain no caller time metadata or mutable engine settings. The full series and summation order remain unchanged on a miss. Keep the cache below time conversion so Delta T changes cannot reuse a result for a different TT. Each body retains 32 entries, using 16,416 bytes per thread on the measured arm64 build. Storage lasts for the thread's lifetime and needs no heap cleanup in `Astronomy_Reset`.

## Updating from upstream

1. **Pick the target upstream commit.** Note its full hash and date, and the
   corresponding `+upstream-A.B.C` engine version.

2. **Diff, don't blind-copy.** Fetch upstream `source/c/astronomy.c` and
   `astronomy.h` at the target commit and diff against the current vendored
   files so you can see exactly what changed and re-apply the local patches
   cleanly:

   ```sh
   # from a checkout of the upstream repo at the target commit
   diff -u path/to/upstream/source/c/astronomy.c \
           Sources/CLibAstronomy/astronomy.c
   ```

3. **Apply the upstream changes**, then **re-apply the local patches** above
   (or, if upstream has adopted equivalent thread-safety fixes, confirm that and
   note it). The patch sites are marked in context by the vendoring note; search
   for `pluto_cache_mutex`, `DeltaTFunc`, and the counter names. In particular,
   preserve the source-level `FP_CONTRACT OFF` pragma (patch 6) after
   `#include "astronomy.h"`. Native math calls must remain unredirected.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the
   upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check
   whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Changelog & tag.** Add a `CHANGELOG.md` entry, then tag
   `X.Y.Z+upstream-A.B.C`.

## Native math and numerical compatibility

AstronomyKit primarily serves Apple platforms. Native libm avoids the measured
cost of vendored scalar transcendentals while retaining the full astronomical
models. Linux remains supported and runs the same accuracy and regression tests.
There is no bit-identity promise between platforms, architectures, OS releases,
toolchains, or optimization levels. Small rounding differences can be amplified
by finite differences and event searches; report timing differences separately.

`AstronomyConfig.ephemerisVersion` identifies the numerical implementation.
Persisted numerical caches should include that version and platform, architecture,
OS and toolchain identity. Regenerate derived data when those identities change.
Do not introduce SwiftPM `unsafeFlags` or fast-math compilation settings.

The former deterministic implementation remains in `detmath/`, with its license
and namespacing intact, solely to reproduce historical benchmark baselines. Its
`ak_*` symbols must never be linked alongside `ak_math.c`.

## Verification

Run the full suite: independent JPL/Audit references check astronomical accuracy;
`ReproducibilityTests` checks tight shared numerical regression budgets;
ThreadSanitizer guards concurrent runtime behavior.

```sh
swift test --no-parallel
swift test --no-parallel -c release
swift test --no-parallel --sanitize=thread
sh Scripts/performance/test-vsop-cache.sh
python3 Scripts/check-native-math.py --configuration debug
python3 Scripts/check-native-math.py --configuration release
```

Keep whole-suite runs nonparallel: the Delta T thread-safety test intentionally
swaps the process-global model. Swift Testing's `.serialized` trait orders tests
inside that suite only and does not isolate unrelated suites from those swaps.

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against
JPL Horizons and audit reference positions to roughly ±1 arcminute; a regression
there requires investigation before release.

The shared numerical fixtures retain their original reference values with
explicit unit-specific tolerances. Nonfinite values fail. Periodic angles use
wrapped differences. Cache replay and caller metadata still require exactness.
Tolerance failures require investigation; do not automatically widen budgets or
regenerate independent reference data. CI checks the shipping manifest and linked
objects to prevent accidentally restoring vendored deterministic math.

CI runs all of these jobs plus release-configuration and per-platform builds on
every pull request.

## Complete model and civil time tables

The major-version accuracy repair restores the full upstream VSOP87B and
IAU2000B data; do not reintroduce the upstream truncation when resyncing C.
`Scripts/model-data/manifest.json` pins source revisions and hashes.
`python3 Scripts/generate-models.py --check` verifies the committed shipping
headers under `Sources/CLibAstronomy/generated`. The same VSOP arrays supply
positions and derivatives. Keep the 77-term function and its fixed offsets.

`python3 Scripts/generate-time-table.py --check` verifies `UTCOffsetTable.swift`
against the archived USNO/IERS sources in `Scripts/accuracy/time-data`.
Updating time standards requires a new snapshot, hash manifest, model identifier,
transition tests and numerical compatibility review. Consumers never generate
or fetch these tables. The historical/future civil conventions are documented
on `AstroTime`; C raw times remain modeled UT1/TT. Preserve the bounded native
TT inverse when resyncing upstream.
