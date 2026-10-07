//
//  EngineMoonEphemerisTests.swift
//  AstronomyKit
//
//  The DE440 Moon table, its evaluator, the blend weight and the EQJ state.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine DE440 Moon")
struct EngineMoonEphemerisTests {
    typealias Ephemeris = Engine.MoonEphemeris

    static let end = Ephemeris.start + Double(Ephemeris.recordCount) * Ephemeris.recordDays

    @Test("The table's shape and dates")
    func table() {
        #expect(Ephemeris.coefficients.count == 823_329)
        #expect(Ephemeris.recordCount * 3 * Ephemeris.degreeCount == Ephemeris.coefficients.count)
        #expect(Ephemeris.degreeCount == 13)
        #expect(Ephemeris.recordDays == 4)
        // 1899-11-26 00:00 TDB to 2131-02-07 00:00 TDB.
        #expect(Ephemeris.start == Engine.Time.days(year: 1899, month: 11, day: 26, hour: 0, minute: 0, second: 0))
        #expect(Self.end == Engine.Time.days(year: 2131, month: 2, day: 7, hour: 0, minute: 0, second: 0))
        let finite = Ephemeris.coefficients.allSatisfy { $0.isFinite }
        #expect(finite)
        // The full-weight span is 1900-01-01 00:00 TT up to 2131-01-01 00:00 TT.
        let days = { (year: Int) in Engine.Time.days(year: year, month: 1, day: 1, hour: 0, minute: 0, second: 0) }
        #expect(Ephemeris.fullWeightStart == days(1900))
        #expect(Ephemeris.fullWeightEnd == days(2131))
    }

    @Test("The records cover the blends, with TDB − TT at its largest")
    func coverage() {
        // |TDB − TT| stays below 1.7 ms, 2e-8 day.
        let margin = 2e-8
        #expect(Ephemeris.start < Ephemeris.fullWeightStart - Ephemeris.blendDays - margin)
        #expect(Self.end > Ephemeris.fullWeightEnd + Ephemeris.blendDays + margin)
        #expect(Ephemeris.state(tt: (Ephemeris.fullWeightStart - Ephemeris.blendDays).nextUp) != nil)
        #expect(Ephemeris.state(tt: (Ephemeris.fullWeightEnd + Ephemeris.blendDays).nextDown) != nil)
    }

    // MARK: - Evaluator

    static func chebyshev(_ k: Int, _ x: Double) -> Double { cos(Double(k) * acos(x)) }

    @Test("Clenshaw's recurrence equals the Chebyshev sums of the record, and its derivative")
    func clenshaw() throws {
        for record in [0, 1, 7_777, 15_000, Ephemeris.recordCount - 1] {
            // Binary fractions, so the time and its x within the record are exact.
            for x in [-0.875, -0.25, 0.0, 0.5, 0.9375] {
                let tdb = Ephemeris.start + Double(record) * Ephemeris.recordDays + (x + 1) / 2 * Ephemeris.recordDays
                let (position, velocity) = try #require(Ephemeris.evaluate(tdb: tdb))
                for axis in 0..<3 {
                    let base = (3 * record + axis) * Ephemeris.degreeCount
                    let c = Ephemeris.coefficients[base..<base + Ephemeris.degreeCount]
                    let value = c.indices.reduce(0.0) { $0 + c[$1] * Self.chebyshev($1 - base, x) }
                    let slope = c.indices.reduce(0.0) {
                        $0 + c[$1] * EnginePlanetPolynomialTests.chebyshevDerivative($1 - base, x)
                    }
                    #expect(abs(position[axis] - value) <= 1e-17, "record \(record), x \(x), axis \(axis)")
                    // Per TDB day: dx/dt is 2 over the record length.
                    let rate = slope * 2 / Ephemeris.recordDays
                    #expect(abs(velocity[axis] - rate) <= 1e-17, "record \(record), x \(x), axis \(axis)")
                }
            }
        }
    }

    @Test("Each record starts at its first day, and the double below stays in the record before")
    func recordBoundaries() throws {
        // Adjacent records meet: DE440 keeps position and velocity
        // continuous across its record boundaries.
        var largestStep = 0.0
        var largestVelocityStep = 0.0
        for record in 1..<Ephemeris.recordCount {
            let boundary = Ephemeris.start + Double(record) * Ephemeris.recordDays
            let above = try #require(Ephemeris.evaluate(tdb: boundary))
            let below = try #require(Ephemeris.evaluate(tdb: boundary.nextDown))
            largestStep = Self.largest([largestStep, Self.largest(above.position - below.position)])
            largestVelocityStep = Self.largest([largestVelocityStep, Self.largest(above.velocity - below.velocity)])
        }
        // 1e-12 AU is 15 cm; 1e-12 AU per day is under 2 µm/s.
        #expect(largestStep < 1e-12, "\(largestStep) AU")
        #expect(largestVelocityStep < 1e-12, "\(largestVelocityStep) AU/day")
    }

