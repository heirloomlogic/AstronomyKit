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
- Constants shared by more than one module live in `Foundation/`, with the published source of each value (see [Constants](#constants)). A constant used by one module stays in that module.

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

```swift
extension Engine.Vector {
    var length: Double { get }
    func angle(to other: Self) throws -> Double
}
extension Engine.State {
    var position: Engine.Vector<F> { get }
}
extension Engine.Rotation {
    func apply(to vector: Engine.Vector<From>) -> Engine.Vector<To>
    func apply(to state: Engine.State<From>) -> Engine.State<To>
}
```

- `length` is `sqrt(x² + y² + z²)` with no scaling, as in `Astronomy_VectorLength`, so a component above about 1e154 gives an infinite length.
- `angle(to:)` returns degrees from 0 through 180, as `Astronomy_AngleBetween` does. It throws `badVector` when the product of the two lengths is below 1e-8 or not finite, and returns exactly 0 or 180 when the cosine rounds to 1 or −1 or beyond.
- `apply(to:)` uses the formula above, and for a state applies it to the position and to the velocity. The result keeps the input's time. It cannot fail: `Astronomy_RotateVector` and `Astronomy_RotateState` return `ASTRO_INVALID_PARAMETER` only for an input that carries an error status, and Swift values have no status.

Combining, inverting and pivoting rotations, and the rotations between frames, belong to #86. Other vector arithmetic stays in the module that uses it until a second module needs it, and then moves here through #84.

## Constants

In the tree: `EngineConstants.swift`. Each constant is the double nearest its definition. `EngineConstantsTests` derives each one from its definition, not from the C engine.

| Constant | Definition |
|---|---|
| `Engine.secondsPerDay` | 86,400 SI seconds |
| `Engine.kilometersPerAU` | 149,597,870.7 km: IAU 2012 Resolution B2 defines the au as exactly 149,597,870,700 m |
| `Engine.speedOfLightAUPerDay` | 173.144 632 674 240 33 AU per day: the SI speed of light, exactly 299,792,458 m/s, times 86,400 s, over the au. Light crosses one au in 499.004 783 836 s, the IAU 2009 value |
| `Engine.radiansPerDegree`, `Engine.degreesPerRadian` | π/180 and 180/π |
| `Engine.radiansPerHour`, `Engine.hoursPerRadian` | π/12 and 12/π |
| `Engine.radiansPerArcsecond` | π/648,000 |

The C engine's `C_AUDAY`, 173.1446326846693, is 86,400 s over 499.0047838061 s, the DE405 light time for one au, and its `KM_PER_AU`, 149,597,870.69098932, is derived from `C_AUDAY`. Both differ from the published values by 6.0e-11 of their size: about 3e-8 s of light time and 9 m per au. The C angle factors (`DEG2RAD`, `RAD2DEG`, `HOUR2RAD`, `RAD2HOUR`, `ASEC2RAD`) are the same doubles as the engine's. `SearchCallbackContractTests` "Fixed positions within one light-day" and "Positions beyond one light-day" test the public API against the C light-day; #96 moves them to the published one. Both are tracked in #166.

## Time and the Delta T model

In the tree: `EngineTime.swift`, `EngineDeltaT.swift`, `EngineCalendar.swift`.

`Engine.Time` holds `ut` (modeled UT1 days), `tt` (Terrestrial Time days) and `deltaTModel`, the public `DeltaTModel` that relates them.

```swift
extension Engine.Time {
    init(ut: Double, tt: Double, deltaTModel: DeltaTModel)
    static func fromPair(ut: Double, tt: Double, deltaTModel: DeltaTModel) -> Engine.Time
    init(ut: Double, deltaTModel: DeltaTModel)
    init(tt: Double, deltaTModel: DeltaTModel)
    func adding(days: Double, fallback: DeltaTModel) -> Engine.Time
    static func civil(utcDays: Double, deltaTModel: DeltaTModel) -> (time: Engine.Time, fromTable: Bool)
    var utcDays: Double { get }
    static func days(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double) -> Double
}
extension Engine.DeltaT {
    static func seconds(ut: Double, model: DeltaTModel) -> Double
}
```

- `init(ut:tt:deltaTModel:)` stores both scales as given. It keeps the model only when both are finite; otherwise the time is invalid and its scales stay as given, so a huge UT with an infinite TT still reports that UT.
- `fromPair(ut:tt:deltaTModel:)` rebuilds a time from recorded scales, as `AstroTime(tt:ut:deltaTModel:)` does, and returns `Engine.Time.invalid` (NaN scales, no model) when either scale is not finite.
- `isValid` is true when both scales are finite.
- `init(ut:deltaTModel:)` sets `tt = ut + ΔT(ut) / 86400`. With Espenak-Meeus, TT overflows from about |ut| = 1e158 days and the time is invalid with its UT kept.
- `init(tt:deltaTModel:)` is the bounded inverse of local patch 10 in MAINTAINING.md. It returns exactly the requested TT. It starts from `ut = tt`, iterates at most 128 times, and accepts a UT whose model TT is within `max(1e-12, 2ε|tt|)` days, where ε = 2.22e-16 is the double epsilon, so a large TT converges at the precision a double holds. In the TT gap left by a positive Delta T jump it bisects to the first representable UT after the jump. In the overlap of a negative jump it returns the solution iteration reaches first: the later one where Delta T is positive and the earlier one where it is negative (1900). A TT that is not finite, an iterate that is not finite, or no convergence gives `invalid`.
- `civil(utcDays:deltaTModel:)` and `utcDays` convert civil UTC with the existing generated table in `UTCOffsetTable.swift` (`CivilTime`), from 1961 on. Before 1961 the civil day count is taken as UT1. A TT inside a positive leap second maps to the following midnight, and where a negative historical step repeats civil times the later occurrence wins.
- `days(year:month:day:hour:minute:second:)` is the proleptic Gregorian day count from 2000-01-01 12:00, with every integer component clamped to `Int32`.
- `Engine.DeltaT.seconds(ut:model:)` evaluates `espenakMeeus(ut:)` or `jplHorizons(ut:)`, which holds UT at 17 tropical years after J2000.

Every time derived from another (adding days, a search step, a light-time backdate) derives TT with the source time's model, so one calculation uses one model from its input to its result. The process default belongs to the public layer, not to `Engine`: engine functions take a model or a time that carries one, and the public layer reads the default once per call, when the caller passes no model.

A time derived from an invalid time, which has no model, uses the `fallback` the caller passes. The public layer passes the default it read for the call. This is what C patch 18 does: `Astronomy_AddDays` on a time with no Delta T function uses the process-wide one, so `AstroTime(ut: 1e160).addingDays(-1e160)` is a valid time at J2000 under the current default. A function that derives times from a caller's time takes the same `fallback` argument.

There is no separate calculation-context object. The C engine kept per-call state in two places: the Delta T function captured in `astro_time_t`, which `Engine.Time` now carries, and the nutation and sidereal-time memo fields (`psi`, `eps`, `st`). The engine recomputes those values, reading nutation from the shared nutation cache (#86). Everything else a calculation needs is an argument or immutable model data.

`Engine.Time` is not `Equatable`. The public `AstroTime` keeps UT-only equality, ordering, hashing and `Codable`; engine code compares the scale it means. `AstroTimeTests` pins the public contract: two times with the same UT are equal and hash alike whatever their TT and model, signed zero UTs included, and the encoded form is exactly the UT, so decoding derives TT again. That loses a TT the model cannot give from the UT, such as a TT in the gap of a positive Delta T jump, which no UT reaches. Such a time is rebuilt from both scales: `fromPair` and `AstroTime(tt:ut:deltaTModel:)` give back every valid time bit for bit, and the times derived from it too (`EngineTimeTests`, `DeltaTModelCaptureTests`). A time whose recorded scales are not both finite is invalid, so it rebuilds as `invalid` with NaN scales and loses a finite UT it held, such as `Engine.Time(ut: 1e160)`.

The process default moves from the C atomic to a `Synchronization.Atomic` in the public layer (`AstronomyConfig`) when #96 switches the API over.

### Differences from the C engine

- `days(year:...)` normalizes the month with floor division before counting days. `Astronomy_MakeTime`'s Fliegel and Van Flandern formula truncates instead. The two agree for months 1 to 14 from year −999,999 on, where every division in that formula has a non-negative numerator. Outside that range the C formula can miss the Gregorian date by a day or two, though not every such month does: month 15 of 2001 gives 2002-03-03 instead of March 1, while months 26 and 38 of 2001 land on the right day.
- Espenak-Meeus keeps the C engine's decimal year, `2000 + (ut − 14) / 365.24217`, which puts 2000.0 at 2000-01-15 12:00 UT. NASA defines the year of a month as `year + (month − 0.5) / 12`, which puts 2000.0 at the start of January, so the engine reaches each decimal year about 14.5 days (0.04 years) later than NASA's definition. Delta T differs by its rate of change times 0.04 years: about 0.02 s in 2026, 0.3 s in 3000 and 0.7 s at −500. The published definition is month-resolution, and a continuous replacement needs a choice of year length and calendar; that choice is open.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Foundation/` check the time code against published sources, not against C output:

- Espenak-Meeus against NASA's polynomial page, transcribed independently, at ten points in each bounded piece, two in each open-ended one, and on both sides of every piece boundary; against Table 1 from −500 to +500 within the 4 seconds that page states, from 600 to 1800 within each value's published standard error, and against Table 2 (1955 to 2005) within the 0.1 s it is published to.
- The TT inverse in the gap or overlap of every Espenak-Meeus discontinuity, under both models where the model reaches it.
- Civil UTC against every row of `Scripts/time-data/tai-utc.dat`, read directly, at the start of each row and halfway to the next; IERS Bulletin C's 37 s; the ERFA `t_utctai` reference; the 2016 leap second and the 1961 negative step.
- Day counts against Meeus (Astronomical Algorithms, chapter 7), ERFA `eraCal2jd`, and Julian Day 0, with the 146,097-day 400-year cycle, normalization and `Int32` clamping.

The JPL Horizons model is a reverse-engineered approximation with no published values; its tests check that it equals Espenak-Meeus before the hold and is constant after it.

### Time tests that depend on the C engine

Issue #96 requires a recorded disposition for each test that imports `CLibAstronomy` or pins C output. Two of the suites it lists are time tests and appear here; #84 leaves the others (cache, ephemeris, polynomial, ecliptic-state and reproducibility tests) unchanged.

| Test | Disposition |
|---|---|
| `CivilTimeTests` | Kept while the C engine ships; #84 only drops an unused `import CLibAstronomy` and renames one test. The suite uses `@testable` access to the internal `CivilTime.terrestrialTime` and `CivilTime.segments`, which the engine shares, and reaches C through `AstroTime` construction, `Sun.searchLongitude` and `Sun.position`, and the C-backed `AstronomyConfig.deltaTEspenakMeeus` in the Delta T jump tests. When #96 switches the public layer over, the same assertions run on the Swift engine. `EngineCivilTimeTests` and `EngineTimeConversionTests` hold the engine's own civil and TT-inverse checks. |
| `DeltaTThreadSafetyTests` "A calculation keeps its time's model when the default changes mid-calculation" | Kept while the C engine ships: it checks local patch 18 through a C Delta T function that changes the process default. The engine has no process default; `EngineTimeConversionTests` checks that derived times keep their model whatever fallback is passed. Planned for #96: retire it and replace the C stand-ins with the public layer's `Atomic` default and its own test. |
| `DeltaTThreadSafetyTests` "Concurrent model swaps never corrupt time construction" | Kept while the C engine ships: it checks local patch 2, the atomic C function pointer, under ThreadSanitizer. Planned for #96: retire it with the same replacement. |

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

In the tree: `EngineSearch.swift`.

```swift
extension Engine.Search {
    static let iterationLimit: Int  // 20
    static func ascendingRoot(
        from start: Engine.Time, to end: Engine.Time, toleranceSeconds: Double, fallback: DeltaTModel,
        _ function: (Engine.Time) throws -> Double
    ) throws -> Engine.Time?
}
extension Engine.LightTravel {
    static let iterationLimit: Int  // 10
    static func correct<F: Engine.Frame>(
        at time: Engine.Time, fallback: DeltaTModel, _ position: (Engine.Time) throws -> Engine.Vector<F>
    ) throws -> Engine.Vector<F>
}
```

The closures are synchronous and non-escaping. They take the place of the C callbacks, which the public `Search.swift` reaches through trampolines. An error a closure throws ends the call and propagates unchanged, and the closure is not called again.

`ascendingRoot` keeps `Astronomy_Search`'s expressions, branch order and 20-pass limit, after which it throws `noConvergence`. It includes local patch 20's ascending-bracket checks, so it does not report the descending root or the short constant window of #142. It returns `nil` where the C function returns `ASTRO_SEARCH_FAILURE`: for a single descending root, a function that never rises through zero in the window, or any window it cannot bracket. A function that is negative up to the later end and zero at it does rise through zero there, so the search does not return `nil` for it. Each time it derives takes the model of the time it comes from, or `fallback` when that time is invalid. Midpoints and interpolated roots come from the window's first bound in argument order, which begins as `start`.

`correct` keeps `Astronomy_CorrectLightTravel`. It calls `position` at most 10 times. Each backdate is `time.adding(days: -distance / Engine.speedOfLightAUPerDay, fallback: fallback)`, a UT offset whose TT comes from the observation time's model, and the iteration stops when TT moves less than 1e-9 days. A distance beyond one light-day throws `invalidParameter`, and a tenth call without convergence throws `noConvergence`. The result is the last vector `position` returned, with its time set to the time that call received, as the public `AstroSearch.correctLightTravel` reports it. The light-day is the published one (see [Constants](#constants)).

## Caches and reset

In the tree: `EngineCache.swift`.

- `Engine.ExactKey` is the bit pattern of a finite `Double`. `0.0` and `-0.0` are different keys. A value that is not finite has no key and bypasses the cache.
- `Engine.BoundedCache<Key, Value>` holds at most `capacity` entries and replaces the oldest insertion when full, as the C caches do. All threads share the entries. The computation runs outside the lock, so it may use any cache, including the one it fills. A computation that throws stores nothing. `statistics` counts hits and misses for work-count tests.
- A cached value is a pure function of its key: never the process Delta T default, never a caller's time metadata. Then a hit returns what recomputing would, and a reset at any moment cannot change a result.
- Each module creates its caches as `static let` properties, registered with `Engine.CacheRegistry.shared`, so a cache that has never been used does not exist yet. That is a convention, not a checked rule: a cache made on every call gives correct results but never a hit. The registry holds its caches weakly. Once nobody references a cache, a reset skips it, and the next registration drops its entry, so after each registration the registry holds no more entries than there are caches alive.
- `Engine.resetCaches()` empties every registered cache. It does not touch the Delta T default, fixed star definitions or gravity simulations, which are not caches. #96 makes `AstronomyConfig.reset()` call it and updates that method's documentation.
- A reset does not wait for computations in progress. A lookup that missed before a reset stores its value after it, and a computation can itself reset. Either way the stored value is the one its key gives, so the next hit returns what recomputing would.
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

`AstroTime` will store an `Engine.Time`, `setDeltaTModel` will write the public layer's atomic default, a `nil` model argument resolves to that default once per public call, and `AstronomyConfig.reset()` will call `Engine.resetCaches()`. `AstroTime(year:...)` and `AstroTime.civil(days:deltaTModel:)` will call `Engine.Time.days` and `Engine.Time.civil(utcDays:deltaTModel:)`, so the civil rules live in one place. Public names, signatures, conformances, `Codable` shape, units, frames and error cases do not change.

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
