//
//  EngineEclipticState.swift
//  AstronomyKit
//
//  A position and velocity on the true ecliptic and equinox of date, and
//  the rotation from an equator to an ecliptic with its rate.
//

import Foundation

extension Engine {
    /// A position and velocity on the true ecliptic and equinox of date, with
    /// the spherical coordinates and their rates.
    struct EclipticState: Sendable {
        /// Position in AU and velocity in AU per TT day.
        var state: State<ECT>
        /// Longitude in [0, 360) and latitude, in degrees.
        var longitude: Double
        var latitude: Double
        /// Distance in AU.
        var distance: Double
        /// Rates in degrees, and AU, per TT day.
        var longitudeRate: Double
        var latitudeRate: Double
        var distanceRate: Double
    }
}

extension Engine.EclipticState {
    /// `state` with its longitude, latitude, distance and distance rate,
    /// and the longitude and latitude rates in degrees per TT day worked out
    /// from its position and velocity.
    ///
    /// - Throws: `AstronomyError.badVector` when the position has no
    ///   component in the ecliptic plane; `AstronomyError.badTime` when a
    ///   coordinate or rate is not finite.
    init(
        state: Engine.State<Engine.ECT>, longitude: Double, latitude: Double, distance: Double, distanceRate: Double
    ) throws {
        let (x, y, z) = (state.x, state.y, state.z)
        let rho2 = x * x + y * y
        guard rho2 > 0 else { throw AstronomyError.badVector }
        let rho = rho2.squareRoot()
        let rhoRate = (x * state.vx + y * state.vy) / rho
        self.init(
            state: state,
            longitude: longitude,
            latitude: latitude,
            distance: distance,
            longitudeRate: Engine.degreesPerRadian * (x * state.vy - y * state.vx) / rho2,
            latitudeRate: Engine.degreesPerRadian * (rho * state.vz - z * rhoRate) / (rho2 + z * z),
            distanceRate: distanceRate)
        let values = [self.longitude, self.latitude, self.distance, longitudeRate, latitudeRate, distanceRate]
        guard values.allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
    }
}

extension Engine {
    /// R1(ε): from an equator to an ecliptic `obliquity` degrees from it,
    /// built as ``Engine/FrameRotation`` builds its ecliptic rotations.
    static func tilted<From, To>(by obliquity: Double) -> Engine.Rotation<From, To> {
        let radians = obliquity * Engine.radiansPerDegree
        let c = cos(radians)
        let s = sin(radians)
        return Engine.Rotation(rot: ((1, 0, 0), (0, c, -s), (0, s, c)))
    }

    /// The derivative per TT day of ``tilted(by:)`` when the obliquity
    /// changes by `rate` degrees per TT day.
    static func tiltRate<From, To>(by obliquity: Double, rate: Double) -> Engine.RotationRate<From, To> {
        let radians = obliquity * Engine.radiansPerDegree
        let radiansRate = rate * Engine.radiansPerDegree
        let c = cos(radians) * radiansRate
        let s = sin(radians) * radiansRate
        return Engine.RotationRate(rot: ((0, 0, 0), (0, -s, -c), (0, c, -s)))
    }
}
