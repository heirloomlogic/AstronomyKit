//
//  AstronomyKit.swift
//  AstronomyKit
//
//  A beautiful Swift interface for astronomical calculations.
//
//  This package wraps the AstronomyEngine C library by Don Cross,
//  providing type-safe, idiomatic Swift APIs for calculating:
//
//  - Celestial body positions (Sun, Moon, planets)
//  - Moon phases and quarters
//  - Seasonal events (equinoxes and solstices)
//  - Rise, set, and culmination times
//  - Lunar and solar eclipses
//  - Coordinate transformations
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
