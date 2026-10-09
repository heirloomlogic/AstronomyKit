//
//  Constellation.swift
//  AstronomyKit
//
//  Constellation identification from celestial coordinates.
//

// MARK: - Constellation

/// A constellation identified from celestial coordinates.
///
/// Constellations are defined with respect to the B1875 equatorial system
/// per IAU standard. The `find(rightAscension:declination:)` function accepts J2000 coordinates
/// and performs the necessary conversion internally.
///
/// ## Example
///
/// ```swift
/// // Find which constellation contains Betelgeuse
/// let constellation = try Constellation.find(rightAscension: 5.9195, declination: 7.4071)
/// print("\(constellation.symbol) - \(constellation.name)") // "Ori - Orion"
/// ```
public struct Constellation: Sendable, Equatable, Hashable {
    /// The 3-character IAU abbreviation (e.g., "Ori" for Orion).
    public let symbol: String

    /// The full constellation name (e.g., "Orion").
    public let name: String

    /// The right ascension in B1875 coordinates (hours).
    public let rightAscension1875: Double

    /// The declination in B1875 coordinates (degrees).
    public let declination1875: Double

    init(_ value: Engine.Constellations.Result) {
        self.symbol = value.symbol
        self.name = value.name
        self.rightAscension1875 = value.rightAscension1875
        self.declination1875 = value.declination1875
    }
}

extension Constellation: CustomStringConvertible {
    /// A textual representation showing the IAU symbol and full name.
    public var description: String {
        "\(symbol) (\(name))"
    }
}

// MARK: - Constellation Lookup

extension Constellation {
    /// Finds which constellation contains the given J2000 equatorial coordinates.
    ///
    /// - Parameters:
    ///   - rightAscension: Right ascension in sidereal hours (0-24).
    ///   - declination: Declination in degrees (-90 to +90).
    /// - Returns: The constellation containing the coordinates.
    /// - Throws: `AstronomyError` if the lookup fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Polaris (the North Star) is in Ursa Minor
    /// let constellation = try Constellation.find(rightAscension: 2.5303, declination: 89.2641)
    /// print(constellation.name) // "Ursa Minor"
    /// ```
    public static func find(rightAscension: Double, declination: Double) throws -> Constellation {
        Constellation(try Engine.Constellations.find(rightAscension: rightAscension, declination: declination))
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
        return try Constellation.find(rightAscension: eq.rightAscension, declination: eq.declination)
    }
}
