//
//  Atmosphere.swift
//  AstronomyKit
//
//  Atmospheric model calculations.
//

import CLibAstronomy

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

    /// The temperature in degrees Celsius.
    ///
    /// Based on the International Standard Atmosphere model.
    public let temperature: Double

    /// The atmospheric density relative to sea level.
    ///
    /// A value of 1.0 represents sea level density.
    /// Higher elevations have lower density.
    public let density: Double

    /// Creates an atmosphere from the C structure.
    internal init(_ raw: astro_atmosphere_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        // Convert from Pascals to millibars (1 mbar = 100 Pa)
        self.pressure = raw.pressure / 100.0
        // Convert from Kelvins to Celsius
        self.temperature = raw.temperature - 273.15
        self.density = raw.density
    }
}

extension Atmosphere: CustomStringConvertible {
    public var description: String {
        String(
            format: "%.1f mbar, %.1f°C, density %.3f",
            pressure, temperature, density)
    }
}

// MARK: - Atmosphere Calculations

extension Atmosphere {
    /// Calculates atmospheric properties at a given elevation.
    ///
    /// Uses the International Standard Atmosphere model.
    ///
    /// - Parameter elevation: The elevation above sea level in meters.
    /// - Returns: The atmospheric properties.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Atmosphere at the summit of Mount Everest
    /// let everest = try Atmosphere.at(elevation: 8848.86)
    /// print("Pressure: \(everest.pressure) mbar") // ~314 mbar
    /// ```
    public static func at(elevation: Double) throws -> Atmosphere {
        let result = Astronomy_Atmosphere(elevation)
        return try Atmosphere(result)
    }
}

// MARK: - Observer Extension

extension Observer {
    /// The atmospheric properties at this observer's elevation.
    ///
    /// Uses the International Standard Atmosphere model based on
    /// the observer's height above sea level.
    public var atmosphere: Atmosphere {
        get throws {
            try Atmosphere.at(elevation: height)
        }
    }
}
