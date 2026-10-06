//
//  EngineDeltaTTests.swift
//  AstronomyKit
//
//  The native Delta T models against NASA's published Espenak-Meeus values.
//

import Foundation
import Testing

@testable import AstronomyKit

/// The Espenak-Meeus polynomials and historical Delta T tables as NASA
/// publishes them (Fred Espenak, GSFC, 2007 March 27):
///
/// - Polynomials: https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html
/// - Tables 1 and 2: https://eclipse.gsfc.nasa.gov/SEhelp/deltat2004.html
///
/// Transcribed from those pages in their own notation, independently of the
/// engine source.
enum PublishedDeltaT {
    /// One polynomial, valid from `startYear` up to the next piece's start.
    struct Piece: Sendable {
        let startYear: Double
        let evaluate: @Sendable (_ y: Double) -> Double
    }

    static let pieces: [Piece] = [
        Piece(startYear: -.infinity) { y in
            let u = (y - 1820) / 100
            return -20 + 32 * pow(u, 2)
        },
        Piece(startYear: -500) { y in
            let u = y / 100
            return 10583.6 - 1014.41 * u + 33.78311 * pow(u, 2) - 5.952053 * pow(u, 3) - 0.1798452 * pow(u, 4)
                + 0.022174192 * pow(u, 5) + 0.0090316521 * pow(u, 6)
        },
        Piece(startYear: 500) { y in
            let u = (y - 1000) / 100
            return 1574.2 - 556.01 * u + 71.23472 * pow(u, 2) + 0.319781 * pow(u, 3) - 0.8503463 * pow(u, 4)
                - 0.005050998 * pow(u, 5) + 0.0083572073 * pow(u, 6)
        },
        Piece(startYear: 1600) { y in
            let t = y - 1600
            return 120 - 0.9808 * t - 0.01532 * pow(t, 2) + pow(t, 3) / 7129
        },
        Piece(startYear: 1700) { y in
            let t = y - 1700
            return 8.83 + 0.1603 * t - 0.0059285 * pow(t, 2) + 0.00013336 * pow(t, 3) - pow(t, 4) / 1_174_000
        },
        Piece(startYear: 1800) { y in
            let t = y - 1800
            return 13.72 - 0.332447 * t + 0.0068612 * pow(t, 2) + 0.0041116 * pow(t, 3) - 0.00037436 * pow(t, 4)
                + 0.0000121272 * pow(t, 5) - 0.0000001699 * pow(t, 6) + 0.000000000875 * pow(t, 7)
        },
        Piece(startYear: 1860) { y in
            let t = y - 1860
            return 7.62 + 0.5737 * t - 0.251754 * pow(t, 2) + 0.01680668 * pow(t, 3) - 0.0004473624 * pow(t, 4)
                + pow(t, 5) / 233_174
        },
        Piece(startYear: 1900) { y in
            let t = y - 1900
            return -2.79 + 1.494119 * t - 0.0598939 * pow(t, 2) + 0.0061966 * pow(t, 3) - 0.000197 * pow(t, 4)
        },
        Piece(startYear: 1920) { y in
            let t = y - 1920
            return 21.20 + 0.84493 * t - 0.076100 * pow(t, 2) + 0.0020936 * pow(t, 3)
        },
        Piece(startYear: 1941) { y in
            let t = y - 1950
            return 29.07 + 0.407 * t - pow(t, 2) / 233 + pow(t, 3) / 2547
        },
        Piece(startYear: 1961) { y in
            let t = y - 1975
            return 45.45 + 1.067 * t - pow(t, 2) / 260 - pow(t, 3) / 718
        },
        Piece(startYear: 1986) { y in
            let t = y - 2000
            return 63.86 + 0.3345 * t - 0.060374 * pow(t, 2) + 0.0017275 * pow(t, 3) + 0.000651814 * pow(t, 4)
                + 0.00002373599 * pow(t, 5)
        },
        Piece(startYear: 2005) { y in
            let t = y - 2000
            return 62.92 + 0.32217 * t + 0.005589 * pow(t, 2)
        },
        Piece(startYear: 2050) { y in
            -20 + 32 * pow((y - 1820) / 100, 2) - 0.5628 * (2150 - y)
        },
        Piece(startYear: 2150) { y in
            let u = (y - 1820) / 100
            return -20 + 32 * pow(u, 2)
        },
    ]

