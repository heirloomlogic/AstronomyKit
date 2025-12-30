//
//  Libration.swift
//  AstronomyKit
//
//  Lunar libration calculations.
//

import CLibAstronomy

// MARK: - Libration

/// Lunar libration angles and related data.
///
/// Libration is the apparent oscillation of the Moon that allows us to see
/// slightly more than 50% of its surface over time. This is caused by
/// the Moon's elliptical orbit and axial tilt.
///
/// ## Example
///
/// ```swift
/// let libration = try Moon.libration(at: .now)
/// print("Sub-Earth point: (\(libration.subEarthLatitude)°, \(libration.subEarthLongitude)°)")
/// print("Moon distance: \(Int(libration.distanceKM)) km")
/// ```
public struct Libration: Sendable, Equatable {
    /// The ecliptic latitude of the sub-Earth point on the Moon's surface.
    ///
    /// This indicates how much the Moon is tilted toward or away from Earth,
    /// allowing observers to see slightly past the lunar poles.
    public let subEarthLatitude: Double

    /// The ecliptic longitude of the sub-Earth point on the Moon's surface.
    ///
    /// This indicates the east-west libration, allowing observers to see
    /// slightly past the Moon's eastern or western limb.
    public let subEarthLongitude: Double

    /// The Moon's geocentric ecliptic latitude in degrees.
    public let moonLatitude: Double

    /// The Moon's geocentric ecliptic longitude in degrees.
    public let moonLongitude: Double

    /// The distance from Earth's center to the Moon's center in kilometers.
    public let distanceKM: Double

    /// The apparent angular diameter of the Moon in degrees.
    ///
    /// This varies from about 0.49° (at apogee) to 0.56° (at perigee).
    public let apparentDiameter: Double

    /// Creates a libration from the C structure.
    internal init(_ raw: astro_libration_t) {
        self.subEarthLatitude = raw.elat
        self.subEarthLongitude = raw.elon
        self.moonLatitude = raw.mlat
        self.moonLongitude = raw.mlon
        self.distanceKM = raw.dist_km
        self.apparentDiameter = raw.diam_deg
    }
}

extension Libration: CustomStringConvertible {
    public var description: String {
        String(
            format: "Libration: (%.2f°, %.2f°), Distance: %.0f km, Diameter: %.3f°",
            subEarthLatitude, subEarthLongitude, distanceKM, apparentDiameter)
    }
}

// MARK: - Moon Extensions

extension Moon {
    /// Calculates the lunar libration at the specified time.
    ///
    /// Libration values indicate how the Moon appears to rock back and forth,
    /// revealing portions of the far side along the limb.
    ///
    /// - Parameter time: The time at which to calculate the libration.
    /// - Returns: The libration data.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let lib = try Moon.libration(at: .now)
    /// if lib.subEarthLongitude > 0 {
    ///     print("More of the Moon's east limb is visible")
    /// } else {
    ///     print("More of the Moon's west limb is visible")
    /// }
    /// ```
    public static func libration(at time: AstroTime) -> Libration {
        let result = Astronomy_Libration(time.raw)
        return Libration(result)
    }
}
