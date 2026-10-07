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

A module that needs another frame, such as Jupiter's equator for its moons, declares it in its own directory. `Engine.EQM`, the mean equator and equinox of date, is declared in `Orientation/` (see [Earth orientation](#earth-orientation)).

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

Combining, inverting and pivoting rotations, and the rotations between frames, are in `Orientation/` (see [Earth orientation](#earth-orientation)). Other vector arithmetic stays in the module that uses it until a second module needs it, and then moves here through #84.

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
    func adding(days: Double) -> Engine.Time
    func derived(ut: Double) -> Engine.Time
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

A time derived from an invalid time, which has no model, is invalid too, even where its UT is finite: it keeps that UT and has a NaN TT. Engine code that derives a time from another uses `adding(days:)` or `derived(ut:)`, which apply this rule, so no engine function takes a fallback model.

There is no separate calculation-context object. The C engine kept per-call state in two places: the Delta T function captured in `astro_time_t`, which `Engine.Time` now carries, and the nutation and sidereal-time memo fields (`psi`, `eps`, `st`). The engine recomputes those values, reading nutation from the shared nutation cache (#86). Everything else a calculation needs is an argument or immutable model data.

`Engine.Time` is not `Equatable`. The public `AstroTime` keeps UT-only equality, ordering, hashing and `Codable`; engine code compares the scale it means. `AstroTimeTests` pins the public contract: two times with the same UT are equal and hash alike whatever their TT and model, signed zero UTs included, and the encoded form is exactly the UT, so decoding derives TT again. That loses a TT the model cannot give from the UT, such as a TT in the gap of a positive Delta T jump, which no UT reaches. Such a time is rebuilt from both scales: `fromPair` and `AstroTime(tt:ut:deltaTModel:)` give back every valid time bit for bit, and the times derived from it too (`EngineTimeTests`, `DeltaTModelCaptureTests`). A time whose recorded scales are not both finite is invalid, so it rebuilds as `invalid` with NaN scales and loses a finite UT it held, such as `Engine.Time(ut: 1e160)`.

The process default moves from the C atomic to a `Synchronization.Atomic` in the public layer (`AstronomyConfig`) when #96 switches the API over.

### Differences from the C engine

- `days(year:...)` normalizes the month with floor division before counting days. `Astronomy_MakeTime`'s Fliegel and Van Flandern formula truncates instead. The two agree for months 1 to 14 from year −999,999 on, where every division in that formula has a non-negative numerator. Outside that range the C formula can miss the Gregorian date by a day or two, though not every such month does: month 15 of 2001 gives 2002-03-03 instead of March 1, while months 26 and 38 of 2001 land on the right day.
- Espenak-Meeus takes NASA's decimal year, not the C engine's `2000 + (ut − 14) / 365.24217`, which puts 2000.0 at 2000-01-15 12:00 UT, about 14.5 days after NASA's 1 January (#165). NASA defines only the middle of each month, `year + (month − 0.5) / 12`. `Engine.DeltaT.decimalYear(ut:)` makes it continuous in the calendar the Canon's dates use: year `Y` is exactly `Y` at 1 January 0:00 UT, Julian through 1582 and Gregorian from 1583, and grows evenly through that year's days. 1582 has 355 days, so there is no jump at the reform. Beyond years −999,999 and 1,000,001 it grows by one mean Julian or Gregorian year. Each polynomial piece starts exactly at 1 January of its year. The C engine reaches each decimal year later than this: by 12.7 to 15.3 days from 1583 through 3000, depending on the leap cycle. Just before the reform the lag is smallest, about 4 days in 1581, because the Canon's Julian 1 January falls up to 10 days after the Gregorian one there, and it grows going back: about 9 days at 1000, 13 at 500, 21 at −500 and 32 at −1999. Within 1582's 355 days it grows from 4.3 to 14.5 days. Delta T moves from the C value by its rate of change times that lag: about 0.02 s in 2026, 0.3 s in 3000, 1.0 s at −500 and 2.1 s at −1999. `EngineDeltaTTests` checks the decimal year against Foundation's calendar, which switches on 1582-10-15 as the Canon does, and against NASA's month middles to within two days. The public solar-altitude bounds (`SolarAltitudeNumerics.md`, `SolarAltitudeObservationTests`) assume the C engine's year and need rechecking when #96 switches over.
- A time derived from an invalid time is invalid. Under local patch 18, `Astronomy_AddDays` on a time with no Delta T function uses the process-wide one, so `AstroTime(ut: 1e160).addingDays(-1e160)` is a valid time at J2000 under the current default. This needs a time whose UT is finite and whose TT is not: with Espenak-Meeus, |ut| above about 8.7e157 days, which a caller passes or a search step at such magnitudes produces. The public result in 3.1.0 is valid, so this is a public difference the owner chose on #168, which #96 tracks as a release decision.

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
| `DeltaTThreadSafetyTests` "A calculation keeps its time's model when the default changes mid-calculation" | Kept while the C engine ships: it checks local patch 18 through a C Delta T function that changes the process default. The engine has no process default; `EngineTimeConversionTests` checks that derived times keep their model. Planned for #96: retire it and replace the C stand-ins with the public layer's `Atomic` default and its own test. |
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
        from start: Engine.Time, to end: Engine.Time, toleranceSeconds: Double,
        _ function: (Engine.Time) throws -> Double
    ) throws -> Engine.Time?
}
extension Engine.LightTravel {
    static let iterationLimit: Int  // 10
    static func correct<F: Engine.Frame>(
        at time: Engine.Time, _ position: (Engine.Time) throws -> Engine.Vector<F>
    ) throws -> Engine.Vector<F>
}
```

The closures are synchronous and non-escaping. They take the place of the C callbacks, which the public `Search.swift` reaches through trampolines. An error a closure throws ends the call and propagates unchanged, and the closure is not called again.

`ascendingRoot` keeps `Astronomy_Search`'s expressions, branch order and 20-pass limit, after which it throws `noConvergence`. It includes local patch 20's ascending-bracket checks, so it does not report the descending root or the short constant window of #142. It returns `nil` where the C function returns `ASTRO_SEARCH_FAILURE`: for a single descending root, a function that never rises through zero in the window, or any window it cannot bracket. A function that is negative up to the later end and zero at it does rise through zero there, so the search does not return `nil` for it. Each time it derives takes the model of the time it comes from, and is invalid when that time is. Midpoints and interpolated roots come from the window's first bound in argument order, which begins as `start`.

`correct` keeps `Astronomy_CorrectLightTravel`. It calls `position` at most 10 times. Each backdate is `time.adding(days: -distance / Engine.speedOfLightAUPerDay)`, a UT offset whose TT comes from the observation time's model, and the iteration stops when TT moves less than 1e-9 days. A distance beyond one light-day throws `invalidParameter`, and a tenth call without convergence throws `noConvergence`. The result is the last vector `position` returned, with its time set to the time that call received, as the public `AstroSearch.correctLightTravel` reports it. The light-day is the published one (see [Constants](#constants)).

## Earth orientation

In the tree: `Orientation/EngineNutation.swift`, `Orientation/EnginePrecession.swift`, `Orientation/EngineEarthRotation.swift`, `Orientation/EngineRotations.swift`, `Orientation/EngineFrameRotations.swift`, `Orientation/EngineCoordinates.swift`, `Orientation/EngineObserver.swift`, `Orientation/EngineAtmosphere.swift`, `Orientation/EngineRefraction.swift`, `Orientation/EngineHorizon.swift` and the generated `Orientation/Generated/IAU2000BTerms.swift`. Every C entry point listed for #86 under [C entry points by owner](#c-entry-points-by-owner) has a native counterpart here.

```swift
extension Engine.Nutation {
    struct Angles { var longitude, obliquity, longitudeRate, obliquityRate: Double }
    static func evaluate(centuries t: Double) -> Angles
    static let cache: Engine.BoundedCache<Engine.ExactKey, Angles>
    static func angles(tt: Double, cache: Engine.BoundedCache<Engine.ExactKey, Angles> = cache) -> Angles
}
extension Engine.EarthTilt {
    init(tt: Double, cache: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> = Engine.Nutation.cache)
    var nutation: Engine.Nutation.Angles
    var meanObliquity, meanObliquityRate: Double
    var trueObliquity, trueObliquityRate, equationOfEquinoxes: Double { get }
    var nutationRotation: Engine.Rotation<Engine.EQM, Engine.EQD> { get }
    var nutationRate: Engine.RotationRate<Engine.EQM, Engine.EQD> { get }
}
extension Engine.Precession {
    static func meanObliquity(tt: Double) -> Double
    static func meanObliquityRate(tt: Double) -> Double
    static func angles(tt: Double) -> Angles  // ψA, ωA, χA and their rates
    static func rotation(tt: Double) -> Engine.Rotation<Engine.EQJ, Engine.EQM>
    static func rate(tt: Double) -> Engine.RotationRate<Engine.EQJ, Engine.EQM>
}
extension Engine.EarthRotation {
    static func angle(ut: Double) -> Double
    static func meanSiderealTime(_ time: Engine.Time) -> Double
    static func apparentSiderealTime(
        _ time: Engine.Time,
        cache: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> = Engine.Nutation.cache
    ) -> Double
}
extension Engine.Rotation {
    func apply(to state: Engine.State<From>, rate: Engine.RotationRate<From, To>) -> Engine.State<To>
    var inverse: Engine.Rotation<To, From> { get }
    func then<Next>(_ next: Engine.Rotation<To, Next>) -> Engine.Rotation<From, Next>
    func pivoted(axis: Int, angle: Double) throws -> Self
}
extension Engine.FrameRotation {
    static let eqjToEcl: Engine.Rotation<Engine.EQJ, Engine.ECL>      // and eclToEqj
    static let eqjToGal: Engine.Rotation<Engine.EQJ, Engine.GAL>      // and galToEqj
    static func eqjToEqd(_ time: Engine.Time) -> Engine.Rotation<Engine.EQJ, Engine.EQD>
    // eqdToEqj, eqjToEct, ectToEqj, eqdToEct, ectToEqd, eqdToEcl, eclToEqd take a time;
    // eqdToHor, horToEqd, eqjToHor, horToEqj, eclToHor, horToEcl take a time and an Observer.
}
extension Engine.Spherical { init<F>(_ vector: Engine.Vector<F>) throws }      // latitude, longitude, distance
extension Engine.Vector { init(_ sphere: Engine.Spherical, time: Engine.Time) }
extension Engine.Equatorial { init<F>(_ vector: Engine.Vector<F>) throws }     // rightAscension, declination, distance
extension Engine.Ecliptic { init(_ vector: Engine.Vector<Engine.EQJ>) }        // vector in ECT, latitude, longitude
extension Engine.Observers {
    static func vectorOfDate(_ observer: Observer, at time: Engine.Time) -> Engine.Vector<Engine.EQD>  // and vector, J2000
    static func stateOfDate(_ observer: Observer, at time: Engine.Time) -> Engine.State<Engine.EQD>    // and state, J2000
    static func observer(atVectorOfDate vector: Engine.Vector<Engine.EQD>) -> Observer          // and atVector:, J2000
    static func gravity(latitude: Double, height: Double) -> Double
}
extension Engine.Atmosphere { init(elevation: Double) throws }               // pressure (Pa), temperature (K), density
extension Engine.AtmosphericRefraction {
    static func angle(_ refraction: Refraction, altitude: Double) -> Double
    static func inverseAngle(_ refraction: Refraction, altitude: Double) -> Double
}
extension Engine.Horizontal {   // azimuth, altitude, rightAscension, declination
    init(time: Engine.Time, observer: Observer, rightAscension: Double, declination: Double, refraction: Refraction)
}
extension Engine.Spherical { init(horizon vector: Engine.Vector<Engine.HOR>, refraction: Refraction) throws }
extension Engine.Vector where F == Engine.HOR {
    init(horizon sphere: Engine.Spherical, time: Engine.Time, refraction: Refraction)
}
```

- Nutation is IAU 2000B as SOFA's `iauNut00b` evaluates it: the 77 luni-solar terms, summed smallest first with each argument reduced to one turn, plus fixed offsets of −0.135 and +0.388 mas for the planetary terms. `Scripts/generate-nutation-table.py` writes the table from ERFA 2.0.1's `nut00b.c`, pinned in `Scripts/orientation-data` with its SHA-256, and `--check` runs in CI. The rates are the derivatives of the same terms. Angles are in degrees and rates in degrees per TT day.
- `angles(tt:)` reads the shared cache, keyed by the exact TT in Julian centuries (`tt / 36525`), the value the series reads. One evaluation gives the angles and the rates, so an angle caller warms the entry a rate caller reads. `Engine.Time` carries no counterpart of the C engine's `psi`, `eps` and `st` memo fields, and reading the cache leaves a time's scales and model untouched. In C a caller could pre-fill those fields and have them used, but no public API does: `AstroTime` gets its `astro_time_t` from the C time constructors, which set them to NaN, or from a C result, which holds only values the C engine computed for that TT, and each public call works on a local copy. So the memo only saved recomputing within one call, and the shared cache now does that with the same values. `EngineNutationCacheTests` counts the evaluations.
- The mean obliquity and the precession angles ψA, ωA and χA are the IAU 2006 polynomials (Capitaine, Wallace and Chapront 2003; SOFA `iauObl06` and `iauP06e`). The precession matrix is P = R3(χA)·R1(−ωA)·R3(−ψA)·R1(ε0), IERS Conventions (2010) equation 5.39, from the mean equator and equinox of J2000 to those of date. There is no frame bias: EQJ is the mean J2000 frame, as in the C engine.
- The nutation matrix is R1(−εA − Δε)·R3(−Δψ)·R1(εA), SOFA's `iauNumat`, from EQM to EQD.
- `Engine.RotationRate` holds the derivative of a rotation per TT day in the rotation's own slots, so it cannot be applied as a rotation. `apply(to:rate:)` takes a state through a rotation that moves with time: the position is rotated, and the velocity is rotated plus the rate applied to the position. They port local patch 12's `precession_rot_rate` and `nutation_rot_rate`.
- `inverse` is the transpose. `then(_:)` is `Astronomy_CombineRotation`: the first rotation, then the second. `pivoted(axis:angle:)` is `Astronomy_Pivot`: after the rotation, it turns vectors `angle` degrees counterclockwise about axis 0, 1 or 2, seen from the axis's positive end. It throws `invalidParameter` for another axis or an angle that is not finite.
- `Engine.FrameRotation` has one rotation for each C frame pair, built the way the C engine builds it: EQJ to EQD is precession then nutation, EQD and ECT differ by R1(εA + Δε), EQJ and ECL by R1(ε0), and the horizon rotations turn the observer's zenith, north and west by apparent sidereal time. Each reverse rotation is the transpose. The horizon rotations read only the observer's latitude and longitude; the public layer validates the observer. Rotations at a time read nutation through the shared cache.
- The galactic rotation is the J2000 frame of the Hipparcos Catalogue (Vol. 1, §1.5.3; Murray 1989), built from its defining angles: north galactic pole at αG = 192.85948°, δG = +27.12825°, and the ascending node at galactic longitude lΩ = 32.93192°. This replaces the C engine's matrix, which converts the IAU 1958 B1950 constants through the true equator of B1950 and is 8.77″ from those axes (#152). The public `RotationMatrix.equatorialJ2000ToGalactic()` and `galacticToEquatorialJ2000()` already return it, ahead of #96.
- `Engine.Spherical(_:)` is `Astronomy_SphereFromVector`: longitude counterclockwise from x seen from +z, in [0, 360), and latitude in degrees. A vector on the z axis has longitude 0 and latitude ±90; one where x² + y² and z are both zero throws `invalidParameter`. `Engine.Equatorial(_:)` is the same with the longitude in hours. `Engine.Ecliptic(_:)` is `Astronomy_Ecliptic`: the J2000 vector rotated to the true ecliptic of date, with longitude 0 on the ecliptic pole. Longitudes that round up to 360 when moved into range are returned as 0.
- Observer positions use the ellipsoid of the IERS Conventions (2010), Table 1.1: equatorial radius 6,378.1366 km and flattening 1/298.25642, in SOFA's `iauGd2gce` form, turned by apparent sidereal time. The velocity of date is the IERS nominal angular velocity 7.292115e-5 rad/s crossed into the position; the J2000 state rotates position and velocity without the rotation rate, as the C engine does. Distances convert with the published au (see [Constants](#constants)), not the C engine's. The inverse runs the C engine's Newton iteration on the ellipsoid, at most 11 steps with tolerance 2e-8 km, and puts a point within 1 mm of the axis at latitude ±90 and longitude 0. A component that is not finite, or too large to convert to kilometres, and an iteration that does not converge give NaN latitude, longitude and height; off the axis the C engine ends the process in both cases (#174), and for an of-date vector on the axis it returns ±90 for a non-finite z (a J2000 one leaves the axis under precession, so C exits). Gravity is the WGS 84 normal gravity of NIMA TR8350.2 (equations 4-1 and 4-3).
- `Observer.geocentric` is at latitude 0 and height −6,378,136.6 m, the ellipsoid's equatorial radius, so its vector is exactly zero (#154). The public constant changed with #86, so the C engine also puts it at the centre.
- `Engine.Atmosphere(elevation:)` is the 1976 U.S. Standard Atmosphere (NOAA-S/T 76-1562) with every layer computed from the defining constants g0, M0, R*, sea-level pressure and temperature and the lapse rates, so the troposphere exponent is g0·M0/(R*·L) = 5.2558761 and the 11 km and 20 km base pressures are 22,632.064 and 5,474.889 Pa (#153). Like the C engine it accepts −500 to 100,000 m, throws `invalidParameter` outside that or for a value that is not finite, and keeps the +1 K/km layer above 32 km, where the standard changes layer (#175). The public `Atmosphere.at(elevation:)` already uses it; rise/set searches still read the C engine's atmosphere for horizon refraction until #96, a difference of at most about 3e-5 relative in density.
- `AtmosphericRefraction.angle` is `Astronomy_Refraction`: Sæmundsson's formula as Meeus gives it (Astronomical Algorithms, 2nd ed., eq. 16.4) with the altitude held at −1° below that, as JPL Horizons does. `.normal` scales the result below −1° linearly to zero at −90°; `.jplHorizons` does not. `.none` gives 0 for any altitude; the other models give 0 outside −90 to 90 and NaN for NaN, as in C. `inverseAngle` is `Astronomy_InverseRefraction`, with the same 1,000-step iteration, 1e-14 tolerance, two-cycle rule and zero results. Sæmundsson's formula is slightly negative at the zenith (−0.0019′); the engine keeps it, as C does, without Meeus's +0.0019279′ correction.
- `Engine.Horizontal` is `Astronomy_Horizon`: azimuth east of north in [0, 360), 0 where the direction has no horizontal component, and azimuth 0 with a NaN altitude for a right ascension or declination that is not finite; with refraction, the altitude rises by the refraction at the geometric altitude and the right ascension and declination turn toward the zenith by the same amount unless the refraction is not positive or the result is within 3e-4° of the zenith. `Engine.Spherical(horizon:refraction:)` and `Engine.Vector(horizon:time:refraction:)` are `Astronomy_HorizonFromVector` and `Astronomy_VectorFromHorizon`.
- The Earth rotation angle is SOFA's `iauEra00`, in degrees from 0 up to 360. Mean sidereal time is `iauGmst06`: the angle at `time.ut` plus the IAU 2006 polynomial at `time.tt`. Apparent sidereal time adds the equation of the equinoxes Δψ·cos εA. Both are in sidereal hours from 0 up to 24; a value that rounds up to the period is returned as 0. A time or day count that is not finite gives NaN, and nutation for it is computed without touching the cache.

### Differences from published definitions

- The equation of the equinoxes leaves out the complementary terms of IAU 1994 Resolution C7 (SOFA `iauEect00`), as `Astronomy_SiderealTime` does. They reach about 2.65 mas between 1950 and 2050. #170 tracks whether to add them.
- The atmosphere keeps the 20 to 32 km layer up to 100 km (#175).

### Differences from the C engine

- The galactic rotation (#152), the atmosphere's constants (#153) and the observer inverse's non-convergence (#174), as described above.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Orientation/` check against SOFA through ERFA 2.0.1 (the commit `THIRD_PARTY_NOTICES` pins), not against C output:

- The values in ERFA's own test program, `t_erfa_c.c`: `t_nut00b`, `t_obl06`, `t_p06e`, `t_numat`, `t_era00` and `t_gmst06`, each within SOFA's tolerance or tighter; `t_bp06` within 1e-13, because SOFA builds that matrix from the Fukushima-Williams angles, which agree with equation 5.39 to 3e-14 there; and `t_gst06a` within the 4 mas that IAU 2000B (1 mas of 2000A from 1995 to 2050) and #170 allow.
- pyerfa 2.0.1.5 at eight epochs from 1600 to 2500, with UT1 and TT apart: nutation to 1e-15 rad, mean obliquity and the precession angles to 1e-15 rad, the precession matrix against equation 5.39 built from the SOFA angles to 1e-15, and the Earth rotation angle and mean sidereal time to 1e-12 rad.
- `t_rx`, `t_ry` and `t_rz` for pivoting, `t_c2s`, `t_p2s`, `t_s2c` and `t_s2p` for the spherical conversions, `t_hd2ae` through the horizon rotation, and `t_icrs2g` through the galactic rotation. The galactic matrix matches `eraIcrs2g`'s to 1e-15 and the Hipparcos Catalogue's printed A_G to its ten decimals.
- At the eight pyerfa epochs, the frame rotations against N·P, R1(εA + Δε) and R1(ε0) built from the SOFA angles, to 2e-15, and the ecliptic of date against the same rotation followed by SOFA's `eraC2s` definition.
- Observer positions against pyerfa `gd2gce` on the IERS 2010 ellipsoid at seven latitudes and heights, including both poles, 2,000 km up and 500 m down, to 1e-6 m; the inverse against `gc2gde` to 1 mm in height; gravity against TR8350.2's equations; and the geocentric observer's zero vector.
- The atmosphere's layer base pressures and temperatures as the 1976 standard prints them, to half a unit in the seventh figure, and the closed form at 1e-12 at thirteen heights, including both sides of the 11 km and 20 km layer boundaries.
- Refraction against Sæmundsson's formula as Meeus prints it, at the horizon (28.98′), across both branches, at −90°, 90° and outside the range; the inverse on both models and on every double from −80° for 2,000 ulps; `t_hd2ae` through `Engine.Horizontal`.
- Rates against five-point differences of the values on exact binary-fraction stencils, and the moving-rotation state against the derivative of the rotated position.
- The nutation cache's work counts with a private registry: one evaluation per instant across angle, rate, tilt and sidereal-time callers, signed-zero keys, nonfinite bypass, eviction of the oldest of 32, reset, and simultaneous callers.

### Orientation tests that depend on the C engine

| Test | Disposition |
|---|---|
| `NutationCacheTests` | Kept while the C engine ships: it pins the C nutation cache (local patch 13) through `_Astronomy_Iau2000bRates`. `EngineNutationCacheTests` holds the engine's work counts. Retired when #96 removes the C engine. |
| `Scripts/performance/test-nutation-cache.sh`, `nutation_cache_probe.c` and `nutation_output_probe.c` | Kept while the C engine ships, for the same reason, and retired with it. |
| `InverseRefractionTests` | Kept while the C engine ships: it checks termination of `Astronomy_InverseRefraction` and pins its bits through the public API. `EngineRefractionTests` checks the native inverse against Sæmundsson's formula. Retired, or moved to the engine's values, when #96 switches the public refraction over. |
| `ReproducibilityTests` | Kept while the C engine ships: it pins public results across modules (positions, rates, events), not published values. The orientation parts it reaches are checked against SOFA here. Retired by #96 with the C engine. The 2026 geocentric equatorial entries were re-recorded with `Observer.geocentric` at the centre (#154). |
| `RotationTests`, `AtmosphereTests`, `ObserverVectorTests` | Public-API checks against published values, as normal assertions for #152, #153 and #154; they need no C. |

## Planetary series

In the tree: `Planets/EnginePlanets.swift`, `Planets/EnginePlanetPolynomial.swift`, `Planets/EngineVSOP87B.swift`, `Planets/EnginePlanetPositions.swift` and the generated tables in `Planets/Generated/`.

```swift
extension Engine {
    enum Planet: Int, CaseIterable { case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune }
    // init?(_ body: CelestialBody): nil for every other body
    static func unpackDoubles(count: Int, _ text: StaticString) -> [Double]
}
extension Engine.VSOP87B {
    struct Model { let termCounts: [[Int]]; let terms: [Double] }   // A, B, C of each term
    static func model(_ planet: Engine.Planet) -> Model
    static func coordinates(_ model: Model, millennia t: Double) -> SIMD3<Double>   // longitude, latitude, radius
    static func derivatives(_ model: Model, millennia t: Double) -> SIMD3<Double>   // per Julian millennium
    static func rectangular(_ sphere: SIMD3<Double>) -> SIMD3<Double>
    static func velocity(_ sphere: SIMD3<Double>, rates: SIMD3<Double>) -> SIMD3<Double>   // AU per day
    final class Cache { init(capacity: Int = 32, registry: Engine.CacheRegistry); let registry: Engine.CacheRegistry }
    static let cache: Cache
    static func coordinates(_ planet: Engine.Planet, millennia t: Double, cache: Cache = cache) -> SIMD3<Double>   // and derivatives
    static let toEquatorial: Engine.Rotation<Engine.VSOP87Ecliptic, Engine.EQJ>
}
extension Engine.Planet {
    static let acceptedTTDays: Double  // 1,461,000
    func heliocentricEclipticPosition(at time: Engine.Time, cache: Engine.VSOP87B.Cache = VSOP87B.cache) throws -> Engine.Vector<Engine.VSOP87Ecliptic>
    func heliocentricEclipticState(at time: Engine.Time, cache: Engine.VSOP87B.Cache = VSOP87B.cache) throws -> Engine.State<Engine.VSOP87Ecliptic>
    func heliocentricPosition(at time: Engine.Time, cache: Engine.VSOP87B.Cache = VSOP87B.cache) throws -> Engine.Vector<Engine.EQJ>   // and heliocentricState
    func heliocentricDistance(at time: Engine.Time, cache: Engine.VSOP87B.Cache = VSOP87B.cache) throws -> Double
}
extension Engine.PlanetPolynomial {
    static let start: Double  // −36,524.5: 1900-01-01 00:00 TT
    static let stop: Double   // 36,889.5: 2101-01-01 00:00 TT
    static func covers(_ tt: Double) -> Bool  // start ≤ tt < stop
    struct Model {
        let degree: Int, width: Double, coefficients: [Double], included: [Bool]
        var excludedSegments: [Int] { get }
        func start(ofSegment k: Int) -> Double
        func segment(containing tt: Double) -> Int?
        func position(tt: Double) -> SIMD3<Double>?
        func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?
    }
    static func model(_ planet: Engine.Planet) -> Model
    static func position(_ planet: Engine.Planet, tt: Double) -> SIMD3<Double>?   // and state
}
```

- `Scripts/generate-planet-tables.py` writes the tables from the C engine's `vsop87b_full.h` and `polynomial-data.h`, whose SHA-256 hashes `Scripts/planet-data/manifest.json` pins, and `--check` runs in CI on macOS and Linux. The headers stay where the C engine reads them; when #96 removes the C target, it moves them to `Scripts/planet-data` and updates the manifest. `--published DIR` also compares the VSOP87B table with the eight files IMCCE publishes, whose URLs and hashes are in the manifest: all 35,080 terms in 135 series match in order and value.
- Each table is a base64 string literal of the doubles' little-endian bit patterns, decoded once per planet on first use. Array literals do not scale: a 100,002-element `[Double]` literal took 390 s and 1.66 GB to compile in Debug, and the polynomial tables hold 1,431,768 doubles. The data is still compiled in; nothing is read from a file. `unpackDoubles` moves to `Foundation/` through #84 when a second module needs it. Decoded, the polynomial tables take 11.5 MB and the VSOP87B terms 0.8 MB, kept for the life of the process.
- VSOP87B gives heliocentric ecliptic longitude and latitude in radians and radius in AU, referred to the dynamical ecliptic and equinox of J2000, as Poisson series in Julian millennia of TT. The tables keep the published term order. `coordinates` and `derivatives` port `VsopCoords` and `VsopDeriv`: every term in table order, with Neumaier compensation inside each power of t and, for the coordinates, across the powers; each longitude power's contribution is reduced modulo 2π. At the four t the tests use, the compensated coordinates equal an exactly rounded sum of the same terms bit for bit, and plain addition is off by 1.4e-12 to 2.2e-10 rad in Mercury's longitude. A t that is not finite gives NaN.
- `Engine.VSOP87Ecliptic` is the frame of VSOP87, declared in `Planets/` with its rotation to EQJ, since only this module uses it. It is not ECL: `toEquatorial`, the rotation to FK5 J2000 that `vsop87.doc` prints, tilts by an obliquity 0.003″ larger than IAU 2006's and adds rotations of up to 0.1″. The engine takes FK5 J2000 as EQJ, as the C engine does.
- The polynomials are AstronomyKit's degree-12 Chebyshev fits of the compensated VSOP87B position in the same frame, in segments of 8 days (Mercury, Earth), 16 (Saturn, Neptune) or 32 (the others), from `start` up to `stop`. 413 segments that did not meet the 1e-12 AU fit budget are excluded: 409 of Mercury's and 4 of Venus's.
- Segment `k` holds `start + k·width ≤ tt < start + (k + 1)·width`, as in `polynomial.h`: the index is `Int((tt − start) / width)`, moved back one where the subtraction rounded the double below a boundary up to the boundary's offset. Every width is a power of two, so the division is exact. Outside the span, including a TT that is not finite, and in an excluded segment, the functions return `nil` and the caller uses the full series. The static functions check the span before they decode a table.
- Clenshaw's recurrence gives the position and its derivative together; velocity is in AU per TT day. A state's position is the same double as the position.
- The `Engine.Planet` functions give the heliocentric position, state and distance in the VSOP87 frame or in EQJ. They throw `badTime` when |TT| is above `acceptedTTDays`, 1,461,000 days as the C engine's `EPHEMERIS_MAX_TT_DAYS`, or is not finite, before touching the cache, and when a result component is not finite. `acceptedTTDays` moves to `Foundation/` through #84 when another module needs it. Inside the polynomial span and outside excluded segments they use the polynomials and never the series or the cache. Elsewhere the position is the series coordinates in rectangular form, the state adds the chain-rule velocity from the derivatives, scaled from per millennium to per day, and the distance is the series radius. The EQJ results are the VSOP87 ones rotated.
- `VSOP87B.cache` keeps, for each planet, 32 coordinate and 32 derivative results, keyed by the exact bits of t, in two `BoundedCache`s registered with `CacheRegistry.shared`. A position, a state and a distance at one instant share one evaluation of each series they need; the distance reads the coordinates entry. A t that is not finite bypasses it. The C engine keeps the radius separately so a distance alone sums only the radius series; here a distance alone sums all three coordinates.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Planets/`:

- VSOP87B terms as IMCCE prints them in `VSOP87B.mer`, `VSOP87B.ear` and `VSOP87B.nep`, the 135 series and 35,080 terms in all, and the term counts of Mercury's series. The comparison of every term is the generator's `--published` mode, which needs the IMCCE files and does not run in CI.
- The IMCCE check values in `vsop87.chk` (VSOP87B, every planet at ten dates from 1100 to 2000, SHA-256 in `PublishedVSOP87.swift`): the series coordinates and their rates within 1e-10, and the ecliptic position and velocity from the planet functions against the rectangular form of the published values, through the polynomials at J2000 and the series at the other nine dates. This pins the axis order and the frame. The rotation's entries equal `vsop87.doc`'s.
- The heliocentric distance from the polynomials alone against the JPL Horizons vectors in `Scripts/reference-data/sources/distance/heldout`, within the allowances `DistanceAccuracyTests` applies to the public distance: 1,067 of the 1,072 planet records. The other 5 fall in excluded segments.
- All 1,072 records through the planet functions, the 5 on the series path included: the distance within the same allowances, and the EQJ direction within 1′ of Horizons' ICRF vector, the accuracy `JPLValidationTests` applies. The largest angle is 2.4″, for Neptune.
- The `JPLValidationTests` geocentric suites for the Sun and Mercury to Neptune and the Asheville suites for Mercury to Neptune, at their 1′ and 1.5′ tolerances: the astrometric J2000 direction, Horizons' definition, from the planet functions, light time through `Engine.LightTravel` and the Asheville observer through `Engine.Observers`, with no aberration. The geocentric distances of the same bodies in `distance-fixtures.json` (1,072 records) within their allowances. The largest separation is 0.025′ except the geocentric Uranus and Neptune rows labelled 2026-01-22, which hold Horizons' 2026-01-21 values (#180).
- Cache work counts with private registries: no lookups inside the polynomial span; one evaluation per series shared by position, state and distance; reuse in an excluded segment; separate entries per planet; signed-zero keys; non-finite bypass; eviction of the oldest of 32; reset through a registry and through `Engine.resetCaches()`; a hit returning the caller's own time; simultaneous callers; and a cache with no capacity, which evaluates every time.
- Compensated summation against exact summation, and the accepted range's ends, NaN, infinities and an invalid time on every planet function.
- Clenshaw's recurrence against T_k(cos θ) = cos kθ and dT_k/dx = k·U_{k−1}(x) for every degree; every boundary of every planet and the double below it; every segment at its first, middle and last double, excluded or not; velocity against five-point differences of the position; and adjacent segments, which meet within 2e-12 AU (2.0e-13 at most).

### Planet tests that depend on the C engine

| Test | Disposition |
|---|---|
| `PolynomialTests` | Kept while the C engine ships: it checks through the C heliocentric functions that position and state agree at the coverage boundaries. `EnginePlanetPolynomialTests` checks the Swift polynomials at every segment boundary and that a state's position is the position. Retired when #96 removes the C engine. |
| `VsopCacheTests` | Kept while the C engine ships: it checks the C thread-local cache (local patch 8): caller time metadata, signed zeros, replay, eviction and threads. `EngineVSOP87BCacheTests` checks the same properties of `VSOP87B.cache` by work counts. Retired when #96 removes the C engine. |
| `Scripts/performance/test-vsop-cache.sh` and `vsop_cache_probe.c` | Kept while the C engine ships, for the same reason, and retired with it. `EngineVSOP87BCacheTests` has the Swift negative control, a cache with no capacity. |
| `ReproducibilityTests` planetary cases | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): they pin public results, not published values. The planet series parts they reach are checked against IMCCE and Horizons here. Retired by #96. |
| `DistanceAccuracyTests` and the `JPLValidationTests` planet suites | Published-value checks of the public API, which runs on the C engine until #96. `EnginePlanetPositionsTests` and `EnginePlanetHorizonsTests` apply the same fixtures and allowances to the Swift planet functions. |

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
| VSOP87B series results | #85 | `Engine.VSOP87B.cache`: per planet, a 32-entry `BoundedCache` of coordinates and one of derivatives, `ExactKey` of the scaled TT the series read | Thread-local, 32 per body (local patch 8) |
| Nutation angles and rates | #86 | `Engine.Nutation.cache`: `BoundedCache`, 32 entries, `ExactKey` of TT in Julian centuries, shared by angle, rate, tilt and sidereal-time callers | Thread-local, 32 entries (local patch 13) |
| Moon longitude, latitude, distance | #87 | `BoundedCache`, 32 entries, `ExactKey` of the scaled TT | Thread-local, 32 entries (local patch 14) |
| Pluto segments | #88 | `BoundedCache` keyed by segment index, one entry per table segment | Allocated segments behind a mutex, freed by `Astronomy_Reset` (local patch 1) |
| Delta T default | #96 | `Atomic` in the public layer | `_Atomic` function pointer (local patch 2) |
| Gravity simulation | #88 | Owned by each `GravitySimulation`, with its own lock | Caller-owned handle |
| Fixed star definitions | #91 | Passed by value | Eight shared slots |
| Constellation B1875 rotation | #91 | `static let` | `pthread_once` (local patch 4) |

## Public layer integration (#96)

The galactic rotations (#152) and `Atmosphere.at(elevation:)` (#153) already run on the engine, and `Observer.geocentric` is at the centre (#154); see [Earth orientation](#earth-orientation).

`AstroTime` will store an `Engine.Time`, `setDeltaTModel` will write the public layer's atomic default, a `nil` model argument resolves to that default once per public call, and `AstronomyConfig.reset()` will call `Engine.resetCaches()`. `AstroTime(year:...)` and `AstroTime.civil(days:deltaTModel:)` will call `Engine.Time.days` and `Engine.Time.civil(utcDays:deltaTModel:)`, so the civil rules live in one place. Public names, signatures, conformances, `Codable` shape, units, frames and error cases do not change.

## C entry points by owner

Every C function the Swift layer calls or names has exactly one owner. `EngineContractTests` fails when a Swift source mentions an `Astronomy_` function that is missing from this list or listed under two owners.

- #84: `Astronomy_MakeTime`, `Astronomy_AddDays`, `Astronomy_TimeFromDaysWithDeltaT`, `Astronomy_TerrestrialTimeWithDeltaT`, `Astronomy_TimeFromPair`, `Astronomy_DeltaT_EspenakMeeus`, `Astronomy_DeltaT_JplHorizons`, `Astronomy_Search`, `Astronomy_CorrectLightTravel`, `Astronomy_AngleBetween`, `Astronomy_RotateVector`, `Astronomy_RotateState`, `Astronomy_Reset`
- #85: none directly. It provides the planet-level heliocentric functions on `Engine.Planet`; #89 composes them with the other bodies into the heliocentric position, state and distance functions it owns.
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
