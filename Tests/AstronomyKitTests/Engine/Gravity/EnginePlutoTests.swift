//
//  EnginePlutoTests.swift
//  AstronomyKit
//
//  Pluto's routing between DE440 and the integrated model, the model's
//  segments, seams and extrapolation, and the velocities.
//

import Foundation
import Testing

@testable import AstronomyKit

/// Pluto's segments outside 1900 to 2100 each take seconds to integrate in a
/// Debug build. The suites that read them run one test at a time, so each
/// segment is integrated once into the shared cache instead of by every
/// parallel test that misses it.
@Suite(.serialized) enum PlutoSegmentSuites {}

extension PlutoSegmentSuites {
    @Suite("Engine.Pluto")
    struct EnginePlutoTests {
        typealias Pluto = Engine.Pluto

        static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

        static func position(_ state: Engine.State<Engine.EQJ>) -> SIMD3<Double> { SIMD3(state.x, state.y, state.z) }
        static func velocity(_ state: Engine.State<Engine.EQJ>) -> SIMD3<Double> { SIMD3(state.vx, state.vy, state.vz) }
        static func largest(_ v: SIMD3<Double>) -> Double { EngineMoonEphemerisTests.largest(v) }

        typealias Moon = Engine.MoonEphemeris

        /// Segments 24 and 25 run from 1920 to 2080, where the planets come from
        /// their polynomial fits, so they take a fraction of a second to
        /// integrate. Pluto itself comes from DE440 there; these tests read the
        /// integrated model directly. Seams between them: the tabulated state at
        /// J2000, and steps every 146 days.
        static let cheapSegmentTimes = [-29_200.0 + 0.25, -7_300.5, -0.5, 0.5, 73, 7_373, 29_199.75 - 40]

        // MARK: - Routing

        @Test("In the DE440 span the state is the tables', bit for bit")
        func de440() throws {
            for tt in [Moon.fullWeightStart, -8.5, 0, 9_497.375, Moon.fullWeightEnd] {
                let state = try Pluto.heliocentricState(at: Self.time(tt: tt))
                let (position, velocity) = try #require(Engine.PlutoEphemeris.heliocentricState(tt: tt))
                #expect(Self.position(state) == position, "tt \(tt)")
                #expect(Self.velocity(state) == velocity, "tt \(tt)")
            }
        }

        @Test("Beyond the blends the state is the integrated model's, bit for bit")
        func model() throws {
            for tt in [Moon.fullWeightStart - Moon.blendDays, -36_600, Moon.fullWeightEnd + Moon.blendDays, 47_900] {
                let state = try Pluto.heliocentricState(at: Self.time(tt: tt))
                let model = try Pluto.modelState(tt: tt, heliocentric: true)
                #expect(Self.position(state) == model.position, "tt \(tt)")
                #expect(Self.velocity(state) == model.velocity, "tt \(tt)")
            }
        }

        @Test(
            "In a blend the state mixes DE440 into the model by the weight, and the velocity carries the weight's rate")
        func blend() throws {
            for tt in [-36_548.25, -36_540.5, 47_854.5, 47_870.75] {
                let (weight, rate) = Moon.weight(tt: tt)
                #expect(weight > 0 && weight < 1)
                let state = try Pluto.heliocentricState(at: Self.time(tt: tt))
                let (position, velocity) = try #require(Engine.PlutoEphemeris.heliocentricState(tt: tt))
                let model = try Pluto.modelState(tt: tt, heliocentric: true)
                let mixed = model.position + weight * (position - model.position)
                let mixedVelocity =
                    model.velocity + weight * (velocity - model.velocity) + rate * (position - model.position)
                #expect(Self.position(state) == mixed, "tt \(tt)")
                #expect(Self.velocity(state) == mixedVelocity, "tt \(tt)")
            }
        }

        @Test("No jump at the ends of either blend")
        func blendEnds() throws {
            for tt in [
                Moon.fullWeightStart - Moon.blendDays, Moon.fullWeightStart, Moon.fullWeightEnd,
                Moon.fullWeightEnd + Moon.blendDays,
            ] {
                let before = try Pluto.heliocentricState(at: Self.time(tt: tt.nextDown))
                let after = try Pluto.heliocentricState(at: Self.time(tt: tt.nextUp))
                #expect(Self.largest(Self.position(before) - Self.position(after)) <= 1e-11, "tt \(tt)")
                #expect(Self.largest(Self.velocity(before) - Self.velocity(after)) <= 1e-11, "tt \(tt)")
            }
        }

