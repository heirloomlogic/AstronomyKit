# Native engine contract

AstronomyKit is replacing the vendored C engine (`Sources/CLibAstronomy`) with Swift. This file is the internal contract the Swift modules are written against: where each module's files live and who edits them, units and frames, how time and the Delta T model are owned, how errors are reported, and how caches are owned and reset. The plan and its sub-issues are in epic #79. The public API keeps calling the C engine until #96 switches it over.

A section marked **Planned** describes code that is not in the tree yet. The PR that adds the code replaces the section with what it actually added.

## Layout and ownership

Engine code is internal and lives in the `Engine` namespace (`enum Engine` in `Sources/AstronomyKit/Engine/Foundation/Engine.swift`). Each area below has one directory and one owning issue. Only that issue's PRs edit the directory; a change another module needs goes through the owner. Tests mirror the layout under `Tests/AstronomyKitTests/Engine/<Area>/`.

| Directory under `Sources/AstronomyKit/Engine/` | Owner | Responsibility |
|---|---|---|
| `Foundation/` | #84 | Namespace, frames, time and Delta T, calendar, vectors and states, constants, root search, light-travel iteration, caches and reset |
| `Planets/` | #85 | VSOP87B series and polynomial evaluation, with their generated tables |
| `Orientation/` | #86 | Nutation, precession, sidereal time, rotations, coordinate conversions, observers, atmosphere, refraction |
| `Moon/` | #87 | Lunar series, Moon positions and states, Earth-Moon barycenter, libration |
| `Gravity/` | #88 | Pluto, gravity simulation, Chiron integration |
| `Positions/` | #89 | Heliocentric, barycentric, geocentric and apparent positions and states, ecliptic states, illumination |
| `Bodies/` | #90 | Jupiter's moons, rotation axes, Lagrange points |
| `Stars/` | #91 | Fixed stars and constellations |
| `Events/` | #92 | Rise/set, altitude and hour-angle searches, seasons, lunar phases, nodes and apsides, planetary event searches |
| `Eclipses/` | #93 | Lunar and solar eclipses, transits |

