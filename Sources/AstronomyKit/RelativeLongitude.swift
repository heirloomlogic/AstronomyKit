//
//  RelativeLongitude.swift
//  AstronomyKit
//
//  Conjunction, opposition, and relative longitude calculations.
//

import CLibAstronomy

extension CelestialBody {
    /// Returns the relative ecliptic longitude between this body and another.
    ///
    /// The result is measured in degrees (0–360) along the ecliptic plane.
    ///
    /// - Parameters:
    ///   - other: The second celestial body.
    ///   - time: The time at which to calculate the relative longitude.
    /// - Returns: The relative ecliptic longitude in degrees.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func pairLongitude(with other: CelestialBody, at time: AstroTime) throws -> Double {
        let result = Astronomy_PairLongitude(raw, other.raw, time.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.angle
    }

    /// Searches for the next time this body reaches the specified relative
    /// ecliptic longitude from the Sun.
    ///
    /// The angle is measured as the heliocentric longitude difference between
    /// the planet and Earth. At 0°, the planet and Earth are in the same
    /// direction from the Sun (opposition for outer planets, inferior conjunction
    /// for inner planets). At 180°, the planet is on the far side of the Sun
    /// (superior conjunction).
    ///
    /// For convenience, see ``searchOpposition(after:)`` and
    /// ``searchSuperiorConjunction(after:)``.
    ///
    /// - Parameters:
    ///   - targetAngle: The target relative longitude in degrees (0–360).
    ///   - startTime: The time to start searching from.
    /// - Returns: The time when the target relative longitude is reached.
    /// - Throws: `AstronomyError` if the search fails.
    public func searchRelativeLongitude(
        _ targetAngle: Double,
        after startTime: AstroTime
    ) throws -> AstroTime {
        let result = Astronomy_SearchRelativeLongitude(raw, targetAngle, startTime.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return AstroTime(raw: result.time)
    }

    /// Searches for the next opposition of this body.
    ///
    /// An opposition occurs when the planet and Earth are on the same side of the
    /// Sun. For outer planets (Mars through Pluto), this is when the planet appears
    /// opposite the Sun in the sky, is closest to Earth, and is brightest.
    ///
    /// For inner planets (Mercury and Venus), a relative longitude of 0° corresponds
    /// to inferior conjunction rather than opposition. Use
    /// ``searchRelativeLongitude(_:after:)`` directly for inner planet events.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The time of the next opposition.
    /// - Throws: `AstronomyError` if the search fails.
    public func searchOpposition(after startTime: AstroTime) throws -> AstroTime {
        try searchRelativeLongitude(0, after: startTime)
    }

    /// Searches for the next superior conjunction of this body.
    ///
    /// A superior conjunction occurs when the planet is on the far side of the Sun
    /// from Earth (180° relative longitude). The planet appears near the Sun in the
    /// sky and is difficult to observe.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The time of the next superior conjunction.
    /// - Throws: `AstronomyError` if the search fails.
    public func searchSuperiorConjunction(after startTime: AstroTime) throws -> AstroTime {
        try searchRelativeLongitude(180, after: startTime)
    }
}
