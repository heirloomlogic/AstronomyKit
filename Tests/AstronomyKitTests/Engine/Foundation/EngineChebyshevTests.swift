//
//  EngineChebyshevTests.swift
//  AstronomyKit
//
//  The Chebyshev record evaluator the Moon and Pluto tables share.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.ChebyshevTable")
struct EngineChebyshevTests {
    /// Two 2-day records from t = 0 holding t², 2t² and −t² on x, y and z.
    /// On record k, t = 2k + 1 + u with u from −1 to 1, and
    /// t² = (2k + 1)² + 1/2 + 2(2k + 1)·T1(u) + T2(u)/2.
    static let table = Engine.ChebyshevTable(
        start: 0, recordDays: 2, recordCount: 2, degreeCount: 3,
        coefficients: [
            1.5, 2, 0.5, 3, 4, 1, -1.5, -2, -0.5,
            9.5, 6, 0.5, 19, 12, 1, -9.5, -6, -0.5,
        ])

    @Test("Values and derivatives across both records, with the end excluded")
    func polynomial() throws {
        for t in [0.0, 0.5, 1, 2.nextDown, 2, 2.nextUp, 3, 4.nextDown] {
            let (position, velocity) = try #require(Self.table.evaluate(tdb: t))
            for (axis, scale) in [1.0, 2, -1].enumerated() {
                #expect(abs(position[axis] - scale * t * t) <= 2e-14, "t \(t), axis \(axis)")
                #expect(abs(velocity[axis] - 2 * scale * t) <= 2e-14, "t \(t), axis \(axis)")
            }
        }
        for t in [-Double.leastNonzeroMagnitude, 4, 5, .nan, .infinity, -.infinity] {
            #expect(Self.table.evaluate(tdb: t) == nil, "t \(t)")
        }
    }

    @Test("A start that is not zero shifts the records")
    func offset() throws {
        let shifted = Engine.ChebyshevTable(
            start: -36_584.5, recordDays: 2, recordCount: 2, degreeCount: 3, coefficients: Self.table.coefficients)
        for u in [0.0, 1.5, 3.25] {
            let (position, _) = try #require(shifted.evaluate(tdb: -36_584.5 + u))
            #expect(abs(position.x - u * u) <= 1e-11)
        }
        #expect(shifted.evaluate(tdb: (-36_584.5).nextDown) == nil)
    }
}
