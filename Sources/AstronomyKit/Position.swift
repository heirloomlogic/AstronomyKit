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
    public func geoPosition(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> Vector3D {
        let result = Astronomy_GeoVector(raw, time.raw, aberration.raw)
        return try Vector3D(result)
    }
    
    /// Calculates the heliocentric position of this body.
    ///
    /// Returns the position relative to the Sun's center at the specified time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The heliocentric position vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func helioPosition(at time: AstroTime) throws -> Vector3D {
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
    ///   - observer: The observer location. Defaults to Earth's center.
    ///   - equatorDate: The equinox reference. Defaults to J2000.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    /// - Returns: The equatorial coordinates (RA/Dec).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func equatorial(
        at time: AstroTime,
        from observer: Observer = .primeMeridian,
        equatorDate: EquatorDate = .j2000,
        aberration: Aberration = .corrected
    ) throws -> Equatorial {
        var t = time.raw
        let result = Astronomy_Equator(raw, &t, observer.raw, equatorDate.raw, aberration.raw)
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
        let eq = try equatorial(at: time, from: observer, equatorDate: .ofDate)
        var t = time.raw
        let result = Astronomy_Horizon(&t, observer.raw, eq.rightAscension, eq.declination, refraction.raw)
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
}

// MARK: - Aberration

/// Light aberration correction mode.
public enum Aberration: Sendable {
    /// No correction for aberration.
    case none
    
    /// Correct for light time and aberration.
    case corrected
    
    internal var raw: astro_aberration_t {
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
    
    internal var raw: astro_equator_date_t {
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
}
