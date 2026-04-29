//
//  Coordinates.swift
//  AstronomyKit
//
//  Coordinate types for astronomical calculations.
//

import CLibAstronomy
import Foundation

// MARK: - Vector3D

/// A 3D Cartesian vector in astronomical units (AU).
public struct Vector3D: Sendable, Equatable, Hashable {
    /// The x-coordinate in AU.
    public let x: Double

    /// The y-coordinate in AU.
    public let y: Double

    /// The z-coordinate in AU.
    public let z: Double

    /// The time at which this vector is valid.
    public let time: AstroTime

    /// Creates a vector with the specified components.
    public init(x: Double, y: Double, z: Double, time: AstroTime) {
        self.x = x
        self.y = y
        self.z = z
        self.time = time
    }

    /// Creates a vector from the C structure.
    internal init(_ raw: astro_vector_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.x = raw.x
        self.y = raw.y
        self.z = raw.z
        self.time = AstroTime(raw: raw.t)
    }

    /// The magnitude (length) of the vector in AU.
    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// Returns a unit vector in the same direction.
    public var normalized: Vector3D {
        let length = magnitude
        guard length > 0 else { return self }
        return Vector3D(x: x / length, y: y / length, z: z / length, time: time)
    }
}

extension Vector3D: CustomStringConvertible {
    /// A textual representation of the vector in AU.
    public var description: String {
        String(format: "(%.6f, %.6f, %.6f) AU", x, y, z)
    }
}

// MARK: - Vector Conversions

extension Vector3D {
    /// Converts this Cartesian vector to spherical coordinates.
    public func toSpherical() -> Spherical {
        let raw = astro_vector_t(status: ASTRO_SUCCESS, x: x, y: y, z: z, t: time.raw)
        let result = Astronomy_SphereFromVector(raw)
        return Spherical(latitude: result.lat, longitude: result.lon, distance: result.dist)
    }

    /// Converts this equatorial J2000 vector to equatorial coordinates.
    public func toEquatorial() -> Equatorial {
        let raw = astro_vector_t(status: ASTRO_SUCCESS, x: x, y: y, z: z, t: time.raw)
        let result = Astronomy_EquatorFromVector(raw)
        return Equatorial(
            rightAscension: result.ra,
            declination: result.dec,
            distance: result.dist,
            time: time
        )
    }

    /// Converts this equatorial J2000 vector to ecliptic coordinates.
    public func toEcliptic() throws -> Ecliptic {
        let raw = astro_vector_t(status: ASTRO_SUCCESS, x: x, y: y, z: z, t: time.raw)
        let result = Astronomy_Ecliptic(raw)
        return try Ecliptic(result)
    }

    /// Creates a Cartesian vector from spherical coordinates.
    public static func from(sphere: Spherical, at time: AstroTime) -> Vector3D {
        let raw = astro_spherical_t(
            status: ASTRO_SUCCESS,
            lat: sphere.latitude,
            lon: sphere.longitude,
            dist: sphere.distance
        )
        let result = Astronomy_VectorFromSphere(raw, time.raw)
        return Vector3D(x: result.x, y: result.y, z: result.z, time: time)
    }

    /// Creates a Cartesian vector from horizontal coordinates.
    public static func from(
        horizon: Spherical,
        at time: AstroTime,
        refraction: Refraction = .normal
    ) -> Vector3D {
        let raw = astro_spherical_t(
            status: ASTRO_SUCCESS,
            lat: horizon.latitude,
            lon: horizon.longitude,
            dist: horizon.distance
        )
        let result = Astronomy_VectorFromHorizon(raw, time.raw, refraction.raw)
        return Vector3D(x: result.x, y: result.y, z: result.z, time: time)
    }

    /// Calculates the angle in degrees between this vector and another.
    public func angle(to other: Vector3D) throws -> Double {
        let rawA = astro_vector_t(status: ASTRO_SUCCESS, x: x, y: y, z: z, t: time.raw)
        let rawB = astro_vector_t(status: ASTRO_SUCCESS, x: other.x, y: other.y, z: other.z, t: other.time.raw)
        let result = Astronomy_AngleBetween(rawA, rawB)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.angle
    }
}

