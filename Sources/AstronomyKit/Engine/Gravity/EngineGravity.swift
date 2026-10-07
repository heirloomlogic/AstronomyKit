//
//  EngineGravity.swift
//  AstronomyKit
//
//  Newtonian motion of a small body under the Sun and the giant planets:
//  the integrator step that Pluto's legacy model and the gravity simulation
//  share.
//

import Foundation

extension Engine {
    /// The pull of the Sun and the giant planets on a body of negligible mass,
    /// and one step of the C engine's integrator.
    ///
    /// Positions and velocities are relative to the solar system barycenter
    /// on EQJ axes, in AU and AU per TT day; accelerations are in AU per TT
    /// day². The barycenter is the one the Sun and Jupiter to Neptune define
    /// with the VSOP87B planets and the masses below.
    enum Gravity {}
}

extension Engine.Gravity {
    // GM of the Sun and the giant planets in AU³/day², from the constants of
    // JPL DE405 (Standish 1998, JPL IOM 312.F-98-048). The Sun's is k², with
    // k the Gaussian gravitational constant 0.01720209895.
    static let sunGM = 0.2959122082855911e-03
    static let jupiterGM = 0.2825345909524226e-06
    static let saturnGM = 0.8459715185680659e-07
    static let uranusGM = 0.1292024916781969e-07
    static let neptuneGM = 0.1524358900784276e-07

    /// A barycentric position and velocity.
    struct BodyState: Sendable {
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
    }

    /// The Sun and Jupiter to Neptune relative to the solar system
    /// barycenter at one TT, the C engine's `MajorBodyBary`.
    struct MajorBodies: Sendable {
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
            // The planet functions read only the TT of their time.
            let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
            var offset = BodyState(position: .zero, velocity: .zero)
            func heliocentric(_ planet: Engine.Planet, gm: Double) throws -> BodyState {
                let state = try planet.heliocentricState(at: time)
                let position = SIMD3(state.x, state.y, state.z)
                let velocity = SIMD3(state.vx, state.vy, state.vz)
                let shift = gm / (gm + sunGM)
                offset.position += shift * position
                offset.velocity += shift * velocity
                return BodyState(position: position, velocity: velocity)
            }
            let jupiter = try heliocentric(.jupiter, gm: jupiterGM)
            let saturn = try heliocentric(.saturn, gm: saturnGM)
            let uranus = try heliocentric(.uranus, gm: uranusGM)
            let neptune = try heliocentric(.neptune, gm: neptuneGM)
            func barycentric(_ body: BodyState) -> BodyState {
                BodyState(position: body.position - offset.position, velocity: body.velocity - offset.velocity)
            }
            self.jupiter = barycentric(jupiter)
            self.saturn = barycentric(saturn)
            self.uranus = barycentric(uranus)
            self.neptune = barycentric(neptune)
            sun = BodyState(position: -offset.position, velocity: -offset.velocity)
        }

        /// The acceleration of a body of negligible mass at barycentric
        /// `position`: GM·d/|d|³ for each of the five bodies, with `d` from
        /// the small body to it, added from the Sun to Neptune.
        func acceleration(at position: SIMD3<Double>) -> SIMD3<Double> {
            var acceleration = SIMD3<Double>.zero
            func pull(_ gm: Double, _ body: BodyState) {
                let d = body.position - position
                let r2 = d.x * d.x + d.y * d.y + d.z * d.z
                acceleration += d * (gm / (r2 * r2.squareRoot()))
            }
            pull(sunGM, sun)
            pull(jupiterGM, jupiter)
            pull(saturnGM, saturn)
            pull(uranusGM, uranus)
            pull(neptuneGM, neptune)
            return acceleration
        }
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
    ///
    /// A trial position carries `step`'s acceleration across the interval;
    /// the mean of that acceleration and the one at the trial position then
    /// gives the new position and velocity, and the acceleration there.
    static func advance(_ step: Step, to tt: Double, bodies: MajorBodies) -> Step {
        let dt = tt - step.tt
        let trial = position(after: dt, from: step.position, velocity: step.velocity, acceleration: step.acceleration)
        let mean = (bodies.acceleration(at: trial) + step.acceleration) / 2
        let position = position(after: dt, from: step.position, velocity: step.velocity, acceleration: mean)
        return Step(
            tt: tt, position: position, velocity: velocity(after: dt, from: step.velocity, acceleration: mean),
            acceleration: bodies.acceleration(at: position))
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
