//
//  EngineGravitySimulation.swift
//  AstronomyKit
//
//  Small bodies stepped through the Solar System under the Sun and the
//  planets, with the state owned by Swift.
//

import Foundation

extension Engine {
    /// Small bodies of negligible mass moved step by step under the Sun and
    /// the eight planets: the C engine's `Astronomy_GravSimInit`,
    /// `Astronomy_GravSimUpdate`, `Astronomy_GravSimSwap`,
    /// `Astronomy_GravSimBodyState`, `Astronomy_GravSimTime` and
    /// `Astronomy_GravSimNumBodies`. The simulation's storage is released
    /// with the object, which replaces `Astronomy_GravSimFree`.
    ///
    /// The simulation keeps two moments, current and previous. An update
    /// computes the new current moment from the current one, which becomes
    /// the previous one; ``swap()`` exchanges them. States go in and come out
    /// relative to ``origin`` on EQJ axes; inside, they are barycentric.
    ///
    /// One lock guards the two moments. An update reads them under the lock,
    /// computes outside it, and stores its result only if no other change
    /// came in between; otherwise it starts again from the newer moments. So
    /// calls from several threads take effect one at a time, as if in some
    /// order, and an update that throws leaves the simulation as it was.
    final class GravitySimulation: @unchecked Sendable {
        /// One moment: its time, the Sun and planets, and the small bodies.
        struct Moment: Sendable {
            var time: Engine.Time
            var solarSystem: Engine.Gravity.SolarSystem
            var bodies: [Engine.Gravity.Step]
        }

        private struct Storage {
            var current: Moment
            var previous: Moment
            /// Counts changes, so an update can tell whether it computed
            /// from the latest moments.
            var generation = 0
        }

        /// The body the states are relative to.
        let origin: CelestialBody

        /// The number of small bodies.
        let bodyCount: Int

        // NSLock rather than Synchronization.Mutex; see NATIVE_ENGINE.md.
        // `storage` is only touched while `lock` is held.
        private let lock = NSLock()
        private var storage: Storage

        /// A simulation of `states` at `time`, relative to `origin`.
        ///
        /// Both moments start at `time`. Each state's TT must equal `time`'s.
        ///
        /// - Throws: `AstronomyError.invalidBody` for an origin the C engine
        ///   does not accept, checked first: anything but the Sun, the
        ///   planets, the solar system barycenter, and Pluto, the Moon and
        ///   the Earth-Moon barycenter, which pass that check and fail the
        ///   last one. `AstronomyError.badTime` for a time outside
        ///   ``Engine/acceptedTTDays``; `AstronomyError.inconsistentTimes`
        ///   when a state's TT differs from `time`'s; `invalidBody` for
        ///   Pluto, the Moon and the Earth-Moon barycenter, which the
        ///   simulation does not model.
        init(origin: CelestialBody, time: Engine.Time, states: [Engine.State<Engine.EQJ>]) throws {
            // The C engine's range, BODY_MERCURY through BODY_SSB.
            guard
                (CelestialBody.mercury.rawValue...CelestialBody.solarSystemBarycenter.rawValue)
                    .contains(origin.rawValue)
            else { throw AstronomyError.invalidBody }
            try Engine.checkAcceptedTime(time)
            guard states.allSatisfy({ $0.time.tt == time.tt }) else { throw AstronomyError.inconsistentTimes }
            let solarSystem = try Engine.Gravity.SolarSystem(tt: time.tt)
            guard let originState = solarSystem.state(of: origin) else { throw AstronomyError.invalidBody }
            let bodies = states.map { state in
                var (position, velocity) = (state.positionVector, state.velocityVector)
                if origin != .solarSystemBarycenter {
                    position += originState.position
                    velocity += originState.velocity
                }
                return Engine.Gravity.Step(
                    tt: state.time.tt, position: position, velocity: velocity,
                    acceleration: solarSystem.acceleration(at: position))
            }
            let moment = Moment(time: time, solarSystem: solarSystem, bodies: bodies)
            self.origin = origin
            bodyCount = states.count
            storage = Storage(current: moment, previous: moment)
        }

        /// The current moment's time.
        var time: Engine.Time { lock.withLock { storage.current.time } }

        /// The current and previous moments, for tests.
        var moments: (current: Moment, previous: Moment) {
            lock.withLock { (storage.current, storage.previous) }
        }