extension Spherical {
    /// Creates spherical coordinates from a Cartesian vector in the horizontal frame.
    public static func fromHorizonVector(
        _ vector: Vector3D,
        refraction: Refraction = .normal
    ) -> Spherical {
        let raw = astro_vector_t(status: ASTRO_SUCCESS, x: vector.x, y: vector.y, z: vector.z, t: vector.time.raw)
        let result = Astronomy_HorizonFromVector(raw, refraction.raw)
        return Spherical(latitude: result.lat, longitude: result.lon, distance: result.dist)
    }
}

// MARK: - Spherical

/// Spherical coordinates (latitude, longitude, distance).
public struct Spherical: Sendable, Equatable, Hashable {
    /// The latitude angle in degrees (-90 to +90).
    public let latitude: Double

    /// The longitude angle in degrees (0 to 360).
    public let longitude: Double

    /// The distance in AU.
    public let distance: Double

    /// Creates spherical coordinates.
    public init(latitude: Double, longitude: Double, distance: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.distance = distance
    }

    /// Creates coordinates from the C structure.
    internal init(_ raw: astro_spherical_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.latitude = raw.lat
        self.longitude = raw.lon
        self.distance = raw.dist
    }
}

extension Spherical: CustomStringConvertible {
    /// A textual representation showing latitude, longitude, and distance.
    public var description: String {
        String(format: "lat: %.2f°, lon: %.2f°, dist: %.4f AU", latitude, longitude, distance)
    }
}

// MARK: - Equatorial

/// Equatorial coordinates (right ascension and declination).
///
/// These coordinates are commonly used in astronomy to specify the
/// position of objects on the celestial sphere.
public struct Equatorial: Sendable, Equatable, Hashable {
    /// Right ascension in sidereal hours (0 to 24).
    public let rightAscension: Double

    /// Declination in degrees (-90 to +90).
    public let declination: Double

    /// Distance from the observer in AU.
    public let distance: Double

    /// The time at which these coordinates are valid.
    public let time: AstroTime

    /// Creates equatorial coordinates.
    public init(rightAscension: Double, declination: Double, distance: Double, time: AstroTime) {
        self.rightAscension = rightAscension
        self.declination = declination
        self.distance = distance
        self.time = time
    }

    /// Creates coordinates from the C structure.
    internal init(_ raw: astro_equatorial_t, time: AstroTime) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.rightAscension = raw.ra
        self.declination = raw.dec
        self.distance = raw.dist
        self.time = time
    }

    /// Right ascension formatted as hours:minutes:seconds.
    public var rightAscensionFormatted: String {
        let totalSeconds = rightAscension * 3_600
        let hours = Int(totalSeconds / 3_600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3_600)) / 60)
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02dh %02dm %.1fs", hours, minutes, seconds)
    }

    /// Declination formatted as degrees:arcminutes:arcseconds.
    public var declinationFormatted: String {
        let sign = declination >= 0 ? "+" : "-"
        let totalArcseconds = abs(declination) * 3_600
        let degrees = Int(totalArcseconds / 3_600)
        let arcminutes = Int((totalArcseconds.truncatingRemainder(dividingBy: 3_600)) / 60)
        let arcseconds = totalArcseconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%@%02d° %02d' %.1f\"", sign, degrees, arcminutes, arcseconds)
    }
}

extension Equatorial: CustomStringConvertible {
    /// A textual representation showing formatted right ascension and declination.
    public var description: String {
        "RA: \(rightAscensionFormatted), Dec: \(declinationFormatted)"
    }
}

// MARK: - Ecliptic

/// Ecliptic coordinates (latitude, longitude, distance).
public struct Ecliptic: Sendable, Equatable, Hashable {
    /// Ecliptic latitude in degrees (-90 to +90).
    public let latitude: Double

    /// Ecliptic longitude in degrees (0 to 360).
    public let longitude: Double

    /// Distance in AU.
    public let distance: Double

    /// Creates ecliptic coordinates.
    public init(latitude: Double, longitude: Double, distance: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.distance = distance
    }

