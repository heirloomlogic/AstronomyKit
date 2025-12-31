# Rise and Set Times

Calculate when celestial bodies rise, set, and reach their highest point.

## Overview

AstronomyKit can find rise times, set times, culmination (transit), and times when bodies reach specific altitudes. These calculations account for atmospheric refraction.

## Basic Rise and Set

### Sunrise and Sunset

```swift
let observer = Observer(latitude: 40.7128, longitude: -74.0060)

if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: observer) {
    print("Sunrise: \(sunrise.date)")
}

if let sunset = try CelestialBody.sun.setTime(after: .now, from: observer) {
    print("Sunset: \(sunset.date)")
}
```

### Moonrise and Moonset

```swift
if let moonrise = try CelestialBody.moon.riseTime(after: .now, from: observer) {
    print("Moonrise: \(moonrise)")
}

if let moonset = try CelestialBody.moon.setTime(after: .now, from: observer) {
    print("Moonset: \(moonset)")
}
```

### Planet Rise and Set

```swift
if let marsRise = try CelestialBody.mars.riseTime(after: .now, from: observer) {
    print("Mars rises at \(marsRise)")
}
```

## Culmination (Transit)

Culmination is when a body crosses the meridian and reaches its highest altitude:

```swift
let transit = try CelestialBody.sun.culmination(after: .now, from: observer)
print("Solar noon: \(transit.time)")
print("Max altitude: \(transit.horizon.altitude)°")
```

This is useful for:
- Finding solar noon
- Determining the best time to observe a planet
- Calculating day length

## Custom Altitude Searches

Find when a body reaches a specific altitude:

```swift
// Astronomical twilight begins when Sun is 18° below horizon
let twilight = try CelestialBody.sun.searchAltitude(
    -18.0,
    direction: .set,
    after: .now,
    from: observer
)
if let time = twilight {
    print("Astronomical twilight begins: \(time)")
}
```

### Civil and Nautical Twilight

```swift
// Civil twilight: Sun at -6°
let civilTwilight = try CelestialBody.sun.searchAltitude(
    -6.0, direction: .set, after: .now, from: observer
)

// Nautical twilight: Sun at -12°
let nauticalTwilight = try CelestialBody.sun.searchAltitude(
    -12.0, direction: .set, after: .now, from: observer
)
```

### Minimum Observation Altitude

```swift
// Find when Mars rises above 20° (good for observation)
let observable = try CelestialBody.mars.searchAltitude(
    20.0,
    direction: .rise,
    after: .now,
    from: observer
)
```

## Hour Angle Searches

Search for a specific hour angle:

```swift
// Hour angle 0 = culmination (upper transit)
let upperTransit = try CelestialBody.saturn.searchHourAngle(
    0,
    after: .now,
    from: observer
)

// Hour angle 12 = lower culmination
let lowerTransit = try CelestialBody.saturn.searchHourAngle(
    12,
    after: .now,
    from: observer
)
```

## Search Limits

All searches have a time limit (default: 366 days):

```swift
// Limit search to next 30 days
let sunrise = try CelestialBody.sun.riseTime(
    after: .now,
    from: observer,
    limitDays: 30
)
```

## Handling "No Result"

Rise/set searches return `nil` if no event occurs in the search period:

```swift
// In polar regions, the Sun may not rise/set
let arcticObserver = Observer(latitude: 78.0, longitude: 15.0)

if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: arcticObserver) {
    print("Sunrise: \(sunrise)")
} else {
    print("Sun does not rise during this period (polar night/day)")
}
```

## Daily Events

Get all events for a single day:

```swift
let events = try CelestialBody.sun.dailyEvents(
    on: .now,
    from: observer
)

if let rise = events.rise {
    print("Rise: \(rise)")
}
if let transit = events.culmination {
    print("Transit: \(transit.time) at \(transit.horizon.altitude)°")
}
if let set = events.set {
    print("Set: \(set)")
}

if events.isVisible {
    print("Sun is visible at some point today")
}
```

This is convenient for building daily almanac displays.

## Time Zones

All returned times are in UTC. Convert for display:

```swift
let sunrise = try CelestialBody.sun.riseTime(after: .now, from: observer)!

let formatter = DateFormatter()
formatter.timeZone = TimeZone(identifier: "America/New_York")
formatter.timeStyle = .short
print("Sunrise: \(formatter.string(from: sunrise.date))")
```