        @Test("The barycentric state is the heliocentric one plus the Sun's barycentric state")
        func barycentric() throws {
            for tt in [-730_000.5, -36_600, -36_540.5, 0, 47_862.5, 730_000.5] {
                let time = Self.time(tt: tt)
                let heliocentric = try Pluto.heliocentricState(at: time)
                let barycentric = try Pluto.barycentricState(at: time)
                let sun = try Engine.Gravity.MajorBodies(tt: tt).sun
                #expect(
                    Self.largest(Self.position(barycentric) - Self.position(heliocentric) - sun.position) <= 1e-13,
                    "tt \(tt)")
                #expect(
                    Self.largest(Self.velocity(barycentric) - Self.velocity(heliocentric) - sun.velocity) <= 1e-17,
                    "tt \(tt)")
            }
        }

        @Test("The position is the state's, and the result keeps the caller's time")
        func positionAndTime() throws {
            for tt in [-36_600.0, -36_540.5, 0] {
                let time = Engine.Time(ut: tt - 0.001, tt: tt, deltaTModel: .jplHorizons)
                let state = try Pluto.heliocentricState(at: time)
                let position = try Pluto.heliocentricPosition(at: time)
                #expect([position.x, position.y, position.z] == [state.x, state.y, state.z])
                #expect(state.time.ut == time.ut && state.time.tt == tt && state.time.deltaTModel == .jplHorizons)
                #expect(position.time.ut == time.ut)
            }
        }

        // MARK: - The integrated model

        @Test("A tabulated state's position comes back exactly at its time")
        func tabulatedStates() throws {
            for index in [24, 25] {
                let state = Pluto.stateTable[index]
                let model = try Pluto.modelState(tt: state.tt, heliocentric: true)
                #expect(model.position == state.position, "state \(index)")
                // The velocity is the interpolant's derivative, which the
                // backward step's acceleration moves by about 1e-7 AU per day.
                #expect(Self.largest(model.velocity - state.velocity) <= 2e-7, "state \(index)")
            }
        }

        @Test("A segment holds 201 steps 146 days apart, from one tabulated state to the next")
        func segmentShape() throws {
            let segment = try Pluto.segment(25)
            #expect(segment.steps.count == Pluto.stepsPerSegment + 1)
            for (i, step) in segment.steps.enumerated() {
                #expect(step.tt == Pluto.stateTable[25].tt + Double(i) * Pluto.stepDays)
            }
            let start = try Engine.Gravity.start(Pluto.stateTable[25]).step
            #expect(segment.steps[0].position == start.position)
            #expect(segment.steps[0].acceleration == start.acceleration)
            let end = Pluto.stateTable[26]
            let last = try Engine.Gravity.start(end).step
            #expect(segment.steps[200].position == last.position)
            #expect(segment.steps[200].velocity == last.velocity)
        }

        /// The forward and backward integrations disagree by up to about
        /// 900,000 km over a segment, from the tabulated states' own errors (see
        /// #119); the mix makes the steps meet both ends.
        @Test("The mix takes i/200 of the backward integration at step i")
        func segmentMix() throws {
            let index = 25
            let segment = try Pluto.segment(index)
            let first = Pluto.stateTable[index]
            var forward = try Engine.Gravity.start(first)
                .step
            for i in 1...100 {
                forward = try Engine.Gravity.advance(forward, to: first.tt + Double(i) * Pluto.stepDays).step
            }
            let last = Pluto.stateTable[index + 1]
            var backward = try Engine.Gravity.start(last)
                .step
            for i in stride(from: 199, through: 100, by: -1) {
                backward = try Engine.Gravity.advance(backward, to: last.tt - Double(200 - i) * Pluto.stepDays).step
            }
            let middle = segment.steps[100]
            #expect(middle.position == 0.5 * forward.position + 0.5 * backward.position)
            #expect(middle.velocity == 0.5 * forward.velocity + 0.5 * backward.velocity)
            #expect(middle.acceleration == 0.5 * forward.acceleration + 0.5 * backward.acceleration)
        }

        @Test("No jump at a segment seam or a step seam")
        func seams() throws {
            // J2000 is the tabulated state between segments 24 and 25; the others
            // are steps of segment 25.
            for tt: Double in [0, 146, 7_300, 29_200 - 146] {
                let before = try Pluto.modelState(tt: tt.nextDown, heliocentric: true)
                let at = try Pluto.modelState(tt: tt, heliocentric: true)
                #expect(Self.largest(before.position - at.position) <= 1e-13, "tt \(tt)")
                // The velocity is continuous to about 6e-12 AU per day.
                #expect(Self.largest(before.velocity - at.velocity) <= 1e-10, "tt \(tt)")
            }
        }

        /// Five-point differences on 1/64-day stencils, which stay inside one
        /// step, as the velocity is the derivative within a step.
        @Test("The model's velocity is the derivative of its position", arguments: cheapSegmentTimes)
        func modelVelocity(tt: Double) throws {
            let h = 1.0 / 64
            func position(_ t: Double) throws -> SIMD3<Double> {
                try Pluto.modelState(tt: t, heliocentric: true).position
            }
            let difference =
                (try position(tt - 2 * h) - 8 * position(tt - h) + 8 * position(tt + h) - position(tt + 2 * h))
                / (12 * h)
            let velocity = try Pluto.modelState(tt: tt, heliocentric: true).velocity
            #expect(Self.largest(velocity - difference) <= 2e-12)
        }

        /// The C engine's test of the public velocities at the transitions and
        /// data seams: five-point differences on 1/256-day stencils within
        /// 2e-9 AU per day.
        @Test(
            "The velocity is the derivative of the position through the blends and the DE440 records",
            arguments: [
                -36_556.5, -36_548.5, -36_540.5, -36_524.5, (-36_524.5).nextUp, -8.5, -0.5, 0, 1, 47_846.5, 47_854.5,
                47_862.5, 47_878.5,
            ])
        func velocity(tt: Double) throws {
            let h = 1.0 / 256
            func position(_ t: Double) throws -> SIMD3<Double> {
                Self.position(try Pluto.heliocentricState(at: Self.time(tt: t)))
            }
            let difference =
                (try position(tt - 2 * h) - 8 * position(tt - h) + 8 * position(tt + h) - position(tt + 2 * h))
                / (12 * h)
            let velocity = Self.velocity(try Pluto.heliocentricState(at: Self.time(tt: tt)))
            #expect(Self.largest(velocity - difference) <= 2e-9)
        }

        // MARK: - Beyond the table

        @Test("Just past the last tabulated state the model integrates one short step from it")
        func pastTheTable() throws {
            let last = Pluto.stateTable[Pluto.segmentCount]
            let at = try Pluto.modelState(tt: last.tt, heliocentric: true)
            let past = try Pluto.modelState(tt: last.tt.nextUp, heliocentric: true)
            #expect(at.position == last.position)
            #expect(Self.largest(past.position - last.position) <= 1e-12)
            #expect(Self.largest(past.velocity - last.velocity) <= 1e-15)
            // A day out, the model has moved a day's motion, plus less than
            // 2e-7 AU from the Sun's pull.
            let day = try Pluto.modelState(tt: last.tt + 1, heliocentric: true)
            #expect(Self.largest(day.position - last.position - last.velocity) <= 2e-7)
        }

        @Test("The model reaches 36,525 days before the first state, and throws badTime beyond either limit")
        func limits() throws {
            let first = Pluto.stateTable[0].tt
            let last = Pluto.stateTable[Pluto.segmentCount].tt
            _ = try Pluto.heliocentricState(at: Self.time(tt: first - Pluto.crawlLimitDays))
            for tt in [
                (first - Pluto.crawlLimitDays).nextDown, (last + Pluto.crawlLimitDays).nextUp, -1e6, 1e6,
                Engine.acceptedTTDays, .nan, .infinity, -.infinity,
            ] {
                let time = Self.time(tt: tt)
                #expect(throws: AstronomyError.badTime, "tt \(tt)") { _ = try Pluto.heliocentricState(at: time) }
                #expect(throws: AstronomyError.badTime, "tt \(tt)") { _ = try Pluto.barycentricState(at: time) }
                #expect(throws: AstronomyError.badTime, "tt \(tt)") { _ = try Pluto.heliocentricPosition(at: time) }
            }
            #expect(throws: AstronomyError.badTime) { _ = try Pluto.heliocentricState(at: .invalid) }
        }
    }
}