    /// Creates coordinates from the C structure.
    internal init(_ raw: astro_ecliptic_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.latitude = raw.elat
        self.longitude = raw.elon
        self.distance = sqrt(raw.vec.x * raw.vec.x + raw.vec.y * raw.vec.y + raw.vec.z * raw.vec.z)
    }
}

extension Ecliptic: CustomStringConvertible {
    /// A textual representation showing ecliptic longitude and latitude.
    public var description: String {
        String(format: "λ: %.2f°, β: %.2f°", longitude, latitude)
    }
}

// MARK: - Horizon

/// Horizontal coordinates (altitude and azimuth) for an observer on Earth.
///
/// These coordinates describe where an object appears in the local sky.
public struct Horizon: Sendable, Equatable, Hashable {
    /// Altitude above the horizon in degrees (-90 to +90).
    ///
    /// Positive values indicate the object is above the horizon.
    /// Negative values indicate it is below the horizon.
    public let altitude: Double

    /// Azimuth angle in degrees (0 to 360).
    ///
    /// Measured clockwise from north: 0° = North, 90° = East,
    /// 180° = South, 270° = West.
    public let azimuth: Double

    /// Right ascension in sidereal hours.
    public let rightAscension: Double

    /// Declination in degrees.
    public let declination: Double

    /// Creates horizon coordinates.
    public init(
        altitude: Double,
        azimuth: Double,
        rightAscension: Double = 0,
        declination: Double = 0
    ) {
        self.altitude = altitude
        self.azimuth = azimuth
        self.rightAscension = rightAscension
        self.declination = declination
    }

    /// Creates coordinates from the C structure.
    internal init(_ raw: astro_horizon_t) {
        self.altitude = raw.altitude
        self.azimuth = raw.azimuth
        self.rightAscension = raw.ra
        self.declination = raw.dec
    }

    /// Whether the object is currently above the horizon.
    public var isAboveHorizon: Bool {
        altitude > 0
    }

    /// The cardinal/intercardinal direction name for the azimuth.
    public var compassDirection: String {
        let directions = [
            "N",
            "NNE",
            "NE",
            "ENE",
            "E",
            "ESE",
            "SE",
            "SSE",
            "S",
            "SSW",
            "SW",
            "WSW",
            "W",
            "WNW",
            "NW",
            "NNW",
        ]
        let index = Int((azimuth + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[index]
    }
}

extension Horizon: CustomStringConvertible {
    /// A textual representation showing altitude, azimuth, and compass direction.
    public var description: String {
        let status = isAboveHorizon ? "↑" : "↓"
        return String(
            format: "%@ Alt: %.1f°, Az: %.1f° (%@)",
            status,
            altitude,
            azimuth,
            compassDirection
        )
    }
}

// MARK: - Refraction

/// Atmospheric refraction correction modes.
public enum Refraction: Sendable {
    /// No atmospheric refraction correction (airless).
    case none

    /// Standard atmospheric refraction correction.
    case normal

    /// JPL Horizons compatibility mode.
    case jplHorizons

    internal var raw: astro_refraction_t {
        switch self {
        case .none: return REFRACTION_NONE
        case .normal: return REFRACTION_NORMAL
        case .jplHorizons: return REFRACTION_JPLHOR
        }
    }

    /// Calculates the atmospheric refraction offset for a given altitude.
    ///
    /// Returns the angular adjustment in degrees to add to a geometric
    /// (airless) altitude to obtain the apparent altitude as seen by an
    /// observer through the atmosphere.
    ///
    /// - Parameter altitude: The geometric altitude in degrees above the horizon.
    /// - Returns: The refraction offset in degrees (always >= 0).
    public func refractionAngle(at altitude: Double) -> Double {
        Astronomy_Refraction(raw, altitude)
    }

    /// Calculates the inverse atmospheric refraction for a given apparent altitude.
    ///
    /// Given an apparent (refracted) altitude, returns the angular adjustment
    /// to subtract to recover the geometric (airless) altitude.
    ///
    /// - Parameter bentAltitude: The apparent altitude in degrees (after refraction).
    /// - Returns: The inverse refraction offset in degrees.
    public func inverseRefractionAngle(at bentAltitude: Double) -> Double {
        Astronomy_InverseRefraction(raw, bentAltitude)
    }
}
