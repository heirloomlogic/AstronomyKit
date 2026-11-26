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
        let (earth, sun) = try Engine.ApparentPlace.earthAndSunBarycentricMotion(tt: time.tt)
        let site = try Engine.ApparentPlace.siteMotion(observer, at: time)
        let position = try Engine.ApparentPlace.positionSolution(
            body: body, at: time, observerMotion: earth + site, sunMotion: sun, aberration: aberration
        ).position
        let j2000 = Engine.Vector<Engine.EQJ>(
            x: position.x, y: position.y, z: position.z, time: time)
        let equatorial =
            switch equatorDate {
            case .j2000: try coordinates(j2000)
            case .ofDate: try coordinates(Engine.FrameRotation.eqjToEqd(time).apply(to: j2000))
            }
        guard equatorial.rightAscension.isFinite, equatorial.declination.isFinite, equatorial.distance.isFinite else {
            throw AstronomyError.badTime
        }
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
