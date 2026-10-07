//
//  EnginePlanetPolynomialTests.swift
//  AstronomyKit
//
//  Chebyshev evaluation, segment selection at every boundary, excluded
//  segments, and heliocentric distance against JPL Horizons.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.PlanetPolynomial")
struct EnginePlanetPolynomialTests {
    typealias Polynomial = Engine.PlanetPolynomial

    static let start = Polynomial.start
    static let stop = Polynomial.stop

    // MARK: - Clenshaw's recurrence

    /// A model of 8-day segments over the span, each with the same
    /// polynomials: T_k on the x axis, zero on y, and Σ T_j / (j + 1) on z.
    static func syntheticModel(k: Int) -> Polynomial.Model {
        var segment = [Double](repeating: 0, count: 39)
        segment[k] = 1
        for j in 0...12 { segment[26 + j] = 1 / Double(j + 1) }
        let count = Int(((stop - start) / 8).rounded(.up))
        return Polynomial.Model(
            degree: 12, width: 8, excludedSegments: [],
            coefficients: Array([[Double]](repeating: segment, count: count).joined()))
    }

    /// dT_k/dx = k·U_{k−1}(x), with U from its own recurrence.
    static func chebyshevDerivative(_ k: Int, _ x: Double) -> Double {
        guard k > 0 else { return 0 }
        var previous = 1.0  // U_0
        var current = 2 * x  // U_1
        if k == 1 { return 1 }
        for _ in 2..<k {
            (previous, current) = (current, 2 * x * current - previous)
        }
        return Double(k) * current
    }

    @Test("Each Chebyshev polynomial and its derivative", arguments: 0...12)
    func chebyshev(k: Int) throws {
        let model = Self.syntheticModel(k: k)
        // x = j/8 − 1 is exact at these binary-fraction epochs in the first
        // segment and in one near J2000; half a width is 4 days.
        let half = 4.0
        for j in 0..<16 {
            let tt = Self.start + 8 * (j.isMultiple(of: 2) ? 0 : 4_565) + 0.5 * Double(j)
            let x = Double(j) / 8 - 1
            let theta = acos(x)
            let state = try #require(model.state(tt: tt))
            #expect(abs(state.position.x - cos(Double(k) * theta)) <= 1e-14, "k \(k), x \(x)")
            #expect(state.position.y == 0)
            let z = (0...12).reduce(0.0) { $0 + cos(Double($1) * theta) / Double($1 + 1) }
            #expect(abs(state.position.z - z) <= 1e-14, "x \(x)")
            // Velocity is per day; times half the width it is per unit of x, exactly.
            let derivative = Self.chebyshevDerivative(k, x)
            #expect(abs(state.velocity.x * half - derivative) <= 1e-14 * max(1, abs(derivative)), "k \(k), x \(x)")
            #expect(state.velocity.y == 0)
        }
    }

    // MARK: - Segments

    @Test("Every boundary starts its segment, and the double below it stays in the segment below")
    func everyBoundary() {
        for planet in Engine.Planet.allCases {
            let model = Polynomial.model(planet)
            var wrong: [Int] = []
            var roundedUp = 0
            for k in 1..<model.segmentCount {
                let boundary = model.start(ofSegment: k)
                if model.segment(containing: boundary) != k || model.segment(containing: boundary.nextDown) != k - 1 {
                    wrong.append(k)
                }
                // The subtraction rounds the predecessor up to the boundary's offset.
                if Int((boundary.nextDown - Self.start) / model.width) == k { roundedUp += 1 }
            }
            #expect(wrong.isEmpty, "\(planet): \(wrong.prefix(5))")
            #expect(roundedUp > 0, "\(planet): no boundary exercises the predecessor correction")
            #expect(model.segment(containing: Self.start) == 0)
            #expect(model.segment(containing: Self.stop.nextDown) == model.segmentCount - 1)
        }
    }

    @Test(
        "Outside the span, including input that is not finite, nothing applies",
        arguments: [
            start.nextDown, stop, stop.nextUp, -1e300, 1e300, .nan, .infinity, -.infinity,
        ])
    func outside(tt: Double) {
        for planet in Engine.Planet.allCases {
            #expect(Polynomial.model(planet).segment(containing: tt) == nil)
            #expect(Polynomial.position(planet, tt: tt) == nil)
            #expect(Polynomial.state(planet, tt: tt) == nil)
        }
    }

    @Test("Excluded segments give nothing from their first double to their last; every other segment gives a value")
    func excludedSegments() {
        for planet in Engine.Planet.allCases {
            let model = Polynomial.model(planet)
            var wrong: [Int] = []
            for k in 0..<model.segmentCount {
                let first = model.start(ofSegment: k)
                let last = min(model.start(ofSegment: k + 1), Self.stop).nextDown
                for tt in [first, (first + last) / 2, last] {
                    let position = Polynomial.position(planet, tt: tt)
                    let state = Polynomial.state(planet, tt: tt)
                    if (position == nil) == model.included[k] || (state == nil) == model.included[k] {
                        wrong.append(k)
                    }
                }
            }
            #expect(wrong.isEmpty, "\(planet): \(wrong.prefix(5))")
        }
    }