Files under `Engine/` never import `CLibAstronomy` or use `Mutex` (see [Caches and reset](#caches-and-reset)); `EngineContractTests` checks both. Generated tables live in a `Generated/` subdirectory of the module that reads them, with a generator under `Scripts/` that has a `--check` mode. Model data is compiled in; nothing is loaded at runtime.

## Conventions

- Engine functions are synchronous. They do not suspend, and they never hold a lock while running caller code or a cache computation.
- Failures are thrown as `AstronomyError` (see [Errors](#errors)). An error thrown by a caller's closure propagates unchanged.
- Units: distances in AU, velocities in AU per TT day, angles in degrees, right ascension and sidereal time in sidereal hours, times in days since 2000-01-01 12:00 on the named scale. A name says so when it departs from this, for example `radians`.
- Bodies are the public `CelestialBody` enum. A function that does not support a body throws `invalidBody` where the C function returns `ASTRO_INVALID_BODY`.
- Constants shared by more than one module live in `Foundation/`, with the published source of each value. A constant used by one module stays in that module.

## Frames, vectors and rotations

In the tree: `Engine.swift` and `EngineVector.swift`.

A frame is a type parameter, so a vector moves between frames only through a rotation and a signature states its frame. The origin is not part of the type; the function name states it (heliocentric, barycentric, geocentric, topocentric).

| Type | Axes | C name |
|---|---|---|
| `Engine.EQJ` | Mean equator and equinox of J2000 | EQJ |
| `Engine.EQD` | True equator and equinox of the vector's time | EQD |
| `Engine.ECL` | Mean ecliptic and equinox of J2000 | ECL |
| `Engine.ECT` | True ecliptic and equinox of the vector's time | ECT |
| `Engine.HOR` | Observer's horizon: x north, y west, z zenith | HOR |
| `Engine.GAL` | Galactic | GAL |

A module that needs another frame, such as Jupiter's equator for its moons, declares it in its own directory.

- `Engine.Vector<F>`: `x`, `y`, `z` in AU and the `time` it is valid at.
- `Engine.State<F>`: position `x`, `y`, `z` in AU, velocity `vx`, `vy`, `vz` in AU per TT day, and `time`.
- `Engine.Rotation<From, To>`: `rot` in the C engine's index order, which the public `RotationMatrix[row:col:]` exposes unchanged. Applied to a vector `v`, component `j` of the result is `rot[0][j]·v.x + rot[1][j]·v.y + rot[2][j]·v.z`. `identity` exists only where `From == To`.

**Planned (#84, part 3).** Applying a rotation to a vector or state, vector length, the angle between two vectors (`badVector` when the product of their lengths is below 1e-8 or not finite, as in `Astronomy_AngleBetween`), and the other vector and state arithmetic that more than one module uses. Combining, inverting and pivoting rotations, and the rotations between frames, belong to #86.

## Time and the Delta T model

In the tree: `EngineTime.swift`.

`Engine.Time` holds `ut` (modeled UT1 days), `tt` (Terrestrial Time days) and `deltaTModel`, the public `DeltaTModel` that relates them.

- `init(ut:tt:deltaTModel:)` stores both scales as given. It keeps the model only when both are finite; otherwise the time is invalid and its scales stay as given, so a huge UT with an infinite TT still reports that UT.
- `fromPair(ut:tt:deltaTModel:)` rebuilds a time from recorded scales, as `AstroTime(tt:ut:deltaTModel:)` does, and returns `Engine.Time.invalid` (NaN scales, no model) when either scale is not finite.
- `isValid` is true when both scales are finite.

Every time derived from another (adding days, a search step, a light-time backdate) derives TT with the source time's model, so one calculation uses one model from its input to its result. The process default belongs to the public layer, not to `Engine`: engine functions take a model or a time that carries one, and the public layer reads the default once per call, when the caller passes no model.

There is no separate calculation-context object. The C engine kept per-call state in two places: the Delta T function captured in `astro_time_t`, which `Engine.Time` now carries, and the nutation and sidereal-time memo fields (`psi`, `eps`, `st`). The engine recomputes those values, reading nutation from the shared nutation cache (#86). Everything else a calculation needs is an argument or immutable model data.

`Engine.Time` is not `Equatable`. The public `AstroTime` keeps UT-only equality, hashing and `Codable`; engine code compares the scale it means.

**Planned (#84, part 2).** The final names are recorded here when the code lands.

```swift
extension Engine.Time {
    init(ut: Double, deltaTModel: DeltaTModel)   // tt = ut + ΔT(ut) / 86400
    init(tt: Double, deltaTModel: DeltaTModel)   // bounded inverse; invalid for nonfinite or nonconvergent input
    func adding(days: Double) -> Engine.Time     // ut + days, TT from this time's model
    static func days(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double) -> Double
}
extension Engine {
    enum DeltaT {
        static func seconds(ut: Double, model: DeltaTModel) -> Double
    }
}
```

The process default moves from the C atomic to a `Synchronization.Atomic` in the public layer (`AstronomyConfig`) when #96 switches the API over. `days(year:...)` is the proleptic Gregorian day count of `Astronomy_MakeTime`, with Int32 clamping and calendar normalization. The TT inverse keeps the C engine's discontinuity-gap and representational-precision behavior (MAINTAINING.md, local patch 10).

## Errors

Engine code throws the public `AstronomyError`; there is no status enum. Each C status maps as follows.

| C status | Engine behavior |
|---|---|
| `ASTRO_SUCCESS` | Return the value |
| `ASTRO_INVALID_BODY` | Throw `invalidBody` |
| `ASTRO_NO_CONVERGE` | Throw `noConvergence` |
| `ASTRO_BAD_TIME` | Throw `badTime`, including for a result that is not finite and for a TT outside the accepted range |
| `ASTRO_BAD_VECTOR` | Throw `badVector` |
| `ASTRO_SEARCH_FAILURE` | The generic root search returns `nil`. Other searches keep each public API's current choice between returning `nil` and throwing `searchFailure` |
| `ASTRO_EARTH_NOT_ALLOWED` | Throw `earthNotAllowed` |
| `ASTRO_NO_MOON_QUARTER`, `ASTRO_WRONG_MOON_QUARTER` | Throw `noMoonQuarter`, `wrongMoonQuarter` |
| `ASTRO_INTERNAL_ERROR` | Throw `internalError` for a failed self-check. A caller's closure error is rethrown as is; the Swift trampolines in `Search.swift` return this status only to stop the C iteration |
| `ASTRO_INVALID_PARAMETER` | Throw `invalidParameter` |
| `ASTRO_FAIL_APSIS` | Throw `failApsis` |
| `ASTRO_INCONSISTENT_TIMES` | Throw `inconsistentTimes` |
| `ASTRO_NOT_INITIALIZED` | Not thrown by engine code. The public `GravitySimulation` throws `notInitialized` itself when it has no simulation handle |
| `ASTRO_BUFFER_TOO_SMALL` | Not thrown. Only `Astronomy_FormatTime` returns it, and the Swift layer does not call it |
| `ASTRO_OUT_OF_MEMORY` | Not thrown. Swift traps on allocation failure |
| Any other value | Not thrown; `AstronomyError.unknown` stays for API compatibility |

## Root search and light travel

**Planned (#84, part 3).** The final names are recorded here when the code lands.

```swift
extension Engine {
    enum Search {
        static func ascendingRoot(
            from start: Engine.Time, to end: Engine.Time, toleranceSeconds: Double,
            _ function: (Engine.Time) throws -> Double
        ) throws -> Engine.Time?
    }
    enum LightTravel {
        static func correct<F: Engine.Frame>(
            at time: Engine.Time, _ position: (Engine.Time) throws -> Engine.Vector<F>
        ) throws -> Engine.Vector<F>
    }
}
```

The closures are synchronous and non-escaping, and replace the C callback trampolines. `ascendingRoot` keeps `Astronomy_Search`'s expressions, branch order and 20-iteration limit (then `noConvergence`), with local patch 20's ascending-bracket checks, and every time it derives uses the start time's model. It returns `nil` when the window has no ascending root, and an error from `function` stops the search and propagates. `correct` keeps `Astronomy_CorrectLightTravel`: at most 10 iterations, backdating with `time.adding(days: -distance / C_AUDAY)` (a UT offset, so the model is the observation time's), stopping when TT moves less than 1e-9 days, `invalidParameter` beyond one light-day, and `noConvergence` after the last iteration. It returns the last vector the closure produced, whose time is the last backdated time.

## Caches and reset

In the tree: `EngineCache.swift`.

- `Engine.ExactKey` is the bit pattern of a finite `Double`. `0.0` and `-0.0` are different keys. A value that is not finite has no key and bypasses the cache.
- `Engine.BoundedCache<Key, Value>` holds at most `capacity` entries and replaces the oldest insertion when full, as the C caches do. All threads share the entries. The computation runs outside the lock, so it may use any cache, including the one it fills. A computation that throws stores nothing. `statistics` counts hits and misses for work-count tests.
- A cached value is a pure function of its key: never the process Delta T default, never a caller's time metadata. Then a hit returns what recomputing would, and a reset at any moment cannot change a result.
- Each module creates its caches as `static let` properties, registered with `Engine.CacheRegistry.shared`. A cache that has never been used does not exist yet, so the registry holds every cache that can contain entries.
- `Engine.resetCaches()` empties every registered cache. It does not touch the Delta T default, fixed star definitions or gravity simulations, which are not caches. #96 makes `AstronomyConfig.reset()` call it and updates that method's documentation.
- Shared mutable state uses `NSLock` or `Synchronization.Atomic`, not `Synchronization.Mutex`. ThreadSanitizer on Linux does not model `Mutex`, and suppressing its reports would also hide races in any computation called through a cache (see `.github/tsan-suppressions.txt`).
- Tests that count work make their own `CacheRegistry` and cache, because the shared caches are process-wide.

| State | Owner | Native form | C counterpart |
|---|---|---|---|
| VSOP87B series results | #85 | `BoundedCache`, 32 entries per body, `ExactKey` of the scaled TT the series reads | Thread-local, 32 per body (local patch 8) |
| Nutation angles and rates | #86 | `BoundedCache`, 32 entries, `ExactKey` of the scaled TT | Thread-local, 32 entries (local patch 13) |
| Moon longitude, latitude, distance | #87 | `BoundedCache`, 32 entries, `ExactKey` of the scaled TT | Thread-local, 32 entries (local patch 14) |
| Pluto segments | #88 | `BoundedCache` keyed by segment index, one entry per table segment | Allocated segments behind a mutex, freed by `Astronomy_Reset` (local patch 1) |
| Delta T default | #96 | `Atomic` in the public layer | `_Atomic` function pointer (local patch 2) |
| Gravity simulation | #88 | Owned by each `GravitySimulation`, with its own lock | Caller-owned handle |
| Fixed star definitions | #91 | Passed by value | Eight shared slots |
| Constellation B1875 rotation | #91 | `static let` | `pthread_once` (local patch 4) |

## Public layer integration (#96)

`AstroTime` will store an `Engine.Time`, `setDeltaTModel` will write the public layer's atomic default, a `nil` model argument resolves to that default once per public call, and `AstronomyConfig.reset()` will call `Engine.resetCaches()`. Public names, signatures, conformances, `Codable` shape, units, frames and error cases do not change.

## C entry points by owner

Every C function the Swift layer calls or names has exactly one owner. `EngineContractTests` fails when a Swift source mentions an `Astronomy_` function that is missing from this list or listed under two owners.

- #84: `Astronomy_MakeTime`, `Astronomy_AddDays`, `Astronomy_TimeFromDaysWithDeltaT`, `Astronomy_TerrestrialTimeWithDeltaT`, `Astronomy_TimeFromPair`, `Astronomy_DeltaT_EspenakMeeus`, `Astronomy_DeltaT_JplHorizons`, `Astronomy_Search`, `Astronomy_CorrectLightTravel`, `Astronomy_AngleBetween`, `Astronomy_RotateVector`, `Astronomy_RotateState`, `Astronomy_Reset`
- #85: none directly; #89 composes the planetary series into the position functions.
- #86: `Astronomy_Rotation_EQJ_ECL`, `Astronomy_Rotation_ECL_EQJ`, `Astronomy_Rotation_EQJ_EQD`, `Astronomy_Rotation_EQD_EQJ`, `Astronomy_Rotation_EQJ_HOR`, `Astronomy_Rotation_HOR_EQJ`, `Astronomy_Rotation_EQJ_GAL`, `Astronomy_Rotation_GAL_EQJ`, `Astronomy_Rotation_ECL_HOR`, `Astronomy_Rotation_HOR_ECL`, `Astronomy_Rotation_EQD_HOR`, `Astronomy_Rotation_HOR_EQD`, `Astronomy_Rotation_EQD_ECL`, `Astronomy_Rotation_ECL_EQD`, `Astronomy_Rotation_EQJ_ECT`, `Astronomy_Rotation_ECT_EQJ`, `Astronomy_Rotation_EQD_ECT`, `Astronomy_Rotation_ECT_EQD`, `Astronomy_InverseRotation`, `Astronomy_CombineRotation`, `Astronomy_Pivot`, `Astronomy_SiderealTime`, `Astronomy_Ecliptic`, `Astronomy_Horizon`, `Astronomy_SphereFromVector`, `Astronomy_VectorFromSphere`, `Astronomy_EquatorFromVector`, `Astronomy_HorizonFromVector`, `Astronomy_VectorFromHorizon`, `Astronomy_ObserverVector`, `Astronomy_ObserverState`, `Astronomy_ObserverGravity`, `Astronomy_VectorObserver`, `Astronomy_Atmosphere`, `Astronomy_Refraction`, `Astronomy_InverseRefraction`
- #87: `Astronomy_GeoMoon`, `Astronomy_GeoMoonState`, `Astronomy_EclipticGeoMoon`, `Astronomy_GeoEmbState`, `Astronomy_MoonEclipticState`, `Astronomy_Libration`
- #88: `Astronomy_GravSimInit`, `Astronomy_GravSimUpdate`, `Astronomy_GravSimSwap`, `Astronomy_GravSimFree`, `Astronomy_GravSimBodyState`, `Astronomy_GravSimTime`, `Astronomy_GravSimNumBodies`
- #89: `Astronomy_HelioVector`, `Astronomy_HelioState`, `Astronomy_HelioDistance`, `Astronomy_BaryState`, `Astronomy_GeoVector`, `Astronomy_BackdatePosition`, `Astronomy_Equator`, `Astronomy_SunPosition`, `Astronomy_SunEclipticState`, `Astronomy_GeoEclipticState`, `Astronomy_Illumination`, `Astronomy_AngleFromSun`, `Astronomy_EclipticLongitude`, `Astronomy_PairLongitude`, `Astronomy_Elongation`
- #90: `Astronomy_JupiterMoons`, `Astronomy_RotationAxis`, `Astronomy_LagrangePoint`, `Astronomy_LagrangePointFast`, `Astronomy_MassProduct`, `Astronomy_PlanetOrbitalPeriod`
- #91: `Astronomy_DefineStar`, `Astronomy_Constellation`
- #92: `Astronomy_SearchRiseSetEx`, `Astronomy_SearchAltitude`, `Astronomy_SearchHourAngleEx`, `Astronomy_HourAngle`, `Astronomy_Seasons`, `Astronomy_SearchSunLongitude`, `Astronomy_MoonPhase`, `Astronomy_SearchMoonPhase`, `Astronomy_SearchMoonQuarter`, `Astronomy_NextMoonQuarter`, `Astronomy_SearchMoonNode`, `Astronomy_NextMoonNode`, `Astronomy_SearchLunarApsis`, `Astronomy_NextLunarApsis`, `Astronomy_SearchPlanetApsis`, `Astronomy_NextPlanetApsis`, `Astronomy_SearchMaxElongation`, `Astronomy_SearchPeakMagnitude`, `Astronomy_SearchRelativeLongitude`
- #93: `Astronomy_SearchLunarEclipse`, `Astronomy_NextLunarEclipse`, `Astronomy_SearchGlobalSolarEclipse`, `Astronomy_NextGlobalSolarEclipse`, `Astronomy_SearchLocalSolarEclipse`, `Astronomy_NextLocalSolarEclipse`, `Astronomy_SearchTransit`, `Astronomy_NextTransit`
- #96: `Astronomy_SetDeltaTFunction`, whose replacement is the public layer's atomic default

Where two issues' wording overlaps, this list decides: `Astronomy_MoonPhase` belongs to #92 (lunar phase angles), with #87 supplying the lunar inputs, and `Astronomy_Elongation` belongs to #89 (separation utilities), with the elongation searches in #92.

## Changing this contract

A module records the signatures it provides here, in the PR that adds them, before a dependent module starts. A change to `Foundation/` or to another module's provided signatures goes through that owner's issue. Each change to this file updates the sections it affects rather than appending history.