    @Test(
        "Outside the records, and for a time that is not finite, there is nothing",
        arguments: [start.nextDown, end, end.nextUp, -1e300, 1e300, .nan, .infinity, -.infinity])
    func outside(tdb: Double) {
        #expect(Ephemeris.evaluate(tdb: tdb) == nil)
        #expect(Ephemeris.state(tt: tdb) == nil)
    }

    static let start = Ephemeris.start

    @Test("The records evaluate from their first double to within rounding of their end")
    func ends() {
        #expect(Ephemeris.evaluate(tdb: Ephemeris.start) != nil)
        // As in the C evaluator, the doubles just below the end can round up
        // to it when the start is subtracted, and then fall outside.
        #expect(Ephemeris.evaluate(tdb: Self.end - 1e-9) != nil)
    }

    @Test("Velocity is the derivative of position")
    func velocity() throws {
        let h = 1.0 / 256
        for tdb in stride(from: Ephemeris.start + 3, to: Self.end - 3, by: 5_037.25) {
            let position = { (k: Double) throws -> SIMD3<Double> in
                try #require(Ephemeris.evaluate(tdb: tdb + k * h)).position
            }
            let difference = try (position(-2) - 8 * position(-1) + 8 * position(1) - position(2)) / (12 * h)
            let velocity = try #require(Ephemeris.evaluate(tdb: tdb)).velocity
            let error = Self.largest(velocity - difference)
            #expect(error <= 1e-13, "tdb \(tdb): \(error) AU/day")
        }
    }

    /// The largest absolute component, or NaN if any is NaN.
    static func largest(_ difference: SIMD3<Double>) -> Double {
        EnginePlanetPolynomialTests.largest([abs(difference.x), abs(difference.y), abs(difference.z)])
    }

    static func largest(_ values: [Double]) -> Double { EnginePlanetPolynomialTests.largest(values) }

    // MARK: - Weight

    @Test("The weight is 1 over the full span and 0 beyond the blends")
    func weightEnds() {
        let start = Ephemeris.fullWeightStart
        let end = Ephemeris.fullWeightEnd
        let blend = Ephemeris.blendDays
        for tt in [start, start + 1, 0, end - 1, end] {
            #expect(Ephemeris.weight(tt: tt) == (1, 0), "tt \(tt)")
        }
        for tt in [start - blend, start - blend - 1, end + blend, end + blend + 1, -1e300, 1e300, .nan, .infinity] {
            #expect(Ephemeris.weight(tt: tt) == (0, 0), "tt \(tt)")
        }
        #expect(Ephemeris.weight(tt: start - blend / 2).weight == 0.5)
        #expect(Ephemeris.weight(tt: end + blend / 2).weight == 0.5)
    }

    @Test("Across each blend the weight is monotonic, its rate is its derivative, and both are continuous at the ends")
    func weightBlend() {
        let h = 1.0 / 1_024
        for (outer, inner, direction) in [
            (Ephemeris.fullWeightStart - Ephemeris.blendDays, Ephemeris.fullWeightStart, 1.0),
            (Ephemeris.fullWeightEnd + Ephemeris.blendDays, Ephemeris.fullWeightEnd, -1.0),
        ] {
            var previous = 0.0
            for step in 1..<128 {
                let tt = outer + direction * Double(step) / 4
                let (weight, rate) = Ephemeris.weight(tt: tt)
                #expect(weight > previous && weight < 1, "tt \(tt)")
                previous = weight
                let derivative = PublishedOrientation.derivative(at: tt, step: h) { Ephemeris.weight(tt: $0).weight }
                #expect(abs(rate - derivative) <= 1e-12, "tt \(tt)")
            }
            // A thousandth of a day inside each end, weight and rate are
            // within x³ and x² of their values outside, x = 1e-3 / 32.
            for (tt, value) in [(outer + direction * 1e-3, 0.0), (inner - direction * 1e-3, 1.0)] {
                let (weight, rate) = Ephemeris.weight(tt: tt)
                #expect(abs(weight - value) < 1e-12, "tt \(tt)")
                #expect(abs(rate) < 1e-7, "tt \(tt)")
            }
        }
    }

    // MARK: - State

    @Test("The EQJ state is the record at TDB, scaled to TT days and rotated off the ICRS")
    func state() throws {
        for tt in [Ephemeris.fullWeightStart, -12_345.678, 0, 9_497.375, Ephemeris.fullWeightEnd] {
            let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / 86_400
            let source = try #require(Ephemeris.evaluate(tdb: tdb))
            let state = try #require(Ephemeris.state(tt: tt))
            let rate = Engine.TDB.rate(tt: tt)
            #expect(state.position == Engine.FrameBias.icrsToEqj.apply(to: source.position))
            #expect(Ephemeris.position(tt: tt) == state.position)
            #expect(state.velocity == Engine.FrameBias.icrsToEqj.apply(to: source.velocity * rate))
        }
    }
}
