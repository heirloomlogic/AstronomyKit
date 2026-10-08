//
//  EngineHeliocentric.swift
//  AstronomyKit
//
//  Heliocentric and barycentric positions, states and distances of every
//  body the planet, Moon and Pluto models cover.
//

import Foundation

extension Engine {
    /// Positions and states of the bodies, composed from the planet series,
    /// the Moon, Pluto and the correction for light travel.
    ///
    /// Every function takes a body and a time, checks the time against
    /// ``Engine/acceptedTTDays`` before the body, and returns EQJ vectors in AU
    /// and AU per TT day with the time it was given.
    enum Positions {}
}

extension Engine.Positions {
    /// The position of `body` relative to the Sun's center, the C engine's
    /// `Astronomy_HelioVector`.
    ///
    /// The Sun is at the origin. A planet's position is
    /// ``Engine/Planet/heliocentricPosition(at:cache:)``'s and Pluto's is
    /// ``Engine/Pluto/heliocentricPosition(at:cache:)``'s. The Moon is its
    /// geocentric position plus Earth's, and the Earth-Moon barycenter is
    /// Earth's position plus the Moon's geocentric position over 1 +
    /// ``Engine/Moon/earthMoonMassRatio``. The solar system barycenter is
    /// offset from the Sun by Σ GM/(GM + GM☉) times the positions of Jupiter
    /// to Neptune, in that order, with the masses of ``Engine/Gravity``.
    ///
    /// - Throws: `AstronomyError.badTime` for a TT beyond
    ///   ``Engine/acceptedTTDays`` or not finite, outside Pluto's range, or
    ///   for a result that is not finite; then `AstronomyError.invalidBody`
    ///   for a body none of these covers.
    static func heliocentricPosition(
        of body: CelestialBody, at time: Engine.Time
    ) throws
        -> Engine.Vector<Engine.EQJ>
    {
        try Engine.checkAcceptedTime(time)
        let position: Engine.Vector<Engine.EQJ>
        switch body {
        case .sun:
            position = Engine.Vector(x: 0, y: 0, z: 0, time: time)
        case .moon:
            let moon = try Engine.Moon.geocentricPosition(at: time)
            let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
            position = Engine.Vector(
                x: moon.x + earth.x, y: moon.y + earth.y, z: moon.z + earth.z, time: time)
        case .earthMoonBarycenter:
            let moon = try Engine.Moon.geocentricPosition(at: time)
            let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
            let scale = 1 + Engine.Moon.earthMoonMassRatio
            position = Engine.Vector(
                x: earth.x + moon.x / scale, y: earth.y + moon.y / scale, z: earth.z + moon.z / scale,
                time: time)
        case .solarSystemBarycenter:
            var offset = SIMD3<Double>.zero
            for (planet, gm) in Engine.Gravity.MajorBodies.planets {
                let vector = try planet.heliocentricPosition(at: time)
                offset += gm / (gm + Engine.Gravity.sunGM) * SIMD3(vector.x, vector.y, vector.z)
            }
            position = Engine.Vector(x: offset.x, y: offset.y, z: offset.z, time: time)
        case .pluto:
            position = try Engine.Pluto.heliocentricPosition(at: time)
        default:
            guard let planet = Engine.Planet(body) else { throw AstronomyError.invalidBody }
            position = try planet.heliocentricPosition(at: time)
        }
        return try checked(position)
    }

    /// The position and velocity of `body` relative to the Sun's center, the
    /// C engine's `Astronomy_HelioState`.
    ///
    /// The bodies are composed as in ``heliocentricPosition(of:at:)``, from
    /// the states of the same models, so a state's position is the same
    /// double as the position. The solar system barycenter is the Sun's
    /// barycentric state of ``Engine/Gravity/MajorBodies`` negated. Pluto's
    /// velocity is the exact derivative of its position, including the rate
    /// of the integrated model's mix between steps.
    ///
    /// - Throws: As ``heliocentricPosition(of:at:)``, including for a velocity
    ///   that is not finite.
    static func heliocentricState(
        of body: CelestialBody, at time: Engine.Time
    ) throws
        -> Engine.State<Engine.EQJ>
    {
        try Engine.checkAcceptedTime(time)
        let state: Engine.State<Engine.EQJ>
        switch body {
        case .sun:
            state = Engine.State(x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, time: time)
        case .moon:
            let earth = try Engine.Planet.earth.heliocentricState(at: time)
            state = sum(try Engine.Moon.geocentricState(at: time), earth)
        case .earthMoonBarycenter:
            let earth = try Engine.Planet.earth.heliocentricState(at: time)
            state = sum(try Engine.Moon.barycenterState(at: time), earth)
        case .solarSystemBarycenter:
            let sun = try Engine.Gravity.MajorBodies(tt: time.tt).sun
            state = Engine.State(position: -sun.position, velocity: -sun.velocity, time: time)
        case .pluto:
            state = try Engine.Pluto.heliocentricState(at: time)
        default:
            guard let planet = Engine.Planet(body) else { throw AstronomyError.invalidBody }
            state = try planet.heliocentricState(at: time)
        }
        return try checked(state)
    }