        /// Moves the simulation to `time`, forward or backward, and returns
        /// the small bodies' states there, relative to ``origin``, with
        /// `time` as their time.
        ///
        /// The current moment becomes the previous one. When `time` has the
        /// current moment's TT, nothing is integrated: the previous moment
        /// becomes a copy of the current one, which keeps its own time.
        /// Otherwise the Sun and planets come from
        /// ``Engine/Gravity/SolarSystem`` at `time`, and each body takes one
        /// step of ``Engine/Gravity/advance(_:to:acceleration:)``.
        ///
        /// - Throws: `AstronomyError.badTime` for a time outside
        ///   ``Engine/acceptedTTDays``, checked first as the C engine checks
        ///   it. Nothing is stored until the new moment is complete, so the
        ///   simulation is then unchanged.
        @discardableResult
        func update(to time: Engine.Time) throws -> [Engine.State<Engine.EQJ>] {
            try Engine.checkAcceptedTime(time)
            // The Sun and planets depend only on `time`, so a retry reuses them.
            var solarSystem: Engine.Gravity.SolarSystem?
            while true {
                let (base, generation) = lock.withLock { (storage.current, storage.generation) }
                let next = try Self.moment(after: base, at: time, solarSystem: &solarSystem)
                let stored = lock.withLock {
                    guard storage.generation == generation else { return false }
                    storage.previous = base
                    storage.current = next
                    storage.generation += 1
                    return true
                }
                if stored { return states(of: next, at: time) }
            }
        }

        /// The current state of the Sun or a planet relative to ``origin``,
        /// with the current moment's time.
        ///
        /// - Throws: `AstronomyError.invalidBody` for any other body, the
        ///   solar system barycenter included, as in the C engine.
        func state(of body: CelestialBody) throws -> Engine.State<Engine.EQJ> {
            let current = lock.withLock { storage.current }
            guard body != .solarSystemBarycenter, let state = current.solarSystem.state(of: body) else {
                throw AstronomyError.invalidBody
            }
            let originState = originState(in: current)
            return Engine.State(
                position: state.position - originState.position, velocity: state.velocity - originState.velocity,
                time: current.time)
        }

        /// Exchanges the current and previous moments. Right after an update
        /// this undoes it; twice in a row, it changes nothing.
        func swap() {
            lock.withLock {
                (storage.current, storage.previous) = (storage.previous, storage.current)
                storage.generation += 1
            }
        }

        // MARK: - Helpers

        /// The moment after `base` at `time`: a copy of `base` at the same
        /// TT, otherwise every body stepped under the Sun and planets at
        /// `time`, which `cached` holds once computed.
        private static func moment(
            after base: Moment, at time: Engine.Time, solarSystem cached: inout Engine.Gravity.SolarSystem?
        ) throws -> Moment {
            guard time.tt - base.time.tt != 0 else { return base }
            let solarSystem = try cached ?? Engine.Gravity.SolarSystem(tt: time.tt)
            cached = solarSystem
            let bodies = base.bodies.map {
                Engine.Gravity.advance($0, to: time.tt, acceleration: solarSystem.acceleration(at:))
            }
            return Moment(time: time, solarSystem: solarSystem, bodies: bodies)
        }

        /// ``origin``'s barycentric state in `moment`.
        private func originState(in moment: Moment) -> Engine.Gravity.BodyState {
            guard let state = moment.solarSystem.state(of: origin) else {
                preconditionFailure("The initializer accepts only origins the solar system models")
            }
            return state
        }

        /// The bodies of `moment` relative to ``origin``, at `time`.
        private func states(of moment: Moment, at time: Engine.Time) -> [Engine.State<Engine.EQJ>] {
            let originState = originState(in: moment)
            return moment.bodies.map { body in
                var position = body.position
                var velocity = body.velocity
                if origin != .solarSystemBarycenter {
                    position -= originState.position
                    velocity -= originState.velocity
                }
                return Engine.State(position: position, velocity: velocity, time: time)
            }
        }
    }
}

extension Engine.State {
    /// A state from SIMD position and velocity.
    init(position: SIMD3<Double>, velocity: SIMD3<Double>, time: Engine.Time) {
        self.init(
            x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z, time: time)
    }

    /// The position as a SIMD vector.
    var positionVector: SIMD3<Double> { SIMD3(x, y, z) }

    /// The velocity as a SIMD vector.
    var velocityVector: SIMD3<Double> { SIMD3(vx, vy, vz) }
}
