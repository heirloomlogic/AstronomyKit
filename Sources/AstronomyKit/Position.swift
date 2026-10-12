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
        Vector3D(try Engine.Positions.geocentricPosition(of: self, at: time.engine, aberration: aberration), at: time)
    }

    /// Calculates the apparent geocentric ecliptic position and velocity of this body.
    ///
    /// The position fields are bit-identical to `geocentricPosition(at: time, aberration: aberration).toEcliptic()`. Rates are per Terrestrial Time day with Delta T held fixed and differentiate barycentric TDB light time, finite-source solar deflection, relativistic aberration and the observation-date frame. Source-table and blend derivatives follow each body's selected trajectory. These derivatives do not establish independent physical rate accuracy.
    ///
    /// Supported bodies are the Sun, the Moon, Mercury through Neptune except
    /// Earth, and Pluto. Other bodies throw ``AstronomyError/invalidBody``.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    /// - Returns: The ecliptic position and velocity.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func geocentricEclipticState(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> EclipticState {
        EclipticState(
            try Engine.Positions.geocentricEclipticState(of: self, at: time.engine, aberration: aberration), at: time)
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
        Vector3D(try Engine.Positions.heliocentricPosition(of: self, at: time.engine), at: time)
    }

    /// Calculates the distance from the Sun to this body.
    ///
    /// - Parameter time: The time at which to calculate the distance.
    /// - Returns: The distance in AU.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func distanceFromSun(at time: AstroTime) throws -> Double {
        try Engine.Positions.heliocentricDistance(of: self, at: time.engine)
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
        try observer.validate()
        return Equatorial(
            try Engine.Positions.equatorial(
                of: self, at: time.engine, from: observer, equatorDate: equatorDate, aberration: aberration),
            at: time)
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
        try observer.validate()
        return Horizon(
            try Engine.Positions.horizontal(of: self, at: time.engine, from: observer, refraction: refraction))
    }

    /// Calculates the ecliptic longitude of this body.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        try Engine.Positions.eclipticLongitude(of: self, at: time.engine)
    }

    /// Calculates the angular separation from the Sun.
    ///
    /// - Parameter time: The time at which to calculate the angle.
    /// - Returns: The angle in degrees (0-180).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func angleFromSun(at time: AstroTime) throws -> Double {
        try Engine.Positions.angleFromSun(of: self, at: time.engine)
    }

    /// Calculates the barycentric state vector (position and velocity relative
    /// to the Solar System Barycenter).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The barycentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func barycentricState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Positions.barycentricState(of: self, at: time.engine), at: time)
    }

    /// Calculates the heliocentric state vector (position and velocity relative
    /// to the Sun's center).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The heliocentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func heliocentricState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Positions.heliocentricState(of: self, at: time.engine), at: time)
    }

    /// Calculates the geocentric state vector of the Earth-Moon Barycenter.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric EMB state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func earthMoonBaryState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Moon.barycenterState(at: time.engine), at: time)
    }

    /// Returns the astrometric or apparent displacement from the receiving body, with the target's emission time in the vector metadata.
    ///
    /// The observer remains at reception while barycentric light time determines the target's emission TT. Corrected mode then applies solar deflection and relativistic aberration; its direction is not a geometric location. The target and observer being the same supported body returns zero.
    ///
    /// - Parameters:
    ///   - time: The reception time within the accepted TT interval.
    ///   - observerBody: The receiving body's center.
    ///   - aberration: The angular-correction mode. At the Sun's center, `.corrected` throws `badVector` because the solar-field observer distance is zero; `.none` remains available.
    /// - Returns: A fixed-EQJ displacement retaining the astrometric range and emission-time metadata.
    /// - Throws: `AstronomyError.badTime` for an invalid reception or uncovered emission, `invalidBody` for an unsupported body, or `badVector` for a singular corrected geometry.
    public func backdatedPosition(
        at time: AstroTime,
        seenFrom observerBody: CelestialBody,
        aberration: Aberration = .corrected
    ) throws -> Vector3D {
        Vector3D(
            try Engine.Positions.backdatedPosition(
                of: self, seenFrom: observerBody, at: time.engine, aberration: aberration))
    }
}

// MARK: - Aberration

/// Selects astrometric or apparent place for solar-system and fixed-star position consumers.
///
/// Solar-system light time is solved in elapsed TDB with the observer at reception, including the Moon. Fixed-star catalog light time is implicit in the catalog definition. Explicitly geometric Moon and heliocentric APIs do not use this mode. Neither mode includes Shapiro delay, planetary deflection, atmospheric refraction or source motion absent from the selected trajectory.
public enum Aberration: Sendable {
    /// Astrometric place: light time and topocentric parallax where requested, without gravitational deflection or observer aberration.
    case none

    /// Apparent place: astrometric place followed by finite-source solar deflection and relativistic barycentric aberration. Topocentric consumers include the site's diurnal velocity. The Sun does not deflect its own image; occulted solar-disk rays use the ERFA limiter.
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
        try Ecliptic(Engine.Positions.sunPosition(at: time.engine))
    }

    /// Calculates the Sun's ecliptic position and velocity.
    ///
    /// The position fields are bit-identical to ``position(at:)`` and the general apparent Sun route on the true ecliptic and equinox of observation date. Rates differentiate the shared barycentric light-time and relativistic-aberration solution per Terrestrial Time day with Delta T held fixed.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The ecliptic position and velocity of the Sun.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func eclipticState(at time: AstroTime) throws -> EclipticState {
        EclipticState(try Engine.Positions.sunEclipticState(at: time.engine), at: time)
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
    /// - Throws: `AstronomyError.invalidParameter` if `targetLongitude` or
    ///   `limitDays` is not finite, or another `AstronomyError` if the
    ///   calculation fails.
    public static func searchLongitude(
        _ targetLongitude: Double,
        after startTime: AstroTime,
        limitDays: Double = 366
    ) throws -> AstroTime? {
        try Engine.Events.searchSunLongitude(targetLongitude, after: startTime.engine, limitDays: limitDays)
            .map(AstroTime.init)
    }
}
