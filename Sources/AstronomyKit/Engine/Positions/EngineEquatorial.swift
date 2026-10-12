//
//  EngineEquatorial.swift
//  AstronomyKit
//
//  Topocentric equatorial coordinates of a body, on the J2000 equator or
//  the true equator of date, and its place in an observer's sky.
//

import Foundation

extension Engine.Positions {
    /// Apparent or astrometric coordinates from the observer's reception position, velocity and acceleration. Site parallax participates in the light-time solve; corrected mode includes diurnal aberration before the requested frame rotation.
    ///
    /// The public layer validates the observer. A zero displacement, including Earth from its center, throws `badVector`; unsupported bodies throw `invalidBody` after the accepted-time check.
    static func equatorial(
        of body: CelestialBody, at time: Engine.Time, from observer: Observer, equatorDate: EquatorDate,
        aberration: Aberration
    ) throws -> Engine.Equatorial {
        try Engine.checkAcceptedTime(time)
        let earth = try Engine.ApparentPlace.earthBarycentricKinematics(tt: time.tt)
        let site = try Engine.ApparentPlace.siteKinematics(observer, at: time)
        let origin = Engine.ApparentPlace.Kinematics(
            motion: earth.motion + site.motion, acceleration: earth.acceleration + site.acceleration)
        let motion = try Engine.ApparentPlace.solution(
            body: body, at: time, observer: origin, aberration: aberration
        ).motion
        let j2000 = Engine.Vector<Engine.EQJ>(
            x: motion.value.x, y: motion.value.y, z: motion.value.z, time: time)
        let equatorial =
            switch equatorDate {
            case .j2000: try coordinates(j2000)
            case .ofDate: try coordinates(Engine.FrameRotation.eqjToEqd(time).apply(to: j2000))
            }
        let values = [equatorial.rightAscension, equatorial.declination, equatorial.distance]
        guard values.allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
        return equatorial
    }

    /// Where `body` appears in `observer`'s sky, as the public
    /// `CelestialBody.horizon(at:from:refraction:)` finds it: the equatorial
    /// coordinates of date with aberration, through ``Engine/Horizontal``.
    ///
    /// - Throws: As ``equatorial(of:at:from:equatorDate:aberration:)``.
    static func horizontal(
        of body: CelestialBody, at time: Engine.Time, from observer: Observer, refraction: Refraction
    ) throws -> Engine.Horizontal {
        let equatorial = try equatorial(
            of: body, at: time, from: observer, equatorDate: .ofDate, aberration: .corrected)
        return Engine.Horizontal(
            time: time, observer: observer, rightAscension: equatorial.rightAscension,
            declination: equatorial.declination, refraction: refraction)
    }

    /// `Engine.Equatorial` of `vector`, with the C engine's `badVector` for a
    /// zero vector where ``Engine/Spherical`` throws `invalidParameter`.
    static func coordinates<F>(_ vector: Engine.Vector<F>) throws -> Engine.Equatorial {
        guard vector.x != 0 || vector.y != 0 || vector.z != 0 else { throw AstronomyError.badVector }
        return try Engine.Equatorial(vector)
    }
}
