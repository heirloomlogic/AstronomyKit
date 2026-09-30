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

12. **Analytic geocentric ecliptic state.** `Astronomy_GeoEclipticState`, `Astronomy_SunEclipticState`, and `Astronomy_MoonEclipticState` return apparent geocentric position and velocity in the true ecliptic and equinox of date (`astro_ecliptic_state_t`). Each mirrors one position function (`Astronomy_GeoVector` + `Astronomy_Ecliptic`, `Astronomy_SunPosition`, `Astronomy_EclipticGeoMoon`) by calling the same helpers in the same order, so the position fields are bit-identical to it; the rate fields are the derivative of that position per TT day with Delta T fixed. Helpers: `iau2000b_eval` (the nutation series with optional rates; the value accumulation is the upstream expression verbatim, so `psi`/`eps` bits do not move), `iau2000b_rates`, `mean_obliq_rate`, `e_tilt_rate`, `precession_rot_rate` and `nutation_rot_rate` (entrywise product-rule derivatives of the identically named expressions in `precession_rot` and `nutation_rot`, stored in the same slots; keep them side by side with the functions they differentiate), `GeoHelioState`, `GeoStateBackdate` (the light-time loop of `Astronomy_CorrectLightTravel` and `BodyPosition` repeated with states; the velocity is the implicit derivative of the converged fixed point, so it does not depend on the iteration count), `ecliptic_state_from_eqj`, `EclipticStateFromEqd`, `MoonEcmState` (central difference of `CalcMoon` over `MOON_STATE_STEP_DAYS`), `EclToEquVel`, `GeoMoonStateEqj`, and the `_Astronomy_Iau2000bRates` / `_Astronomy_EclipticStateFromEqj` test hooks. `CalcPluto` takes an `exact_velocity` flag that adds the `(rb - ra) / PLUTO_DT` term the blended velocity omits; every pre-existing caller passes 0. Invariants: backdate through `Astronomy_AddDays` (it recomputes TT from Delta T), never `tt - tau`; rate helpers never produce a value matrix; `dist` in `EclipticStateFromEqd` uses the same `sqrt(x*x + y*y + z*z)` expression as the Swift `Ecliptic` wrapper; new code stays below the `FP_CONTRACT OFF` pragma.

13. **Exact nutation cache.** A 32-entry thread-local cache retains the IAU2000B nutation angles and their rates. Both value-only and rate callers populate the full tuple, so an angle calculation can warm a later state calculation at the same instant. Keys use the exact bits of the scaled TT consumed by the series, including signed zero; nonfinite inputs bypass the cache. Entries exclude caller-owned `astro_time_t` metadata and mutable engine settings, and a caller's populated `psi`/`eps` memo remains authoritative. Storage lasts for the thread's lifetime and needs no cleanup in `Astronomy_Reset`.

14. **Exact Moon cache.** A 32-entry thread-local cache retains the complete longitude, latitude, and distance tuple from `CalcMoonRaw`. Every existing lunar client continues to call the `CalcMoon` wrapper, including the center and two offset samples in `MoonEcmState`, so repeated state calls reuse three exact epochs without changing the rate stencil. Keys use the exact bits of the scaled TT consumed by the series, including signed zero; nonfinite inputs bypass the cache. Entries contain no caller time metadata or mutable engine settings. Storage lasts for the thread's lifetime and needs no cleanup in `Astronomy_Reset`.

15. **Extreme-input guards.** Non-finite or extreme inputs used to hang these sites or reach undefined behavior. Each now returns an error status or runs in constant time, and results for ordinary inputs are unchanged. Every change is an added line; no upstream line was edited. `InternalSearchAltitude`, shared by `Astronomy_SearchRiseSetEx` and `Astronomy_SearchAltitude`, returns `ASTRO_INVALID_PARAMETER` for a non-finite `limitDays`, and `ASTRO_BAD_TIME` when adding its 0.42-day step does not advance the time (from |UT| = 2^52 days, whether the window starts there or reaches it). A large finite `limitDays` is not capped: the search costs one altitude evaluation per step, so its running time is proportional to the window. `CalcPluto` returns `ASTRO_BAD_TIME` for a non-finite TT before `GetSegment`, because a NaN passed both table-range comparisons and reached `(int) floor(NaN)` in `ClampIndex`. `Astronomy_SearchMoonNode` returns `ASTRO_BAD_TIME` when its 10-day step does not advance the time, which covers a non-finite start and |UT| of 2^57 days or more. `BruteSearchPlanetApsis` (Neptune and Pluto) returns `ASTRO_BAD_TIME` for a non-finite start, whose NaN sample interval kept `PlanetExtreme` looping. `LongitudeOffset` and `NormalizeLongitude` reduce their argument with `fmod(x, 360.0) + 0.0` before the upstream loops, which took |x|/360 steps (hanging `Astronomy_Libration` far from J2000 and the longitude searches for a huge target angle) and never ended for an infinity. For |x| < 2^56 every step of the old loop was exact, so the result is the same double; the `+ 0.0` turns the -0 that `fmod` returns for a negative multiple of 360 into the +0 the loop reached, and zero itself skips the reduction to keep its sign. The Swift wrappers of the two longitude searches reject a non-finite target angle with `invalidParameter`. The C sites carry an "extreme-input guards" comment.

