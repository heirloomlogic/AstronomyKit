//
//  EngineGravity.swift
//  AstronomyKit
//
//  Newtonian motion of a small body under the Sun and the planets: the
//  masses, the planets' barycentric states and the integrator step that
//  Pluto's model and the gravity simulation share.
//

import Foundation

extension Engine {
    /// The pull of the Sun and the planets on a body of negligible mass, and
    /// one step of the C engine's integrator.
    ///
    /// Positions and velocities are relative to the solar system barycenter
    /// on EQJ axes, in AU and AU per TT day; accelerations are in AU per TT
    /// day². The barycenter is the one the Sun and the planets in use define
    /// with the VSOP87B planets and the masses below: Jupiter to Neptune for
    /// Pluto's model (``MajorBodies``), all eight for the simulation
    /// (``SolarSystem``).
    enum Gravity {}
}

extension Engine.Gravity {
    // GM of the Sun and the planets in AU³/day², from the constants of JPL
    // DE405 (Standish 1998, JPL IOM 312.F-98-048). The Sun's is k², with k
    // the Gaussian gravitational constant 0.01720209895. Earth's is Earth's
    // alone; the simulation adds the Moon's, Earth's over
    // ``Engine/Moon/earthMoonMassRatio``.
    static let sunGM = 0.2959122082855911e-03
    static let mercuryGM = 0.4912547451450812e-10
    static let venusGM = 0.7243452486162703e-09
    static let earthGM = 0.8887692390113509e-09
    static let marsGM = 0.9549535105779258e-10
    static let jupiterGM = 0.2825345909524226e-06
    static let saturnGM = 0.8459715185680659e-07
    static let uranusGM = 0.1292024916781969e-07
    static let neptuneGM = 0.1524358900784276e-07

    /// The VSOP87B cache the integrator reads the planets through: none. A
    /// step's planets are at a new TT almost every time, so storing them
    /// would only push out the shared cache's entries.
    static let seriesCache = Engine.VSOP87B.Cache(capacity: 0, registry: Engine.CacheRegistry())

    /// A barycentric position and velocity.
    struct BodyState: Sendable {
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
    }

    /// The Sun and Jupiter to Neptune relative to the solar system
    /// barycenter at one TT, the C engine's `MajorBodyBary`.
    struct MajorBodies: Sendable {
        /// Jupiter to Neptune with their GM, in the order they are added.
        static let planets: [(Engine.Planet, Double)] = [
            (.jupiter, jupiterGM), (.saturn, saturnGM), (.uranus, uranusGM), (.neptune, neptuneGM),
        ]

        var sun: BodyState
        var jupiter: BodyState
        var saturn: BodyState
        var uranus: BodyState
        var neptune: BodyState

        /// The bodies at `tt` days of TT from J2000.
        ///
        /// Each planet's heliocentric state comes from
        /// ``Engine/Planet/heliocentricState(at:cache:)``. The barycenter is
        /// offset from the Sun by Σ GM/(GM + GM☉) times each planet's
        /// position, and the same sum of the velocities, accumulated from
        /// Jupiter to Neptune; the Sun is that offset negated.
        ///
        /// - Throws: As the planet functions do: `AstronomyError.badTime`
        ///   for |TT| above ``Engine/acceptedTTDays`` or not finite.
        init(tt: Double) throws {
            let (sun, planets) = try barycentricStates(Self.planets, tt: tt)
            self.sun = sun
            (jupiter, saturn, uranus, neptune) = (planets[0], planets[1], planets[2], planets[3])
        }

        /// The acceleration of a body of negligible mass at barycentric
        /// `position`: GM·d/|d|³ for each of the five bodies, with `d` from
        /// the small body to it, added from the Sun to Neptune.
        func acceleration(at position: SIMD3<Double>) -> SIMD3<Double> {
            var acceleration = SIMD3<Double>.zero
            acceleration += pull(of: sunGM, at: sun.position, on: position)
            acceleration += pull(of: jupiterGM, at: jupiter.position, on: position)
            acceleration += pull(of: saturnGM, at: saturn.position, on: position)
            acceleration += pull(of: uranusGM, at: uranus.position, on: position)
            acceleration += pull(of: neptuneGM, at: neptune.position, on: position)
            return acceleration
        }
    }

    /// The Sun and the eight planets relative to the solar system barycenter
    /// at one TT, the C engine's `CalcSolarSystem`, which the simulation
    /// reads.
    struct SolarSystem: Sendable {
        var sun: BodyState
        /// Mercury to Neptune, indexed by ``Engine/Planet/rawValue``.
        var planets: [BodyState]

        /// The GM each planet pulls with, in table order. Earth's includes
        /// the Moon's.
        static let planetGM = [
            mercuryGM, venusGM, earthGM + earthGM / Engine.Moon.earthMoonMassRatio, marsGM, jupiterGM, saturnGM,
            uranusGM, neptuneGM,
        ]

        /// The planets with their GM, Mercury first.
        static let planetsWithGM = Array(zip(Engine.Planet.allCases, planetGM))

        /// The bodies at `tt` days of TT from J2000, built as
        /// ``MajorBodies`` builds its own, from Mercury to Neptune.
        ///
        /// - Throws: As ``MajorBodies/init(tt:)``.
        init(tt: Double) throws {
            (sun, planets) = try barycentricStates(Self.planetsWithGM, tt: tt)
        }

