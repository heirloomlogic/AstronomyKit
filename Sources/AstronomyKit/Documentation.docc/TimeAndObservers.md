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

The difference between TT and UT (ΔT) varies over time and comes from a model. AstronomyKit defaults to the Espenak-Meeus model. Set the model once at startup, before any other AstronomyKit call, if you want a different one:

```swift
// Switch to the JPL Horizons Delta T model
AstronomyConfig.setDeltaTModel(.jplHorizons)

// Query Delta T for a specific time
let deltaT = AstronomyConfig.deltaTEspenakMeeus(universalTime: 0)  // Seconds at J2000

// Back to the default model
AstronomyConfig.setDeltaTModel(.espenakMeeus)
```

`AstronomyConfig.reset()` does not touch the Delta T model. It only frees the Pluto orbit cache.

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

`universalTime` and `init(ut:)` are modeled UT1 coordinates, not UTC timestamps. `terrestrialTime` and `init(tt:)` are TT. Native search results already carry both scales; their `.date` uses the same civil inverse as every other time. `addingDays` and `addingHours` add UT1 coordinate intervals. For civil calendar arithmetic, use Foundation and construct a new `AstroTime` from the resulting date.

Foundation cannot represent leap seconds. TT instants in positive UTC gaps map to the next transition; negative historical steps choose the later civil occurrence. Those instants cannot round-trip through `Date`. Positive gaps in the selected Delta T model similarly map TT to the first UT1 coordinate after the jump. At negative overlaps, fixed-point iteration returns the first solution reached from its initial `ut = tt` estimate. TT remains exact in memory, but numeric Codable remains UT1-based, so decoding a gap-clamped value derives TT again from the selected model. The table's future convention and the modeled UT1 values do not establish future UTC or Earth-orientation accuracy. Review serialized times and invalidate version-dependent cached calculations when upgrading.
