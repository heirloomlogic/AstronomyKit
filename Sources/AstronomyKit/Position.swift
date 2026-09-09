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
    /// - Throws: `AstronomyError` if the calculation fails.
    public func geocentricPosition(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> Vector3D {
        let result = Astronomy_GeoVector(raw, time.raw, aberration.raw)
        return try Vector3D(result)
    }

    /// Calculates the apparent geocentric ecliptic position and velocity of this body.
    ///
    /// The position fields are bit-identical to
    /// `geocentricPosition(at: time, aberration: aberration).toEcliptic()`. The rates
    /// are the analytic time derivative of that position in degrees (or AU) per
    /// Terrestrial Time day with Delta T held fixed, including the light-time
    /// derivative, the observer's motion under the aberration approximation, and the
    /// rotation of the true ecliptic and equinox of date. The Moon's rates are a
    /// central difference of the lunar series over about 43 seconds; every other
    /// supported body's rates are analytic. Pluto's velocity is the exact derivative
    /// of its interpolated position, which has small kinks at the interpolation
    /// table's 146-day steps.
    ///
    /// Supported bodies are the Sun, the Moon, Mercury through Neptune except
    /// Earth, and Pluto. Other bodies throw ``AstronomyError/invalidBody``.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    ///     Ignored for the Moon, as in `geocentricPosition(at:aberration:)`.
    /// - Returns: The ecliptic position and velocity.
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
    public func heliocentricPosition(at time: AstroTime) throws -> Vector3D {
        let result = Astronomy_HelioVector(raw, time.raw)
        return try Vector3D(result)
    }

    /// Calculates the distance from the Sun to this body.
    ///
    /// - Parameter time: The time at which to calculate the distance.
    /// - Returns: The distance in AU.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func distanceFromSun(at time: AstroTime) throws -> Double {
        let result = Astronomy_HelioDistance(raw, time.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.value
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
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
    public func horizon(
        at time: AstroTime,
        from observer: Observer,
        refraction: Refraction = .normal
    ) throws -> Horizon {
        let rawObserver = try observer.validatedRaw()
        var rawTime = time.raw
        let eq = try Equatorial(Astronomy_Equator(raw, &rawTime, rawObserver, EQUATOR_OF_DATE, ABERRATION), time: time)
        let result = Astronomy_Horizon(&rawTime, rawObserver, eq.rightAscension, eq.declination, refraction.raw)
        return Horizon(result)
    }

    /// Calculates the ecliptic longitude of this body.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        let result = Astronomy_EclipticLongitude(raw, time.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.angle
    }

    /// Calculates the angular separation from the Sun.
    ///
    /// - Parameter time: The time at which to calculate the angle.
    /// - Returns: The angle in degrees (0-180).
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
    public func barycentricState(at time: AstroTime) throws -> StateVector {
        let result = Astronomy_BaryState(raw, time.raw)
        return try StateVector(result)
    }

    /// Calculates the heliocentric state vector (position and velocity relative
    /// to the Sun's center).
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The heliocentric state vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func heliocentricState(at time: AstroTime) throws -> StateVector {
        let result = Astronomy_HelioState(raw, time.raw)
        return try StateVector(result)
    }

    /// Calculates the geocentric state vector of the Earth-Moon Barycenter.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric EMB state vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func earthMoonBaryState(at time: AstroTime) throws -> StateVector {
        let result = Astronomy_GeoEmbState(time.raw)
        return try StateVector(result)
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
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
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
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func searchLongitude(
        _ targetLongitude: Double,
        after startTime: AstroTime,
        limitDays: Double = 366
    ) throws -> AstroTime? {
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
