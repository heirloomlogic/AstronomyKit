//
//  Illumination.swift
//  AstronomyKit
//
//  Visual magnitude and illumination calculations.
//

import CLibAstronomy

// MARK: - Illumination

/// Information about the brightness and illuminated shape of a celestial body.
///
/// The `Illumination` struct provides data about how bright a body appears
/// and what fraction of its visible disc is illuminated.
///
/// ## Example
///
/// ```swift
/// let venus = try CelestialBody.venus.illumination(at: .now)
/// print("Venus magnitude: \(venus.magnitude)")
/// print("Illuminated: \(Int(venus.phaseFraction * 100))%")
/// ```
public struct Illumination: Sendable, Equatable {
    /// The date and time of the observation.
    public let time: AstroTime

    /// The visual magnitude of the body.
    ///
    /// Smaller values indicate brighter objects. For reference:
    /// - Sun: -26.7
    /// - Full Moon: -12.7
    /// - Venus (brightest): -4.9
    /// - Sirius: -1.5
    /// - Faintest naked-eye stars: +6.0
    public let magnitude: Double

    /// The angle in degrees between the Sun and Earth, as seen from the body.
    ///
    /// This indicates the phase of the body:
    /// - 0° = full phase (body between Earth and Sun)
    /// - 90° = half phase
    /// - 180° = new phase (body opposite from Sun)
    public let phaseAngle: Double

    /// The fraction of the body's apparent disc that is illuminated.
    ///
    /// Values range from 0.0 (not illuminated) to 1.0 (fully illuminated).
    public let phaseFraction: Double

    /// The distance from the Sun to the body in AU.
    public let helioDistance: Double

    /// The tilt angle of Saturn's rings as seen from Earth, in degrees.
    ///
    /// This is 0 for all bodies except Saturn.
    public let ringTilt: Double

    /// Creates an illumination result from the C structure.
    internal init(_ raw: astro_illum_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.time = AstroTime(raw: raw.time)
        self.magnitude = raw.mag
        self.phaseAngle = raw.phase_angle
        self.phaseFraction = raw.phase_fraction
        self.helioDistance = raw.helio_dist
        self.ringTilt = raw.ring_tilt
    }
}

extension Illumination: CustomStringConvertible {
    public var description: String {
        String(
            format: "Mag %.1f, Phase %.0f%%, Ring tilt %.1f°",
            magnitude, phaseFraction * 100, ringTilt)
    }
}

// MARK: - CelestialBody Extensions

extension CelestialBody {
    /// Calculates the illumination of this body at the specified time.
    ///
    /// Returns information about the visual magnitude and phase of the body.
    ///
    /// - Parameter time: The time at which to calculate the illumination.
    /// - Returns: The illumination data for this body.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let mars = try CelestialBody.mars.illumination(at: .now)
    /// print("Mars magnitude: \(mars.magnitude)")
    /// ```
    public func illumination(at time: AstroTime) throws -> Illumination {
        let result = Astronomy_Illumination(raw, time.raw)
        return try Illumination(result)
    }

    /// Searches for the time when this body reaches peak visual magnitude.
    ///
    /// This function is primarily useful for Venus, which has dramatic
    /// brightness variations due to its changing phase and distance.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The illumination data at peak magnitude.
    /// - Throws: `AstronomyError` if the search fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let peak = try CelestialBody.venus.searchPeakMagnitude(after: .now)
    /// print("Venus brightest at \(peak.time): \(peak.magnitude)")
    /// ```
    public func searchPeakMagnitude(after startTime: AstroTime) throws -> Illumination {
        let result = Astronomy_SearchPeakMagnitude(raw, startTime.raw)
        return try Illumination(result)
    }
}