16. **Non-finite result guards.** The engine's models accept any time, and far from J2000 they overflow. With the default Delta T model, TT itself is infinite from about |ut| = 1e158 days; the planetary and lunar series overflow at finite TT well before that (the tests use ut = 1e70). These public functions used to report `ASTRO_SUCCESS` with NaN or infinite fields, and now return `ASTRO_BAD_TIME` when a field of a successful result is not finite: `Astronomy_HelioVector`, `Astronomy_HelioDistance`, `Astronomy_HelioState`, `Astronomy_BaryState`, `Astronomy_GeoVector`, `Astronomy_Equator`, `Astronomy_GeoMoon`, `Astronomy_GeoMoonState`, `Astronomy_EclipticGeoMoon`, `Astronomy_SunPosition`, `Astronomy_Illumination`, `Astronomy_JupiterMoons` (each moon's state), `Astronomy_LagrangePoint`, and `Astronomy_SunEclipticState`. `Astronomy_BackdatePosition`, `Astronomy_GeoEclipticState`, and `Astronomy_MoonEclipticState` get the same check, though none of the three was seen to succeed with a non-finite result. Finite results are unchanged, except for the `Astronomy_LagrangePoint` L4 and L5 results described below. The six with several return paths (`HelioVector`, `HelioDistance`, `HelioState`, `BaryState`, `BackdatePosition`, `Equator`) keep the upstream body as a static `*Unguarded` function behind a checking wrapper, so internal callers get the checked result; the others check before their final return. `Astronomy_GeoEmbState` inherits the check from `Astronomy_GeoMoonState`, and the planetary apsis searches inherit it from `Astronomy_HelioDistance`, which measures every sample. `Astronomy_LagrangePoint` used to report `ASTRO_SUCCESS` with NaN fields when `major_body` and `minor_body` were the same, because their zero separation reached a division by zero in `Astronomy_LagrangePointFast`; it now returns `ASTRO_INVALID_BODY` for that call, after its mass checks. `Astronomy_LagrangePointFast` returns `ASTRO_INVALID_PARAMETER` when the squared distance `R2` between the two positions is zero or not finite. A zero `R2`, from coincident positions or a separation that underflows when squared, would divide by zero. A non-finite `R2`, from a non-finite coordinate or a separation that overflows when squared, makes `R` infinite or NaN, and an infinite `R` becomes NaN through terms such as inf/inf and inf - inf. For L4 and L5 it also returns `ASTRO_INVALID_PARAMETER` when `U`, the length of the tangent vector, is zero or not finite. `U` is zero when the relative velocity is zero or exactly parallel to the separation, where the orbital plane is undefined, or when the tangent or its squared length underflows; dividing by it gave NaN or infinity. `U` is infinite when that squared length overflows, and dividing a finite tangent by it gave a zero vector and a finite but wrong point; far from J2000, `Astronomy_LagrangePoint` reported that as success, with the same point for L4 and L5. `U` is infinite or NaN when the relative velocity is not finite or the cross products overflow. A last check returns `ASTRO_INVALID_PARAMETER` for a result field that is not finite, such as from an L1 to L3 relative velocity that is not finite, or L1 to L3 masses whose sum overflows. `Astronomy_LagrangePointFast` returns `ASTRO_NO_CONVERGE` when its L1 to L3 Newton iteration has not converged after 10000 steps; for some finite inputs, including some L3 inputs with masses of similar size, the iteration did not converge and the function hung. `Astronomy_LagrangePoint` returns `ASTRO_BAD_TIME` when `Astronomy_LagrangePointFast` returns `ASTRO_INVALID_PARAMETER` for a point from 1 to 5: its masses are the engine's own mass products and its states succeeded, so the rejected input is a state, which comes from the time. A user-defined star whose distance overflows reports `ASTRO_BAD_TIME` too. `Astronomy_SearchLunarApsis` used to report `ASTRO_INTERNAL_ERROR` when the lunar distance was NaN, because a NaN slope from `moon_distance_slope` never shows a sign change; that function now reports `ASTRO_BAD_TIME` for a slope that is not finite, and the search returns it. `Astronomy_Libration` has no status and is unchanged. Finite but meaningless results far from J2000, such as negative distances, still report success; the accepted time range is an open question (#62). In Swift, `Sun.position(at:)`, `FixedStar.ecliptic(at:)`, and `Vector3D.toEcliptic()` share an `Ecliptic` initializer that computes the distance from the returned vector and throws `badTime` when the latitude, longitude, or distance is not finite. The C sites carry a "non-finite result guards" comment.

