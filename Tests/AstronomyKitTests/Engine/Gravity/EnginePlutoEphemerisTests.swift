//
//  EnginePlutoEphemerisTests.swift
//  AstronomyKit
//
//  The DE440 and PLU060 Pluto tables, Astronomy Engine's tabulated states,
//  and the heliocentric state they give.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine DE440 and PLU060 Pluto")
struct EnginePlutoEphemerisTests {
    typealias Ephemeris = Engine.PlutoEphemeris

    struct Table: Sendable, CustomTestStringConvertible {
        let name: String
        let table: Engine.ChebyshevTable
        let recordDays: Double
        let degreeCount: Int
        let recordCount: Int
        /// The first record's start and the last record's end, 00:00 TDB.
        let first: (year: Int, month: Int, day: Int)
        let last: (year: Int, month: Int, day: Int)
        var testDescription: String { name }
    }

    static let tables = [
        Table(
            name: "barycenter", table: Ephemeris.barycenter, recordDays: 32, degreeCount: 6, recordCount: 2_640,
            first: (1899, 11, 2), last: (2131, 2, 19)),
        Table(
            name: "barycenterFromSun", table: Ephemeris.barycenterFromSun, recordDays: 16, degreeCount: 11,
            recordCount: 5_279, first: (1899, 11, 18), last: (2131, 2, 19)),
        Table(
            name: "center", table: Ephemeris.center, recordDays: 3, degreeCount: 16, recordCount: 28_151,
            first: (1899, 11, 22), last: (2131, 2, 12)),
    ]

    static func days(_ date: (year: Int, month: Int, day: Int)) -> Double {
        Engine.Time.days(year: date.year, month: date.month, day: date.day, hour: 0, minute: 0, second: 0)
    }

    static func end(_ table: Engine.ChebyshevTable) -> Double {
        table.start + Double(table.recordCount) * table.recordDays
    }

    @Test("Each table's shape and dates", arguments: tables)
    func shape(_ entry: Table) {
        let table = entry.table
        #expect(table.recordDays == entry.recordDays)
        #expect(table.degreeCount == entry.degreeCount)
        #expect(table.recordCount == entry.recordCount)
        #expect(table.coefficients.count == entry.recordCount * 3 * entry.degreeCount)
        #expect(table.start == Self.days(entry.first))
        #expect(Self.end(table) == Self.days(entry.last))
        let finite = table.coefficients.allSatisfy { $0.isFinite }
        #expect(finite)
    }

    /// The tables must reach past both blends of ``Engine/MoonEphemeris``,
    /// read at TDB, which is within 1.7 ms (2e-8 day) of TT.
    @Test("Every table covers both blends, with TDB − TT at its largest", arguments: tables)
    func coverage(_ entry: Table) {
        let margin = 2e-8
        let moon = Engine.MoonEphemeris.self
        #expect(entry.table.start < moon.fullWeightStart - moon.blendDays - margin)
        #expect(Self.end(entry.table) > moon.fullWeightEnd + moon.blendDays + margin)
    }

    @Test("The state is defined across both blends, and not beyond the records or for a TT that is not finite")
    func definedSpan() {
        let moon = Engine.MoonEphemeris.self
        #expect(Ephemeris.heliocentricState(tt: (moon.fullWeightStart - moon.blendDays).nextUp) != nil)
        #expect(Ephemeris.heliocentricState(tt: (moon.fullWeightEnd + moon.blendDays).nextDown) != nil)
        // The center table starts last and ends first.
        #expect(Ephemeris.heliocentricState(tt: Ephemeris.center.start - 1) == nil)
        #expect(Ephemeris.heliocentricState(tt: Self.end(Ephemeris.center) + 1) == nil)
        for tt in [Double.nan, .infinity, -.infinity] {
            #expect(Ephemeris.heliocentricState(tt: tt) == nil)
        }
    }

