//
//  EngineStar.swift
//  AstronomyKit
//
//  Immutable fixed-star definitions and native position calculations.
//

import Foundation

extension Engine {
    /// A fixed star at a catalog position on the mean equator and equinox of J2000.
    struct Star: Equatable, Hashable, Sendable {
        /// The C engine's conversion, retained as part of the fixed-star distance contract.
        static let astronomicalUnitsPerLightYear = 63_241.077_088_075_46

        /// Right ascension in sidereal hours on the J2000 equator.
        let rightAscension: Double

        /// Declination in degrees on the J2000 equator.
        let declination: Double

        /// Distance from the Sun in light-years.
        let distance: Double

        /// The star's fixed heliocentric position on J2000 axes.
        func heliocentricPosition(at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
            try validate()
            try Engine.checkAcceptedTime(time)
            let sphere = Engine.Spherical(
                latitude: declination,
                longitude: 15 * rightAscension,
                distance: distance * Self.astronomicalUnitsPerLightYear
            )
            return try Engine.Positions.checked(Engine.Vector(sphere, time: time))
        }

        /// The star's position relative to Earth on J2000 axes.
        func geocentricPosition(at time: Engine.Time, aberration: Aberration) throws -> Engine.Vector<Engine.EQJ> {
            let star = try heliocentricPosition(at: time)
            let corrected: SIMD3<Double>
            switch aberration {
            case .none:
                let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
                corrected = SIMD3(star.x - earth.x, star.y - earth.y, star.z - earth.z)
            case .corrected:
                let earth = try Engine.Planet.earth.heliocentricState(at: time)
                let position = SIMD3(star.x - earth.x, star.y - earth.y, star.z - earth.z)
                let distance = (position * position).sum().squareRoot()
                corrected = position + earth.velocityVector * (distance / Engine.speedOfLightAUPerDay)
            }
            return try Engine.Positions.checked(
                Engine.Vector(x: corrected.x, y: corrected.y, z: corrected.z, time: time)
            )
        }

        /// The apparent topocentric coordinates on the requested equator.
        func equatorial(
            at time: Engine.Time,
            from observer: Observer,
            equatorDate: EquatorDate
        ) throws -> Engine.Equatorial {
            try validate()
            try Self.validate(observer)
            let site = Engine.Observers.vector(observer, at: time)
            let geocentric = try geocentricPosition(at: time, aberration: .corrected)
            let j2000 = Engine.Vector<Engine.EQJ>(
                x: geocentric.x - site.x,
                y: geocentric.y - site.y,
                z: geocentric.z - site.z,
                time: time
            )
            let result =
                switch equatorDate {
                case .j2000:
                    try Engine.Positions.coordinates(j2000)
                case .ofDate:
                    try Engine.Positions.coordinates(Engine.FrameRotation.eqjToEqd(time).apply(to: j2000))
                }
            guard result.rightAscension.isFinite, result.declination.isFinite, result.distance.isFinite else {
                throw AstronomyError.badTime
            }
            return result
        }

        /// The apparent geocentric coordinates on the true ecliptic and equinox of date.
        func ecliptic(at time: Engine.Time) throws -> Engine.Ecliptic {
            let result = Engine.Ecliptic(try geocentricPosition(at: time, aberration: .corrected))
            guard result.vector.x.isFinite, result.vector.y.isFinite, result.vector.z.isFinite,
                result.latitude.isFinite, result.longitude.isFinite
            else { throw AstronomyError.badTime }
            return result
        }

        /// The apparent topocentric coordinates in an observer's sky.
        func horizontal(
            at time: Engine.Time,
            from observer: Observer,
            refraction: Refraction
        ) throws -> Engine.Horizontal {
            let equatorial = try equatorial(at: time, from: observer, equatorDate: .ofDate)
            return Engine.Horizontal(
                time: time,
                observer: observer,
                rightAscension: equatorial.rightAscension,
                declination: equatorial.declination,
                refraction: refraction
            )
        }

        /// Checks the public fixed-star catalog limits.
        private func validate() throws {
            guard rightAscension.isFinite, (0..<24).contains(rightAscension), declination.isFinite,
                (-90...90).contains(declination), distance.isFinite, distance >= 1
            else { throw AstronomyError.invalidParameter }
        }

        /// Checks the public observer limits without constructing a C observer.
        private static func validate(_ observer: Observer) throws {
            guard observer.latitude.isFinite, observer.longitude.isFinite, observer.height.isFinite,
                (-90...90).contains(observer.latitude)
            else { throw AstronomyError.invalidParameter }
        }
    }
}
