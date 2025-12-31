//
//  Coordinates.swift
//  AstronomyKit
//
//  Coordinate types for astronomical calculations.
//

import CLibAstronomy

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
        guard magnitude > 0 else { return self }
        return Vector3D(x: x / magnitude, y: y / magnitude, z: z / magnitude, time: time)
    }
}

extension Vector3D: CustomStringConvertible {
    public var description: String {
        String(format: "(%.6f, %.6f, %.6f) AU", x, y, z)
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
    public var description: String {
        "RA: \(rightAscensionFormatted), Dec: \(declinationFormatted)"
    }
}

// MARK: - Ecliptic

/// Ecliptic coordinates referenced to the true equinox of date.
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
        self.distance = raw.vec.x * raw.vec.x + raw.vec.y * raw.vec.y + raw.vec.z * raw.vec.z
    }
}

extension Ecliptic: CustomStringConvertible {
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
    public init(altitude: Double, azimuth: Double, rightAscension: Double = 0, declination: Double = 0) {
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
    public var description: String {
        let status = isAboveHorizon ? "↑" : "↓"
        return String(format: "%@ Alt: %.1f°, Az: %.1f° (%@)",
                      status, altitude, azimuth, compassDirection)
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
}
