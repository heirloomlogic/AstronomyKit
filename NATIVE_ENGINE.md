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

Combining, inverting and pivoting rotations, and the rotations between frames, are in `Orientation/` (see [Earth orientation](#earth-orientation)). Other vector arithmetic stays in the module that uses it until a second module needs it, and then moves here (see [Changing this contract](#changing-this-contract)).

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

## Compiled-in tables and the accepted range

In the tree: `EngineTables.swift` and `EngineChebyshev.swift`. `acceptedTTDays`, `unpackDoubles` and the planets' range check moved here from `Planets/` when the Moon became their second user, and the Moon's Chebyshev evaluator when Pluto became its second (#88).

```swift
extension Engine {
    static let acceptedTTDays: Double  // 1,461,000
    static func checkAcceptedTime(_ time: Engine.Time) throws
    static func unpackDoubles(count: Int, _ text: StaticString) -> [Double]
    struct ChebyshevTable {
        init(start: Double, recordDays: Double, recordCount: Int, degreeCount: Int, coefficients: [Double])
        func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?
    }
}
```

- `acceptedTTDays` is 4,000 Julian years, the C engine's `EPHEMERIS_MAX_TT_DAYS`. `checkAcceptedTime` throws `badTime` for a TT beyond it either way, or not finite; the planet and Moon functions call it first.
- `unpackDoubles` decodes a generated table: a base64 string literal of the doubles' little-endian bit patterns, skipping characters outside the base64 alphabet. It traps when the text does not hold exactly `count` doubles, which only a damaged generated file can cause.
- `ChebyshevTable` holds records in the layout of a JPL SPK type 2 segment: equal records from `start` in TDB days, coefficients record by record, then x, y and z, then by ascending degree. `evaluate(tdb:)` is the evaluator of the C engine's `ephemeris.c`: record `k` holds `start + k·recordDays ≤ tdb < start + (k + 1)·recordDays`, and Clenshaw's recurrence gives the value and its derivative per TDB day together. It returns `nil` before the first record, from the end on, and for a time that is not finite; as in C, the last doubles before the end can round up to it when the start is subtracted and fall outside. The initializer traps when the coefficients do not match the shape.

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

In the tree: `Orientation/EngineNutation.swift`, `Orientation/EngineEquationOfEquinoxes.swift`, `Orientation/EnginePrecession.swift`, `Orientation/EngineEarthRotation.swift`, `Orientation/EngineRotations.swift`, `Orientation/EngineFrameRotations.swift`, `Orientation/EngineCoordinates.swift`, `Orientation/EngineObserver.swift`, `Orientation/EngineAtmosphere.swift`, `Orientation/EngineRefraction.swift`, `Orientation/EngineHorizon.swift` and the generated `Orientation/Generated/IAU2000BTerms.swift` and `Orientation/Generated/EquinoxComplementaryTerms.swift`. Every C entry point listed for #86 under [C entry points by owner](#c-entry-points-by-owner) has a native counterpart here.

```swift
extension Engine.Nutation {
    struct Angles { var longitude, obliquity, longitudeRate, obliquityRate: Double }
    static func evaluate(centuries t: Double) -> Angles
    static let cache: Engine.BoundedCache<Engine.ExactKey, Angles>
    static func angles(tt: Double, cache: Engine.BoundedCache<Engine.ExactKey, Angles> = cache) -> Angles
    static func complementaryEquationOfEquinoxes(centuries t: Double) -> Double  // radians
}
extension Engine.EarthTilt {
    init(tt: Double, cache: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> = Engine.Nutation.cache)
    var tt: Double
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
- The Earth rotation angle is SOFA's `iauEra00`, in degrees from 0 up to 360. Mean sidereal time is `iauGmst06`: the angle at `time.ut` plus the IAU 2006 polynomial at `time.tt`. Apparent sidereal time adds the equation of the equinoxes, `iauEe00`: Δψ·cos εA plus the complementary terms of IAU 1994 Resolution C7 (IERS Conventions (2010), Table 5.2e; SOFA `iauEect00`). Both sidereal times are in hours from 0 up to 24; a value that rounds up to the period is returned as 0. A time or day count that is not finite gives NaN, and nutation for it is computed without touching the cache. The complementary terms are the 33 terms and the one multiplied by t that `Scripts/generate-nutation-table.py` writes from ERFA 2.0.1's `eect00.c`, pinned beside `nut00b.c`. The series reads the IERS 2003 fundamental arguments (`iauFal03`, `iauFalp03`, `iauFaf03`, `iauFad03`, `iauFaom03`, `iauFave03`, `iauFae03`, `iauFapa03`) and is summed smallest term first, as SOFA sums it. It reaches about 2.65 mas between 1950 and 2050. `Engine.EarthTilt` evaluates it when `equationOfEquinoxes` is read, not with the cached nutation, so the rotations that never read that property do not pay for it.

### Differences from published definitions

- The atmosphere keeps the 20 to 32 km layer up to 100 km (#175).

### Differences from the C engine

- The galactic rotation (#152), the atmosphere's constants (#153) and the observer inverse's non-convergence (#174), as described above.
- Apparent sidereal time includes the complementary terms of the equation of the equinoxes (#170); `Astronomy_SiderealTime` leaves them out. The two differ by up to about 2.65 mas of rotation angle between 1950 and 2050 (about 8 cm of position at the equator). Every native function that reads `Engine.EarthRotation.apparentSiderealTime` inherits the difference: the observer's position and state, of date and J2000 (`Engine.Observers.vectorOfDate`, `vector`, `stateOfDate`, `state`); the observer recovered from a vector, of date and J2000 (`observer(atVectorOfDate:)`, `observer(atVector:)`), where it shifts the longitude by the same angle; the horizon rotations from and to the equator of date, J2000 and the ecliptic (`Engine.FrameRotation.eqdToHor`, `eqjToHor`, `eclToHor` and their inverses); and `Engine.Horizontal(time:observer:rightAscension:declination:refraction:)`. The nutation matrix, the precession matrix and the ecliptic rotations do not read it.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Orientation/` check against SOFA through ERFA 2.0.1 (the commit `THIRD_PARTY_NOTICES` pins), not against C output:

- The values in ERFA's own test program, `t_erfa_c.c`: `t_nut00b`, `t_obl06`, `t_p06e`, `t_numat`, `t_era00` and `t_gmst06`, each within SOFA's tolerance or tighter; `t_bp06` within 1e-13, because SOFA builds that matrix from the Fukushima-Williams angles, which agree with equation 5.39 to 3e-14 there; and `t_gst06a` within the 1 mas that separates IAU 2000B from 2000A from 1995 to 2050; and `t_eect00` within 1e-20 and `t_ee00b` within 1e-12.
- pyerfa 2.0.1.5 at eight epochs from 1600 to 2500, with UT1 and TT apart: nutation to 1e-15 rad, mean obliquity and the precession angles to 1e-15 rad, the precession matrix against equation 5.39 built from the SOFA angles to 1e-15, the Earth rotation angle and mean sidereal time to 1e-12 rad, `eect00` to 1e-20 rad, and the eight fundamental arguments it reads to 5e-12 rad.
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
- Each table is a base64 string literal of the doubles' little-endian bit patterns, decoded once per planet on first use. Array literals do not scale: a 100,002-element `[Double]` literal took 390 s and 1.66 GB to compile in Debug, and the polynomial tables hold 1,431,768 doubles. The data is still compiled in; nothing is read from a file. `Engine.unpackDoubles` decodes them (see [Compiled-in tables and the accepted range](#compiled-in-tables-and-the-accepted-range)). Decoded, the polynomial tables take 11.5 MB and the VSOP87B terms 0.8 MB, kept for the life of the process.
- VSOP87B gives heliocentric ecliptic longitude and latitude in radians and radius in AU, referred to the dynamical ecliptic and equinox of J2000, as Poisson series in Julian millennia of TT. The tables keep the published term order. `coordinates` and `derivatives` port `VsopCoords` and `VsopDeriv`: every term in table order, with Neumaier compensation inside each power of t and, for the coordinates, across the powers; each longitude power's contribution is reduced modulo 2π. At the four t the tests use, the compensated coordinates equal an exactly rounded sum of the same terms bit for bit, and plain addition is off by 1.4e-12 to 2.2e-10 rad in Mercury's longitude. A t that is not finite gives NaN.
- `Engine.VSOP87Ecliptic` is the frame of VSOP87, declared in `Planets/` with its rotation to EQJ, since only this module uses it. It is not ECL: `toEquatorial`, the rotation to FK5 J2000 that `vsop87.doc` prints, tilts by an obliquity 0.003″ larger than IAU 2006's and adds rotations of up to 0.1″. The engine takes FK5 J2000 as EQJ, as the C engine does.
- The polynomials are AstronomyKit's degree-12 Chebyshev fits of the compensated VSOP87B position in the same frame, in segments of 8 days (Mercury, Earth), 16 (Saturn, Neptune) or 32 (the others), from `start` up to `stop`. 413 segments that did not meet the 1e-12 AU fit budget are excluded: 409 of Mercury's and 4 of Venus's.
- Segment `k` holds `start + k·width ≤ tt < start + (k + 1)·width`, as in `polynomial.h`: the index is `Int((tt − start) / width)`, moved back one where the subtraction rounded the double below a boundary up to the boundary's offset. Every width is a power of two, so the division is exact. Outside the span, including a TT that is not finite, and in an excluded segment, the functions return `nil` and the caller uses the full series. The static functions check the span before they decode a table.
- Clenshaw's recurrence gives the position and its derivative together; velocity is in AU per TT day. A state's position is the same double as the position.
- The `Engine.Planet` functions give the heliocentric position, state and distance in the VSOP87 frame or in EQJ. They throw `badTime` when |TT| is above `Engine.acceptedTTDays` or is not finite, before touching the cache, and when a result component is not finite. Inside the polynomial span and outside excluded segments they use the polynomials and never the series or the cache. Elsewhere the position is the series coordinates in rectangular form, the state adds the chain-rule velocity from the derivatives, scaled from per millennium to per day, and the distance is the series radius. The EQJ results are the VSOP87 ones rotated.
- `VSOP87B.cache` keeps, for each planet, 32 coordinate and 32 derivative results, keyed by the exact bits of t, in two `BoundedCache`s registered with `CacheRegistry.shared`. A position, a state and a distance at one instant share one evaluation of each series they need; the distance reads the coordinates entry. A t that is not finite bypasses it. The C engine keeps the radius separately so a distance alone sums only the radius series; here a distance alone sums all three coordinates.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Planets/`:

- VSOP87B terms as IMCCE prints them in `VSOP87B.mer`, `VSOP87B.ear` and `VSOP87B.nep`, the 135 series and 35,080 terms in all, and the term counts of Mercury's series. The comparison of every term is the generator's `--published` mode, which needs the IMCCE files and does not run in CI.
- The IMCCE check values in `vsop87.chk` (VSOP87B, every planet at ten dates from 1100 to 2000, SHA-256 in `PublishedVSOP87.swift`): the series coordinates and their rates within 1e-10, and the ecliptic position and velocity from the planet functions against the rectangular form of the published values, through the polynomials at J2000 and the series at the other nine dates. This pins the axis order and the frame. The rotation's entries equal `vsop87.doc`'s.
- The heliocentric distance from the polynomials alone against the JPL Horizons vectors in `Scripts/reference-data/sources/distance/heldout`, within the allowances `DistanceAccuracyTests` applies to the public distance: 1,067 of the 1,072 planet records. The other 5 fall in excluded segments.
- All 1,072 records through the planet functions, the 5 on the series path included: the distance within the same allowances, and the EQJ direction within 1′ of Horizons' ICRF vector, the accuracy `JPLValidationTests` applies. The largest angle is 2.4″, for Neptune.
- The `JPLValidationTests` geocentric suites for the Sun and Mercury to Neptune and the Asheville suites for Mercury to Neptune, at their tolerances (1′, and 1.5′ for Asheville Neptune): the astrometric J2000 direction, Horizons' definition, from `Engine.Positions.geocentricPosition` with no aberration, which backdates the planet functions through `Engine.LightTravel`, and the Asheville observer through `Engine.Observers`. The geocentric distances of the same bodies in `distance-fixtures.json` (1,072 records) within their allowances. The parallax at Asheville is at most about 13″ on these dates, too small for the 1′ check to see, so the shift between an Asheville row and the geocentric row on the same date is checked against the engine's within 0.2″; the rows are printed to 0.01 s and 0.1″. Mercury's 02-11 row has no geocentric row on that date, so it is skipped. The check fails with no observer or with a negated one; an observer misplaced by less than about a degree would still pass it.
- Cache work counts with private registries: no lookups inside the polynomial span; one evaluation per series shared by position, state and distance; reuse in an excluded segment; separate entries per planet; signed-zero keys; non-finite bypass; eviction of the oldest of 32; reset through a registry; a hit returning the caller's own time; simultaneous callers; and a cache with no capacity, which evaluates every time. Separately, the shared cache is checked to be registered with `CacheRegistry.shared`, which `Engine.resetCaches()` empties.
- Compensated summation against exact summation, and the accepted range's ends, NaN, infinities and an invalid time on every planet function.
- Clenshaw's recurrence against T_k(cos θ) = cos kθ and dT_k/dx = k·U_{k−1}(x) for every degree; every boundary of every planet and the double below it; every segment at its first, middle and last double, excluded or not; velocity against five-point differences of the position; and adjacent segments, which meet within 2e-12 AU (2.0e-13 at most).

### Planet tests that depend on the C engine

| Test | Disposition |
|---|---|
| `PolynomialTests` | Kept while the C engine ships: it checks through the C heliocentric functions that position and state agree at the coverage boundaries. `EnginePlanetPolynomialTests` checks the Swift polynomials at every segment boundary and that a state's position is the position. Retired when #96 removes the C engine. |
| `VsopCacheTests` | Kept while the C engine ships: it checks the C thread-local cache (local patch 8): caller time metadata, signed zeros, replay, eviction and threads. `EngineVSOP87BCacheTests` checks the same properties of `VSOP87B.cache` by work counts. Retired when #96 removes the C engine. |
| `Scripts/performance/test-vsop-cache.sh` and `vsop_cache_probe.c` | Kept while the C engine ships, for the same reason, and retired with it. `EngineVSOP87BCacheTests` has the Swift negative control, a cache with no capacity. |
| `ReproducibilityTests` planetary cases | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): they pin public results, not published values. The planet series parts they reach are checked against IMCCE and Horizons here. Retired by #96. |
| `DistanceAccuracyTests` and the `JPLValidationTests` planet suites | Published-value checks of the public API, which runs on the C engine until #96. `EnginePlanetPositionsTests` and `EnginePlanetHorizonsTests` apply the same fixtures and allowances to the Swift planet functions. `EnginePlanetHorizonsTests` reads the geocentric vector from `Engine.Positions.geocentricPosition` (see [Positions](#positions)). |

## Moon

In the tree: `Moon/EngineMoon.swift`, `Moon/EngineMoonStates.swift`, `Moon/EngineLibration.swift`, `Moon/EngineMoonEphemeris.swift`, `Moon/EngineLunarSeries.swift`, `Moon/EngineTDB.swift`, `Moon/EngineFrameBias.swift` and the generated `Moon/Generated/MoonDE440Coefficients.swift` and `Moon/Generated/TDBTerms.swift`. Every C entry point listed for #87 under [C entry points by owner](#c-entry-points-by-owner) has a native counterpart here: `Astronomy_GeoMoon`, `Astronomy_EclipticGeoMoon`, `Astronomy_GeoMoonState`, `Astronomy_GeoEmbState`, `Astronomy_MoonEclipticState` and `Astronomy_Libration`.

```swift
extension Engine {
    enum ECM: Frame {}    // mean ecliptic and equinox of date
    enum ICRS: Frame {}
    struct EclipticState { var state: State<ECT>; var longitude, latitude, distance, longitudeRate, latitudeRate, distanceRate: Double }   // in Foundation/, with tilted(by:) and tiltRate(by:rate:)
    struct Libration { var latitude, longitude, moonLatitude, moonLongitude, distanceKilometers, diameter: Double }
    static func normalizedLongitude(_ longitude: Double) -> Double    // [0, 360), the C engine's NormalizeLongitude
    static func longitudeOffset(_ difference: Double) -> Double       // (−180, 180], the C engine's LongitudeOffset
}
extension Engine.Moon {
    typealias Cache = Engine.BoundedCache<Engine.ExactKey, SIMD3<Double>>
    static let cache: Cache
    static func coordinates(centuries t: Double, cache: Cache = cache) -> SIMD3<Double>   // longitude, latitude (radians, ECM), distance (AU)
    static func evaluate(centuries t: Double) -> SIMD3<Double>      // the same, without the cache
    static func meanEclipticPosition(tt: Double) -> SIMD3<Double>?  // DE440 alone, ECM
    static func meanEclipticSourceState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?
    static func meanEclipticState(at time: Engine.Time, cache: Cache = cache) -> (state: Engine.State<Engine.ECM>, distance: Double, distanceRate: Double)
    static func rectangular(_ sphere: SIMD3<Double>) -> SIMD3<Double>
    static func eclipticAngles(_ vector: Engine.Vector<Engine.ECT>) -> (longitude: Double, latitude: Double)   // degrees, longitude in [0, 360)
    static func meanEquatorToEcliptic(tt: Double) -> Engine.Rotation<Engine.EQM, Engine.ECM>
    static func geocentricPosition(at time: Engine.Time, cache: Cache = cache) throws -> Engine.Vector<Engine.EQJ>
    static func eclipticPosition(at time: Engine.Time, cache: Cache = cache) throws -> Engine.Spherical       // ECT, degrees, AU
    static func geocentricState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ>
    static func barycenterState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ>
    static func eclipticState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.EclipticState
    static let stateStepDays: Double      // 5e-4
    static let earthMoonMassRatio: Double // 81.30056
    static func libration(at time: Engine.Time, cache: Cache = cache) -> Engine.Libration
    static func eclipticLongitude(at time: Engine.Time, cache: Cache = cache) throws -> Double   // degrees, true ecliptic of date
    static func distance(at time: Engine.Time, cache: Cache = cache) throws -> Double            // AU
    static let meanRadiusKilometers: Double   // 1,737.4
    static let equatorInclination: Double     // 1°32′32.7″
}
extension Engine.MoonEphemeris {
    static let start, recordDays: Double              // −36,560.5 TDB days, 4
    static let recordCount, degreeCount: Int          // 21,111, 13
    static let coefficients: [Double]
    static let fullWeightStart, fullWeightEnd, blendDays: Double   // −36,524.5, 47,846.5, 32
    static func weight(tt: Double) -> (weight: Double, rate: Double)
    static func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?   // ICRS, per TDB day
    static func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?       // EQJ, per TT day
    static func position(tt: Double) -> SIMD3<Double>?                                          // EQJ
}
extension Engine.LunarSeries {
    static func coordinates(centuries t: Double) -> SIMD3<Double>
}
extension Engine.TDB {
    static func offsetSeconds(tt: Double) -> Double
    static func rate(tt: Double) -> Double
    static func offsetSeconds(date1: Double, date2: Double, ut: Double, longitude: Double, u: Double, v: Double) -> Double
}
extension Engine.FrameBias {
    static func fukushimaWilliams(gamma: Double, phi: Double, psi: Double, epsilon: Double) -> [[Double]]
    static let icrsToEqj: Engine.Rotation<Engine.ICRS, Engine.EQJ>
}
extension Engine.Rotation {
    func apply(to vector: SIMD3<Double>) -> SIMD3<Double>   // as apply(to: Vector), for values with no time
}
extension Engine.RotationRate {
    func apply(to vector: SIMD3<Double>) -> SIMD3<Double>
    var inverse: Engine.RotationRate<To, From> { get }        // the transpose
}
```

- The lunar model is the C engine's `CalcMoon` with local patch 19. From 1900-01-01 00:00 TT (`fullWeightStart`) up to 2131-01-01 00:00 TT (`fullWeightEnd`) it is the Moon of JPL DE440. Beyond the 32 days outside each end it is the lunar series. Inside those 32 days the two positions are blended with the quintic smoothstep x³(10 − 15x + 6x²), so the weight and its first two derivatives are continuous. `evaluate(centuries:)` reads DE440 at TT = t · 36,525, as `CalcMoon` does, and returns the series alone where the weight is 0 or the records do not reach. `coordinates(centuries:cache:)` is `evaluate(centuries:)` read through `cache`, and every position and state reads it.
- `MoonDE440Coefficients.swift` holds DE440's Chebyshev records for the Moon minus those for Earth, both relative to the Earth-Moon barycenter, divided by the au: 21,111 four-day records of 13 coefficients per axis on ICRS axes, from 1899-11-26 to 2131-02-07 TDB. `Scripts/generate-moon-tables.py` writes it from the C engine's `moon_data.inc`, whose SHA-256 `Scripts/moon-data/manifest.json` pins, and `--check` runs in CI on macOS and Linux. `--published DIR` reads `de440s.bsp` as NAIF publishes it (URL and SHA-256 in the manifest) and checks all 823,329 coefficients against the DE440 records bit for bit. The table uses the encoding of [Compiled-in tables and the accepted range](#compiled-in-tables-and-the-accepted-range); decoded, it takes 6.6 MB for the life of the process.
- `evaluate(tdb:)` reads the records through `table`, an `Engine.ChebyshevTable` (see [Compiled-in tables and the accepted range](#compiled-in-tables-and-the-accepted-range)): record `k` holds `start + 4k ≤ tdb < start + 4(k + 1)`.
- `state(tt:)` reads the records at TDB = TT + `Engine.TDB.offsetSeconds(tt:)`, scales the velocity by `Engine.TDB.rate(tt:)`, and rotates both by `Engine.FrameBias.icrsToEqj`. `position(tt:)` is its position without the rate, which is all `evaluate(centuries:)` reads.
- `Engine.TDB` is SOFA's `iauDtdb`: Fairhead and Bretagnon's 787 terms, JPL's planetary mass adjustments and the topocentric terms. `TDBTerms.swift` is generated by the same script from ERFA 2.0.1's `dtdb.c`, which the C engine already vendors and the manifest pins with its URL; that file equals ERFA's at the commit `THIRD_PARTY_NOTICES` pins. The Moon reads the geocentric offset at TT, as the C engine does. The rate is one plus the offset's change across ±0.01 day, the C engine's step.
- `Engine.FrameBias.icrsToEqj` is SOFA's `iauPmat06` at J2000: `iauFw2m` at the Fukushima-Williams angles of `iauPfw06` and `iauObl06` for t = 0, where precession is the identity. It is about 23 mas.
- `Engine.LunarSeries` is the C engine's `CalcMoonRaw`: Montenbruck and Pfleger's series from the Improved Lunar Ephemeris of 1954, with the same 104 solar terms, the series N, and the long-period and planetary terms, in the same order. The distance comes from the parallax and Earth's equatorial radius, 6,378.1366 km, converted with the published au.
- DE440 positions reach the mean ecliptic of date as in the C engine: precession to the mean equator of date, then the mean obliquity. `geocentricPosition(at:)` takes the model's coordinates back through the mean obliquity and the inverse precession. `eclipticPosition(at:)` takes them through the mean obliquity, nutation and the true obliquity, and reports the model's distance. Both throw `badTime` for a TT beyond `Engine.acceptedTTDays` or not finite, and for a result that is not finite. The ecliptic longitude is in [0, 360) and 0 where the vector has no component in the ecliptic plane.
- Pluto (#88) also reads `TDB`, `FrameBias` and `weight(tt:)`. They stay in `Moon/`, beside the TDB terms the Moon's generator writes; the Chebyshev evaluator moved to `Foundation/`. `EclipticState`, with an initializer that works out the longitude and latitude rates from the state, and `Engine.tilted(by:)` and `Engine.tiltRate(by:rate:)` moved to `Foundation/EngineEclipticState.swift` when #89's ecliptic states became their second user. `tilted(by:)` repeats the arithmetic of `Engine.FrameRotation`'s private ecliptic rotation, which belongs to the closed #86. `eclipticAngles(_:)`, which repeats `Engine.Ecliptic`'s, and the SIMD and rotation-rate helpers are used only by the Moon; when another module needs them, they move to `Foundation/` (see [Changing this contract](#changing-this-contract)). The evaluator is not the planet polynomials' Clenshaw recurrence: each keeps its C original's order of operations, so the two are not interchangeable bit for bit.
- `Engine.Moon.cache` is the lunar cache of local patch 14: 32 entries of longitude, latitude and distance, keyed by the exact bits of the Julian centuries `coordinates(centuries:cache:)` reads, registered with `CacheRegistry.shared`. `0.0` and `-0.0` are different keys, and centuries that are not finite bypass it. It holds only model values, so a hit returns the caller's own time.
- `meanEclipticState(at:cache:)` is the C engine's `MoonEcmState`, with its sample offsets. The position is the cached coordinates at `time`. Where DE440 has weight, the velocity is DE440's analytic derivative carried through precession and the mean obliquity and their rates, at TT = (`time.tt` / 36,525) · 36,525. In a blend it is mixed with a central difference of the series over ±`stateStepDays`, 5e-4 day, plus the weight's rate times the difference of the two positions; those three series samples bypass the cache, as `CalcMoonRaw` does in C. Elsewhere velocity and distance rate are central differences of the cached model at `(time.tt ± 5e-4) / 36,525`, so a repeated state reads three cached epochs.
- `geocentricState(at:cache:)` is `Astronomy_GeoMoonState`: that state through the mean obliquity and precession with their rates. Its position is the same double for double as `geocentricPosition(at:cache:)`. `barycenterState(at:cache:)` is `Astronomy_GeoEmbState`, the Moon's state divided by 1 + 81.30056, the C engine's Earth/Moon mass ratio. `eclipticState(at:cache:)` is `Astronomy_MoonEclipticState`: through the mean obliquity, nutation and the true obliquity with their rates; its longitude, latitude and distance are `eclipticPosition(at:cache:)`'s, the distance and its rate are the model's, and it throws `badVector` when the position has no component in the ecliptic plane. All three throw `badTime` as the positions do, including for a rate that is not finite.
- `libration(at:cache:)` is `Astronomy_Libration`: Meeus, Astronomical Algorithms, chapter 53, the optical libration from the model's mean ecliptic coordinates at `time.tt` / 36,525 centuries and the physical libration from the series ρ, σ and τ, with the C engine's sums in its order and its `NormalizeLongitude` and `LongitudeOffset` reductions (`Engine.normalizedLongitude(_:)`, `Engine.longitudeOffset(_:)`, declared in `Moon/` for the phase and search code of #92 to share). The longitude is in (−180, 180]. The Moon's latitude and longitude are on the mean ecliptic of date, in degrees. The distance is the model's in km with the published au, and the diameter is 2·atan(R / √(d² − R²)) with R = 1,737.4 km. Like the C function it does not check the time: a time that is not finite gives NaN in every field.
- The Moon's inputs to the phase and event searches of #92: `eclipticLongitude(at:cache:)` is the Moon's side of `Astronomy_MoonPhase`, the true-ecliptic longitude of `geocentricPosition(at:cache:)`, from which the search subtracts the Sun's; `distance(at:cache:)` is the C engine's `MoonDistance`, with the accepted-range check that `moon_distance_slope` applies; the node search reads the latitude of `eclipticPosition(at:cache:)`.
- `moon_data.inc` and `dtdb.c` stay where the C engine reads them; when #96 removes the C target, it moves them to `Scripts/moon-data` and updates the manifest.

### Differences from published values

- Outside 1900 to 2130 the Moon comes from the series, which is up to 52′ from DE441 within the accepted range. Of the Horizons samples below, those from 1499 to 2500 are within 1′, and those up to 999 and from 3000 on are not (#184). The C engine uses the same series, and the epic keeps it.
- Libration latitude is about 1.40′ above NASA SVS's on average, from Meeus's formulas, and at most 1.6692′ from it, at 2020-01-12 08:00 UT.

### Differences from the C engine

- The series' distance converts Earth's radius with the published au, not the C engine's `KM_PER_AU`; the two differ by 6.0e-11 of the distance, about 2e-5 km (see [Constants](#constants)).
- An ecliptic longitude that rounds up to 360 when moved into range is 0; `Astronomy_EclipticGeoMoon` can return 360.
- The libration distance converts the model's distance with the published au, a difference of 6.0e-11 of it.
- `equatorInclination` is the 1°32′32.7″ Meeus prints for I in the chapter 53 model, not the C engine's 1.543°, for which Astronomy Engine cites no source. The libration latitude moves by up to 0.035′, the difference between the two.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Moon/`:

- The table against DE440 coefficient for coefficient, through the generator's `--published` mode, which needs `de440s.bsp` and does not run in CI. The tests check the table's shape and dates, and that its records reach past both blends with TDB − TT at its largest.
- ERFA's `t_dtdb` within its 1e-15 s, and pyerfa 2.0.1.5's geocentric `dtdb` at eleven dates from −4,000 to +4,000 years within 1e-14 s; the rate against a five-point difference of the offset.
- ERFA's `t_fw2m`, pyerfa's `pmat06` at J2000 within 1e-16, and the IERS Conventions (2010) frame bias offsets ξ0, η0 and dα0 to their printed precision.
- Clenshaw's recurrence against the Chebyshev sums and their derivatives; every record boundary, where adjacent records meet within 1e-12 AU and 1e-12 AU per day; the ends and the inputs that are not finite; velocity against five-point differences.
- The weight: 1 and 0 where it should be, monotonic across each blend, its rate against differences, and its value and rate near each blend end.
- The `JPLValidationTests` geocentric and Asheville Moon suites within their 1′, as astrometric directions through `Engine.LightTravel` and, for Asheville, `Engine.Observers`; the 134 Moon records of `distance-fixtures.json` within their 28.689 km; and the Horizons observer rows of 1900, 2000 and 2100 in `reference-fixtures.json` within 1′, in J2000 equatorial and true ecliptic of date coordinates.
- Horizons geometric vectors at 30 dates from 2002 BCE to 6000 CE (`Scripts/reference-data/sources/horizons/moon-vector.json`), eleven of them within 40 days of the two blends: the 17 from 1499 to 2500 within 1′ and 28.689 km, the other 13 recorded as known issues of #184. Inside the DE440 span the samples measure within 15 m of Horizons, which uses DE441; the tests do not assert that.
- Every Horizons state in Astronomy Engine's `barystate/GeoMoon.txt` and `GeoEMB.txt` at the pinned revision, 3,196 each every 8 days from 1970 to 2040, within the relative limits its `ctest.c` applies to them: Moon position 4.086e-5 and velocity 5.347e-5, barycenter 4.076e-5 and 5.335e-5. `build-fixtures.py` copies them into `reference-fixtures.json`.
- Rates against five-point differences of the same positions on 1/64-day stencils at thirteen instants in the series, both blends and DE440: the EQJ velocity within (1 + |t|) · 1e-8 of the speed, t in Julian centuries from J2000, and the ecliptic longitude, latitude and distance rates within the same fraction of the Moon's largest motion, 15° and 6e-4 AU per day. That covers the series' central difference and the rounding of its arguments, which grow with t.
- The state's position against the position, the barycenter against the Moon scaled, and the ecliptic state against the ecliptic position, all double for double.
- Cache work counts with a private registry: three epochs for the first state in the series and three hits for the next, one epoch where DE440 has weight with the blend's series samples uncached, positions sharing the states' entries, a cache with no capacity that evaluates every time, signed-zero keys, non-finite bypass, eviction of the oldest of 32, a registry reset, a hit returning the caller's own time, and simultaneous callers.
- Libration against all 26,305 hourly rows of NASA's Scientific Visualization Studio Moon Phase and Libration tables for 2020, 2021 and 2022 (`Scripts/reference-data/sources/mooninfo_2020.txt` to `mooninfo_2022.txt`, as Astronomy Engine pins them), within the limits of its harness of 0.1304′ in longitude, 54.377 km in distance and 0.00009° in diameter, and within 1.67′ in latitude. The harness's 1.6476′ was set for upstream's lunar series; with the DE440 Moon the C engine's 1.543° already reaches 1.6507′. 1.67′ is the largest difference on the three tables, 1.6692′, rounded up: a measured bound, not a published accuracy.
- The phase input: at USNO's twelve quarter times in `reference-fixtures.json`, the Moon's longitude less the Sun's is within 1′ of the quarter, the limit Astronomy Engine's harness sets for those times. The Sun's longitude comes from `Engine.Planet.earth` as the C engine finds it, at the heliocentric origin with no aberration.
- The apsis input: the model's distance at the six published lunar apsides within their 25 km. The node input: the ecliptic latitude at Espenak's six node times within the latitude's rate times the 220.86 s time limit, and its direction matching the node's.
- Routing between DE440, the blend and the series; no jump at the blends' ends; longitudes across the wrap; the ecliptic position against the J2000 position seen on the true ecliptic of date; the accepted range's ends and the doubles beyond; and NaN and infinite times.

### Moon tests that depend on the C engine

| Test | Disposition |
|---|---|
| `MoonCacheTests` | Kept while the C engine ships: it checks the C thread-local lunar cache (local patch 14) through the public API: replayed bits, shared clients, non-finite propagation and threads. `EngineMoonCacheTests` holds the engine's work counts for the same properties. Retired when #96 removes the C engine. |
| `Scripts/performance/test-moon-cache.sh`, `moon_cache_probe.c` and `moon_output_probe.c` | Kept while the C engine ships, for the same reason, and retired with it. `EngineMoonCacheTests` has the Swift negative control, a cache with no capacity. |
| `BundledEphemerisTests` | Kept while the C engine ships: it checks the C evaluator, the blend and Pluto's bundled data through the C entry points, and pins legacy Moon and Pluto values. `EngineMoonEphemerisTests` and `EngineMoonTests` check the Swift evaluator, blend and routing, and `EngineMoonStatesTests` the velocities across the blends. Its Horizons check of the public apsis and node searches calls the C entry points, so #96 must move it; #92 ports the searches and does not track that check. Its Pluto cases are recorded under [Pluto](#pluto-the-gravity-simulation-and-chiron). Retired when #96 removes the C engine. |
| `ReproducibilityTests` Moon cases | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): they pin public results, not published values. The lunar model they reach is checked against DE440, Horizons and NASA here. Retired by #96. |
| `EclipticStateTests` | Kept while the C engine ships: it imports `CLibAstronomy` and calls the C ecliptic-state and rotation entry points directly, and #96 lists it for a disposition. `EngineMoonStatesTests` checks the Swift Moon's ecliptic state. Retired, or moved onto the engine, by #96. |
| `MoonTests`, `LibrationTests` and the Moon suites of `JPLValidationTests`, `DistanceAccuracyTests` and `AuditValidationTests` | Public-API checks, run on the C engine until #96. `EngineMoonHorizonsTests`, `EngineMoonStatesTests` and `EngineLibrationTests` apply the published ones, at the same tolerances, to the Swift functions. `LibrationTests` and the illumination checks in `MoonTests` are named sanity checks. |

## Pluto, the gravity simulation and Chiron

In the tree: `Gravity/EngineGravity.swift`, `Gravity/EngineGravitySimulation.swift`, `Gravity/EngineChiron.swift`, `Gravity/EnginePluto.swift`, `Gravity/EnginePlutoEphemeris.swift` and the generated `Gravity/Generated/PlutoBarycenterCoefficients.swift`, `PlutoSunCoefficients.swift`, `PlutoCenterCoefficients.swift` and `PlutoStateTable.swift`. They port the C engine's `CalcPluto`, the integrator step it shares with the gravity simulation, and the simulation (`Astronomy_GravSimInit`, `Astronomy_GravSimUpdate`, `Astronomy_GravSimSwap`, `Astronomy_GravSimBodyState`, `Astronomy_GravSimTime`, `Astronomy_GravSimNumBodies` and `Astronomy_GravSimFree`). `EngineChiron.swift` gives Chiron's heliocentric state from the simulation; #89 composes the apparent positions the public `Chiron` API reports.

```swift
extension Engine.Gravity {
    static let sunGM, mercuryGM, venusGM, earthGM, marsGM, jupiterGM, saturnGM, uranusGM, neptuneGM: Double   // AU³/day², DE405
    static let seriesCache: Engine.VSOP87B.Cache   // no capacity
    struct BodyState { var position, velocity: SIMD3<Double> }
    struct MajorBodies {               // sun, jupiter, saturn, uranus, neptune, barycentric
        init(tt: Double) throws
        func acceleration(at position: SIMD3<Double>) -> SIMD3<Double>
    }
    struct SolarSystem {               // sun and planets[Engine.Planet.rawValue], barycentric
        static let planetGM: [Double]  // Earth's includes the Moon's
        init(tt: Double) throws
        func state(of body: CelestialBody) -> BodyState?
        func acceleration(at position: SIMD3<Double>) -> SIMD3<Double>
    }
    static func pull(of gm: Double, at body: SIMD3<Double>, on position: SIMD3<Double>) -> SIMD3<Double>
    struct Step { var tt: Double; var position, velocity, acceleration: SIMD3<Double> }
    static func start(heliocentric position: SIMD3<Double>, velocity: SIMD3<Double>, tt: Double) throws -> (step: Step, bodies: MajorBodies)
    static func start(_ state: Engine.Pluto.TableState) throws -> (step: Step, bodies: MajorBodies)
    static func advance(_ step: Step, to tt: Double) throws -> (step: Step, bodies: MajorBodies)
    static func advance(_ step: Step, to tt: Double, bodies: MajorBodies) -> Step
    static func advance(_ step: Step, to tt: Double, acceleration: (SIMD3<Double>) -> SIMD3<Double>) -> Step
}
extension Engine {
    final class GravitySimulation {
        init(origin: CelestialBody, time: Engine.Time, states: [Engine.State<Engine.EQJ>]) throws
        let origin: CelestialBody
        let bodyCount: Int
        var time: Engine.Time { get }
        func update(to time: Engine.Time) throws -> [Engine.State<Engine.EQJ>]
        func state(of body: CelestialBody) throws -> Engine.State<Engine.EQJ>
        func swap()
    }
}
extension Engine.Chiron {
    struct Anchor { let tt: Double; let position, velocity: SIMD3<Double> }   // EQJ, heliocentric
    static let anchors: [Anchor]          // 2000, 2010, 2020, 2030, 2040
    static let stepDays: Double           // 0.5
    static let earliestUT, latestTT: Double
    static func checkSupported(_ time: Engine.Time) throws
    static func nearestAnchor(tt: Double) -> Int
    static func heliocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ>
    final class ReusableSimulation {
        func heliocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ>
    }
}
extension Engine.PlutoEphemeris {
    static let barycenter, barycenterFromSun, center: Engine.ChebyshevTable
    static func heliocentricState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)?
}
extension Engine.Pluto {
    typealias Cache = Engine.BoundedCache<Int, Segment>
    static let cache: Cache
    static let stateTable: [TableState]           // 51 states, TT −730,000 to +730,000
    static func heliocentricState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ>
    static func barycentricState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ>
    static func heliocentricPosition(at time: Engine.Time, cache: Cache = cache) throws -> Engine.Vector<Engine.EQJ>
    static func modelState(tt: Double, heliocentric: Bool, cache: Cache = cache) throws -> (position: SIMD3<Double>, velocity: SIMD3<Double>)
}
```

- `Engine.Gravity` is the C engine's integrator for a body of negligible mass. `MajorBodies(tt:)` is `MajorBodyBary`: Jupiter to Neptune from `Engine.Planet.heliocentricState`, the barycenter offset from the Sun by Σ GM/(GM + GM☉) times each planet's position and velocity, summed from Jupiter to Neptune, and the Sun at minus that offset. `acceleration(at:)` is `SmallBodyAcceleration`: GM·d/|d|³ from the Sun to Neptune. `start` is `GravFromState`, and `advance` is `GravSim`, given the major bodies at the new time or finding them: a trial position under the old acceleration, then the position and velocity under the mean of the old acceleration and the one at the trial position. A step's error is third order in its length. The GM values are DE405's (Standish 1998, JPL IOM 312.F-98-048): the Sun's is k² with the Gaussian constant, and each planet's is the Sun's over DE405's mass ratio. They stay in `Gravity/` until a second module needs them. Both `MajorBodies` and `SolarSystem` read the planets through `seriesCache`, which stores nothing: a step's planets are at a new TT almost every time, and storing them would only push other callers' entries out of the shared VSOP87B cache. The C engine reads them through its thread-local cache.
- `SolarSystem(tt:)` is `CalcSolarSystem`: the same construction with all eight planets, Mercury first, and Earth pulling with Earth's GM plus the Moon's, Earth's over `Engine.Moon.earthMoonMassRatio`. Its `acceleration(at:)` is `CalcBodyAccelerations`, from the Sun outward. `state(of:)` gives the Sun, a planet, or zero for the barycenter, and `nil` for any other body.
- `Engine.GravitySimulation` holds two moments, current and previous, each a time, a `SolarSystem` and the small bodies' `Step`s. The initializer checks, in the C engine's order: an origin outside Mercury through the barycenter in `CelestialBody`'s numbering (`invalidBody`), the time against `Engine.acceptedTTDays` (`badTime`), each state's TT against the time's, compared exactly (`inconsistentTimes`), and then whether the solar system models the origin: Pluto, the Moon and the Earth-Moon barycenter pass the first check and throw `invalidBody` here. States are moved from the origin to the barycenter, and both moments start equal. `update(to:)` checks the time first, as the C engine does, and stores nothing until the new moment is complete, so a rejected update changes nothing. At the current TT it integrates nothing: the previous moment becomes a copy of the current one, which keeps its own time, as `GravSimDuplicate` does. Otherwise the current moment becomes the previous one and each body takes one `advance` step under the new `SolarSystem`. It returns the bodies relative to the origin, with the caller's time. `state(of:)` gives the Sun or a planet relative to the origin at the current moment's time, and throws `invalidBody` for anything else, the barycenter included, as `Astronomy_GravSimBodyState` does. `swap()` exchanges the moments. The object owns its storage; there is no free call. Like the C engine, an update that produces a non-finite state does not throw.
- One `NSLock` guards the moments. An update reads them under the lock, computes outside it, and stores its result only if no swap or other update came in between; otherwise it starts again from the newer moments. So concurrent calls take effect one at a time, no lock is held while the planets are computed, and an update that throws stores nothing. In a one-off comparison during development, with a harness that was not committed, 302 updates of two bodies (including a swap and a repeated time) from four origins gave the C simulation's results bit for bit; no test checks this.
- `Engine.PlutoEphemeris` holds three tables of `plu060.bsp` as NAIF publishes it (3 April 2024), each in km converted to AU on ICRS axes: the Pluto system barycenter from the solar system barycenter (DE440, 32-day records of 6 coefficients), the solar system barycenter from the Sun (DE440's Sun negated, 16 days, 11 coefficients), and Pluto's center from the Pluto system barycenter (PLU060, 3 days, 16 coefficients). `heliocentricState(tt:)` is `Astronomy_BundledPluto`'s sum: each table read at TDB = TT + `Engine.TDB.offsetSeconds(tt:)`, its velocity scaled by `Engine.TDB.rate(tt:)`, each rotated by `Engine.FrameBias.icrsToEqj`, and the three added in that order. It returns `nil` where a table has no record or for a TT that is not finite. The records start between 1899-11-02 and 1899-11-22 TDB and end between 2131-02-12 and 2131-02-19, past both blends.
- `Scripts/generate-pluto-tables.py` writes the tables from `pluto_barycenter.inc`, `pluto_negative_sun.inc` and `pluto_center_offset.inc`, whose SHA-256 hashes `Scripts/pluto-data/manifest.json` pins, and `PlutoStateTable.swift` from the `PlutoStateTable` block of `astronomy.c`, whose own SHA-256 the manifest pins so local patches elsewhere in the file do not touch it. `--check` runs in CI on macOS and Linux. `--published DIR` reads `plu060.bsp` (URL and SHA-256 in the manifest), joins PLU060's two segments for Pluto's center at 2013, and checks all 1,572,975 coefficients bit for bit; it also checks the state table against Astronomy Engine's `astronomy.c` at revision 826e26ff. Decoded, the tables take 12.6 MB for the life of the process. The `.inc` files stay where the C engine reads them until #96 moves them to `Scripts/pluto-data`.
- `Engine.Pluto` is `CalcPluto`. Where `Engine.MoonEphemeris.weight(tt:)` is 1, from 1900-01-01 00:00 TT to 2131-01-01 00:00 TT, the heliocentric state is `PlutoEphemeris`'s, bit for bit; the barycentric one adds the Sun's barycentric state from `MajorBodies`. Where the weight is 0, it is the integrated model's. In the 32-day blends the position is model + w·(DE440 − model) and the velocity is model + w·(DE440 − model) + w′·(DE440 position − model position), the C engine's arithmetic.
- The integrated model is Astronomy Engine's: 51 heliocentric EQJ states every 29,200 days from TT −730,000 to +730,000 (0001 to 3998), which #119 traced to TOP2013. `modelState` is `CalcPlutoLegacy` with the exact velocity. Segment `k` runs from state `k` to state `k + 1` in 200 steps of 146 days: integrated forward from the first, backward from the last, and mixed so step `i` takes `i`/200 of the backward result, in position, velocity and acceleration. The backward pass reuses the major bodies the forward pass found at the same times. At a time inside the table, the two steps either side are carried to it under the mean of their accelerations and mixed by the fraction of the step elapsed; the velocity is the same mix plus the mix's rate, so it is the derivative of the position within a step. Across a step seam the velocity moves by about 6e-12 AU per day. Indices are `floor` held to the valid range, as `ClampIndex` holds them. A tabulated state's position comes back exactly at its time.
- Beyond the table, up to 36,525 days (`crawlLimitDays`) before the first state or after the last, `crawl` integrates from that state to the time in steps of 146 days, the last one shortened to land on it, without the cache: `CalcPlutoOneWay`, at most 251 steps. Further out, and for a TT that is not finite, the functions throw `badTime`, as the C engine's crawl guard does. They also throw `badTime` for a result that is not finite. Pluto's range is narrower than `Engine.acceptedTTDays`, so the functions do not check that.
- `Engine.Pluto.cache` holds the 50 segments, keyed by index and registered with `CacheRegistry.shared`. A segment is a pure function of its index, so a reset at any moment leaves results unchanged. Unlike the C engine, which integrates a segment while holding its mutex, the `BoundedCache` integrates outside its lock, so two threads that miss the same segment both integrate it and the first result stays. A segment outside 1900 to 2100, where the planets come from their full series, took about 5 s in a Debug build on the development machine; segments 24 and 25 (1920 to 2080) take a fraction of a second, so the cache tests use them.

- `Engine.Chiron` starts from the nearest of five JPL Horizons states of 2060 Chiron, 00:00 TDB on 1 January 2000, 2010, 2020, 2030 and 2040 (target 2060, center 500@10, ICRF, geometric), the values the public `Chiron` API uses. Horizons' current solution, recorded in `Scripts/reference-data/sources/horizons/chiron-anchor-vector.json`, moves them by 0.6 to 4.1 km. Each anchor is placed at its TT (TDB less `Engine.TDB.offsetSeconds(tt:)`) and rotated from ICRF to EQJ by `Engine.FrameBias.icrsToEqj`. The nearest anchor is the one closest in TT, the earlier one on an exact tie. The span is checked on TT alone, since the state depends on nothing else: from 1900-01-01 00:00 UT, as TT with the time's Delta T model, through 2150-01-01 00:00 UTC, which is TT 54,786.5 days plus 69.184 s. The time's UT is not checked, so a pair rebuilt from recorded scales that disagree with its model is judged by its TT. Espenak-Meeus Delta T drops from −2.7016 s to −2.79 s at 1900.0, where its 1860–1900 and 1900–1920 polynomials meet, and both models use those pieces there; so a UT up to 88.4 ms before 1900-01-01 00:00 has a TT after the start's and is accepted. Outside the span, or for an invalid time, the functions throw `badTime` before any stepping. `ReusableSimulation` keeps one `GravitySimulation` across calls, as the public class of the same name does: it steps on from the last time when the anchor is the same and the path since the anchor, plus this step, stays within max(2 × the distance from the anchor to the time, 365 days); otherwise it starts again at the anchor. The path counts the days the simulation actually moved. Steps are equal parts of the interval, at most 0.5 TT day each, every intermediate time the part's TT with the caller's Delta T model. One is meant for one calculation on one thread, such as the iterations of a light-time correction; `heliocentricState(at:)` uses a fresh one.

### Differences from published values

- The integrated model is up to 5.1′ from DE441 at the ends of its table, and 2.2′ to 2.9′ at the ends of the extrapolation (#190). From 1840 to 2159 it is within 17″. The C engine computes the same positions; the epic keeps the model.
- Chiron drifts from Horizons with distance from its anchors: within 1,200 km and 0.09″ at the midpoints between them, 32″ (254,000 km) a century back in 1900, 15″ (102,000 km) in 2100 and 3.1″ (22,000 km) in 2150, heliocentric.

### Differences from the C engine

- Chiron's anchors sit at 00:00 TDB, the time Horizons gives for them, and are rotated from ICRF to EQJ. The public `Chiron` API places them at 00:00 UTC, 64 to 69 s later, and uses the ICRF values as EQJ, a 23 mas rotation. Together they move Chiron by under 0.2″: Chiron covers at most about 0.14″ of arc around the Sun in 69 s, at perihelion. The engine picks the anchor nearest in TT, between anchors at 00:00 TT; the public API picks the one nearest in UT, between anchors at 00:00 UTC. Both switch at the same calendar midpoint, one in TT and one in UT, so they start from different anchors for UT times up to TT − UTC before each midpoint: 64.2 s before 2004-12-31 12:00, 67.2 s before 2015-01-01 00:00, and 69.2 s before 2024-12-31 12:00 and 2035-01-01 00:00. At 2004-12-31 11:59:30 UT, for example, the engine starts from 2010 and the public API from 2000. Both check the span on TT, but the C engine's decimal year reaches 1900.0 about two weeks after 1900-01-01, so its Delta T has no drop at the start of the span and the public API rejects the UTs up to 88.4 ms before it that the engine accepts. #96 adopts the engine's choices or records otherwise.
- The operations follow the C engine's, in its order, but the results are not all the same bits. At Pluto's 44 Horizons epochs below, the heliocentric and barycentric positions are within 2e-15 AU of the C engine's and the velocities within 5e-19 AU per day; 59 of the 88 states match to the bit, and the other 29 differ in the last bits.
- The simulation and Pluto's model read the planets through no cache (see above), and concurrent updates are linearized without holding a lock during the computation. Neither changes a result.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Gravity/`:

- The tables against `plu060.bsp` coefficient for coefficient, through the generator's `--published` mode, which needs the kernel and does not run in CI. The tests check each table's shape and dates, that the records cover both blends with TDB − TT at its largest, Clenshaw's recurrence against the Chebyshev sums and their derivatives, and that adjacent records meet within 1e-13 AU and 1e-15 AU per day.
- The GM values against k² and DE405's mass ratios, Earth's with the Moon's against DE405's Earth-Moon ratio; the accelerations against Newton's law; the third-order local error of a step; the major bodies and the solar system against the planet functions.
- The simulation against Horizons states of the Pluto system barycenter on 1990, 2000, 2001 and 2010-01-01 (`Scripts/reference-data/sources/horizons/pluto-barycenter-decade.json`): from the 2000 state, one-day steps forward and backward land within 10,000 km, 0.5″ and 5e-6 of the speed (measured: 2,700 km, 0.12″ and 1.5e-6 after ten years; 4- and 16-day steps land as close, so the gap is the force model's).
- Chiron: the anchors against Horizons' current states within 5 km and 2e-11 AU per day; the state at each anchor's time equal to the anchor; the 12 Horizons vectors at the four midpoints between anchors with a day either side within 2,000 km, 0.5″ and 5e-6 of the speed (measured 1,200 km, 0.09″ and 2.3e-6); 1900-01-01 within 1′ (32″), and 2150-01-01 within 1′ (3.1″) in optimized builds only, since 50 years against the planets' full series take many minutes in Debug; the `chiron-vector` rows of `AuditValidationTests` within their 0.01 AU; the span's ends on TT, including pairs whose UT disagrees with their TT and the UTs just before 1900 that the Delta T drop admits, anchor choice and exact ties, the reuse budget step by step and after a rejected time, a light-time correction on one reusable simulation within 1e-9 AU of fresh starts, the caller's time and model, and separate simulations on separate threads giving the serial results.
- The simulation's behavior: both moments at the start, no bodies, unsupported origins and the order of errors, bodies independent of each other, origins that only shift the states, the gap after stepping out and back shrinking as the cube of the step (an eighth for half the step), a repeated TT, the caller's time and model, swaps after an update and before any, the light-time pattern of trial and swap, rejected updates leaving every bit of both moments unchanged, the bodies' states relative to the origin, and simultaneous updates to one time stepping once with the serial result.
- The `JPLValidationTests` geocentric (1′) and Asheville (1.5′) Pluto suites as astrometric directions through `Engine.Positions.geocentricPosition` and `Engine.Observers`; the `pluto-observer` rows of 1900, 2000 and 2100 in J2000 and true ecliptic of date coordinates within 1.5′; and the 268 Pluto records of `distance-fixtures.json` within their allowances.
- Horizons vectors of Pluto's center at 29 dates from 1840 to 2159 (`Scripts/reference-data/sources/horizons/pluto-vector.json`): through both blends, across DE440 and PLU060 record seams, and across the model's segment seams on 1840-02-09 and 2159-11-23 and a step seam in 1880, with samples a day apart. The 9 in the DE440 span are within 1 km and 1e-8 of the speed (measured: 0.005″, under 0.05 km and 4e-10); the other 20 are within 1′ (16.6″ at most, in 2159).
- Horizons vectors of the Pluto system barycenter at 15 dates from 100 BCE to 4098 CE (`pluto-barycenter-vector.json`), where Horizons has no Pluto center: the first and last tabulated states with a day either side, a segment seam in 800 and a step seam in 840, and both ends of the extrapolation. All 15 miss 1′ and are recorded as known issues of #190.
- Velocities against five-point differences of the positions: 1/256-day stencils through both blends and the DE440 records within 2e-9 AU per day, the C engine's test, and 1/64-day stencils inside the model's steps within 2e-12.
- Routing, blend arithmetic and continuity at the blend ends, segment and step seams, the step past the last state, both crawl limits, NaN and infinite times.
- Cache work counts with private registries: one integration per segment, reuse within it, no lookups in the DE440 span or the extrapolation, eviction, a registry reset, a cache with no capacity, and simultaneous callers, with resets in progress, getting the serial bits and staying within 1′ of the Horizons vectors in segments 24 and 25.

### Pluto, simulation and Chiron tests that depend on the C engine

| Test | Disposition |
|---|---|
| `BundledEphemerisTests` Pluto cases | Kept while the C engine ships: they call `CLibAstronomy` for the C evaluator, the blend weight, velocities at the seams, concurrent first calls, and pin legacy Pluto values captured from the C engine. `EnginePlutoEphemerisTests` and `EnginePlutoTests` check the Swift evaluator, weight routing and velocities, and `EnginePlutoCacheTests` concurrent calls. The pinned legacy values are not published values; the Horizons vectors above replace them as evidence. Retired when #96 removes the C engine. |
| `ReproducibilityTests` Pluto rows | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): they pin public results, not published values. The Pluto model they reach is checked against Horizons here. Retired by #96. |
| `PlutoRangeTests`, `PlutoThreadSafetyTests` | Public-API checks that run on the C engine until #96: the crawl limits and NaN guard, and concurrent calls with `AstronomyConfig.reset()` against seven longitudes the file attributes to the Swiss Ephemeris. `EnginePlutoTests` and `EnginePlutoCacheTests` check the same properties of the Swift functions against Horizons. |
| `ChironTests` "Reference anchors remain exact" | Kept while the C engine ships: it pins the public API's positions at the anchor dates to the anchor values within 1e-12 AU, which checks the anchor arithmetic, not a published value. `EngineChironTests` checks the anchors against Horizons' recorded states within 5 km and the engine's state at each anchor against the anchor. Retired by #96, or moved onto the engine with the anchors at 00:00 TDB. |
| `ChironTests` (other cases) | Public-API checks on the C engine until #96: span, continuity across anchor changes, reuse and light-time bounds, named sanity bounds. `EngineChironTests` checks the same properties of the engine against Horizons. |
| `ReproducibilityTests` Chiron row | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): it pins a public result, not a published value. The Chiron state it reaches is checked against Horizons here. Retired by #96. |
| `AuditValidationTests.chironPosition` | A published-value sanity check of the public API (0.01 AU), on the C engine until #96. `EngineChironTests` applies it to the engine, with tighter checks at the anchors' midpoints and the span's ends. |
| `GravitySimulationTests` | Public-API checks that run on the C engine until #96: construction, updates, swaps and errors, with named sanity bounds, not published values. `EngineGravitySimulationTests` checks the Swift simulation against Horizons and the C engine's behavior. Moves onto the engine when #96 switches the public `GravitySimulation` over. |
| The Pluto suites of `JPLValidationTests`, `DistanceAccuracyTests` and `AuditValidationTests` | Published-value checks of the public API, which runs on the C engine until #96. `EnginePlutoHorizonsTests` applies the same references and allowances to the Swift functions, reading the geocentric vector from `Engine.Positions.geocentricPosition` (see [Positions](#positions)). |

## Positions

In the tree: `Positions/EngineHeliocentric.swift`, `Positions/EngineGeocentric.swift`, `Positions/EngineEcliptic.swift` and `Positions/EngineEquatorial.swift`. They port `Astronomy_HelioVector`, `Astronomy_HelioState`, `Astronomy_HelioDistance`, `Astronomy_BaryState`, `Astronomy_BackdatePosition`, `Astronomy_GeoVector`, `Astronomy_Equator`, `Astronomy_SunPosition`, `Astronomy_EclipticLongitude`, `Astronomy_GeoEclipticState` and `Astronomy_SunEclipticState`, and compose the horizontal coordinates the public `horizon(at:from:refraction:)` reports. `Engine.EclipticState` and the obliquity rotation and its rate moved from `Moon/` to `Foundation/EngineEclipticState.swift` when this module became their second user.

**Planned** (#89): Chiron's apparent positions, illumination and the separation utilities (`Astronomy_Illumination`, `Astronomy_AngleFromSun`, `Astronomy_PairLongitude`, `Astronomy_Elongation`).

```swift
extension Engine.Positions {
    static func heliocentricPosition(of body: CelestialBody, at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ>
    static func heliocentricState(of body: CelestialBody, at time: Engine.Time) throws -> Engine.State<Engine.EQJ>
    static func heliocentricDistance(of body: CelestialBody, at time: Engine.Time) throws -> Double
    static func barycentricState(of body: CelestialBody, at time: Engine.Time) throws -> Engine.State<Engine.EQJ>
    static func backdatedPosition(
        of target: CelestialBody, seenFrom observer: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ>
    static func geocentricPosition(of body: CelestialBody, at time: Engine.Time, aberration: Aberration) throws -> Engine.Vector<Engine.EQJ>
    static func geocentricState(of body: CelestialBody, at time: Engine.Time, aberration: Aberration) throws -> Engine.State<Engine.EQJ>
    static func geocentricEclipticState(of body: CelestialBody, at time: Engine.Time, aberration: Aberration) throws -> Engine.EclipticState
    static func sunPosition(at time: Engine.Time) throws -> Engine.Ecliptic
    static func sunEclipticState(at time: Engine.Time) throws -> Engine.EclipticState
    static func eclipticLongitude(of body: CelestialBody, at time: Engine.Time) throws -> Double
    static func equatorial(
        of body: CelestialBody, at time: Engine.Time, from observer: Observer, equatorDate: EquatorDate, aberration: Aberration
    ) throws -> Engine.Equatorial
    static func horizontal(of body: CelestialBody, at time: Engine.Time, from observer: Observer, refraction: Refraction) throws -> Engine.Horizontal
}
```

- The bodies are the Sun, Mercury to Neptune, Pluto, the Moon, the Earth-Moon barycenter and the solar system barycenter. Every function checks the time against `Engine.acceptedTTDays` first and throws `badTime`, then throws `invalidBody` for any other body, as the C functions do in that order. Each also throws `badTime` for a result that is not finite. Results carry the time they were given, except a backdated position, which carries the backdated time.
- Heliocentric positions come from each body's model: `Engine.Planet` for the planets, `Engine.Pluto` for Pluto, the Moon's geocentric position plus Earth's, and Earth's position plus the Moon's over 1 + `Engine.Moon.earthMoonMassRatio` for the Earth-Moon barycenter. The solar system barycenter is offset from the Sun by Σ GM/(GM + GM☉) times the positions of Jupiter to Neptune, the C engine's `CalcSolarSystemBarycenter`, with the masses of `Engine.Gravity`. A heliocentric state is composed the same way from the models' states, so its position is the same double as the position; the solar system barycenter's state is the Sun's from `Engine.Gravity.MajorBodies`, negated. The distance is `Engine.Planet.heliocentricDistance` for a planet, 0 for the Sun, and the position's length otherwise.
- Barycentric states are relative to the barycenter of `MajorBodies`: the Sun and Jupiter to Neptune are its states, Mercury to Mars the Sun's plus the planet's, the Moon and the Earth-Moon barycenter their geocentric states plus the sum of the Sun's and Earth's, in the C engine's order of additions, and Pluto `Engine.Pluto.barycentricState`.
- `backdatedPosition` runs `Engine.LightTravel.correct` on the target's heliocentric position less the observer's. With `.none` the observer is at the observation time; with `.corrected` it is backdated with the target. That backdating is the C engine's aberration approximation: in the light time the observer moves along a chord nearly parallel to its velocity, which turns the direction by the observer's transverse speed over the speed of light, Bradley's first-order aberration. The observer's position is evaluated before the target's each time.
- `geocentricPosition` is zero for Earth and `Engine.Moon.geocentricPosition` for the Moon, with no light time or aberration whatever `aberration` says, as `Astronomy_GeoVector` does. For any other body it is `backdatedPosition` seen from Earth, with the observation time. Every backdated time is checked against the accepted range, so near −`acceptedTTDays` a backdated body throws `badTime` while Earth and the Moon do not.
- `equatorial` is `geocentricPosition` less the observer's J2000 position, `Engine.Observers.vector`, on the J2000 equator, or rotated by `Engine.FrameRotation.eqjToEqd` for `.ofDate`. A zero vector, Earth's center from the geocentric observer, throws `badVector`, as the C engine's `vector2radec` does. `horizontal` takes the apparent equatorial coordinates of date, with aberration, through `Engine.Horizontal`, as the public `horizon` does.
- `sunPosition` is `Astronomy_SunPosition`: Earth's heliocentric position negated, one astronomical unit's light time before the time, on the true ecliptic of that earlier time, reported at the time. `eclipticLongitude` is the heliocentric position's longitude on the ecliptic of date, and throws `invalidBody` for the Sun before it checks the time, as the C function does.
- `geocentricState` gives the state behind `Astronomy_GeoEclipticState`, for the Sun, the Moon, Mercury to Neptune except Earth, and Pluto. Its position is `geocentricPosition`'s, double for double. The Moon's is `Engine.Moon.geocentricState`. For a backdated body the velocity is the derivative of the converged light-time solution τ = |p(t − τ)| / c by implicit differentiation, so it does not depend on the iteration count: with `.corrected`, ṗ = v / (1 + q), with v the relative velocity at the backdated time and q = p̂ · v / c; with `.none`, ṗ = v(s) (1 + b) / (1 + a) − v⊕(t), with a = p̂ · v(s) / c and b = p̂ · v⊕(t) / c. Pluto's velocity is `Engine.Pluto`'s exact derivative throughout. Rates are per TT day with Delta T held fixed.
- `geocentricEclipticState` and `sunEclipticState` port local patch 12. Their position, longitude, latitude and distance are `Engine.Ecliptic` of `geocentricPosition` and of the Sun's backdated position, and that vector's length, double for double. The velocity goes through precession, nutation and the true obliquity one rotation at a time, each with its rate, and gives the longitude, latitude and distance rates with the C engine's expressions. A position with no component in the ecliptic plane throws `badVector`.
- User-defined stars, which the C functions also take, stay with #91: the engine passes star definitions by value, and `CelestialBody` has no star cases.

### Differences from the C engine

- The light time uses the published light-day (see [Constants](#constants)), which moves a backdated time by 6.0e-11 of the light time.
- The ecliptic and equatorial outputs rotate with `Engine.FrameRotation`'s IAU 2006/2000B matrices and apparent sidereal time with the complementary terms (see [Earth orientation](#earth-orientation)), not the C engine's, so their positions are not the C engine's bits; the identities above are between the engine's own functions.
- Pluto's states carry `Engine.Pluto`'s exact velocity everywhere. `Astronomy_HelioState` and `Astronomy_BaryState` leave out the rate of the integrated model's mix between steps; at 92 times from 1890 to 1899 the two velocities differ by at most 6e-20 AU per day.

### Published-value checks

Tests under `Tests/AstronomyKitTests/Engine/Positions/`:

- Barycentric states of the Sun, Mercury to Neptune, Pluto, the Moon and the Earth-Moon barycenter against JPL Horizons (DE441, `Scripts/reference-data/sources/horizons/*-barycentric-vector.json`), within the limits of Astronomy Engine's `BaryStateTest` in `ctest.c`. Upstream set the Pluto limit against `barystate/Pluto.txt`, the Pluto system barycenter (Horizons 9); the fixture here is Pluto's center (999), which is about 2,100 km from it, under 1e-6 of the limit. 84 states inside the span each limit was set on, every 25 years from 1900 to 2099 for the Sun, the outer planets and Pluto, every 10 years from 1980 to 2020 for Mercury to Mars, and at 5 dates from 1970 to 2040 for the Moon and the barycenter. The largest is Jupiter's velocity, at 0.63 of its limit; positions reach at most 0.57 (the Sun's, absolute). The checks fail for the heliocentric Sun, the barycenter given as the Moon, and a day's error.
- All 2,546 records of `distance-fixtures.json`, in all 19 body and mode series, within their allowances: the heliocentric distance, and the length of the geocentric position with no aberration. The checks fail for the heliocentric distance against a geocentric record, the corrected position and a day's error.
- The `JPLValidationTests` geocentric and Asheville Moon suites within 1′ through `geocentricPosition`, which, as the public API does, gives the Moon no light time (about 0.7″). `EnginePlanetHorizonsTests` and `EnginePlutoHorizonsTests` read their geocentric vectors from `geocentricPosition` with no aberration.
- The aberration approximation against the first-order formula, Earth's transverse velocity halfway through the light time over c, within 0.1% and 0.002″ for the Sun, Mars, Jupiter, Saturn and Neptune weekly through 2025; the Sun's shift against the IAU constant of aberration κ = 20.49552″, within κ(1 ± e).
- The 19 `JPLValidationTests` geocentric and Asheville suites through `equatorial`, J2000 with aberration as the public `equatorial(at:from:equatorDate:)` calls it, at their tolerances: 1′, and 1.5′ for Asheville Neptune and Pluto.
- The 12 Horizons observer rows of `reference-fixtures.json` (the Moon, Mars and Pluto at 1900, 2000 and 2100, and Mercury through its 2025-08-11 station), with each column as Horizons defines it: the astrometric direction within the row's 1′ or 1.5′; the apparent ecliptic of date from `geocentricEclipticState` within the same; the apparent RA (times cos δ) and Dec rates on the true equator of date, from `geocentricState` through precession and nutation with their rates, within 0.02″ per hour for the planets (measured 0.013) and 0.25″ per hour for the Moon, whose rates lack aberration's turning, up to κ times its angular speed, 0.22″ per hour, because the engine, like the public API, gives the Moon no aberration (measured 0.14); `delta`, the range with light time and no aberration, from `backdatedPosition` for every body, the Moon included, within the body's `distance-fixtures.json` allowance (measured 0.4 km for the Moon); and `deldot`, the target's velocity at the backdated time less Earth's now along the line of sight, within 1e-4 km/s (measured 9.0e-5, Pluto in the 1900 blend, and 7e-6 elsewhere). Horizons solves light time in the barycentric frame and the engine in the heliocentric one. The rate checks fail a day off.
- Azimuth and elevation of the Sun, the Moon and Mars from the Asheville site every three hours on 2026-01-02 and 2026-07-02 against Horizons (`sources/horizons/*-asheville-airless.json` and `*-asheville-refracted.json`, 96 rows), through `horizontal` with no refraction for the airless rows and `.jplHorizons` for the refracted ones, within 1′, above and below the horizon. Horizons' UTC is taken as UT1, which it stays within 0.9 s of. Measured, the largest angle is 5.6″, for the Moon. The checks fail with no refraction near the horizon, with `.normal` below it, and a minute off.
- Mathematical bounds: routing to each body's model double for double; the ecliptic states' positions against `Engine.Ecliptic` of the positions, and the Sun's against `sunPosition`, bit for bit, at 120 and 200 instants from 1901 to 2099 and 4 beyond; their rates against five-point differences of those positions on 1/64-day stencils within the allowances `EclipticStateTests` sets (5e-8° and 2e-9 AU per day, the Moon 5e-7° and 1e-9 AU, Pluto 1e-6° and 2e-9 AU), at 60 instants, the series beyond the fits and the 2026 March equinox, where the Sun's longitude wraps; Pluto's in its integrated model, mid-blend and astride a 146-day step; rates continuous across polynomial segment boundaries, the Moon's blends and Pluto's 1900 blend; Mercury's rate smooth across changes in the light-time iteration count; and Mercury's 2025-08-11 station from the rate within 1 s of the differenced longitude's; states' positions against positions; barycentric states against the Sun's barycentric state plus the heliocentric ones, exactly for the Sun and the planets and within 1e-14 AU and 1e-17 AU per day for the Moon, the barycenter and Pluto; the light-time solution and the backdated time's model; the accepted range at both ends, beyond them and for times that are not finite; and velocities against five-point differences on 1/64-day stencils in 1800, 1945, 2000, 2026 and 2200, within (1 + |t|) · 1e-11 AU per day, t in Julian centuries, plus the lunar series' allowance where it applies.

### Position tests that depend on the C engine

| Test | Disposition |
|---|---|
| `DistanceAccuracyTests` and the `JPLValidationTests` geocentric and Asheville suites | Published-value checks of the public API, which runs on the C engine until #96. `EnginePositionsReferenceTests`, `EnginePlanetHorizonsTests` and `EnginePlutoHorizonsTests` apply the same fixtures and allowances to `Engine.Positions`. |
| `EclipticStateTests` | Kept while the C engine ships: it checks the public ecliptic states, local patch 12, against the public positions bit for bit and against differenced positions, and calls `CLibAstronomy` directly for the EQJ to ECT rotation rate (`_Astronomy_EclipticStateFromEqj`), the nutation rates (`_Astronomy_Iau2000bRates`) and polynomial seams (`Astronomy_HelioState`). `EngineEclipticStateTests` holds the same identities, rate budgets, iteration-count, seam and station checks for the engine; `EngineNutationTests` and `EnginePrecessionTests` check the engine's nutation and precession rates and rotation rates against differences (see [Earth orientation](#earth-orientation)), and `EnginePlanetPolynomialTests` its seams. #96 moves the public identities onto the engine and retires the `CLibAstronomy` calls with the C engine. |
| `ReproducibilityTests` position, equatorial, ecliptic-rate and topocentric rows | Kept while the C engine ships, as recorded under [Earth orientation](#earth-orientation): they pin public results, not published values. The positions, equatorial coordinates, topocentric Moon and ecliptic rates they reach are checked here against Horizons and against differenced positions. Retired by #96. |
| `AuditValidationTests.jplGeocentricObservation` and `jplApparentRangeDiagnostic` | Published-value check and named sanity check of the public API on the C engine until #96. `EngineObserverRowTests` applies every column of the same rows to the engine, the range under Horizons' definition. |
| `LightTravelTests` | Named sanity checks of the public light-time solver and backdated positions, on the C engine until #96. `EngineLightTravelTests` checks the engine's solver, and `EnginePositionsTests` its backdated positions against the light-time equation. |

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
| Moon longitude, latitude, distance | #87 | `Engine.Moon.cache`: `BoundedCache`, 32 entries, `ExactKey` of TT in Julian centuries, shared by positions and states | Thread-local, 32 entries (local patch 14) |
| Pluto segments | #88 | `Engine.Pluto.cache`: `BoundedCache` of 50 entries, one per segment, keyed by segment index | Allocated segments behind a mutex, freed by `Astronomy_Reset` (local patch 1) |
| Delta T default | #96 | `Atomic` in the public layer | `_Atomic` function pointer (local patch 2) |
| Gravity simulation | #88 | `Engine.GravitySimulation`: two moments behind its own `NSLock`, updated optimistically | Caller-owned handle |
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

A module records the signatures it provides here, in the PR that adds them, before a dependent module starts. A change to another module's provided signatures goes through that owner's issue. `Foundation/`'s owner, #84, is closed: the #87 PRs moved `unpackDoubles` and `acceptedTTDays` into it and recorded that here in the same PRs, and no other rule has been set for it. Each change to this file updates the sections it affects rather than appending history.
