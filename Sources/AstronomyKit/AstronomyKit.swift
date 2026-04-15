//
//  AstronomyKit.swift
//  AstronomyKit
//
//  AstronomyKit wraps the [Astronomy Engine](https://github.com/cosinekitty/astronomy) library by
//  Don Cross, exposing the underlying C functionality through idiomatic Swift APIs for calculating:
//
//  - Positions for the Sun, Moon, planets, and Jupiter's moons
//  - Moon phase angles, quarters, illumination, and libration
//  - User-defined fixed stars from J2000 catalog coordinates
//  - Gravity-simulated position for 2060 Chiron
//  - Rise, set, and culmination times
//  - Lunar and solar eclipse predictions
//  - Equinoxes and solstices
//  - Coordinate transforms across equatorial, ecliptic, horizon, and galactic systems
//  - Apsides, elongation, and transits
//  - Lagrange points and lunar nodes
//  - Full `Sendable` conformance for Swift 6
//
//  ## Quick Start
//
//  ```swift
//  import AstronomyKit
//
//  // Get current moon phase
//  let angle = try Moon.phaseAngle(at: .now)
//  print(Moon.phaseName(for: angle))
//
//  // Find next sunrise
//  let seattle = Observer(latitude: 47.6062, longitude: -122.3321)
//  if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: seattle) {
//      print("Sunrise: \(sunrise)")
//  }
//
//  // Get Mars position
//  let mars = try CelestialBody.mars.horizon(at: .now, from: seattle)
//  print(mars)
//  ```
//

// Re-export everything
@_exported import struct Foundation.Date

// This file serves as the main entry point and documentation for AstronomyKit.
// All public types are automatically exported from their respective files.
