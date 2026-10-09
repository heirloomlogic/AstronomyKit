//
//  EnginePluto.swift
//  AstronomyKit
//
//  Pluto: DE440/PLU060 center states from 1900 through 2130 TT, blended
//  into a DE441 system-barycenter approximation outside that span.
//

import Foundation

extension Engine {
    /// Pluto's center in the central DE440/PLU060 span, and a system-barycenter approximation outside it.
    ///
    /// The 32-day blends retain the central center offset with a smooth weight. DE441 supplies the outer barycenter without a physical-center correction; full-range center position and velocity accuracy remain unqualified. The legacy integrated model and its cache remain available through `modelState` for diagnostics.
    enum Pluto {}
}

extension Engine.Pluto {
    /// A tabulated state: heliocentric position in AU and velocity in AU per
    /// TT day on EQJ axes, at `tt` days of TT from J2000.
    struct TableState: Sendable {
        var tt: Double
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
    }

    /// The model's integrated steps between two tabulated states.
    struct Segment: Sendable {
        /// ``stepsPerSegment`` + 1 steps from one tabulated state to the
        /// next, ``stepDays`` apart, barycentric.
        let steps: [Engine.Gravity.Step]
    }

    /// A cache of segments, keyed by segment index.
    typealias Cache = Engine.BoundedCache<Int, Segment>

    /// The segments shared by every engine caller: one entry for each.
    static let cache = Cache(capacity: segmentCount, registry: .shared)

    /// The days between tabulated states.
    static let tableStepDays = 29_200.0

    /// The number of segments, one fewer than the states.
    static let segmentCount = stateTable.count - 1

    /// The intervals in a segment; it holds one more step than this.
    static let stepsPerSegment = 200

    /// The days between steps within a segment, 146.
    static let stepDays = tableStepDays / Double(stepsPerSegment)

    /// How far beyond the first or last tabulated state the model reaches.
    static let crawlLimitDays = 36_525.0

    // MARK: - Positions and states

    /// Pluto's position in AU and velocity in AU per TT day relative to the
    /// Sun's center, on EQJ axes.
    ///
    /// The velocity differentiates the TT/TDB conversion and the DE440 blend weight. Outside the central span it is the system-barycenter rate, not Pluto's physical-center rate.
    ///
    /// - Throws: `AstronomyError.badTime` for a TT that is not finite, more
    ///   than ``crawlLimitDays`` before the first tabulated state or after
    ///   the last, or a result that is not finite.
    static func heliocentricState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ> {
        try state(at: time, heliocentric: true)
    }

    /// Pluto's position in AU and velocity in AU per TT day relative to the
    /// solar system barycenter of ``Engine/Gravity/MajorBodies``, on EQJ
    /// axes.
    ///
    /// - Throws: As ``heliocentricState(at:cache:)``.
    static func barycentricState(at time: Engine.Time, cache: Cache = cache) throws -> Engine.State<Engine.EQJ> {
        try state(at: time, heliocentric: false)
    }

    /// The position of ``heliocentricState(at:cache:)``, the same double for
    /// double.
    static func heliocentricPosition(at time: Engine.Time, cache: Cache = cache) throws -> Engine.Vector<Engine.EQJ> {
        try heliocentricState(at: time, cache: cache).position
    }

    /// Retains the central center model and blends it into the outer system barycenter.
    private static func state(
        at time: Engine.Time, heliocentric: Bool
    ) throws -> Engine.State<Engine.EQJ> {
        let tt = time.tt
        guard tt.isFinite, abs(tt) <= Engine.PlutoDE441.acceptedTTDays else { throw AstronomyError.badTime }
        let (weight, rate) = Engine.MoonEphemeris.weight(tt: tt)
        var position: SIMD3<Double>
        var velocity: SIMD3<Double>
        if weight > 0, let source = Engine.PlutoEphemeris.heliocentricState(tt: tt) {
            (position, velocity) = source
            if !heliocentric {
                let sun = try Engine.Gravity.MajorBodies(tt: tt).sun
                position += sun.position
                velocity += sun.velocity
            }
            if weight < 1 {
                let model = try outerState(tt: tt, heliocentric: heliocentric)
                velocity = model.velocity + weight * (velocity - model.velocity) + rate * (position - model.position)
                position = model.position + weight * (position - model.position)
            }
        } else {
            (position, velocity) = try outerState(tt: tt, heliocentric: heliocentric)
        }
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
            velocity.x.isFinite, velocity.y.isFinite, velocity.z.isFinite
        else { throw AstronomyError.badTime }
        return Engine.State(
            x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z, time: time)
    }

    /// DE441 heliocentric system barycenter, optionally translated into the existing MajorBodies origin.
    static func outerState(tt: Double, heliocentric: Bool) throws -> (position: SIMD3<Double>, velocity: SIMD3<Double>)
    {
        guard let source = Engine.PlutoDE441.state(tt: tt) else { throw AstronomyError.badTime }
        guard !heliocentric else { return source }
        let sun = try Engine.Gravity.MajorBodies(tt: tt).sun
        return (source.position + sun.position, source.velocity + sun.velocity)
    }

    // MARK: - The integrated model

