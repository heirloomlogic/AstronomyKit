//
//  Constellation.swift
//  AstronomyKit
//
//  Constellation identification from celestial coordinates.
//

import CLibAstronomy

// MARK: - Constellation

/// A constellation identified from celestial coordinates.
///
/// Constellations are defined with respect to the B1875 equatorial system
/// per IAU standard. The `find(ra:dec:)` function accepts J2000 coordinates
/// and performs the necessary conversion internally.
///
/// ## Example
///
/// ```swift
/// // Find which constellation contains Betelgeuse
/// let constellation = try Constellation.find(ra: 5.9195, dec: 7.4071)
/// print("\(constellation.symbol) - \(constellation.name)") // "Ori - Orion"
/// ```
public struct Constellation: Sendable, Equatable, Hashable {
    /// The 3-character IAU abbreviation (e.g., "Ori" for Orion).
    public let symbol: String

    /// The full constellation name (e.g., "Orion").
    public let name: String

    /// The right ascension in B1875 coordinates (hours).
    public let ra1875: Double

    /// The declination in B1875 coordinates (degrees).
    public let dec1875: Double

    /// Creates a constellation from the C structure.
    internal init(_ raw: astro_constellation_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.symbol = String(cString: raw.symbol)
        self.name = String(cString: raw.name)
        self.ra1875 = raw.ra_1875
        self.dec1875 = raw.dec_1875
    }
}

extension Constellation: CustomStringConvertible {
    public var description: String {
        "\(symbol) (\(name))"
    }
}

// MARK: - Constellation Lookup

extension Constellation {
    /// Finds which constellation contains the given J2000 equatorial coordinates.
    ///
    /// - Parameters:
    ///   - ra: Right ascension in sidereal hours (0-24).
    ///   - dec: Declination in degrees (-90 to +90).
    /// - Returns: The constellation containing the coordinates.
    /// - Throws: `AstronomyError` if the lookup fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Polaris (the North Star) is in Ursa Minor
    /// let constellation = try Constellation.find(ra: 2.5303, dec: 89.2641)
    /// print(constellation.name) // "Ursa Minor"
    /// ```
    public static func find(ra: Double, dec: Double) throws -> Constellation {
        let result = Astronomy_Constellation(ra, dec)
        return try Constellation(result)
    }
}

// MARK: - CelestialBody Extensions

extension CelestialBody {
    /// Finds which constellation this body is in at the specified time.
    ///
    /// - Parameter time: The time at which to determine the body's constellation.
    /// - Returns: The constellation containing the body.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let constellation = try CelestialBody.mars.constellation(at: .now)
    /// print("Mars is in \(constellation.name)")
    /// ```
    public func constellation(at time: AstroTime) throws -> Constellation {
        let eq = try equatorial(at: time)
        return try Constellation.find(ra: eq.rightAscension, dec: eq.declination)
    }
}
