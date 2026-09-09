# ``AstronomyKit``

Swift bindings for Don Cross’ [Astronomy Engine](https://github.com/cosinekitty/astronomy) library.

@Metadata {
    @DisplayName("AstronomyKit")
    @TitleHeading("Framework")
}

## Overview

![AstronomyKit logo — a bronze armillary sphere](AstronomyKit-logo)

AstronomyKit wraps Don Cross's [Astronomy Engine](https://github.com/cosinekitty/astronomy) and exposes the underlying C functionality through idiomatic Swift APIs.

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

### Planetary evaluation

Qualified segments from 1900 through 2100 TT use compiled polynomial approximations
of the full VSOP87B model. Position and heliocentric velocity share one representation.
Dates outside that interval and unqualified segments use the full series, preserving
the supported date range. The tables add roughly 11 MB before platform packaging.

### Numerical compatibility

AstronomyKit prioritizes Apple performance and uses platform-native math. Linux
remains supported with the same astronomical accuracy tests. Results may differ
slightly across platforms, architectures, OS releases, toolchains, and build
configurations; cross-platform bit identity is not guaranteed. These rounding
differences can be amplified in event-time calculations.

For persisted numerical caches, include `AstronomyConfig.ephemerisVersion` and
the platform, architecture, OS, and toolchain identity. Review stored positions
and event times when upgrading. Numerical regression tolerances are separate
from absolute astronomical accuracy limits.

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
