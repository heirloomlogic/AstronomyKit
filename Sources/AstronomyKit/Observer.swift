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
