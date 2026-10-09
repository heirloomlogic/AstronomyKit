//
//  Position.swift
//  AstronomyKit
//
//  Position calculations for celestial bodies.
//

import CLibAstronomy

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
        let result = Astronomy_GeoVector(raw, time.raw, aberration.raw)
        return try Vector3D(result)
    }

    /// Calculates the apparent geocentric ecliptic position and velocity of this body.
    ///
    /// The position fields are bit-identical to `geocentricPosition(at: time, aberration: aberration).toEcliptic()`. Rates are in degrees (or AU) per Terrestrial Time day with Delta T held fixed and include the light-time derivative, the observer's motion under the aberration approximation, and the rotation of the true ecliptic and equinox of date. Throughout 1900–2130 TT, Moon and Pluto states use analytic derivatives of the bundled coefficients. The 32-day exterior transitions include the derivative of the blend weight. Farther outside that interval, the Moon uses a central difference of the legacy lunar series over about 43 seconds, and Pluto uses the derivative of its legacy interpolant, with small kinks at the 146-day table steps. These derivative conventions do not establish independent rate accuracy.
    ///
    /// Supported bodies are the Sun, the Moon, Mercury through Neptune except
    /// Earth, and Pluto. Other bodies throw ``AstronomyError/invalidBody``.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    ///     Ignored for the Moon, as in `geocentricPosition(at:aberration:)`.
    /// - Returns: The ecliptic position and velocity.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func geocentricEclipticState(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> EclipticState {
        let result = Astronomy_GeoEclipticState(raw, time.raw, aberration.raw)
        return try EclipticState(result)
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
        Vector3D(try Engine.Positions.heliocentricPosition(of: self, at: time.coordinateTime), at: time)
    }

    /// Calculates the distance from the Sun to this body.
    ///
    /// - Parameter time: The time at which to calculate the distance.
    /// - Returns: The distance in AU.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func distanceFromSun(at time: AstroTime) throws -> Double {
        try Engine.Positions.heliocentricDistance(of: self, at: time.coordinateTime)
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
        var rawTime = time.raw
        let result = Astronomy_Equator(raw, &rawTime, try observer.validatedRaw(), equatorDate.raw, aberration.raw)
        return try Equatorial(result, time: time)
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
        let rawObserver = try observer.validatedRaw()
        if self == .sun, let model = time.deltaTModel {
            let native = Engine.Time.fromPair(ut: time.universalTime, tt: time.terrestrialTime, deltaTModel: model)
            let result = try Engine.Positions.horizontal(of: .sun, at: native, from: observer, refraction: refraction)
            return Horizon(
                altitude: result.altitude, azimuth: result.azimuth,
                rightAscension: result.rightAscension, declination: result.declination)
        }
        var rawTime = time.raw
        let eq = try Equatorial(Astronomy_Equator(raw, &rawTime, rawObserver, EQUATOR_OF_DATE, ABERRATION), time: time)
        return Horizon(
            Engine.Horizontal(
                time: time.coordinateTime, observer: observer,
                rightAscension: eq.rightAscension, declination: eq.declination, refraction: refraction
            ))
    }

    /// Calculates the ecliptic longitude of this body.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        try Engine.Positions.eclipticLongitude(of: self, at: time.coordinateTime)
    }

    /// Calculates the angular separation from the Sun.
    ///
    /// - Parameter time: The time at which to calculate the angle.
    /// - Returns: The angle in degrees (0-180).
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func angleFromSun(at time: AstroTime) throws -> Double {
        let result = Astronomy_AngleFromSun(raw, time.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.angle
    }

    /// Calculates the barycentric state vector (position and velocity relative
    /// to the Solar System Barycenter).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The barycentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func barycentricState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Positions.barycentricState(of: self, at: time.coordinateTime), at: time)
    }

    /// Calculates the heliocentric state vector (position and velocity relative
    /// to the Sun's center).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The heliocentric state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public func heliocentricState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Positions.heliocentricState(of: self, at: time.coordinateTime), at: time)
    }

    /// Calculates the geocentric state vector of the Earth-Moon Barycenter.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric EMB state vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func earthMoonBaryState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Moon.barycenterState(at: time.coordinateTime), at: time)
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
        let result = Astronomy_BackdatePosition(
            time.raw,
            observerBody.raw,
            raw,
            aberration.raw
        )
        return try Vector3D(result)
    }
}

// MARK: - Aberration

/// Light aberration correction mode.
public enum Aberration: Sendable {
    /// No correction for aberration.
    case none

    /// Correct for light time and aberration.
    case corrected

    var raw: astro_aberration_t {
        switch self {
        case .none: return NO_ABERRATION
        case .corrected: return ABERRATION
        }
    }
}

// MARK: - Equator Date

/// The equinox reference for equatorial coordinates.
public enum EquatorDate: Sendable {
    /// Use J2000 epoch coordinates.
    case j2000

    /// Use coordinates of the current date.
    case ofDate

    var raw: astro_equator_date_t {
        switch self {
        case .j2000: return EQUATOR_J2000
        case .ofDate: return EQUATOR_OF_DATE
        }
    }
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
        let result = Astronomy_SunPosition(time.raw)
        return try Ecliptic(result)
    }

    /// Calculates the Sun's ecliptic position and velocity.
    ///
    /// The position fields are bit-identical to ``position(at:)``, including its
    /// fixed one-AU light-time adjustment. The rates are the analytic time derivative
    /// of that position per Terrestrial Time day with Delta T held fixed.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The ecliptic position and velocity of the Sun.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func eclipticState(at time: AstroTime) throws -> EclipticState {
        let result = Astronomy_SunEclipticState(time.raw)
        return try EclipticState(result)
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
        let result = Astronomy_SearchSunLongitude(targetLongitude, startTime.raw, limitDays)
        if result.status == ASTRO_SEARCH_FAILURE {
            return nil
        }
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return AstroTime(raw: result.time)
    }
}
