//
//  AstronomyKit.swift
//  AstronomyKit
//
//  AstronomyKit is a Swift astronomy library. Its engine follows the published
//  models recorded in NATIVE_ENGINE.md and calculates:
//
//  - Positions for the Sun, Moon, planets, and Jupiter's moons
//  - Moon phase angles, quarters, illumination, and libration
//  - User-defined fixed stars from J2000 catalog coordinates
//  - Position for 2060 Chiron from a table fitted to JPL Horizons
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

import Synchronization

// MARK: - Delta T Models

/// The Delta T model used to convert between Universal Time and Terrestrial Time.
public enum DeltaTModel: Sendable, CaseIterable {
    /// The Espenak-Meeus model (default).
    case espenakMeeus

    /// Legacy approximation of the Horizons delta-T model. This is not the
    /// civil UTC leap-second conversion used by `AstroTime(Date)`.
    case jplHorizons
}

// MARK: - Module-Level Functions

/// Module-level configuration and utility functions.
public enum AstronomyConfig {
    /// Numerical model identifier for provenance and version-dependent caches.
    /// Changes to this value require reviewing cached positions and event times.
    /// Persisted numerical caches must also account for platform, architecture,
    /// OS, and toolchain: native math does not guarantee identical output bits.
    public static let ephemerisVersion = "3.0.0+vsop87b-comp.poly-v2.iau2000b.utc-c72.native-libm"

    /// The index into ``DeltaTModel/allCases`` of the process default model.
    ///
    /// `setDeltaTModel` stores a whole index and a time being created reads a
    /// whole index, so a concurrent swap gives either the old or the new model.
    private static let defaultModelIndex = Atomic<Int>(0)

    /// The process default Delta T model, read once per public call that is
    /// given no model.
    static var deltaTModel: DeltaTModel {
        DeltaTModel.allCases[defaultModelIndex.load(ordering: .relaxed)]
    }

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the Espenak-Meeus model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTEspenakMeeus(universalTime: Double) -> Double {
        Engine.DeltaT.espenakMeeus(ut: universalTime)
    }

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the JPL Horizons model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTJplHorizons(universalTime: Double) -> Double {
        Engine.DeltaT.jplHorizons(ut: universalTime)
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
        let index = DeltaTModel.allCases.firstIndex(of: model) ?? 0
        defaultModelIndex.store(index, ordering: .relaxed)
    }

    /// Clears the engine's calculation caches.
    ///
    /// Later calls recompute removed entries. Immutable coefficient tables and
    /// live gravity simulations remain allocated. This does not change the
    /// Delta T model or fixed-star definitions and is safe to call concurrently
    /// with calculations.
    public static func reset() {
        Engine.resetCaches()
    }
}