    /// The published value at decimal year `y`; NaN for a NaN year.
    static func seconds(year y: Double) -> Double {
        pieces.last { y >= $0.startYear }?.evaluate(y) ?? .nan
    }

    /// A published table value and the bound the polynomials meet it within.
    struct TableValue: Sendable, CustomTestStringConvertible {
        let year: Double
        let seconds: Double
        let bound: Double
        var testDescription: String { "\(year): \(seconds) ± \(bound) s" }
    }

    /// Table 1 from -500 to +500, with -500 changed to 17203.7 as the
    /// polynomial page states. That page says the -500 to +500 polynomial
    /// reproduces these "with an error not larger than 4 seconds".
    static let ancientTable = [
        (-500, 17203.7), (-400, 15530), (-300, 14080), (-200, 12790), (-100, 11640), (0, 10580),
        (100, 9600), (200, 8640), (300, 7680), (400, 6700), (500, 5710),
    ].map { TableValue(year: $0.0, seconds: $0.1, bound: 4) }

    /// Table 1 from 600 to 1800, bounded by each value's published standard error.
    static let historicalTable = [
        (600, 4740, 120), (700, 3810, 100), (800, 2960, 80), (900, 2200, 70), (1000, 1570, 55),
        (1100, 1090, 40), (1200, 740, 30), (1300, 490, 20), (1400, 320, 20), (1500, 200, 20),
        (1600, 120, 20), (1700, 9, 5), (1750, 13, 2), (1800, 14, 1),
    ].map { TableValue(year: $0.0, seconds: $0.1, bound: $0.2) }

    /// Table 2, from direct observation (Astronomical Almanac for 2006, page
    /// K9), bounded by its published precision of 0.1 second.
    static let observedTable = [
        (1955, 31.1), (1960, 33.2), (1965, 35.7), (1970, 40.2), (1975, 45.5), (1980, 50.5),
        (1985, 54.3), (1990, 56.9), (1995, 60.8), (2000, 63.8), (2005, 64.7),
    ].map { TableValue(year: $0.0, seconds: $0.1, bound: 0.1) }
}

@Suite("Engine Delta T")
struct EngineDeltaTTests {
    /// The engine's decimal year of UT `ut` (see `Engine.DeltaT.espenakMeeus`).
    static func year(ut: Double) -> Double {
        2000 + (ut - 14) / Engine.DeltaT.daysPerTropicalYear
    }

    /// A UT whose decimal year is `year`, to within rounding.
    static func ut(year: Double) -> Double {
        14 + (year - 2000) * Engine.DeltaT.daysPerTropicalYear
    }

    /// The last UT before decimal year `boundary` and the first UT at or after it.
    static func straddle(_ boundary: Double) -> (before: Double, after: Double) {
        var after = ut(year: boundary)
        while year(ut: after) >= boundary { after = after.nextDown }
        while year(ut: after) < boundary { after = after.nextUp }
        return (after.nextDown, after)
    }

    /// The piece boundaries, where the published polynomials meet.
    static let boundaries = PublishedDeltaT.pieces.dropFirst().map(\.startYear)

    /// `|a - b|` within 1e-9 s per 1,000 s of Delta T: a few rounding errors
    /// of the largest term, from evaluating powers in a different order.
    static func agrees(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(1, abs(b) / 1_000)
    }

