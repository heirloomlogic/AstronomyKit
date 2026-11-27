# ``AstronomyKit``

Pure Swift 6 astronomical calculations based on Don Cross' [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library.

@Metadata {
    @DisplayName("AstronomyKit")
    @TitleHeading("Framework")
}

## Overview

![AstronomyKit logo — a bronze armillary sphere](AstronomyKit-logo)

AstronomyKit is a 100% pure Swift 6 library based on Don Cross' [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library, with zero C dependencies, strict concurrency checking, and full `Sendable` conformance.

### Features

- Positions and ecliptic velocities for the Sun, Moon, planets, and Jupiter's Galilean moons
- Moon phase angles, quarters, illumination, libration, and lunar nodes
- Rise, set, culmination, and custom altitude searches
- Lunar, global solar, and local solar eclipse predictions
- Equinoxes, solstices, planetary apsides, elongations, and transits
- Coordinate transforms across equatorial, ecliptic, horizontal, and galactic frames
- Stateless fixed stars, gravity-simulated 2060 Chiron, and generic root-finding search
- Pure Swift 6 implementation with zero C dependencies and full `Sendable` conformance

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
- ``Constellation``
- ``Aberration``
- ``EquatorDate``

### Moon

- <doc:MoonPhases>
- ``Moon``
- ``MoonPhase``
- ``MoonQuarter``
- ``Libration``
- ``LunarNode``
- ``NodeKind``

### Events

- <doc:RiseSetTimes>
- <doc:Eclipses>
- <doc:SeasonsAndEvents>
- ``AstroSearch``
- ``Seasons``
- ``Sun``
- ``Eclipse``
- ``LunarEclipse``
- ``GlobalSolarEclipse``
- ``LocalSolarEclipse``
- ``EclipseEvent``
- ``EclipseKind``
- ``Apsis``
- ``ApsisKind``
- ``Elongation``
- ``Visibility``
- ``Illumination``
- ``Transit``
- ``DailyEvents``
- ``HourAngleEvent``
- ``RiseSetDirection``

### Advanced

- <doc:AdvancedFeatures>
- ``Chiron``
- ``FixedStar``
- ``GravitySimulation``
- ``LagrangePoint``
- ``LagrangePointID``
- ``Jupiter``
- ``JupiterMoons``
- ``RotationAxis``
- ``Atmosphere``

### Coordinates

- ``Equatorial``
- ``Ecliptic``
- ``EclipticState``
- ``Horizon``
- ``Spherical``
- ``Vector3D``
- ``StateVector``
- ``RotationMatrix``
- ``Refraction``

### Time

- ``AstroTime``

### Configuration

- ``AstronomyConfig``
- ``DeltaTModel``

### Errors

- ``AstronomyError``