    @Test("A state's position is the position, double for double")
    func stateMatchesPosition() throws {
        for planet in Engine.Planet.allCases {
            let model = Polynomial.model(planet)
            for k in stride(from: 0, to: model.segmentCount, by: 7) where model.included[k] {
                for tt in [model.start(ofSegment: k), model.start(ofSegment: k) + model.width / 3] {
                    let position = try #require(model.position(tt: tt))
                    let state = try #require(model.state(tt: tt))
                    #expect(
                        [position.x, position.y, position.z].map(\.bitPattern)
                            == [state.position.x, state.position.y, state.position.z].map(\.bitPattern))
                }
            }
        }
    }

    /// With a 1/64-day step the five-point difference's truncation is about
    /// 2e-15 AU per day for Mercury's 88-day orbit. Its rounding, about 18
    /// rounding errors of the position over 12 steps, reaches about 4e-14
    /// AU per day per AU of distance, so the allowance scales with it.
    @Test("Velocity is the derivative of the position")
    func velocity() throws {
        let step = 1.0 / 64
        for planet in Engine.Planet.allCases {
            let model = Polynomial.model(planet)
            for k in stride(from: 0, to: model.segmentCount, by: model.segmentCount / 40) where model.included[k] {
                // The stencil stays inside the segment.
                let tt = model.start(ofSegment: k) + model.width / 2
                let state = try #require(model.state(tt: tt))
                for axis in 0..<3 {
                    let difference = PublishedOrientation.derivative(at: tt, step: step) {
                        model.position(tt: $0)![axis]
                    }
                    let tolerance = 5e-14 * max(1, abs(state.position[axis]))
                    #expect(abs(state.velocity[axis] - difference) <= tolerance, "\(planet) segment \(k) axis \(axis)")
                }
            }
        }
    }

    /// Adjacent fits each stay within 1e-12 AU of the series they were fitted
    /// to, so they meet within 2e-12 AU, plus the motion across the one-ulp
    /// step from the predecessor to the boundary.
    @Test("Adjacent segments meet at every shared boundary")
    func continuity() throws {
        for planet in Engine.Planet.allCases {
            let model = Polynomial.model(planet)
            var jumps: [Double] = []
            for k in 1..<model.segmentCount where model.included[k - 1] && model.included[k] {
                let boundary = model.start(ofSegment: k)
                let before = try #require(model.state(tt: boundary.nextDown))
                let after = try #require(model.position(tt: boundary))
                let step = boundary - boundary.nextDown
                for axis in 0..<3 {
                    jumps.append(abs(after[axis] - before.position[axis]) - abs(before.velocity[axis]) * step)
                }
            }
            let worst = Self.largest(jumps)
            #expect(worst <= 2e-12, "\(planet): \(worst) AU")
        }
    }

    /// The largest of `values`, or NaN when any of them is NaN, so a NaN
    /// anywhere fails a `<=` check.
    static func largest(_ values: [Double]) -> Double {
        if values.contains(where: \.isNaN) { return .nan }
        return values.max() ?? -.infinity
    }

    @Test("A NaN at any seam fails the continuity check", arguments: [0, 1, 2])
    func largestKeepsNaN(position: Int) {
        var values = [1e-13, 2e-13, 1e-14]
        values[position] = .nan
        #expect(Self.largest(values).isNaN)
        #expect(Self.largest([1e-13, 3e-13, 2e-13]) == 3e-13)
    }

    // MARK: - Published values

    typealias DistanceReference = DistanceReferenceArchive.Reference

    static let heliocentric = PlanetTestSupport.heliocentric

    static func errorKm(_ planet: Engine.Planet, _ reference: DistanceReference, offset: Double = 0) -> Double? {
        guard let position = Polynomial.position(planet, tt: reference.julianDateTT - 2_451_545 + offset) else {
            return nil
        }
        let range = (position * position).sum().squareRoot()
        return abs(range - reference.referenceRangeAU) * Engine.kilometersPerAU
    }

    /// The allowances are those `DistanceAccuracyTests` applies to the public
    /// heliocentric distance. A record in an excluded segment needs the full
    /// series and is not checked here.
    @Test("Heliocentric distance against JPL Horizons, within the held-out allowances")
    func horizonsDistance() {
        #expect(Self.heliocentric.count == 8 * 134)
        var checked = 0
        for (planet, reference) in Self.heliocentric {
            guard let error = Self.errorKm(planet, reference) else { continue }
            checked += 1
            #expect(error <= reference.allowedErrorKm, "\(planet) JD TT \(reference.julianDateTT): \(error) km")
        }
        #expect(checked == 1_067)
    }

    @Test("The distance check fails for the wrong planet or a day's error")
    func horizonsNegativeControls() throws {
        let (planet, reference) = try #require(
            Self.heliocentric.first { $0.planet == .mercury && Self.errorKm(.mercury, $0.reference) != nil })
        try #expect(#require(Self.errorKm(.venus, reference)) > reference.allowedErrorKm)
        try #expect(#require(Self.errorKm(planet, reference, offset: 1)) > reference.allowedErrorKm)
    }
}
