//
//  Observer.swift
//  AstronomyKit
//
//  Geographic observer location.
//

import CLibAstronomy

/// A geographic location for observing celestial objects.
///
/// An `Observer` represents a point on Earth's surface from which
/// astronomical observations are made.
///
/// ## Creating Observers
///
/// ```swift
/// // New York City
/// let nyc = Observer(latitude: 40.7128, longitude: -74.0060)
///
/// // Mount Everest summit
/// let everest = Observer(
///     latitude: 27.9881,
///     longitude: 86.9250,
///     height: 8848.86
/// )
/// ```
public struct Observer: Sendable, Equatable, Hashable {
    /// The geographic latitude in degrees, ranging from -90 (south) to +90 (north).
    public let latitude: Double

    /// The geographic longitude in degrees, ranging from -180 (west) to +180 (east).
    public let longitude: Double

    /// The height above sea level in meters.
    public let height: Double

    /// Creates an observer at the specified location.
    ///
    /// - Parameters:
    ///   - latitude: Geographic latitude in degrees (-90 to +90).
    ///   - longitude: Geographic longitude in degrees (-180 to +180).
    ///   - height: Height above sea level in meters. Defaults to 0.
    public init(latitude: Double, longitude: Double, height: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.height = height
    }

    /// A geocentric observer.
    ///
    /// Uses Center geodetic: 0.0, 0.0, -6378.137 km, which places the observer at Earth's center,
    /// not on the surface.
    static let geocentric = Observer(latitude: 0, longitude: 0, height: -6_378_137)

    /// The underlying C observer structure.
    internal var raw: astro_observer_t {
        Astronomy_MakeObserver(latitude, longitude, height)
    }

    /// The local gravitational acceleration in m/s².
    ///
    /// This accounts for latitude and altitude effects on gravity.
    public var gravity: Double {
        Astronomy_ObserverGravity(latitude, height)
    }
}

// MARK: - Common Locations

extension Observer {
    /// The prime meridian at the equator (0°, 0°).
    public static let primeMeridian = Observer(latitude: 0, longitude: 0)

    /// Greenwich Observatory, UK.
    public static let greenwich = Observer(
        latitude: 51.4769,
        longitude: -0.0005,
        height: 48
    )
}

// MARK: - Codable

extension Observer: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, height
    }
}

// MARK: - CustomStringConvertible

extension Observer: CustomStringConvertible {
    public var description: String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        let lat = String(format: "%.4f°%@", abs(latitude), latDir)
        let lon = String(format: "%.4f°%@", abs(longitude), lonDir)

        if height != 0 {
            return "\(lat), \(lon), \(Int(height))m"
        }
        return "\(lat), \(lon)"
    }
}

// MARK: - Observer Vectors

extension Observer {
    /// The coordinate frame for observer vectors.
    public enum EquatorFrame: Sendable {
        /// J2000 equatorial coordinates.
        case j2000

        /// Equatorial coordinates of the specified date.
        case ofDate

        internal var raw: astro_equator_date_t {
            switch self {
            case .j2000: return EQUATOR_J2000
            case .ofDate: return EQUATOR_OF_DATE
            }
        }
    }

    /// Returns this observer's position as a vector.
    ///
    /// The position is relative to Earth's center in the specified
    /// equatorial coordinate frame.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - equator: The coordinate frame (.j2000 or .ofDate).
    /// - Returns: The position vector in AU.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func vector(at time: AstroTime, equator: EquatorFrame = .j2000) throws -> Vector3D {
        var t = time.raw
        let result = Astronomy_ObserverVector(&t, raw, equator.raw)
        return try Vector3D(result)
    }

    /// Returns this observer's complete state (position and velocity).
    ///
    /// The state is relative to Earth's center in the specified
    /// equatorial coordinate frame.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the state.
    ///   - equator: The coordinate frame (.j2000 or .ofDate).
    /// - Returns: The state vector with position in AU and velocity in AU/day.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func state(at time: AstroTime, equator: EquatorFrame = .j2000) throws -> StateVector {
        var t = time.raw
        let result = Astronomy_ObserverState(&t, raw, equator.raw)
        return try StateVector(result)
    }
}
