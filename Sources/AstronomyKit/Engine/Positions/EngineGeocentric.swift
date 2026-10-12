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
        let kinematics: Engine.ApparentPlace.Kinematics
        if observer == .earth {
            kinematics = try Engine.ApparentPlace.earthBarycentricKinematics(tt: time.tt)
        } else {
            // This API returns a position only; acceleration does not enter its value.
            kinematics = try Engine.ApparentPlace.Kinematics(
                motion: Engine.ApparentPlace.bodyMotion(observer, tt: time.tt), acceleration: .zero)
        }
        if target == observer { return Engine.Vector(x: 0, y: 0, z: 0, time: time) }
        let result = try Engine.ApparentPlace.solution(
            body: target, at: time, observer: kinematics, aberration: aberration)
        guard let model = time.deltaTModel else { throw AstronomyError.badTime }
        let emission = Engine.Time(tt: result.emissionTT, deltaTModel: model)
        return try checked(
            Engine.Vector(
                x: result.motion.value.x, y: result.motion.value.y, z: result.motion.value.z, time: emission))
    }

    /// Astrometric or apparent position relative to Earth's center, at the reception time.
    ///
    /// Earth remains the zero vector. Every other supported body, including the Moon, uses the shared barycentric light-time and angular-correction model. Explicit geometric Moon APIs remain geometric.
    static func geocentricPosition(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        if body == .earth { return Engine.Vector(x: 0, y: 0, z: 0, time: time) }
        let motion = try Engine.ApparentPlace.geocentricMotion(body: body, at: time, aberration: aberration)
        return try checked(Engine.Vector(x: motion.value.x, y: motion.value.y, z: motion.value.z, time: time))
    }
}
