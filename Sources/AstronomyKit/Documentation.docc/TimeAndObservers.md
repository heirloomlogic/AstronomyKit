# Time and Observers

Work with astronomical time and geographic observer locations.

## Overview

AstronomyKit uses ``AstroTime`` for time and ``Observer`` for geographic locations.

## Working with Time

### Creating Times

```swift
// Current time
let now = AstroTime.now

// From calendar components (in UTC)
let eclipse = AstroTime(year: 2024, month: 4, day: 8, hour: 18, minute: 15)

// From Foundation Date
let time = AstroTime(Date())

// From UT1 days since J2000 noon
let ut = AstroTime(ut: 9132.5)
```

### Time Arithmetic

```swift
let now = AstroTime.now

// Add days or hours
let tomorrow = now.addingDays(1)
let nextHour = now.addingHours(1)
let lastWeek = now.addingDays(-7)

// Compare times
if tomorrow > now {
    print("Tomorrow comes after now")
}
```

### Converting to Date

```swift
let time = AstroTime.now
let date: Date = time.date

// Format for display
let formatter = DateFormatter()
formatter.dateStyle = .medium
formatter.timeStyle = .short
print(formatter.string(from: time.date))
```

### Understanding UT vs TT

AstroTime stores two time values internally. Universal Time (UT1) follows Earth's rotation and drives rise and set times. Terrestrial Time (TT) is the uniform scale used for planetary orbits.

```swift
let time = AstroTime.now
print("UT: \(time.universalTime)")  // Days since J2000 noon (UT1)
print("TT: \(time.terrestrialTime)")  // Days since J2000 noon (TT)

// Create from Terrestrial Time directly
let fromTT = AstroTime(tt: 9132.5)
```

AstronomyKit applies the difference (ΔT) for you.

### Delta T Configuration

The difference between TT and UT1 (ΔT) follows Earth's rotation, which is observed, not predicted by theory. A civil ``AstroTime`` takes TT exactly from the leap-second table and recovers UT1 by inverting the selected ΔT model, so the model sets Earth's rotation angle, hour angles, azimuths, house cusps and rise and set times for every civil instant. A ΔT error of 1 s turns Earth by 15″ and moves rise and set by about a second.

AstronomyKit defaults to ``DeltaTModel/iersObserved``. No call is needed to use it. It draws on four sources, joined so that ΔT is continuous:

| Regime | Span | Source | ΔT |
|---|---|---|---|
| ``DeltaTRegime/extrapolatedPast`` | before −720 | HMNAO long-term length-of-day model | integral of lod = 1.72 t − 3.5 sin(2π(t + 0.75)/14) ms, t in centuries from 1825.0 |
| ``DeltaTRegime/historical`` | −720 to 1962-01-01 | Morrison, Stephenson, Hohenkerk and Zawilski (2021), Table S15 v2020 | cubic spline fitted to eclipse and occultation timings, continuous in value and rate |
| ``DeltaTRegime/observed`` | 1962-01-01 to the last observation | IERS EOP 20 C04, then IERS Bulletin A rapid values | (TAI − UTC) + 32.184 s − (UT1 − UTC), daily at 0h UTC |
| ``DeltaTRegime/predicted`` | about a year further | IERS Bulletin A predictions | as observed |
| ``DeltaTRegime/extrapolatedFuture`` | after the last prediction | HMNAO long-term length-of-day model | as before −720 |

Between the daily rows ΔT is linear in UT1. Against the IERS C04 series sampled at 12h, linear interpolation is off by at most 0.16 ms (rms 0.019 ms, 1984–2026), far below a millisecond of Earth rotation.

