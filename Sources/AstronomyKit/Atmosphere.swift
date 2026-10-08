//
//  Atmosphere.swift
//  AstronomyKit
//
//  Atmospheric model calculations.
//

// MARK: - Atmosphere

/// Atmospheric properties at a given elevation.
///
/// This structure provides a simple model of Earth's atmosphere
/// based on elevation above sea level.
///
/// ## Example
///
/// ```swift
/// let atm = try Atmosphere.at(elevation: 5000)
/// print("Pressure: \(atm.pressure) mbar")
/// print("Temperature: \(atm.temperature)°C")
/// ```
public struct Atmosphere: Sendable, Equatable {
    /// The atmospheric pressure in millibars.
    ///
    /// At sea level, this is approximately 1013.25 mbar.
    public let pressure: Double

    /// The kinetic temperature in degrees Celsius.
    public let temperature: Double

    /// The atmospheric density relative to sea level.
    ///
    /// A value of 1.0 represents the sea level density of 1.2250 kg/m³.
    /// Higher elevations have lower density.
    public let density: Double

    /// Creates an atmosphere from the native engine's values.
    init(_ engine: Engine.Atmosphere) {
        self.pressure = engine.pressure / 100.0
        self.temperature = engine.temperature - 273.15
        self.density = engine.density
    }
}

extension Atmosphere: CustomStringConvertible {
    /// A textual representation including pressure, temperature, and density.
    public var description: String {
        String(
            format: "%.1f mbar, %.1f°C, density %.3f",
            pressure,
            temperature,
            density
        )
    }
}

// MARK: - Atmosphere Calculations

extension Atmosphere {
    /// Calculates atmospheric properties at a given elevation.
    ///
    /// Uses the 1976 U.S. Standard Atmosphere (NOAA-S/T 76-1562), computed
    /// from its defining constants, through all of its layers up to 100 km.
    /// Below 32 km it agrees with the ISO 2533 standard atmosphere, whose
    /// molar mass is 28.96442 kg/kmol rather than 28.9644, to within 3.3e-6
    /// in pressure; the difference grows with height, from 1.0e-6 at 11 km.
    ///
    /// Up to 84,852 m (86 km geometric height) the standard's seven layers
    /// are linear in geopotential height. Above that the standard works in
    /// geometric height and follows the diffusion of nitrogen, oxygen,
    /// argon and helium separately, which this model integrates. Between
    /// 80 and 86 km geometric height the temperature is the standard's
    /// kinetic temperature, which its printed tables leave uncorrected and
    /// overstate by up to 0.08 K.
    ///
    /// - Parameter elevation: The geopotential height above sea level in
    ///   meters, from -500 to 100,000.
    /// - Returns: The atmospheric properties.
    /// - Throws: ``AstronomyError/invalidParameter`` for an elevation outside
    ///   -500 to 100,000 meters or one that is not finite.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Atmosphere at the summit of Mount Everest
    /// let everest = try Atmosphere.at(elevation: 8848.86)
    /// print("Pressure: \(everest.pressure) mbar") // ~314 mbar
    /// ```
    public static func at(elevation: Double) throws -> Atmosphere {
        try Atmosphere(Engine.Atmosphere(elevation: elevation))
    }
}

// MARK: - Observer Extension

extension Observer {
    /// The atmospheric properties at this observer's elevation.
    ///
    /// Uses the 1976 U.S. Standard Atmosphere model (see
    /// ``Atmosphere/at(elevation:)``), passing the observer's height above
    /// sea level unchanged as the geopotential height. The two differ by
    /// h²/r: about 12 m at 8,849 m, which lowers the pressure by about 0.2 %.
    public var atmosphere: Atmosphere {
        get throws {
            try Atmosphere.at(elevation: height)
        }
    }
}