    /// The model's position and velocity at `tt`, heliocentric or
    /// barycentric, the C engine's `CalcPlutoLegacy` with the exact
    /// velocity.
    ///
    /// Inside the table the time falls between two steps of its segment.
    /// Each step is carried to the time with the mean of the two steps'
    /// accelerations, and the two results are mixed linearly by the
    /// fraction of the interval elapsed. The velocity is the same mix plus
    /// the mix's rate, (later − earlier position) / ``stepDays``, so it is
    /// the derivative of the position.
    ///
    /// - Throws: As ``heliocentricState(at:cache:)``, except for the result
    ///   check.
    static func modelState(
        tt: Double, heliocentric: Bool, cache: Cache = cache
    ) throws -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        guard tt.isFinite else { throw AstronomyError.badTime }
        let first = stateTable[0]
        let last = stateTable[segmentCount]
        if tt < first.tt || tt > last.tt {
            guard tt >= first.tt - crawlLimitDays, tt <= last.tt + crawlLimitDays else {
                throw AstronomyError.badTime
            }
            let (step, bodies) =
                tt < first.tt
                ? try crawl(from: first, to: tt, by: -stepDays)
                : try crawl(from: last, to: tt, by: stepDays)
            guard heliocentric else { return (step.position, step.velocity) }
            return (step.position - bodies.sun.position, step.velocity - bodies.sun.velocity)
        }

        let index = clampedIndex((tt - first.tt) / tableStepDays, count: segmentCount)
        let steps = try cache.value(for: index) { try segment(index) }.steps
        let left = clampedIndex((tt - steps[0].tt) / stepDays, count: stepsPerSegment)
        let (earlier, later) = (steps[left], steps[left + 1])
        let acceleration = (earlier.acceleration + later.acceleration) / 2
        func carried(_ step: Engine.Gravity.Step) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
            let dt = tt - step.tt
            return (
                Engine.Gravity.position(
                    after: dt, from: step.position, velocity: step.velocity, acceleration: acceleration),
                Engine.Gravity.velocity(after: dt, from: step.velocity, acceleration: acceleration)
            )
        }
        let (fromEarlier, fromLater) = (carried(earlier), carried(later))
        let ramp = (tt - earlier.tt) / stepDays
        let position = (1 - ramp) * fromEarlier.position + ramp * fromLater.position
        let velocity =
            (1 - ramp) * fromEarlier.velocity + ramp * fromLater.velocity
            + (fromLater.position - fromEarlier.position) / stepDays
        guard heliocentric else { return (position, velocity) }
        let sun = try Engine.Gravity.MajorBodies(tt: tt).sun
        return (position - sun.position, velocity - sun.velocity)
    }

    /// Segment `index`, from tabulated state `index` to the next: the C
    /// engine's `GetSegment`.
    ///
    /// Both ends are the tabulated states. The steps between are integrated
    /// forward from the first and backward from the last, and step `i` takes
    /// `i`/200 of the backward result and the rest of the forward one, in
    /// position, velocity and acceleration.
    static func segment(_ index: Int) throws -> Segment {
        precondition((0..<segmentCount).contains(index), "Pluto segment \(index) out of range")
        let count = stepsPerSegment
        let start = try Engine.Gravity.start(stateTable[index]).step
        let end = try Engine.Gravity.start(stateTable[index + 1]).step

        // The backward pass steps through the forward pass's times, so it
        // reuses the major bodies found there.
        var forward = [start]
        var bodies: [Engine.Gravity.MajorBodies] = []
        forward.reserveCapacity(count + 1)
        bodies.reserveCapacity(count)
        var tt = start.tt
        for i in 1..<count {
            tt += stepDays
            let next = try Engine.Gravity.advance(forward[i - 1], to: tt)
            forward.append(next.step)
            bodies.append(next.bodies)
        }
        forward.append(end)

        var backward = [Engine.Gravity.Step](repeating: end, count: count + 1)
        for i in stride(from: count - 1, to: 0, by: -1) {
            backward[i] = Engine.Gravity.advance(backward[i + 1], to: forward[i].tt, bodies: bodies[i - 1])
        }

        for i in stride(from: count - 1, to: 0, by: -1) {
            let ramp = Double(i) / Double(count)
            forward[i].position = (1 - ramp) * forward[i].position + ramp * backward[i].position
            forward[i].velocity = (1 - ramp) * forward[i].velocity + ramp * backward[i].velocity
            forward[i].acceleration = (1 - ramp) * forward[i].acceleration + ramp * backward[i].acceleration
        }
        return Segment(steps: forward)
    }

    /// Integration from tabulated state `state` to `tt` in steps of `days`,
    /// the last one shortened to land on `tt`: the C engine's
    /// `CalcPlutoOneWay`. It returns the step at `tt` and the major bodies
    /// there.
    static func crawl(
        from state: TableState, to tt: Double, by days: Double
    ) throws -> (step: Engine.Gravity.Step, bodies: Engine.Gravity.MajorBodies) {
        var (step, bodies) = try Engine.Gravity.start(state)
        let count = Int(((tt - step.tt) / days).rounded(.up))
        for i in 0..<count {
            (step, bodies) = try Engine.Gravity.advance(step, to: i + 1 == count ? tt : step.tt + days)
        }
        return (step, bodies)
    }

    /// `floor(fraction)` held to `0..<count`, the C engine's `ClampIndex`.
    private static func clampedIndex(_ fraction: Double, count: Int) -> Int {
        min(max(Int(fraction.rounded(.down)), 0), count - 1)
    }
}

extension Engine.Gravity {
    /// ``start(heliocentric:velocity:tt:)`` for a tabulated Pluto state.
    static func start(_ state: Engine.Pluto.TableState) throws -> (step: Step, bodies: MajorBodies) {
        try start(heliocentric: state.position, velocity: state.velocity, tt: state.tt)
    }
}