The spline is the 2020 addendum to Stephenson, Morrison and Hohenkerk (2016), as published by HM Nautical Almanac Office. HMNAO publishes it as cubic polynomials rounded to 1 ms, so at a knot the two neighbouring segments disagree by up to 1 ms in value and 1.1e-6 s per day in rate. A jump that size is physically negligible but shows up in numerical derivatives taken across the knot. AstronomyKit therefore rebuilds each segment as the cubic Hermite curve through the mean of the two one-sided values and rates at its knots. The rebuilt spline is continuous in value and rate at every knot and stays within 0.65 ms of the published polynomials. The spline departs from the IERS series by up to 0.68 s over 1962–2019. At 1962.0 it is 0.376 s below the first IERS value and 0.9 ms per day slower, so the 1959–1962 segment ends on the first C04 value and the rate of the first C04 day instead, and ΔT stays continuous in value and rate across 1962. Beyond the spline and the predictions, the long-term model is the one HMNAO uses to extrapolate the spline to −2000 and 2500: tidal deceleration of 1.72 ms per century with a 1400-year fluctuation. Its integration constant is fixed by the value at the join, so ΔT is continuous there. Its rate, the excess length of day, is not matched there: after the last prediction the model's 0.17 ms replaces the last predicted day's 0.03 ms, and at −720 the model's −47.3 ms replaces the spline's −44.2 ms (HMNAO tabulates −44.2 ms there). Matching it would mean inventing a transition that no source describes. Inside the daily table the rate also steps at each row, by the day-to-day change in length of day (median 0.1 ms, largest 1.9 ms at the start of 1984), because the interpolation is linear. Swiss Ephemeris since version 2.06 extrapolates the future with a cubic its source attributes to the same HMNAO data; it gives about 107 s for 2126.

The extrapolations are estimates, not observations. HMNAO gives 80 ± 10 s for 2100 and 160 ± 20 s for 2200, and decade-scale fluctuations in Earth's rotation can move them. The Espenak–Meeus model, by comparison, gives 203 s for 2100.

| UT | ``DeltaTModel/iersObserved`` | ``DeltaTModel/espenakMeeus`` | ``DeltaTModel/jplHorizons`` |
|---|---|---|---|
| 2026.8 (predicted) | 69.22 s | 75.55 s | 69.99 s |
| 2050.0 | 71.9 s | 93.0 s | 69.99 s |
| 2126.0 | 100.9 s | 266.0 s | 69.99 s |

``AstronomyConfig/deltaTIersObservedUncertainty(universalTime:)`` gives a stated, sourced uncertainty for the default model. It is a figure of about one standard error, not a proved bound, and the sources do not all state a confidence level:

- Observed: the row's published UT1 − UTC error (C04's formal error, then Bulletin A's), plus up to 0.16 ms of interpolation at midday. About 2 ms in 1962 and 0.02 ms today.
- Predicted: Bulletin A's stated error for each day, 0.6 ms a day ahead and 24 ms a year ahead.
- Historical: HMNAO's error estimate, 180 s at −720 and 15 s from 1000 to 1600, never less than the spline's 0.68 s departure from IERS.
- Extrapolated: HMNAO's estimate for its extrapolation, 2 s at 2030, 10 s at 2100, 100 s at 2500, and 0.3 h at −2000. Before −2000 and after 2500 no figure is published, so the estimate grows with the square of the time from 1825.0.

``AstronomyConfig/deltaTIersObservedRegime(universalTime:)`` reports the regime. ``AstronomyConfig/ephemerisVersion`` names the table's last observation and last prediction; a new table is a new version.

The two models upstream Astronomy Engine provides remain available for comparison with tools built on them. ``DeltaTModel/espenakMeeus`` is upstream's default; from 2005 it extrapolates a ΔT that runs about 6.3 s above observed UT1 in 2026. ``DeltaTModel/jplHorizons`` is Espenak–Meeus held at its 2017.0 value. Set the model once at startup, before any other AstronomyKit call:

```swift
// Compare with a tool that uses the Espenak-Meeus polynomials
AstronomyConfig.setDeltaTModel(.espenakMeeus)

// Query Delta T and its stated uncertainty for a specific UT1 (days since J2000)
let deltaT = AstronomyConfig.deltaTIersObserved(universalTime: 9_800)
let sigma = AstronomyConfig.deltaTIersObservedUncertainty(universalTime: 9_800)

// Back to the default model
AstronomyConfig.setDeltaTModel(.iersObserved)
```