## Updating from upstream

1. **Pick the target upstream commit.** Note its full hash and date, and the corresponding `+upstream-A.B.C` engine version.

2. **Diff, don't blind-copy.** Fetch upstream `source/c/astronomy.c` and `astronomy.h` at the target commit and diff against the current vendored files so you can see exactly what changed and re-apply the local patches cleanly:

   ```sh
   # from a checkout of the upstream repo at the target commit
   diff -u path/to/upstream/source/c/astronomy.c \
           Sources/CLibAstronomy/astronomy.c
   ```

3. **Apply the upstream changes**, then **re-apply the local patches** above (or, if upstream has adopted equivalent fixes, confirm that and note it). The patch sites are marked in context by the vendoring note; search for `pluto_cache_mutex`, `DeltaTFunc`, `VsopCache`, `MoonCache`, `PolynomialPosition`, `VSOP_COMPENSATED_ADD`, `Astronomy_GeoEclipticState`, `extreme-input guards`, `non-finite result guards`, and the counter names.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Tag & release.** Tag `X.Y.Z+upstream-A.B.C` and publish a GitHub release for it with the release notes.

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
sh Scripts/performance/test-nutation-cache.sh
sh Scripts/performance/test-moon-cache.sh
```

Plain `swift test` is enough locally. The Delta T thread-safety test swaps the process-global model, but only between two functions that return identical results, so suites running in parallel cannot see the swap. CI still passes `--no-parallel`.

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against JPL Horizons and audit reference positions to roughly ±1 arcminute; a regression there requires investigation before release. `ReproducibilityTests` holds tight numerical regression budgets against frozen reference bits; tolerance failures also require investigation. Do not widen budgets or regenerate independent reference data to make a change pass.

CI runs all of these on every pull request, plus release-configuration tests and iOS/tvOS/watchOS builds.

After an upstream sync, also replay the fuzz corpus through the C library under ASan and UBSan. The Fuzz workflow runs these, plus a libFuzzer run, on pull requests that touch the C library and every week ([Fuzzing/README.md](Fuzzing/README.md#ci)):

```sh
sh Fuzzing/build.sh replay && .build/fuzz/replay-bridge Fuzzing/corpus
python3 Fuzzing/make_corpus.py --check
```

The harness skips inputs that reach known engine defects; each filter names its issue. When a sync fixes one of them, delete its filter. See [Fuzzing/README.md](Fuzzing/README.md).

## Generated tables

Three generators produce checked-in sources from pinned, checksummed inputs. Consumers never run them; CI runs each with `--check` to confirm the committed output is current.

- `Scripts/generate-models.py` reads `Scripts/model-data/` (full VSOP87B and IAU2000B source tables pinned to the vendored upstream revision) and writes `Sources/CLibAstronomy/generated/vsop87b_full.h` and `iau2000b_full.h`.
- `Scripts/generate-time-table.py` reads `Scripts/time-data/` (archived USNO TAI-UTC and IERS Bulletin C records) and writes `Sources/AstronomyKit/UTCOffsetTable.swift`. Updating time standards requires a new snapshot, hash manifest, a new `ephemerisVersion`, and transition tests.
- `Scripts/performance/polynomial/embed.py` reads the frozen coefficient archive in `Scripts/performance/polynomial/data/` and writes `Sources/CLibAstronomy/generated/polynomial-data.h`. See [that directory's README](Scripts/performance/polynomial/README.md) for coverage and provenance.
