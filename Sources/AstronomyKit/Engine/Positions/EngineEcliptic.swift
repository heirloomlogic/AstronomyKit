//
//  EngineEcliptic.swift
//  AstronomyKit
//
//  Geocentric states, and positions and states on the true ecliptic and
//  equinox of date: the Sun's, the bodies' apparent ones and heliocentric
//  longitudes.
//

import Foundation

extension Engine.Positions {
    /// The heliocentric longitude of `body` in degrees on the true ecliptic
    /// and equinox of date, in [0, 360): the C engine's
    /// `Astronomy_EclipticLongitude`.
    ///
    /// - Throws: `AstronomyError.invalidBody` for the Sun, before anything
    ///   else; then as ``heliocentricPosition(of:at:)``.
    static func eclipticLongitude(of body: CelestialBody, at time: Engine.Time) throws -> Double {
        guard body != .sun else { throw AstronomyError.invalidBody }
        return Engine.Ecliptic(try heliocentricPosition(of: body, at: time)).longitude
    }

    /// The Sun's geocentric position on the true ecliptic and equinox of
    /// date, the C engine's `Astronomy_SunPosition`.
    ///
    /// The Sun is Earth's heliocentric position negated, both taken one
    /// astronomical unit's light time before `time`, and the ecliptic of date
    /// is the one at that earlier time. The vector's time is `time`.
    ///
    /// - Throws: `AstronomyError.badTime` when the earlier time is beyond
    ///   ``Engine/acceptedTTDays`` or not finite, or for a result that is not
    ///   finite.
    static func sunPosition(at time: Engine.Time) throws -> Engine.Ecliptic {
        let adjusted = sunLightTime(time)
        let earth = try Engine.Planet.earth.heliocentricPosition(at: adjusted)
        var ecliptic = Engine.Ecliptic(Engine.Vector(x: -earth.x, y: -earth.y, z: -earth.z, time: adjusted))
        ecliptic.vector = try checked(ecliptic.vector)
        ecliptic.vector.time = time
        guard ecliptic.longitude.isFinite, ecliptic.latitude.isFinite else { throw AstronomyError.badTime }
        return ecliptic
    }

    /// The position and velocity of `body` relative to Earth's center, on EQJ
    /// axes, as ``geocentricPosition(of:at:aberration:)`` sees it: the state
    /// behind the C engine's `Astronomy_GeoEclipticState`.
    ///
    /// The position is the same double as
    /// ``geocentricPosition(of:at:aberration:)``'s; the Moon's state is
    /// ``Engine/Moon/geocentricState(at:cache:)``. For a backdated body the
    /// velocity is the derivative of the converged light-time solution
    /// τ = |p(t − τ)| / c by implicit differentiation, so it does not depend
    /// on how many iterations ran. Rates are per TT day with Delta T held
    /// fixed.
    ///
    /// The bodies are the Sun, the Moon, Mercury to Neptune except Earth, and
    /// Pluto.
    ///
    /// - Throws: `AstronomyError.badTime` for a TT beyond
    ///   ``Engine/acceptedTTDays`` or not finite; then
    ///   `AstronomyError.invalidBody` for any other body; then as
    ///   ``backdatedPosition(of:seenFrom:at:aberration:)`` and
    ///   ``heliocentricState(of:at:)`` at the backdated time.
    static func geocentricState(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.State<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        switch body {
        case .moon:
            return try Engine.Moon.geocentricState(at: time)
        case .sun, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
            break
        default:
            throw AstronomyError.invalidBody
        }
        let vector = try backdatedPosition(of: body, seenFrom: .earth, at: time, aberration: aberration)
        let position = SIMD3(vector.x, vector.y, vector.z)
        let direction = position / vector.length
        let target = try heliocentricState(of: body, at: vector.time).velocityVector
        let c = Engine.speedOfLightAUPerDay
        let velocity: SIMD3<Double>
        switch aberration {
        case .corrected:
            let relative = target - (try heliocentricState(of: .earth, at: vector.time).velocityVector)
            velocity = relative * (1 / (1 + (direction * relative).sum() / c))
        case .none:
            let earth = try heliocentricState(of: .earth, at: time).velocityVector
            let a = (direction * target).sum() / c
            let b = (direction * earth).sum() / c
            velocity = target * ((1 + b) / (1 + a)) - earth
        }
        return try checked(Engine.State(position: position, velocity: velocity, time: time))
    }

