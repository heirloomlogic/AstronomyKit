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
    init(_ raw: astro_vector_t) throws {
        if raw.status != ASTRO_SUCCESS {
            throw AstronomyError(status: raw.status) ?? .internalError
        }
        self.x = raw.x
        self.y = raw.y
        self.z = raw.z
        self.time = AstroTime(raw: raw.t)
    }

    /// The magnitude (length) of the vector in AU.
    public var magnitude: Double {
        let ax = abs(x)
        let ay = abs(y)
        let az = abs(z)
        let scale = max(ax, max(ay, az))
        guard scale.isFinite else { return scale }
        guard scale > 0 else { return 0 }
        let sx = ax / scale
        let sy = ay / scale
        let sz = az / scale
        return scale * (sx * sx + sy * sy + sz * sz).squareRoot()
    }

    /// Returns a unit vector in the same direction.
    ///
    /// Returns `self` unchanged when the magnitude is zero or non-finite, since a zero
    /// or non-finite vector has no unit direction to normalize.
    public var normalized: Vector3D {
        let length = magnitude
        guard length.isFinite, length > 0 else { return self }
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
        EngineRotation.sphereFromVector(self)
    }

    /// Converts this equatorial J2000 vector to equatorial coordinates.
    public func toEquatorial() -> Equatorial {
        EngineRotation.equatorFromVector(self)
    }

    /// Converts this equatorial J2000 vector to ecliptic coordinates.
    public func toEcliptic() throws -> Ecliptic {
        try EnginePositions.ecliptic(of: self)
    }

    /// Creates a Cartesian vector from spherical coordinates.
    public static func from(sphere: Spherical, at time: AstroTime) -> Vector3D {
        EngineRotation.vectorFromSphere(sphere, at: time)
    }

    /// Creates a Cartesian vector from horizontal coordinates.
    public static func from(
        horizon: Spherical,
        at time: AstroTime,
        refraction: Refraction = .normal
    ) -> Vector3D {
        EngineRotation.vectorFromHorizon(horizon, at: time, refraction: refraction)
    }

    /// Calculates the angle in degrees between this vector and another.
    public func angle(to other: Vector3D) throws -> Double {
        try EngineMath.angleBetween(self, other)
    }
}

extension Spherical {
    /// Creates spherical coordinates from a Cartesian vector in the horizontal frame.
    public static func fromHorizonVector(
        _ vector: Vector3D,
        refraction: Refraction = .normal
    ) -> Spherical {
        EngineRotation.horizonFromVector(vector, refraction: refraction)
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

    /// Right ascension formatted as hours:minutes:seconds.
    public var rightAscensionFormatted: String {
        guard rightAscension.isFinite else { return String(rightAscension) }
        // Round to the displayed 0.1 s precision first so that e.g. 59.96 s
        // rolls over into the next minute instead of printing "60.0s", and
        // wrap into [0, 24 h) so negative values and 24 h rollovers format cleanly.
        let wrappedHours = rightAscension.truncatingRemainder(dividingBy: 24)
        let normalizedHours = wrappedHours < 0 ? wrappedHours + 24 : wrappedHours
        var totalTenths = (normalizedHours * 36_000).rounded()
            .truncatingRemainder(dividingBy: 864_000)
        if totalTenths < 0 { totalTenths += 864_000 }
        guard totalTenths.isFinite, totalTenths >= 0, totalTenths < 864_000 else {
            return String(rightAscension)
        }
        let hours = Int(totalTenths / 36_000)
        let minutes = Int(totalTenths.truncatingRemainder(dividingBy: 36_000) / 600)
        let seconds = totalTenths.truncatingRemainder(dividingBy: 600) / 10
        return String(format: "%02dh %02dm %.1fs", hours, minutes, seconds)
    }

    /// Declination formatted as degrees:arcminutes:arcseconds.
    public var declinationFormatted: String {
        guard declination.isFinite else { return String(declination) }
        let absDeclination = abs(declination)
        // Guard against Int overflow for extreme synthetic values.
        guard absDeclination <= 1e12 else { return "\(declination)°" }
        let sign = declination >= 0 ? "+" : "-"
        // Round to the displayed 0.1" precision first so seconds cannot
        // print as "60.0" (see rightAscensionFormatted).
        let totalTenths = (absDeclination * 36_000).rounded()
        let degrees = Int(totalTenths / 36_000)
        let arcminutes = Int(totalTenths.truncatingRemainder(dividingBy: 36_000) / 600)
        let arcseconds = totalTenths.truncatingRemainder(dividingBy: 600) / 10
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
        guard azimuth.isFinite else { return directions[0] }
        // Normalize into [0, 360) so out-of-range azimuths cannot index
        // outside the table.
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
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

    /// Calculates the atmospheric refraction offset for a given altitude.
    ///
    /// Returns the angular adjustment in degrees to add to a geometric
    /// (airless) altitude to obtain the apparent altitude as seen by an
    /// observer through the atmosphere.
    ///
    /// - Parameter altitude: The geometric altitude in degrees above the horizon.
    /// - Returns: The refraction offset in degrees (always >= 0).
    public func refractionAngle(at altitude: Double) -> Double {
        EngineRotation.refraction(self, altitude: altitude)
    }

    /// Calculates the inverse atmospheric refraction for a given apparent altitude.
    ///
    /// Given an apparent (refracted) altitude, returns the angular adjustment
    /// to subtract to recover the geometric (airless) altitude.
    ///
    /// - Parameter bentAltitude: The apparent altitude in degrees (after refraction).
    /// - Returns: The inverse refraction offset in degrees.
    public func inverseRefractionAngle(at bentAltitude: Double) -> Double {
        EngineRotation.inverseRefraction(self, bentAltitude: bentAltitude)
    }
}
