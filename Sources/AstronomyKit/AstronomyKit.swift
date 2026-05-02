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

import CLibAstronomy

// MARK: - Delta T Models

/// The Delta T model used to convert between Universal Time and Terrestrial Time.
public enum DeltaTModel: Sendable {
    /// The Espenak-Meeus model (default).
    case espenakMeeus

    /// The JPL Horizons model, for compatibility with JPL tools.
    case jplHorizons
}

// MARK: - Module-Level Functions

/// Module-level configuration and utility functions.
public enum AstronomyConfig {
    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the Espenak-Meeus model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTEspenakMeeus(universalTime: Double) -> Double {
        Astronomy_DeltaT_EspenakMeeus(universalTime)
    }

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the JPL Horizons model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTJplHorizons(universalTime: Double) -> Double {
        Astronomy_DeltaT_JplHorizons(universalTime)
    }

    /// Sets the Delta T model used for all subsequent calculations.
    ///
    /// Delta T is the difference between Terrestrial Time and Universal Time.
    /// Different models produce slightly different values, especially for
    /// dates far from the present.
    ///
    /// - Parameter model: The Delta T model to use.
    public static func setDeltaTModel(_ model: DeltaTModel) {
        switch model {
        case .espenakMeeus:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus)
        case .jplHorizons:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons)
        }
    }

    /// Resets all internal state in the Astronomy Engine.
    ///
    /// This clears cached calculations, resets the Delta T function to
    /// the default (Espenak-Meeus), and undefines any custom star definitions.
    /// Call this if you need a clean slate.
    public static func reset() {
        Astronomy_Reset()
    }
}