    /// The position and velocity of `body` relative to the solar system
    /// barycenter of ``Engine/Gravity/MajorBodies``, the C engine's
    /// `Astronomy_BaryState`.
    ///
    /// The Sun and Jupiter to Neptune are the major bodies' states. Mercury
    /// to Mars are the Sun's state plus the planet's heliocentric one. The
    /// Moon and the Earth-Moon barycenter are their geocentric states plus
    /// the sum of the Sun's and Earth's. Pluto is
    /// ``Engine/Pluto/barycentricState(at:cache:)``.
    ///
    /// - Throws: As ``heliocentricState(of:at:)``.
    static func barycentricState(
        of body: CelestialBody, at time: Engine.Time
    ) throws
        -> Engine.State<Engine.EQJ>
    {
        try Engine.checkAcceptedTime(time)
        let state: Engine.State<Engine.EQJ>
        switch body {
        case .solarSystemBarycenter:
            state = Engine.State(x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, time: time)
        case .pluto:
            state = try Engine.Pluto.barycentricState(at: time)
        case .sun, .jupiter, .saturn, .uranus, .neptune:
            let bodies = try Engine.Gravity.MajorBodies(tt: time.tt)
            let major: Engine.Gravity.BodyState =
                switch body {
                case .sun: bodies.sun
                case .jupiter: bodies.jupiter
                case .saturn: bodies.saturn
                case .uranus: bodies.uranus
                default: bodies.neptune
                }
            state = Engine.State(position: major.position, velocity: major.velocity, time: time)
        case .moon, .earthMoonBarycenter:
            let sun = try Engine.Gravity.MajorBodies(tt: time.tt).sun
            let earth = try Engine.Planet.earth.heliocentricState(at: time)
            let geocentric =
                body == .moon
                ? try Engine.Moon.geocentricState(at: time) : try Engine.Moon.barycenterState(at: time)
            // The C engine adds the Sun and Earth first, then the Moon.
            let origin = Engine.State<Engine.EQJ>(
                position: sun.position + earth.positionVector,
                velocity: sun.velocity + earth.velocityVector,
                time: time)
            state = sum(geocentric, origin)
        default:
            guard let planet = Engine.Planet(body) else { throw AstronomyError.invalidBody }
            // Mercury to Mars.
            let sun = try Engine.Gravity.MajorBodies(tt: time.tt).sun
            let heliocentric = try planet.heliocentricState(at: time)
            state = sum(
                Engine.State(position: sun.position, velocity: sun.velocity, time: time), heliocentric)
        }
        return try checked(state)
    }

    /// The distance in AU between the centers of `body` and the Sun, the C
    /// engine's `Astronomy_HelioDistance`.
    ///
    /// 0 for the Sun, ``Engine/Planet/heliocentricDistance(at:cache:)`` for a
    /// planet, and the length of ``heliocentricPosition(of:at:)`` for any
    /// other body.
    ///
    /// - Throws: As ``heliocentricPosition(of:at:)``.
    static func heliocentricDistance(of body: CelestialBody, at time: Engine.Time) throws -> Double {
        try Engine.checkAcceptedTime(time)
        let distance: Double
        if body == .sun {
            distance = 0
        } else if let planet = Engine.Planet(body) {
            distance = try planet.heliocentricDistance(at: time)
        } else {
            distance = try heliocentricPosition(of: body, at: time).length
        }
        guard distance.isFinite else { throw AstronomyError.badTime }
        return distance
    }

    // MARK: - Helpers

    /// `a + b` component by component, at `a`'s time.
    static func sum(
        _ a: Engine.State<Engine.EQJ>, _ b: Engine.State<Engine.EQJ>
    )
        -> Engine.State<Engine.EQJ>
    {
        Engine.State(
            x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, vx: a.vx + b.vx, vy: a.vy + b.vy, vz: a.vz + b.vz,
            time: a.time)
    }

    /// `vector`, or `badTime` when a component is not finite.
    static func checked<F>(_ vector: Engine.Vector<F>) throws -> Engine.Vector<F> {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else {
            throw AstronomyError.badTime
        }
        return vector
    }

    /// `state`, or `badTime` when a component is not finite.
    static func checked<F>(_ state: Engine.State<F>) throws -> Engine.State<F> {
        guard state.x.isFinite, state.y.isFinite, state.z.isFinite,
            state.vx.isFinite, state.vy.isFinite, state.vz.isFinite
        else { throw AstronomyError.badTime }
        return state
    }
}
