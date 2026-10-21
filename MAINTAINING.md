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

The Swift layer in `Sources/AstronomyKit/` is ours and is not part of the
vendored code.

The top of `astronomy.c` carries a **vendoring note** recording the exact
upstream commit and the local patches. That note is the source of truth; keep it
current when you update.

## Version & tag scheme

Release tags are AstronomyKit's own [semantic version](https://semver.org), `X.Y.Z`, with no build metadata. Releases before 4.0.0 were tagged `X.Y.Z+upstream-A.B.C`; that suffix is dropped because Astronomy Engine development has ended and the vendored `astronomy.c` stays at its final release, 2.1.19.

## Local patches (must survive every update)

The vendored `astronomy.c` differs from upstream only by these patches, most of them for thread safety. Upstream is single-threaded by design; AstronomyKit advertises
`Sendable` safety, so these are required. **After any upstream sync they must be
re-applied, or verified as adopted upstream.**

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

6. **Extreme-input guards.** Non-finite or extreme inputs used to hang these sites or reach undefined behavior; each now returns an error status or runs in constant time, and results for ordinary inputs are unchanged. `InternalSearchAltitude` (rise/set and altitude searches) returns `ASTRO_INVALID_PARAMETER` for a non-finite `limitDays` and `ASTRO_BAD_TIME` when its 0.42-day step no longer advances the time (|UT| ≥ 2^52 days). `CalcPluto` returns `ASTRO_BAD_TIME` for a non-finite TT before `GetSegment`, whose `ClampIndex` converted NaN to `int`. `Astronomy_SearchMoonNode` returns `ASTRO_BAD_TIME` when its 10-day step no longer advances the time. `BruteSearchPlanetApsis` (Neptune, Pluto) returns `ASTRO_BAD_TIME` for a non-finite start. `LongitudeOffset` and `NormalizeLongitude` reduce with `fmod(x, 360.0) + 0.0` before the upstream loops, which took |x|/360 steps; the result is the same double for |x| < 2^56. `Astronomy_TerrestrialTime` returns a NaN time for a non-finite TT and returns its last iterate after 128 steps instead of looping forever; inputs that converge are unchanged. Each site carries an "extreme-input guards" comment.

7. **Accepted time range.** The ephemeris evaluators return `ASTRO_BAD_TIME` unless |TT| ≤ 1,461,000 days (`EPHEMERIS_MAX_TT_DAYS`, 4000 Julian years either side of J2000), which also rejects a non-finite TT. Far outside that span the models return absurd values and then NaN while reporting success. The check sits in `CalcVsop`, `Astronomy_HelioVector`, `Astronomy_HelioDistance`, `Astronomy_GeoVector`, `Astronomy_BaryState`, `Astronomy_HelioState`, `Astronomy_GeoMoon`, `Astronomy_EclipticGeoMoon`, `Astronomy_JupiterMoons`, `Astronomy_GravSimInit`, `Astronomy_GravSimUpdate` and `moon_distance_slope`; every other position, search and event function reaches one of these. `Astronomy_GeoMoonState` and the Moon node search now check the status of `Astronomy_GeoMoon` and `Astronomy_EclipticGeoMoon`, which upstream treats as infallible. Results inside the range are bit-identical, and Pluto keeps its narrower range (patch 5). Each site carries an "accepted time range" comment.

8. **Degenerate Lagrange inputs.** `Astronomy_LagrangePoint` returns `ASTRO_INVALID_BODY` when both bodies are the same, whose zero separation reached a division by zero. `Astronomy_LagrangePointFast` returns `ASTRO_INVALID_PARAMETER` when the squared separation is zero or not finite, when the L4/L5 tangent length is zero or not finite (a relative velocity that is zero or parallel to the separation leaves the orbital plane undefined), and for any result field that is not finite; its L1 to L3 Newton iteration returns `ASTRO_NO_CONVERGE` after 10,000 steps instead of hanging. Each site carries a "degenerate Lagrange inputs" comment.

9. **Observed Delta T.** `Astronomy_DeltaT_Observed` replaces `Astronomy_DeltaT_EspenakMeeus` as the initial value of `DeltaTFunc`, and Swift exposes it as `DeltaTModel.observed`. Espenak-Meeus's 2005–2050 polynomial has drifted from the Earth's rotation, about 6 seconds high by 2027. The function interpolates linearly in `DeltaTObserved`, a yearly table of IERS Delta T from 1962; before the table it is Espenak-Meeus plus an offset that fades to zero by 1952, and after the table the last yearly rate continues and blends into the long-term parabola by 2150. See "Refreshing the Delta T table" below.

## Refreshing the Delta T table

Refresh `DeltaTObserved` in `astronomy.c` before each release, so the table ends about a year past the release date. Nothing is committed but the table: no data files or scripts.

1. Download the IERS EOP 20 C04 series (`https://hpiers.obspm.fr/iers/eop/eopc04/eopc04.1962-now`) and the rapid series with predictions (`https://maia.usno.navy.mil/ser7/finals2000A.all`).
2. For each day, Delta T = 32.184 s + (TAI − UTC) − (UT1 − UTC), taking UT1 − UTC from C04 where it exists and from finals2000A after it. TAI − UTC is 37 s since 2017; earlier values are in the IERS Bulletin C history.
3. For each Julian epoch Y.0 from 1962.0 to the last whole year the predictions reach, interpolate Delta T linearly at UT days since J2000 = 365.25 (Y − 2000), and write it to 3 decimals.
4. Append the new entries and update the retrieval date in the comment above the table. Earlier entries change only if IERS revised C04. Update the table's last year in the three places that state it: the `Astronomy_DeltaT_Observed` doc comment, the `DeltaTModel.observed` documentation, and `tableEnd` in `DeltaTObservedTests`.
5. Run `DeltaTObservedTests`, and bump `AstronomyConfig.ephemerisVersion` at release, since results change.

## Updating from upstream

1. **Pick the target upstream commit.** Note its full hash and date.

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
   for `pluto_cache_mutex`, `DeltaTFunc`, `Astronomy_DeltaT_Observed`, `extreme-input guards`, `accepted time range`, `degenerate Lagrange inputs`, and the counter names.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the
   upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check
   whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Tag and release.** Tag `X.Y.Z`, bump `AstronomyConfig.ephemerisVersion` if any calculated value changed, and describe the change in the GitHub release. Releases are the only change record.

## Verification

Run the full suite — the JPL/Audit accuracy tests are the correctness gate, and
the ThreadSanitizer run guards the local patches:

```sh
touch .dev-tooling          # enable dev tooling for local builds
swift package resolve
swift build
swift test                  # all suites, incl. JPLValidationTests / AuditValidationTests
swift test --sanitize=thread  # exercises the Pluto / Delta T / counter patches
```

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against
JPL Horizons and audit reference positions to roughly ±1 arcminute; a regression
there means the vendored math changed and needs investigation before release.
CI runs these jobs plus release-configuration and per-platform builds on every
pull request.