    @Test("Espenak-Meeus matches the published polynomials across every piece")
    func publishedPolynomials() {
        // Ten samples inside each piece, plus the two open-ended extrapolations.
        var years: [Double] = [-3000, -1999, 2500, 3000]
        for (start, end) in zip(Self.boundaries, Self.boundaries.dropFirst()) {
            years += (0..<10).map { start + (end - start) * (Double($0) + 0.5) / 10 }
        }
        for year in years {
            let ut = Self.ut(year: year)
            let expected = PublishedDeltaT.seconds(year: Self.year(ut: ut))
            #expect(Self.agrees(Engine.DeltaT.espenakMeeus(ut: ut), expected), "year \(year)")
        }
    }

    @Test("Both sides of every piece boundary take the published polynomial for that side")
    func boundarySides() {
        for (index, boundary) in Self.boundaries.enumerated() {
            let (before, after) = Self.straddle(boundary)
            #expect(Self.year(ut: before) < boundary)
            #expect(Self.year(ut: after) >= boundary)
            let below = PublishedDeltaT.pieces[index].evaluate(Self.year(ut: before))
            let above = PublishedDeltaT.pieces[index + 1].evaluate(Self.year(ut: after))
            #expect(Self.agrees(Engine.DeltaT.espenakMeeus(ut: before), below), "below \(boundary)")
            #expect(Self.agrees(Engine.DeltaT.espenakMeeus(ut: after), above), "above \(boundary)")
        }
    }

    @Test(
        "Delta T is within each published table value's bound",
        arguments: PublishedDeltaT.ancientTable + PublishedDeltaT.historicalTable + PublishedDeltaT.observedTable
    )
    func publishedTables(value: PublishedDeltaT.TableValue) {
        let deltaT = Engine.DeltaT.espenakMeeus(ut: Self.ut(year: value.year))
        #expect(abs(deltaT - value.seconds) <= value.bound, "\(deltaT)")
    }

    @Test("Decimal year 2000.0 is 2000-01-15 12:00 UT")
    func decimalYearOrigin() {
        let ut = EngineCalendarTests.days(2000, 1, 15, hour: 12)
        #expect(ut == 14)
        #expect(Self.year(ut: ut) == 2000)
    }

    @Test("JPL Horizons follows Espenak-Meeus until 17 tropical years after J2000, then holds")
    func jplHorizons() {
        let limit = 17 * Engine.DeltaT.daysPerTropicalYear
        for ut in [-1e6, -36_525, 0, 6_000, limit.nextDown, limit] {
            #expect(Engine.DeltaT.jplHorizons(ut: ut) == Engine.DeltaT.espenakMeeus(ut: ut))
        }
        let held = Engine.DeltaT.espenakMeeus(ut: limit)
        for ut in [limit.nextUp, 7_000, 36_525, 1e6, 1e300, .greatestFiniteMagnitude, .infinity] {
            #expect(Engine.DeltaT.jplHorizons(ut: ut) == held)
        }
        #expect(Engine.DeltaT.seconds(ut: 36_525, model: .jplHorizons) == held)
        #expect(Engine.DeltaT.seconds(ut: 36_525, model: .espenakMeeus) == Engine.DeltaT.espenakMeeus(ut: 36_525))
    }

    @Test(
        "Nonfinite and extreme UT",
        arguments: [
            (Double.nan, DeltaTModel.espenakMeeus, nil),
            (.nan, .jplHorizons, nil),
            (.infinity, .espenakMeeus, Double.infinity),
            (-.infinity, .espenakMeeus, .infinity),
            (-.infinity, .jplHorizons, .infinity),
            (1e160, .espenakMeeus, .infinity),
            (-1e160, .jplHorizons, .infinity),
        ] as [(Double, DeltaTModel, Double?)]
    )
    func nonfinite(ut: Double, model: DeltaTModel, expected: Double?) {
        let deltaT = Engine.DeltaT.seconds(ut: ut, model: model)
        if let expected {
            #expect(deltaT == expected)
        } else {
            #expect(deltaT.isNaN)
        }
    }
}
