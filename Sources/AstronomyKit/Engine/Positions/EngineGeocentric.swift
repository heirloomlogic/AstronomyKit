//
//  EngineGeocentric.swift
//  AstronomyKit
//
//  Positions of one body seen from another, corrected for light travel
//  time and optionally for aberration, and geocentric positions.
//

import Foundation

extension Engine.Positions {
    /// Barycentric elapsed-TDB light time, with the observer fixed at reception.
    ///
    /// `.none` returns astrometric place. `.corrected` adds finite-source solar deflection and relativistic aberration. The vector retains emission-time metadata; the direction is expressed on fixed EQJ axes.
    static func backdatedPosition(
        of target: CelestialBody, seenFrom observer: CelestialBody, at time: Engine.Time,
        aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        let observerMotion: Engine.ApparentPlace.VectorRate
        let sunMotion: Engine.ApparentPlace.VectorRate?
        if observer == .earth {
            let (earth, sun) = try Engine.ApparentPlace.earthAndSunBarycentricMotion(tt: time.tt)
            observerMotion = earth
            sunMotion = sun
        } else {
            observerMotion = try Engine.ApparentPlace.bodyMotion(observer, tt: time.tt)
            sunMotion = nil
        }
        if target == observer { return Engine.Vector(x: 0, y: 0, z: 0, time: time) }
        let result = try Engine.ApparentPlace.positionSolution(
            body: target, at: time, observerMotion: observerMotion, sunMotion: sunMotion, aberration: aberration)
        guard let model = time.deltaTModel else { throw AstronomyError.badTime }
        let emission = Engine.Time(tt: result.emissionTT, deltaTModel: model)
        return try checked(
            Engine.Vector(
                x: result.position.x, y: result.position.y, z: result.position.z, time: emission))
    }

    /// Astrometric or apparent position relative to Earth's center, at the reception time.
    ///
    /// Earth remains the zero vector. Every other supported body, including the Moon, uses the shared barycentric light-time and angular-correction model. Explicit geometric Moon APIs remain geometric.
    static func geocentricPosition(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        if body == .earth { return Engine.Vector(x: 0, y: 0, z: 0, time: time) }
        let position = try Engine.ApparentPlace.geocentricPositionValue(
            body: body, at: time, aberration: aberration)
        return try checked(Engine.Vector(x: position.x, y: position.y, z: position.z, time: time))
    }
}