        /// The barycentric state of `body`: the Sun, a planet, or the
        /// barycenter itself, which is zero. `nil` for any other body.
        func state(of body: CelestialBody) -> BodyState? {
            if body == .solarSystemBarycenter { return BodyState(position: .zero, velocity: .zero) }
            if body == .sun { return sun }
            return Engine.Planet(body).map { planets[$0.rawValue] }
        }

        /// The acceleration of a body of negligible mass at barycentric
        /// `position`: GM·d/|d|³ from the Sun, then Mercury to Neptune, the
        /// C engine's `CalcBodyAccelerations`.
        func acceleration(at position: SIMD3<Double>) -> SIMD3<Double> {
            var acceleration = SIMD3<Double>.zero
            acceleration += pull(of: sunGM, at: sun.position, on: position)
            for (planet, gm) in zip(planets, Self.planetGM) {
                acceleration += pull(of: gm, at: planet.position, on: position)
            }
            return acceleration
        }
    }

    /// GM·d/|d|³, the C engine's `AddAcceleration` term for one body at
    /// `body`, with `d` from `position` to it.
    static func pull(of gm: Double, at body: SIMD3<Double>, on position: SIMD3<Double>) -> SIMD3<Double> {
        let d = body - position
        let r2 = d.x * d.x + d.y * d.y + d.z * d.z
        return d * (gm / (r2 * r2.squareRoot()))
    }

    /// The Sun's barycentric state and the planets' at `tt`, the C engine's
    /// `AdjustBarycenterPosVel` loop: each planet's heliocentric state from
    /// ``Engine/Planet/heliocentricState(at:cache:)``, the barycenter offset
    /// from the Sun by Σ GM/(GM + GM☉) times each position and velocity, in
    /// the order given, then every planet moved to the barycenter and the
    /// Sun put at minus the offset.
    private static func barycentricStates(
        _ planets: [(Engine.Planet, Double)], tt: Double
    ) throws -> (sun: BodyState, planets: [BodyState]) {
        // The planet functions read only the TT of their time.
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        var offset = BodyState(position: .zero, velocity: .zero)
        var heliocentric: [BodyState] = []
        heliocentric.reserveCapacity(planets.count)
        for (planet, gm) in planets {
            let state = try planet.heliocentricState(at: time, cache: seriesCache)
            let (position, velocity) = (state.positionVector, state.velocityVector)
            let shift = gm / (gm + sunGM)
            offset.position += shift * position
            offset.velocity += shift * velocity
            heliocentric.append(BodyState(position: position, velocity: velocity))
        }
        let barycentric = heliocentric.map {
            BodyState(position: $0.position - offset.position, velocity: $0.velocity - offset.velocity)
        }
        return (BodyState(position: -offset.position, velocity: -offset.velocity), barycentric)
    }

    /// A small body's barycentric position, velocity and acceleration at a
    /// TT, the C engine's `body_grav_calc_t`.
    struct Step: Sendable {
        var tt: Double
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
        var acceleration: SIMD3<Double>
    }

    /// The step for a heliocentric state at `tt`, with the major bodies at
    /// that time, the C engine's `GravFromState`. The state moves to the
    /// barycenter by adding the Sun's barycentric position and velocity.
    static func start(
        heliocentric position: SIMD3<Double>, velocity: SIMD3<Double>, tt: Double
    ) throws -> (step: Step, bodies: MajorBodies) {
        let bodies = try MajorBodies(tt: tt)
        let barycentric = position + bodies.sun.position
        return (
            Step(
                tt: tt, position: barycentric, velocity: velocity + bodies.sun.velocity,
                acceleration: bodies.acceleration(at: barycentric)),
            bodies
        )
    }

    /// One step from `step` to `tt`, forward or backward, with the major
    /// bodies at `tt`: the C engine's `GravSim`.
    static func advance(_ step: Step, to tt: Double) throws -> (step: Step, bodies: MajorBodies) {
        let bodies = try MajorBodies(tt: tt)
        return (advance(step, to: tt, bodies: bodies), bodies)
    }

    /// One step from `step` to `tt` with `bodies`, the major bodies at `tt`.
    static func advance(_ step: Step, to tt: Double, bodies: MajorBodies) -> Step {
        advance(step, to: tt, acceleration: bodies.acceleration(at:))
    }

    /// One step from `step` to `tt` under `acceleration`, the field at `tt`.
    ///
    /// A trial position carries `step`'s acceleration across the interval;
    /// the mean of that acceleration and the one at the trial position then
    /// gives the new position and velocity, and the acceleration there.
    static func advance(
        _ step: Step, to tt: Double, acceleration: (SIMD3<Double>) -> SIMD3<Double>
    ) -> Step {
        let dt = tt - step.tt
        let trial = position(after: dt, from: step.position, velocity: step.velocity, acceleration: step.acceleration)
        let mean = (step.acceleration + acceleration(trial)) / 2
        let position = position(after: dt, from: step.position, velocity: step.velocity, acceleration: mean)
        return Step(
            tt: tt, position: position, velocity: velocity(after: dt, from: step.velocity, acceleration: mean),
            acceleration: acceleration(position))
    }

    /// `r + (v + a·dt/2)·dt`, the C engine's `UpdatePosition`.
    static func position(
        after dt: Double, from position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>
    ) -> SIMD3<Double> {
        position + (velocity + acceleration * dt / 2) * dt
    }

    /// `v + dt·a`, the C engine's `UpdateVelocity`.
    static func velocity(after dt: Double, from velocity: SIMD3<Double>, acceleration: SIMD3<Double>) -> SIMD3<Double> {
        velocity + dt * acceleration
    }
}
