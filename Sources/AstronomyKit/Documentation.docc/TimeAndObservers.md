# Time and Observers

Work with astronomical time and geographic observer locations.

## Overview

Accurate time handling is fundamental to astronomy. AstronomyKit provides ``AstroTime`` for precise time representation and ``Observer`` for geographic locations.

## Working with Time

### Creating Times

```swift
// Current time
let now = AstroTime.now

// From calendar components (in UTC)
let eclipse = AstroTime(year: 2024, month: 4, day: 8, hour: 18, minute: 15)

// From Foundation Date
let time = AstroTime(Date())

// From Julian days since J2000
let jd = AstroTime(ut: 9132.5)
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

AstroTime stores two time values internally:

- **Universal Time (UT)**: Based on Earth's rotation, used for rise/set times
- **Terrestrial Time (TT)**: Uniform time scale, used for planetary orbits

```swift
let time = AstroTime.now
print("UT: \(time.universalTime)")  // Days since J2000 noon (UTC)
print("TT: \(time.terrestrialTime)")  // Days since J2000 noon (TT)

// Create from Terrestrial Time directly
let fromTT = AstroTime(tt: 9132.5)
```

The difference (ΔT) is automatically handled by AstronomyKit.

### Accepted Range

Positions, states, distances, and the searches built on them accept a Terrestrial Time within 4,000 Julian years of J2000: `abs(time.terrestrialTime) <= 1_461_000` days, roughly the years −2000 to +6000. That is about the span over which the VSOP87 planetary theory claims validity. Outside it, and for a non-finite time, they throw ``AstronomyError/badTime``. Pluto accepts a narrower span, about the years −100 to +4100.

A calculation that samples nearby times can throw within a short distance of either edge: light-travel correction looks back up to a few hours, the Moon's state vectors sample about a second either side, and searches step by days to years, sometimes backward before stepping forward. Creating an `AstroTime` outside the range is not an error; only the calculations reject it.

### Delta T Configuration

The difference between TT and UT (called ΔT) varies over time and is estimated using a model. AstronomyKit defaults to ``DeltaTModel/observed``, a yearly table of IERS Earth-rotation values that is extrapolated beyond its last entry. You can switch to Espenak-Meeus or, for compatibility, JPL Horizons:

```swift
// Switch to JPL Horizons Delta T model
AstronomyConfig.setDeltaTModel(.jplHorizons)

// Query Delta T for a specific time
let deltaT = AstronomyConfig.deltaTObserved(universalTime: 0)  // Seconds at J2000

// Restore the default
AstronomyConfig.setDeltaTModel(.observed)
```

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

The result is in 0 up to, but not including, 24 hours for any finite longitude. An infinite or NaN longitude returns `.nan`.

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

- **Latitude**: -90° (south) to +90° (north)
- **Longitude**: -180° (west) to +180° (east)
- **Height**: Meters above sea level

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
