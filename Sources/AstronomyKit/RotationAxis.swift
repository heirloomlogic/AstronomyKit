//
//  RotationAxis.swift
//  AstronomyKit
//
//  Planetary rotation axis calculations.
//

import Foundation

// MARK: - Rotation Axis

/// Information about a body's rotation axis orientation.
///
/// This structure describes the direction of a body's north pole and
/// the rotation angle of its prime meridian at a given time.
///
/// ## Example
///
/// ```swift
/// let axis = try CelestialBody.mars.rotationAxis(at: .now)
/// print("Mars north pole RA: \(axis.rightAscension) hours")
/// print("Prime meridian spin: \(axis.spin)°")
/// ```
public struct RotationAxis: Sendable, Equatable {
    /// The right ascension of the body's north pole in J2000 coordinates (hours).
    public let rightAscension: Double

    /// The declination of the body's north pole in J2000 coordinates (degrees).
    public let declination: Double

    /// The rotation angle of the body's prime meridian in degrees.
    ///
    /// This value increases continuously as the body rotates (or decreases
    /// for retrograde rotators such as Venus and Uranus) and does not wrap
    /// modulo 360°.
    public let spin: Double

    /// A unit vector pointing toward the body's north pole in J2000 coordinates.
    public let north: Vector3D
}

extension RotationAxis: CustomStringConvertible {
    /// A textual representation showing right ascension, declination, and spin angle of the pole.
    public var description: String {
        String(
            format: "Pole: RA %.2fh, Dec %.1f°, Spin: %.1f°",
            rightAscension,
            declination,
            spin
        )
    }
}

// MARK: - CelestialBody Extensions

extension CelestialBody {
    /// Calculates the rotation axis orientation for this body at the specified time.
    ///
    /// Returns the direction of the body's north pole and the rotation state
    /// of its prime meridian.
    ///
    /// - Parameter time: The time at which to calculate the axis orientation.
    /// - Returns: The rotation axis data.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let axis = try CelestialBody.jupiter.rotationAxis(at: .now)
    /// print("Jupiter's north pole: RA \(axis.rightAscension)h, Dec \(axis.declination)°")
    /// ```
    public func rotationAxis(at time: AstroTime) throws -> RotationAxis {
        try EngineRotationAxis.rotationAxis(of: self, at: time)
    }
}
