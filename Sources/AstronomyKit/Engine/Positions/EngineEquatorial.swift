//
//  EngineEquatorial.swift
//  AstronomyKit
//
//  Topocentric equatorial coordinates of a body, on the J2000 equator or
//  the true equator of date, and its place in an observer's sky.
//

import Foundation

extension Engine.Positions {
    /// The right ascension, declination and distance of `body` seen from
    /// `observer`, the C engine's `Astronomy_Equator`.
    ///
    /// The vector is ``geocentricPosition(of:at:aberration:)`` less the
    /// observer's J2000 position, ``Engine/Observers/vector(_:at:)``, and
    /// with `.ofDate` it is then rotated to the true equator of date. The
    /// public layer validates the observer.
    ///
    /// - Throws: As ``geocentricPosition(of:at:aberration:)``;
    ///   `AstronomyError.badVector` for a zero vector, which Earth gives from
    ///   the geocentric observer; `AstronomyError.badTime` for a result that
    ///   is not finite.
    static func equatorial(
        of body: CelestialBody, at time: Engine.Time, from observer: Observer, equatorDate: EquatorDate,
        aberration: Aberration
    ) throws -> Engine.Equatorial {
        let site = Engine.Observers.vector(observer, at: time)
        let geocentric = try geocentricPosition(of: body, at: time, aberration: aberration)
        let j2000 = Engine.Vector<Engine.EQJ>(
            x: geocentric.x - site.x, y: geocentric.y - site.y, z: geocentric.z - site.z, time: time)
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
