//
//  EnginePlanetTablesTests.swift
//  AstronomyKit
//
//  The generated VSOP87B and polynomial tables: layout, decoding and
//  published VSOP87B terms.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine planet tables")
struct EnginePlanetTablesTests {
    /// Term `index` of power `power` of coordinate `coordinate` (0 longitude,
    /// 1 latitude, 2 radius) as (A, B, C).
    static func term(_ planet: Engine.Planet, coordinate: Int, power: Int, index: Int) -> (Double, Double, Double) {
        let model = Engine.VSOP87B.model(planet)
        let before =
            model.termCounts[..<coordinate].joined().reduce(0, +)
            + model.termCounts[coordinate][..<power].reduce(0, +)
        let offset = 3 * (before + index)
        return (model.terms[offset], model.terms[offset + 1], model.terms[offset + 2])
    }

    @Test("Each planet maps from its body, and no other body maps")
    func planets() {
        #expect(
            Engine.Planet.allCases.map { CelestialBody(rawValue: Int32($0.rawValue)) } == [
                .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune,
            ])
        for body in CelestialBody.allCases {
            let planet = Engine.Planet(body)
            #expect(planet.map { Int32($0.rawValue) } == (body.rawValue <= 7 ? body.rawValue : nil), "\(body)")
        }
    }

    @Test("Doubles decode bit for bit, skipping line breaks")
    func unpack() {
        let values = Engine.unpackDoubles(
            count: 5,
            """
            AAAAAAAA8D8AAAAAAAAAgAAAAAAAAPB/
            AQAAAAAAAAAB8DeQp27Wvw==
            """
        )
        let expected = [1.0, -0.0, .infinity, .leastNonzeroMagnitude, -0x1.66ea79037f001p-2]
        #expect(values.map(\.bitPattern) == expected.map(\.bitPattern))
        #expect(Engine.unpackDoubles(count: 0, "").isEmpty)
    }

    /// The 135 series of the IMCCE files VSOP87B.mer to VSOP87B.nep, with
    /// 35,080 terms. Every term was compared with those files by
    /// `Scripts/generate-planet-tables.py --published`.
    @Test("The VSOP87B tables hold every published series")
    func vsopLayout() {
        var series = 0
        var terms = 0
        for planet in Engine.Planet.allCases {
            let model = Engine.VSOP87B.model(planet)
            #expect(model.termCounts.count == 3)
            #expect(model.termCounts.allSatisfy { (4...6).contains($0.count) && !$0.contains(0) })
            let count = model.termCounts.joined().reduce(0, +)
            #expect(model.terms.count == 3 * count)
            #expect(model.terms.allSatisfy { $0.isFinite })
            series += model.termCounts.joined().count
            terms += count
        }
        #expect(series == 135)
        #expect(terms == 35_080)
        #expect(
            Engine.VSOP87B.mercury.termCounts == [
                [1_583, 931, 438, 162, 23, 12], [818, 492, 231, 39, 13, 10], [1_209, 706, 318, 111, 17, 10],
            ])
        #expect(Engine.VSOP87B.neptune.termCounts[2] == [596, 251, 71, 23, 7])
    }

    /// Terms as IMCCE prints them in the VSOP87B files: the amplitude A, the
    /// phase B in radians and the frequency C in radians per Julian
    /// millennium.
    @Test("Published VSOP87B terms")
    func publishedTerms() {
        // VSOP87B.mer, variable 1 (L), T**0, terms 1 and 2.
        #expect(Self.term(.mercury, coordinate: 0, power: 0, index: 0) == (4.40250710144, 0, 0))
        #expect(
            Self.term(.mercury, coordinate: 0, power: 0, index: 1) == (0.40989414977, 1.48302034195, 26_087.90314157420)
        )
        // VSOP87B.ear, variable 1 (L), T**0 term 2; T**1 term 1; variable 3 (R), T**0 term 1.
        #expect(
            Self.term(.earth, coordinate: 0, power: 0, index: 1) == (0.03341656453, 4.66925680415, 6_283.07584999140))
        #expect(Self.term(.earth, coordinate: 0, power: 1, index: 0) == (6_283.07584999140, 0, 0))
        #expect(Self.term(.earth, coordinate: 2, power: 0, index: 0) == (1.00013988784, 0, 0))
        // VSOP87B.nep, variable 3 (R), T**4, the last term.
        #expect(
            Self.term(.neptune, coordinate: 2, power: 4, index: 6) == (0.00000002295, 5.67776133184, 168.05251279940))
    }

    @Test("The polynomial tables cover 1900 through 2100 TT in whole segments")
    func polynomialLayout() {
        #expect(
            Engine.PlanetPolynomial.start
                == Engine.Time.days(year: 1900, month: 1, day: 1, hour: 0, minute: 0, second: 0))
        #expect(
            Engine.PlanetPolynomial.stop
                == Engine.Time.days(year: 2101, month: 1, day: 1, hour: 0, minute: 0, second: 0))
        let span = Engine.PlanetPolynomial.stop - Engine.PlanetPolynomial.start
        let widths: [Engine.Planet: Double] = [
            .mercury: 8, .venus: 32, .earth: 8, .mars: 32, .jupiter: 32, .saturn: 16, .uranus: 32, .neptune: 16,
        ]
        let excluded: [Engine.Planet: Int] = [.mercury: 409, .venus: 4]
        for planet in Engine.Planet.allCases {
            let model = Engine.PlanetPolynomial.model(planet)
            #expect(model.degree == 12)
            #expect(model.width == widths[planet])
            // The last segment runs past `stop`, so the count rounds up.
            #expect(model.segmentCount == Int((span / model.width).rounded(.up)))
            #expect(model.coefficients.count == model.segmentCount * 3 * 13)
            #expect(model.coefficients.allSatisfy { $0.isFinite })
            #expect(model.excludedSegments.count == excluded[planet, default: 0])
            #expect(model.excludedSegments == model.excludedSegments.sorted())
            #expect(model.included.indices.filter { !model.included[$0] } == model.excludedSegments)
        }
        #expect(Engine.PlanetPolynomial.mercury.coefficients[0] == -0x1.66ea79037f001p-2)
        #expect(Engine.PlanetPolynomial.venus.excludedSegments == [17, 2_219, 2_291, 2_292])
    }
}