    @Test("Clenshaw's recurrence equals the Chebyshev sums and their derivatives", arguments: tables)
    func clenshaw(_ entry: Table) throws {
        let table = entry.table
        for record in [0, 1, table.recordCount / 2, table.recordCount - 1] {
            for x in [-0.875, -0.25, 0.0, 0.5, 0.9375] {
                let tdb = table.start + Double(record) * table.recordDays + (x + 1) / 2 * table.recordDays
                let (position, velocity) = try #require(table.evaluate(tdb: tdb))
                for axis in 0..<3 {
                    let base = (3 * record + axis) * table.degreeCount
                    let c = table.coefficients[base..<base + table.degreeCount]
                    let value = c.indices.reduce(0.0) { $0 + c[$1] * EngineMoonEphemerisTests.chebyshev($1 - base, x) }
                    let slope = c.indices.reduce(0.0) {
                        $0 + c[$1] * EnginePlanetPolynomialTests.chebyshevDerivative($1 - base, x)
                    }
                    let scale = max(1, abs(value))
                    #expect(abs(position[axis] - value) <= 1e-15 * scale, "record \(record), x \(x), axis \(axis)")
                    #expect(
                        abs(velocity[axis] - slope * 2 / table.recordDays) <= 1e-17 * scale,
                        "record \(record), x \(x), axis \(axis)")
                }
            }
        }
    }

    /// JPL fits each record to meet its neighbors, so the position and
    /// velocity barely move across a boundary. The largest steps are about
    /// 2e-14 AU, in the barycenter's 40 AU, and 1e-16 AU per day.
    @Test("Adjacent records meet within 1e-13 AU and 1e-15 AU per day", arguments: tables)
    func recordBoundaries(_ entry: Table) throws {
        let table = entry.table
        var steps: [Double] = []
        var velocitySteps: [Double] = []
        for record in 1..<table.recordCount {
            let boundary = table.start + Double(record) * table.recordDays
            let before = try #require(table.evaluate(tdb: boundary.nextDown))
            let after = try #require(table.evaluate(tdb: boundary))
            steps.append(EngineMoonEphemerisTests.largest(before.position - after.position))
            velocitySteps.append(EngineMoonEphemerisTests.largest(before.velocity - after.velocity))
        }
        #expect(EngineMoonEphemerisTests.largest(steps) <= 1e-13)
        #expect(EngineMoonEphemerisTests.largest(velocitySteps) <= 1e-15)
    }

    @Test("The state is the three tables read at TDB and rotated to EQJ, in order")
    func composition() throws {
        for tt in [-36_540.5, -8.5, 0, 9_497.375, 47_862.5] {
            let (position, velocity) = try #require(Ephemeris.heliocentricState(tt: tt))
            let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / 86_400
            let rate = Engine.TDB.rate(tt: tt)
            var expectedPosition = SIMD3<Double>.zero
            var expectedVelocity = SIMD3<Double>.zero
            for table in [Ephemeris.barycenter, Ephemeris.barycenterFromSun, Ephemeris.center] {
                let (p, v) = try #require(table.evaluate(tdb: tdb))
                expectedPosition += Engine.FrameBias.icrsToEqj.apply(to: p)
                expectedVelocity += Engine.FrameBias.icrsToEqj.apply(to: v * rate)
            }
            #expect(position == expectedPosition, "tt \(tt)")
            #expect(velocity == expectedVelocity, "tt \(tt)")
        }
    }

    // MARK: - Tabulated states

    @Test("Astronomy Engine's 51 states run every 29,200 days from TT −730,000 to +730,000")
    func stateTable() {
        let table = Engine.Pluto.stateTable
        #expect(table.count == Engine.Pluto.segmentCount + 1)
        for (k, state) in table.enumerated() {
            #expect(state.tt == -730_000 + 29_200 * Double(k))
            let distance = (state.position * state.position).sum().squareRoot()
            let speed = (state.velocity * state.velocity).sum().squareRoot()
            // Pluto stays between 29 and 50 AU from the Sun and moves at 2.0
            // to 3.7 milliAU per day.
            #expect(distance > 29 && distance < 50, "state \(k)")
            #expect(speed > 2.0e-3 && speed < 3.7e-3, "state \(k)")
        }
        // The first row as Astronomy Engine prints it.
        #expect(table[0].position == SIMD3(-26.118207232108, -14.376168177825, 3.384402515299))
        #expect(table[0].velocity == SIMD3(1.6339372163656e-03, -2.7861699588508e-03, -1.3585880229445e-03))
    }
}
