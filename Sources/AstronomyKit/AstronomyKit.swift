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
    /// Observed Earth rotation (default).
    ///
    /// From 1962 through 2027, a yearly table of International Earth Rotation
    /// and Reference Systems Service (IERS) values, within 0.09 seconds of
    /// the daily series. Before 1962, the Espenak-Meeus model, joined to the
    /// table without a jump. After 2027, the last yearly rate continues and
    /// blends into the long-term parabola, which applies alone from 2150. The
    /// Earth's rotation cannot be predicted for more than a year or so, so
    /// expect errors of about half a second three years past the table and
    /// more after that.
    case observed

    /// The Espenak-Meeus model.
    ///
    /// Its polynomial for 2005 to 2050 has drifted from the observed Earth
    /// rotation: it is about 2 seconds high in 2020 and 6 seconds high in 2027.
    case espenakMeeus

    /// The JPL Horizons model, for compatibility with JPL tools.
    case jplHorizons
}

// MARK: - Module-Level Functions

/// Module-level configuration and utility functions.
public enum AstronomyConfig {
    /// Numerical model identifier for provenance and version-dependent caches.
    ///
    /// It changes whenever a release changes calculated values, so a cache keyed
    /// on it never mixes results from two models. The engine uses the host's
    /// math library, so the last bits of a result can differ between platforms
    /// and OS releases that share one value.
    public static let ephemerisVersion = "4.0.0+upstream-2.1.19"

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the observed model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTObserved(universalTime: Double) -> Double {
        Astronomy_DeltaT_Observed(universalTime)
    }

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
    /// - Note: This is safe to call from any thread at any time. A
    ///   calculation already in flight on another thread may use either the
    ///   old or the new model for that one calculation, so for reproducible
    ///   results set the model once at startup.
    ///
    /// - Parameter model: The Delta T model to use.
    public static func setDeltaTModel(_ model: DeltaTModel) {
        switch model {
        case .observed:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_Observed)
        case .espenakMeeus:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus)
        case .jplHorizons:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons)
        }
    }

    /// Frees all dynamic memory allocated by the Astronomy Engine.
    ///
    /// The engine allocates memory in only one place: a cache of orbit
    /// segments that speeds up Pluto calculations. This purges that cache,
    /// which slows down the next nearby Pluto calculation but releases the
    /// memory (useful before running leak checkers). It does not affect the
    /// Delta T model or any ``FixedStar`` definitions.
    ///
    /// This is safe to call concurrently with other calculations.
    public static func reset() {
        Astronomy_Reset()
    }
}
