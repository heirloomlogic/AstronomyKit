# ``AstronomyKit``

Swift bindings for Don Cross’ [Astronomy Engine](https://github.com/cosinekitty/astronomy) library.

@Metadata {
    @DisplayName("AstronomyKit")
}

## Overview

AstronomyKit wraps the [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library and exposes the underlying C functionality through idiomatic Swift APIs.

### Features

- **Celestial Body Positions** — Calculate positions for the Sun, Moon, planets, and Jupiter's moons
- **Moon Phases** — Phase angles, quarter searches, illumination, and libration
- **Rise/Set Times** — Sunrise, sunset, moonrise, culmination, and custom altitude searches
- **Eclipses** — Predict lunar and solar eclipses with detailed timing
- **Seasons** — Find equinoxes and solstices for any year
- **Coordinate Systems** — Transform between equatorial, ecliptic, horizontal, and galactic frames
- **Swift 6 Ready** — Full `Sendable` conformance for safe concurrency

### Quick Start

```swift
import AstronomyKit

// Your location
let observer = Observer(latitude: 40.7128, longitude: -74.0060)  // NYC

// Current moon phase
let angle = try Moon.phaseAngle(at: .now)
print("\(Moon.emoji(for: angle)) \(Moon.phaseName(for: angle))")

// Next sunrise
if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: observer) {
    print("Sunrise: \(sunrise.date)")
}

// Where is Mars?
let mars = try CelestialBody.mars.horizon(at: .now, from: observer)
print("Mars: \(mars.altitude)° \(mars.compassDirection)")
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TimeAndObservers>

### Position Calculations

- <doc:CelestialPositions>
- <doc:CoordinateSystems>
- ``CelestialBody``
- ``Observer``

### Moon

- <doc:MoonPhases>
- ``Moon``
- ``MoonPhase``
- ``MoonQuarter``
- ``Libration``
- ``LunarNode``

### Events

- <doc:RiseSetTimes>
- <doc:Eclipses>
- <doc:SeasonsAndEvents>
- ``Seasons``
- ``LunarEclipse``
- ``GlobalSolarEclipse``
- ``LocalSolarEclipse``

### Advanced

- <doc:AdvancedFeatures>
- ``GravitySimulation``
- ``LagrangePoint``
- ``Transit``

### Coordinates

- ``Equatorial``
- ``Ecliptic``
- ``Horizon``
- ``Vector3D``
- ``StateVector``
- ``RotationMatrix``

### Time

- ``AstroTime``

### Errors

- ``AstronomyError``
