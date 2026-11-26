//
//  Position.swift
//  AstronomyKit
//
//  Position calculations for celestial bodies.
//

// MARK: - Position Calculations

extension CelestialBody {
    /// Calculates the geocentric position of this body.
    ///
    /// Returns the position as seen from Earth's center at the specified time.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    /// - Returns: The geocentric position vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func geocentricPosition(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> Vector3D {
        try EnginePositions.geoVector(of: self, at: time, aberration: aberration)
    }

    /// Calculates the heliocentric position of this body.
    ///
    /// Returns the position relative to the Sun's center at the specified time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The heliocentric position vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func heliocentricPosition(at time: AstroTime) throws -> Vector3D {
        try EnginePositions.helioVector(of: self, at: time)
    }

    /// Calculates the distance from the Sun to this body.
    ///
    /// - Parameter time: The time at which to calculate the distance.
    /// - Returns: The distance in AU.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func distanceFromSun(at time: AstroTime) throws -> Double {
        try EnginePositions.helioDistance(of: self, at: time)
    }

    /// Calculates the equatorial coordinates of this body.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The observer location. Defaults to Earth's center;
    ///     pass a surface location for topocentric coordinates (parallax
    ///     matters most for the Moon).
    ///   - equatorDate: The equinox reference. Defaults to J2000.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    /// - Returns: The equatorial coordinates (RA/Dec).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func equatorial(
        at time: AstroTime,
        from observer: Observer = .geocentric,
        equatorDate: EquatorDate = .j2000,
        aberration: Aberration = .corrected
    ) throws -> Equatorial {
        try EngineObserver.equator(
            of: self,
            at: time,
            observer: try observer.validated(),
            equatorDate: equatorDate,
            aberration: aberration
        )
    }

    /// Calculates the horizontal coordinates for an observer.
    ///
    /// Returns where the body appears in the local sky (altitude and azimuth).
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The geographic observer location.
    ///   - refraction: Atmospheric refraction correction. Defaults to `.normal`.
    /// - Returns: The horizon coordinates (altitude/azimuth).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func horizon(
        at time: AstroTime,
        from observer: Observer,
        refraction: Refraction = .normal
    ) throws -> Horizon {
        let validObserver = try observer.validated()
        let gc = try EnginePositions.geoVector(of: self, at: time, aberration: .corrected)
        return try EngineObserver.horizon(
            geocentric: gc,
            at: time,
            observer: validObserver,
            refraction: refraction
        )
    }

    /// Calculates the ecliptic longitude of this body.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        try EnginePositions.eclipticLongitude(of: self, at: time)
    }

    /// Calculates the angular separation from the Sun.
    ///
    /// - Parameter time: The time at which to calculate the angle.
    /// - Returns: The angle in degrees (0-180).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func angleFromSun(at time: AstroTime) throws -> Double {
        try EnginePositions.angleFromSun(of: self, at: time)
    }

    /// Calculates the barycentric state vector (position and velocity relative
    /// to the Solar System Barycenter).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The barycentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func barycentricState(at time: AstroTime) throws -> StateVector {
        try EnginePositions.baryState(of: self, at: time)
    }

    /// Calculates the heliocentric state vector (position and velocity relative
    /// to the Sun's center).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The heliocentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func heliocentricState(at time: AstroTime) throws -> StateVector {
        try EnginePositions.helioState(of: self, at: time)
    }

    /// Calculates the geocentric state vector of the Earth-Moon Barycenter.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric EMB state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func earthMoonBaryState(at time: AstroTime) throws -> StateVector {
        try EnginePositions.geoEmbState(at: time)
    }

    /// Returns the position this body actually occupied when it emitted the light
    /// arriving at the observer body at the given time.
    ///
    /// This accounts for the finite speed of light: the returned position is
    /// where the target was in the past, not where it is "now."
    ///
    /// - Parameters:
    ///   - time: The time when light arrives at the observer.
    ///   - observerBody: The body receiving the light (e.g., `.earth`).
    ///   - aberration: Whether to correct for stellar aberration.
    /// - Returns: The backdated position vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func backdatedPosition(
        at time: AstroTime,
        seenFrom observerBody: CelestialBody,
        aberration: Aberration = .corrected
    ) throws -> Vector3D {
        try EnginePositions.backdatePosition(
            at: time,
            observerBody: observerBody,
            targetBody: self,
            aberration: aberration
        )
    }
}

// MARK: - Aberration

/// Light aberration correction mode.
public enum Aberration: Sendable {
    /// No correction for aberration.
    case none

    /// Correct for light time and aberration.
    case corrected
}

// MARK: - Equator Date

/// The equinox reference for equatorial coordinates.
public enum EquatorDate: Sendable {
    /// Use J2000 epoch coordinates.
    case j2000

    /// Use coordinates of the current date.
    case ofDate
}

// MARK: - Sun Position

/// Contains functions for calculating Sun position and related values.
public enum Sun {
    /// Calculates the Sun's ecliptic position.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates of the Sun.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func position(at time: AstroTime) throws -> Ecliptic {
        try EnginePositions.sunPosition(at: time)
    }

    /// Searches for the next time the Sun reaches the specified ecliptic longitude.
    ///
    /// This is useful for finding specific seasonal moments. For example,
    /// 0° corresponds to the March equinox and 90° to the June solstice.
    ///
    /// - Parameters:
    ///   - targetLongitude: The target ecliptic longitude in degrees (0–360).
    ///   - startTime: The time to start searching from.
    ///   - limitDays: Maximum number of days to search. Defaults to 366.
    /// - Returns: The time when the Sun reaches the target longitude, or
    ///   `nil` if it does not do so within `limitDays`.
    /// - Throws: `AstronomyError.invalidParameter` if `targetLongitude` is not
    ///   finite, or another `AstronomyError` if the calculation fails.
    public static func searchLongitude(
        _ targetLongitude: Double,
        after startTime: AstroTime,
        limitDays: Double = 366
    ) throws -> AstroTime? {
        guard targetLongitude.isFinite else { throw AstronomyError.invalidParameter }
        do {
            return try EngineEvents.searchSunLongitude(
                targetLon: targetLongitude,
                after: startTime,
                limitDays: limitDays
            )
        } catch AstronomyError.searchFailure {
            return nil
        }
    }
}
