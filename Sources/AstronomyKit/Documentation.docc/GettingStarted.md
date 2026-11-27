# Getting Started with AstronomyKit

Learn how to add AstronomyKit to your project and perform basic astronomical calculations.

## Overview

AstronomyKit is a pure Swift 6 library for on-device astronomical calculations, based on Don Cross' [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library with zero C dependencies. This article covers installation and your first calculations.

## Installation

Add AstronomyKit to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/heirloomlogic/AstronomyKit", from: "4.2.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Your First Calculations

### Import the Package

```swift
import AstronomyKit
```

### Set Up Your Observer Location

Most astronomical calculations require an observer location on Earth:

```swift
// New York City
let observer = Observer(latitude: 40.7128, longitude: -74.0060)

// With elevation (in meters)
let denver = Observer(latitude: 39.7392, longitude: -104.9903, height: 1609)
```

### Get the Current Time

AstronomyKit uses ``AstroTime`` for all time-based calculations:

```swift
// Current time
let now = AstroTime.now

// From a specific date
let newYear = AstroTime(year: 2025, month: 1, day: 1, hour: 12)

// From Foundation Date
let fromDate = AstroTime(Date())
```

### Calculate a Position

Find where a celestial body appears in your sky:

```swift
// Mars in the local sky
let mars = try CelestialBody.mars.horizon(at: .now, from: observer)
print("Altitude: \(mars.altitude)°")     // Height above horizon
print("Direction: \(mars.compassDirection)")  // N, NE, E, etc.
```

### Find the Moon Phase

```swift
let angle = try Moon.phaseAngle(at: .now)
print("\(Moon.emoji(for: angle)) \(Moon.phaseName(for: angle))")
// Output: 🌔 Waxing Gibbous
```

### Get Rise and Set Times

```swift
if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: observer) {
    print("Sunrise: \(sunrise.date)")
}

if let sunset = try CelestialBody.sun.setTime(after: .now, from: observer) {
    print("Sunset: \(sunset.date)")
}
```

## Error Handling

Calculations that can fail throw ``AstronomyError``:

```swift
do {
    _ = try CelestialBody.earth.riseTime(after: .now, from: observer)
} catch AstronomyError.earthNotAllowed {
    print("Cannot observe Earth from Earth!")
} catch {
    print("Calculation failed: \(error)")
}
```

## Next Steps

- <doc:TimeAndObservers> — Time scales, Delta T, and observer locations
- <doc:CelestialPositions> — Positions for solar system bodies and fixed stars
- <doc:MoonPhases> — Moon phases, libration, nodes, and apsides
