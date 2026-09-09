# Moon Phases

Calculate moon phases, quarters, libration, and lunar nodes.

## Overview

The ``Moon`` type covers phase angles, illumination, quarter searches, position and velocity, libration, and node crossings.

## Phase Angle

The phase angle indicates the Moon's position in its cycle:

```swift
let angle = try Moon.phaseAngle(at: .now)
print("Phase angle: \(angle)°")
// 0° = New Moon, 90° = First Quarter, 180° = Full, 270° = Third Quarter
```

## Phase Names and Emoji

Convert angles to human-readable descriptions:

```swift
let angle = try Moon.phaseAngle(at: .now)

print(Moon.phaseName(for: angle))  // "Waxing Gibbous"
print(Moon.emoji(for: angle))      // "🌔"
```

The eight phase names:
- New Moon (🌑)
- Waxing Crescent (🌒)
- First Quarter (🌓)
- Waxing Gibbous (🌔)
- Full Moon (🌕)
- Waning Gibbous (🌖)
- Third Quarter (🌗)
- Waning Crescent (🌘)

## Illumination

Calculate the fraction of the Moon that's lit:

```swift
let angle = try Moon.phaseAngle(at: .now)
let illumination = Moon.illumination(for: angle)
print("Moon is \(Int(illumination * 100))% illuminated")
```

## Finding Quarter Phases

### Search for a Specific Phase

```swift
// Next full moon (nil if none occurs within the search window)
if let fullMoon = try Moon.searchPhase(.full, after: .now) {
    print("Next full moon: \(fullMoon)")
}
```

### Get the Next Quarter

```swift
let quarter = try Moon.searchQuarter(after: .now)
print("\(quarter.phase.emoji) \(quarter.phase.name) at \(quarter.time)")
```

### All Quarters in a Date Range

```swift
let start = AstroTime(year: 2025, month: 1, day: 1)
let end = AstroTime(year: 2025, month: 2, day: 1)

let quarters = try Moon.quarters(from: start, to: end)
for quarter in quarters {
    print("\(quarter.phase.emoji) \(quarter.time)")
}
```

## Lunar Position

### Ecliptic Coordinates

```swift
let position = try Moon.ecliptic(at: .now)
print("Longitude: \(position.longitude)°")
print("Latitude: \(position.latitude)°")
print("Distance: \(position.distance) AU")
```

### Ecliptic Position and Velocity

For the Moon's speed along the ecliptic, ask for the state instead of differencing two positions:

```swift
let state = try Moon.eclipticState(at: .now)
print("Longitude: \(state.longitude)°")
print("Rate: \(state.longitudeRate)°/day")  // About 12 to 15
```

The position fields match `Moon.ecliptic(at:)` bit for bit. The rates are a central difference of the lunar series inside the engine, per Terrestrial Time day, accurate to roughly 1e-7 degrees per day. See <doc:CelestialPositions> for the full rate contract.

### Cartesian State

Get the Moon's geocentric state vector in equatorial J2000 coordinates:

```swift
let state = try Moon.geoState(at: .now)

// Position in AU
print("Distance: \(state.position.magnitude) AU")

// Velocity in AU/day
let speed = sqrt(
    state.velocity.x * state.velocity.x +
    state.velocity.y * state.velocity.y +
    state.velocity.z * state.velocity.z
)
print("Speed: \(speed) AU/day")
```

> Tip: Use `eclipticState(at:)` or `geoState(at:)` for velocities. Differencing two positions a short interval apart is noisier and costs two calls.

### Using CelestialBody

The Moon is also available as a ``CelestialBody``:

```swift
let horizon = try CelestialBody.moon.horizon(at: .now, from: observer)
let equatorial = try CelestialBody.moon.equatorial(at: .now)
```

## Libration

Libration is the Moon's apparent wobble that lets us see slightly more than 50% of its surface:

```swift
let lib = Moon.libration(at: .now)

// Sub-Earth point (what's at the center of the visible disc)
print("Latitude: \(lib.subEarthLatitude)°")
print("Longitude: \(lib.subEarthLongitude)°")

// Distance and apparent size
print("Distance: \(Int(lib.distanceKM)) km")
print("Apparent diameter: \(lib.apparentDiameter)°")
```

Interpret libration values:
- Positive latitude: More of the north polar region is visible
- Positive longitude: More of the Moon's east limb is visible

## Lunar Nodes

The nodes are where the Moon's orbit crosses the ecliptic plane:

```swift
// Find next node crossing
let node = try Moon.searchNode(after: .now)
print("\(node.kind.symbol) \(node.kind.name) at \(node.time)")
// Output: "☊ Ascending Node at 2025-01-15..."
```

### Node Types

- Ascending (☊): the Moon crosses from south to north of the ecliptic
- Descending (☋): the Moon crosses from north to south

### All Nodes in a Range

```swift
let nodes = try Moon.nodeCrossings(
    from: AstroTime(year: 2025, month: 1, day: 1),
    to: AstroTime(year: 2025, month: 12, day: 31)
)
for node in nodes {
    print("\(node.kind.symbol) \(node.time)")
}
```

## Lunar Apsis

Find perigee (closest) and apogee (farthest) points:

```swift
let apsis = try Moon.searchApsis(after: .now)
print("\(apsis.kind.lunarName): \(Int(apsis.distanceKM)) km")
// Output: "Perigee: 356,500 km"
```

### All Apsides in a Range

```swift
let apsides = try Moon.apsides(
    from: .now,
    to: .now.addingDays(60)
)
for apsis in apsides {
    print("\(apsis.kind.lunarName) at \(apsis.time)")
}
```

## Moonrise and Moonset

Use the ``CelestialBody`` interface:

```swift
let observer = Observer(latitude: 40.7, longitude: -74.0)

if let moonrise = try CelestialBody.moon.riseTime(after: .now, from: observer) {
    print("Moonrise: \(moonrise)")
}

if let moonset = try CelestialBody.moon.setTime(after: .now, from: observer) {
    print("Moonset: \(moonset)")
}
```
