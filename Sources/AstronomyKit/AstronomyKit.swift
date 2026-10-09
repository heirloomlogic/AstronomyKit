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
public enum DeltaTModel: Sendable, CaseIterable {
    /// The Espenak-Meeus model (default).
    case espenakMeeus

    /// Legacy approximation of the Horizons delta-T model. This is not the
    /// civil UTC leap-second conversion used by `AstroTime(Date)`.
    case jplHorizons
}

extension DeltaTModel {
    /// The engine function that evaluates this model.
    var function: astro_deltat_func {
        switch self {
        case .espenakMeeus: Astronomy_DeltaT_EspenakMeeus
        case .jplHorizons: Astronomy_DeltaT_JplHorizons
        }
    }

    /// The model that `function` evaluates, or `nil` for a function
    /// AstronomyKit does not name, such as one installed through the C API.
    init?(function: astro_deltat_func?) {
        guard let function else { return nil }
        // C function pointers are not Equatable in Swift; compare addresses.
        let address = unsafeBitCast(function, to: UnsafeRawPointer.self)
        let named = Self.allCases.first { model in
            unsafeBitCast(model.function, to: UnsafeRawPointer.self) == address
        }
        guard let named else { return nil }
        self = named
    }
}

// MARK: - Module-Level Functions

/// Module-level configuration and utility functions.
public enum AstronomyConfig {
    /// Numerical model identifier for provenance and version-dependent caches.
    /// Changes to this value require reviewing cached positions and event times.
    /// Persisted numerical caches must also account for platform, architecture,
    /// OS, and toolchain: native math does not guarantee identical output bits.
    public static let ephemerisVersion = "3.0.0+vsop87b-comp.poly-v2.iau2000b.utc-c72.native-libm"

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

    /// Selects the Delta T model for times created afterwards.
    ///
    /// Delta T is the difference between Terrestrial Time and Universal Time.
    /// Different models produce slightly different values, especially for
    /// dates far from the present.
    ///
    /// An existing ``AstroTime`` keeps the model it captured, and so does every
    /// calculation that starts from it; see "Delta T Model" under `AstroTime`.
    /// To pick a model for one value instead of the whole process, pass
    /// `deltaTModel:` to the `AstroTime` initializer.
    ///
    /// - Note: This is safe to call from any thread at any time. A time being
    ///   created on another thread at the same moment captures either the old
    ///   or the new model.
    ///
    /// - Parameter model: The Delta T model to use.
    public static func setDeltaTModel(_ model: DeltaTModel) {
        Astronomy_SetDeltaTFunction(model.function)
    }

    /// Clears the engine's calculation caches.
    ///
    /// Later calls recompute removed entries. Immutable coefficient tables and
    /// live gravity simulations remain allocated. This does not change the
    /// Delta T model or fixed-star definitions and is safe to call concurrently
    /// with calculations.
    public static func reset() {
        Engine.resetCaches()
        Astronomy_Reset()
    }
}
