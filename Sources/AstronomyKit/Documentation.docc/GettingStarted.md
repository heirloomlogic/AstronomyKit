# Getting Started with AstronomyKit

Learn how to add AstronomyKit to your project and perform basic astronomical calculations.

## Overview

AstronomyKit provides a type-safe Swift interface for astronomical calculations. This article walks you through installation and your first calculations.

## Installation

Add AstronomyKit to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/heirloomlogic/AstronomyKit.git", from: "2.1.19")
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

All potentially failing calculations throw ``AstronomyError``:

```swift
do {
    let position = try CelestialBody.earth.horizon(at: .now, from: observer)
} catch AstronomyError.earthNotAllowed {
    print("Cannot observe Earth from Earth!")
} catch {
    print("Calculation failed: \(error)")
}
```

## Next Steps

- <doc:TimeAndObservers> — Deep dive into time and location handling
- <doc:CelestialPositions> — Calculate positions for any celestial body
- <doc:MoonPhases> — Explore moon phase calculations
