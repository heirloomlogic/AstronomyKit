//
//  EngineVSOP87BTests.swift
//  AstronomyKit
//
//  The full VSOP87B series against IMCCE's check values, and their summation.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.VSOP87B series")
struct EngineVSOP87BTests {
    static let daysPerMillennium = 365_250.0

    /// Values are printed to ten decimals, so each is within 5e-11 of the
    /// series; the published computation's own rounding adds up to about
    /// 3e-11 in longitude, which sums seven powers of the series.
    static let tolerance = 1e-10

    @Test("Coordinates and their rates against IMCCE vsop87.chk", arguments: PublishedVSOP87.records)
    func published(record: PublishedVSOP87.Record) {
        let model = Engine.VSOP87B.model(record.planet)
        let t = record.tt / Self.daysPerMillennium
        let sphere = Engine.VSOP87B.coordinates(model, millennia: t)
        let rates = Engine.VSOP87B.derivatives(model, millennia: t) / Self.daysPerMillennium
        #expect(abs(remainder(sphere[0] - record.longitude, 2 * .pi)) <= Self.tolerance)
        #expect(abs(sphere[1] - record.latitude) <= Self.tolerance)
        #expect(abs(sphere[2] - record.radius) <= Self.tolerance)
        #expect(abs(rates[0] - record.longitudeRate) <= Self.tolerance)
        #expect(abs(rates[1] - record.latitudeRate) <= Self.tolerance)
        #expect(abs(rates[2] - record.radiusRate) <= Self.tolerance)
    }

    @Test("The check values cover every planet at ten dates")
    func publishedCoverage() {
        #expect(PublishedVSOP87.records.count == 80)
        for planet in Engine.Planet.allCases {
            #expect(PublishedVSOP87.records.filter { $0.planet == planet }.count == 10)
        }
    }

    // MARK: - Summation

    /// The correctly rounded sum of `values`, by Shewchuk's algorithm as
    /// Python's `math.fsum` implements it.
    static func exactSum(_ values: [Double]) -> Double {
        var partials: [Double] = []
        for value in values {
            var x = value
            var kept = 0
            for index in partials.indices {
                var y = partials[index]
                if abs(x) < abs(y) { swap(&x, &y) }
                let high = x + y
                let low = y - (high - x)
                if low != 0 {
                    partials[kept] = low
                    kept += 1
                }
                x = high
            }
            partials.removeSubrange(kept...)
            partials.append(x)
        }
        var n = partials.count
        guard n > 0 else { return 0 }
        n -= 1
        var high = partials[n]
        var low = 0.0
        while n > 0 {
            let x = high
            n -= 1
            let y = partials[n]
            high = x + y
            low = y - (high - x)
            if low != 0 { break }
        }
        if n > 0, (low < 0 && partials[n - 1] < 0) || (low > 0 && partials[n - 1] > 0) {
            let y = low * 2
            let x = high + y
            if y == x - high { high = x }
        }
        return high
    }

    /// The series evaluated with `sum` for every addition, in the engine's
    /// structure: each power's terms, then each power's contribution, with
    /// longitude contributions reduced modulo 2π.
    static func coordinates(_ model: Engine.VSOP87B.Model, t: Double, sum: ([Double]) -> Double) -> SIMD3<Double> {
        var result = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var increments: [Double] = []
            var power = 1.0
            for count in model.termCounts[coordinate] {
                // Split up so Swift 6.2 on Linux type-checks it in time.
                var values: [Double] = []
                for i in term..<term + count {
                    let amplitude: Double = model.terms[3 * i]
                    let phase: Double = model.terms[3 * i + 1]
                    let frequency: Double = model.terms[3 * i + 2]
                    values.append(amplitude * cos(phase + t * frequency))
                }
                term += count
                var increment = power * sum(values)
                if coordinate == 0 { increment = increment.truncatingRemainder(dividingBy: 2 * .pi) }
                increments.append(increment)
                power *= t
            }
            result[coordinate] = sum(increments)
        }
        return result
    }

    /// At the 1900 and 2100 ends of the polynomial span and further out,
    /// plain addition loses low bits on Mercury's longitude: every term of
    /// the t¹ series is rounded at the precision of its first, about 26,088
    /// radians per millennium, and the loss is multiplied by t.
    @Test("Compensated sums match exact summation where plain addition does not", arguments: [-0.1, 0.1, -2.5, 3.75])
    func compensation(t: Double) {
        let model = Engine.VSOP87B.model(.mercury)
        let compensated = Engine.VSOP87B.coordinates(model, millennia: t)
        let exact = Self.coordinates(model, t: t, sum: Self.exactSum)
        let plain = Self.coordinates(model, t: t, sum: { $0.reduce(0, +) })
        for axis in 0..<3 {
            #expect(compensated[axis].bitPattern == exact[axis].bitPattern, "axis \(axis)")
        }
        // Plain addition is off by 1.4e-12 to 2.2e-10 radians at these t.
        #expect(abs(plain[0] - exact[0]) >= 1e-12)
    }

    @Test("Input that is not finite gives NaN", arguments: [Double.nan, .infinity, -.infinity])
    func nonfinite(t: Double) {
        for planet in Engine.Planet.allCases {
            let model = Engine.VSOP87B.model(planet)
            let sphere = Engine.VSOP87B.coordinates(model, millennia: t)
            let rates = Engine.VSOP87B.derivatives(model, millennia: t)
            for axis in 0..<3 {
                #expect(sphere[axis].isNaN, "\(planet) axis \(axis)")
                #expect(rates[axis].isNaN, "\(planet) axis \(axis)")
            }
        }
    }
}