`AstronomyConfig.reset()` does not touch the Delta T model. It only frees the Pluto orbit cache.

Polar motion and the celestial pole offsets dX and dY, which the same IERS series carry, are not applied.

### Sidereal Time

Get the sidereal time at the prime meridian:

```swift
let sidereal = AstroTime.now.siderealTime
print("Greenwich Sidereal Time: \(sidereal) hours")
```

Calculate local sidereal time for any longitude:

```swift
let observer = Observer(latitude: 40.7, longitude: -74.0)  // NYC
let lst = AstroTime.now.siderealTime(longitude: observer.longitude)
print("Local Sidereal Time: \(lst) hours")
```

## Working with Observers

### Creating Observers

```swift
// Basic location (sea level)
let seattle = Observer(latitude: 47.6062, longitude: -122.3321)

// With height above sea level (meters)
let everest = Observer(
    latitude: 27.9881,
    longitude: 86.9250,
    height: 8848.86
)
```

### Coordinate Conventions

- Latitude: -90° (south) to +90° (north)
- Longitude: -180° (west) to +180° (east)
- Height: meters above sea level

### Built-in Locations

```swift
let greenwich = Observer.greenwich       // Royal Observatory
let primeMeridian = Observer.primeMeridian  // 0°, 0°
```

### Observer Properties

```swift
let observer = Observer(latitude: 40.0, longitude: -105.0, height: 1600)

// Local gravity (accounts for latitude and altitude)
let gravity = observer.gravity  // m/s²

// Atmospheric conditions at this elevation
let atmosphere = try observer.atmosphere
print("Pressure: \(atmosphere.pressure) mbar")
```

### Observer Vectors

Get the observer's position relative to Earth's center:

```swift
let observer = Observer.greenwich

// Position vector in AU
let position = try observer.vector(at: .now)

// Full state (position and velocity)
let state = try observer.state(at: .now)
print("Position: \(state.position)")
print("Velocity: \(state.velocity)")
```

## Time Zones

AstronomyKit works entirely in UTC. Convert to local time using Foundation:

```swift
let sunrise = try CelestialBody.sun.riseTime(after: .now, from: observer)!

let formatter = DateFormatter()
formatter.timeZone = TimeZone(identifier: "America/New_York")
formatter.timeStyle = .short
print("Sunrise (local): \(formatter.string(from: sunrise.date))")
```

## Codable Support

Both types support `Codable` for persistence:

```swift
let observer = Observer(latitude: 40.7, longitude: -74.0)
let data = try JSONEncoder().encode(observer)

let time = AstroTime.now
let timeData = try JSONEncoder().encode(time)
```

## Civil time and numerical compatibility

`AstroTime(Date)`, calendar components and `.now` use civil UTC. From 1961 onward, a bundled USNO table converts UTC to TT, including the rate adjustments before 1972. Future dates retain the last announced leap-second offset. Before 1961, civil dates use the engine's historical UT1 proxy.

`universalTime` and `init(ut:)` are UT1 coordinates from the selected Delta T model, not UTC timestamps. `terrestrialTime` and `init(tt:)` are TT. Native search results already carry both scales; their `.date` uses the same civil inverse as every other time. `addingDays` and `addingHours` add UT1 coordinate intervals. For civil calendar arithmetic, use Foundation and construct a new `AstroTime` from the resulting date.

Foundation cannot represent leap seconds. TT instants in positive UTC gaps map to the next transition; negative historical steps choose the later civil occurrence. Those instants cannot round-trip through `Date`. The default Delta T model is continuous. In a model with positive gaps, such as Espenak–Meeus at its 1986 join, TT maps to the first UT1 coordinate after the jump. At negative overlaps, fixed-point iteration returns the first solution reached from its initial `ut = tt` estimate. TT remains exact in memory, but numeric Codable remains UT1-based, so decoding a gap-clamped value derives TT again from the selected model. The table's future convention and the predicted and extrapolated UT1 values do not establish future UTC or Earth-orientation accuracy. Review serialized times and invalidate version-dependent cached calculations when upgrading.