    /// The apparent geocentric position and velocity of `body` on the true
    /// ecliptic and equinox of date, the C engine's
    /// `Astronomy_GeoEclipticState`.
    ///
    /// The position, longitude, latitude and distance are the same doubles
    /// as ``Engine/Ecliptic`` of ``geocentricPosition(of:at:aberration:)``
    /// and that vector's length. The rates are the derivative of that
    /// position per TT day, with Delta T held fixed: the light-time and
    /// aberration terms of ``geocentricState(of:at:aberration:)`` and the
    /// rotation of the true ecliptic and equinox of date.
    ///
    /// - Throws: As ``geocentricState(of:at:aberration:)``;
    ///   `AstronomyError.badVector` when the position has no component in the
    ///   ecliptic plane; `AstronomyError.badTime` for a result that is not
    ///   finite.
    static func geocentricEclipticState(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.EclipticState {
        try eclipticState(try geocentricState(of: body, at: time, aberration: aberration), reportedAt: time)
    }

    /// The Sun's geocentric position and velocity on the true ecliptic and
    /// equinox of date, the C engine's `Astronomy_SunEclipticState`.
    ///
    /// The position, longitude, latitude and distance are the same doubles
    /// as ``sunPosition(at:)``'s and its vector's length, including the
    /// fixed light time of one astronomical unit and the frame at the earlier
    /// time. The rates are their derivative per TT day, with Delta T held
    /// fixed.
    ///
    /// - Throws: As ``sunPosition(at:)``.
    static func sunEclipticState(at time: Engine.Time) throws -> Engine.EclipticState {
        let adjusted = sunLightTime(time)
        let earth = try Engine.Planet.earth.heliocentricState(at: adjusted)
        let sun = Engine.State<Engine.EQJ>(
            position: -earth.positionVector, velocity: -earth.velocityVector, time: adjusted)
        return try eclipticState(sun, reportedAt: time)
    }

    // MARK: - Helpers

    /// `time` less the light time of one astronomical unit.
    private static func sunLightTime(_ time: Engine.Time) -> Engine.Time {
        time.adding(days: -1 / Engine.speedOfLightAUPerDay)
    }

    /// `state` on the true equator and equinox of its time: precession and
    /// then nutation, each rotated and its rate applied to the position.
    static func trueEquatorState(_ state: Engine.State<Engine.EQJ>) -> Engine.State<Engine.EQD> {
        let tt = state.time.tt
        let tilt = Engine.EarthTilt(tt: tt)
        let mean = Engine.Precession.rotation(tt: tt).apply(to: state, rate: Engine.Precession.rate(tt: tt))
        return tilt.nutationRotation.apply(to: mean, rate: tilt.nutationRate)
    }

    /// `state` on the true ecliptic and equinox of its time, with `time` as
    /// the result's time.
    ///
    /// The position, longitude and latitude are ``Engine/Ecliptic``'s and
    /// the distance its vector's length, so their bits are those of the
    /// position functions. The velocity goes through precession, nutation
    /// and the true obliquity one rotation at a time, each with its rate, as
    /// the C engine's `ecliptic_state_from_eqj` does.
    private static func eclipticState(
        _ state: Engine.State<Engine.EQJ>, reportedAt time: Engine.Time
    ) throws -> Engine.EclipticState {
        let ecliptic = Engine.Ecliptic(state.position)
        let tilt = Engine.EarthTilt(tt: state.time.tt)
        let trueTilt: Engine.Rotation<Engine.EQD, Engine.ECT> = Engine.tilted(by: tilt.trueObliquity)
        let velocity = trueTilt.apply(
            to: trueEquatorState(state), rate: Engine.tiltRate(by: tilt.trueObliquity, rate: tilt.trueObliquityRate)
        ).velocityVector
        let position = SIMD3(ecliptic.vector.x, ecliptic.vector.y, ecliptic.vector.z)
        let distance = ecliptic.vector.length
        guard velocity.x.isFinite, velocity.y.isFinite, velocity.z.isFinite else { throw AstronomyError.badTime }
        return try Engine.EclipticState(
            state: Engine.State(position: position, velocity: velocity, time: time), longitude: ecliptic.longitude,
            latitude: ecliptic.latitude, distance: distance, distanceRate: (position * velocity).sum() / distance)
    }
}
