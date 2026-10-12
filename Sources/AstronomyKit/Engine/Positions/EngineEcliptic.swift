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

    /// The shared apparent Sun solution on the true ecliptic and equinox of reception date.
    static func sunPosition(at time: Engine.Time) throws -> Engine.Ecliptic {
        Engine.Ecliptic(try geocentricPosition(of: .sun, at: time, aberration: .corrected))
    }

    /// The shared astrometric/apparent EQJ position and its analytic derivative per reception TT day.
    ///
    /// Position and state use identical light-time, deflection and aberration composition. The public state body set remains Sun, Moon, Mercury through Neptune excluding Earth, and Pluto.
    static func geocentricState(
        of body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> Engine.State<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        switch body {
        case .moon, .sun, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
            break
        default:
            throw AstronomyError.invalidBody
        }
        let motion = try Engine.ApparentPlace.geocentricMotion(body: body, at: time, aberration: aberration)
        return try checked(Engine.State(position: motion.value, velocity: motion.rate, time: time))
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

    /// The shared apparent Sun state on the true ecliptic and equinox of reception date.
    static func sunEclipticState(at time: Engine.Time) throws -> Engine.EclipticState {
        try geocentricEclipticState(of: .sun, at: time, aberration: .corrected)
    }

    // MARK: - Helpers

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
