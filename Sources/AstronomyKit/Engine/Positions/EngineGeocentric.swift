//
//  EngineGeocentric.swift
//  AstronomyKit
//
//  Positions of one body seen from another, corrected for light travel
//  time and optionally for aberration, and geocentric positions.
//

import Foundation

extension Engine.Positions {
    /// The position of `target` relative to `observer` at the time light left
    /// `target`, for light that reaches `observer` at `time`: the C engine's
    /// `Astronomy_BackdatePosition`.
    ///
    /// ``Engine/LightTravel/correct(at:_:)`` finds the light time from
    /// heliocentric positions. With `.none` the observer stays where it is at
    /// `time`. With `.corrected` it is backdated with the target, which
    /// approximates aberration to first order: in the light time the observer
    /// moves by its velocity times that time, which turns the direction by
    /// the observer's transverse speed over the speed of light. The vector's
    /// time is the backdated time.
    ///
    /// - Throws: As ``heliocentricPosition(of:at:)`` for either body at any
    ///   time the iteration reaches, the observer first; the errors of
    ///   ``Engine/LightTravel/correct(at:_:)``; and `AstronomyError.badTime`
    ///   for a result that is not finite.
    static func backdatedPosition(
        of target: CelestialBody, seenFrom observer: CelestialBody, at time: Engine.Time,
        aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ> {
        let fixedObserver = aberration == .none ? try heliocentricPosition(of: observer, at: time) : nil
        let vector = try Engine.LightTravel.correct(at: time) { backdated in
            let origin = try fixedObserver ?? heliocentricPosition(of: observer, at: backdated)
            let position = try heliocentricPosition(of: target, at: backdated)
            return Engine.Vector<Engine.EQJ>(
                x: position.x - origin.x, y: position.y - origin.y, z: position.z - origin.z,
                time: backdated)
        }
        return try checked(vector)
    }

    /// The position of `body` relative to Earth's center as seen at `time`,
    /// the C engine's `Astronomy_GeoVector`.
    ///
    /// Earth is at the origin. The Moon is ``Engine/Moon/geocentricPosition(at:cache:)``
    /// with no light-time correction and no aberration, whatever `aberration`
    /// says. Every other body is ``backdatedPosition(of:seenFrom:at:aberration:)``
    /// seen from Earth. The vector's time is `time`, not the backdated time.
    ///
    /// - Throws: `AstronomyError.badTime` for a TT beyond
    ///   ``Engine/acceptedTTDays`` or not finite, before anything else; then
    ///   as ``backdatedPosition(of:seenFrom:at:aberration:)``.
    static func geocentricPosition(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        var vector: Engine.Vector<Engine.EQJ>
        switch body {
        case .earth:
            vector = Engine.Vector(x: 0, y: 0, z: 0, time: time)
        case .moon:
            vector = try Engine.Moon.geocentricPosition(at: time)
        default:
            vector = try backdatedPosition(of: body, seenFrom: .earth, at: time, aberration: aberration)
        }
        vector.time = time
        return try checked(vector)
    }
}
