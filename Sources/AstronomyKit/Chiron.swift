//
//  Chiron.swift
//  AstronomyKit
//
//  Position calculations for 2060 Chiron from a table fitted to JPL Horizons.
//

import Foundation

// MARK: - Chiron

/// Provides position calculations for 2060 Chiron.
///
/// Chiron is a minor planet (centaur) orbiting between Saturn and Uranus.
/// Astronomy Engine has no built-in Chiron, so AstronomyKit adds one.
///
/// ## Overview
///
/// Chiron's heliocentric state comes from a table of Chebyshev polynomials
/// fitted to JPL Horizons' heliocentric vectors of 2060 Chiron (orbit
/// solution JPL#171). Each call evaluates one 38-day record, so it takes the
/// same time anywhere in the supported span. Apparent positions add light
/// time and Earth's position.
///
/// ## Accuracy
///
/// The heliocentric position is within 10 km of every archived Horizons
/// vector across the span. Horizons' small-body integration varies with how
/// it is queried, so the gap depends on the query: 0.13 km at the 14,419
/// epochs held out of the fit, up to 2.3 km at vectors requested as time
/// lists, and up to 7.1 km at a 38-day series offset from the fit's grid.
/// That is agreement with Horizons, not the physical accuracy of its orbit
/// solution.
/// The apparent positions carry no aberration or parallax.
///
/// Calculations are supported for years 1900 through 2150. Times outside
/// this range throw ``AstronomyError/badTime``. The range is checked on the
/// time's ``AstroTime/terrestrialTime``: from 1900-01-01 00:00 UT, as TT with
/// the time's Delta T model, through 2150-01-01 00:00 UTC.
///
/// ## Example
///
/// ```swift
/// // Get Chiron's ecliptic longitude
/// let longitude = try Chiron.eclipticLongitude(at: .now)
/// print("Chiron is at \(longitude)°")
///
/// // Get Chiron's geocentric position
/// let position = try Chiron.geocentricPosition(at: .now)
/// print("Chiron position: \(position)")
/// ```
public enum Chiron {
    /// Throws unless `time`'s TT is from 1900-01-01 00:00 UT, as TT with
    /// `time`'s Delta T model, through 2150-01-01 00:00 UTC.
    ///
    /// The state depends on TT alone, so `time`'s UT is not checked. For a
    /// time made with ``AstroTime/init(tt:ut:deltaTModel:)`` it need not agree
    /// with the TT.
    ///
    /// - Throws: ``AstronomyError/badTime`` outside that span, including for
    ///   a time that is not valid.
    static func checkSupported(_ time: AstroTime) throws {
        try Engine.Chiron.checkSupported(time.engine)
    }

    // MARK: - Position Calculations

    /// Calculates Chiron's heliocentric position at a given time.
    ///
    /// Returns the position vector relative to the Sun's center.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The heliocentric position vector in AU (J2000 equatorial frame).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func heliocentricPosition(at time: AstroTime) throws -> Vector3D {
        Vector3D(try Engine.Chiron.heliocentricState(at: time.engine).position, at: time)
    }

    /// Calculates Chiron's geocentric position at a given time.
    ///
    /// Returns the position vector as seen from Earth's center,
    /// corrected for light travel time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The geocentric position vector in AU (J2000 equatorial frame).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geocentricPosition(at time: AstroTime) throws -> Vector3D {
        Vector3D(try Engine.Positions.chironGeocentricPosition(at: time.engine))
    }

    /// Calculates Chiron's geocentric state (position and velocity) at a given time.
    ///
    /// The state is geometric (instantaneous): unlike ``geocentricPosition(at:)``,
    /// it is not corrected for light travel time.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric state vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geoState(at time: AstroTime) throws -> StateVector {
        StateVector(try Engine.Positions.chironGeocentricState(at: time.engine), at: time)
    }

    /// Calculates Chiron's equatorial coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The equatorial coordinates (RA/Dec) in J2000.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func equatorial(at time: AstroTime) throws -> Equatorial {
        try geocentricPosition(at: time).toEquatorial()
    }

    /// Calculates Chiron's ecliptic longitude at a given time.
    ///
    /// This is the value commonly used in astrological calculations.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLongitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).longitude
    }

    /// Calculates Chiron's ecliptic latitude at a given time.
    ///
    /// - Parameter time: The time at which to calculate the latitude.
    /// - Returns: The ecliptic latitude in degrees (-90 to +90).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLatitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).latitude
    }

    /// Calculates Chiron's full ecliptic coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates (longitude, latitude, distance).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func ecliptic(at time: AstroTime) throws -> Ecliptic {
        try geocentricPosition(at: time).toEcliptic()
    }

    /// Calculates Chiron's horizontal coordinates for an observer.
    ///
    /// The geocentric position of ``geocentricPosition(at:)`` is rotated from
    /// the J2000 equator to the true equator and equinox of `time`, as
    /// ``CelestialBody/horizon(at:from:refraction:)`` does, before the
    /// conversion to altitude and azimuth. Like ``equatorial(at:)``, the
    /// position carries no aberration or parallax. The returned
    /// ``Horizon/rightAscension`` and ``Horizon/declination`` are on that
    /// equator of date, not J2000.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The geographic observer location.
    ///   - refraction: Atmospheric refraction correction. Defaults to `.normal`.
    /// - Returns: The horizon coordinates (altitude/azimuth).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func horizon(
        at time: AstroTime,
        from observer: Observer,
        refraction: Refraction = .normal
    ) throws -> Horizon {
        let ofDate = try geocentricPosition(at: time)
            .rotated(by: .equatorialJ2000ToEquatorialOfDate(at: time))
            .toEquatorial()
        try observer.validate()
        return Horizon(
            Engine.Horizontal(
                time: time.engine, observer: observer,
                rightAscension: ofDate.rightAscension, declination: ofDate.declination, refraction: refraction
            ))
    }
}
