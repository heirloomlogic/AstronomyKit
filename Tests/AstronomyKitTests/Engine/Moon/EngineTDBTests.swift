//
//  EngineTDBTests.swift
//  AstronomyKit
//
//  TDB − TT against SOFA, through ERFA 2.0.1.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine TDB − TT")
struct EngineTDBTests {
    @Test("ERFA's t_dtdb: the topocentric case of its test program, within its 1e-15 s")
    func erfaTestProgram() {
        // t_erfa_c.c at ERFA 9915ba38: eraDtdb(2448939.5, 0.123, 0.76543, 5.0123, 5525.242, 3190.0).
        let offset = Engine.TDB.offsetSeconds(
            date1: 2_448_939.5, date2: 0.123, ut: 0.76543, longitude: 5.0123, u: 5_525.242, v: 3_190.0)
        #expect(abs(offset - -0.128_036_800_593_699_899_1e-2) <= 1e-15)
    }

    /// pyerfa 2.0.1.5 (ERFA 2.0.1) `dtdb(2451545.0, tt, 0, 0, 0, 0)`, the
    /// geocentric case the Moon reads, at the accepted range's ends, the
    /// DE440 Moon's record start and full-weight ends, the blend's outer end
    /// at 2131, J2000 and dates between.
    static let geocentric: [(tt: Double, seconds: Double)] = [
        (-1_461_000.0, 0.001_043_629_980_804_909_4),
        (-730_000.25, 0.000_861_332_114_631_834_4),
        (-36_560.5, -0.001_004_912_030_252_125_4),
        (-36_524.5, -1.846_023_201_048_302_3e-05),
        (0.0, -9.930_719_894_379_447e-05),
        (9_497.375, -5.729_838_764_588_522_6e-05),
        (26_000.0625, 0.001_474_377_182_795_573_4),
        (47_846.5, -0.000_151_331_344_713_873_21),
        (47_878.0, 0.000_726_633_424_332_302_3),
        (730_000.75, -0.000_710_349_635_046_501),
        (1_461_000.0, -0.000_963_829_042_190_120_1),
    ]

    /// pyerfa's compiled C may round some operations differently, for
    /// example by fusing a multiply and an add. One rounding of a term's
    /// argument, up to 3e5 rad four millennia out, moves the sum by at most
    /// a few times 1e-15 s.
    @Test("The geocentric offset against pyerfa within 1e-14 s")
    func geocentricOffset() {
        for (tt, seconds) in Self.geocentric {
            #expect(abs(Engine.TDB.offsetSeconds(tt: tt) - seconds) <= 1e-14, "tt \(tt)")
        }
    }

    @Test("The rate is one plus the derivative of the offset")
    func rate() {
        // A five-point difference on a binary-fraction stencil; the offset's
        // largest term is 1.66 ms with a one-year period, so its rate is at
        // most about 3.3e-10 and its truncation here is below 1e-20.
        let h = 1.0 / 64
        for (tt, _) in Self.geocentric {
            let tt = tt.rounded()
            let offset = { (k: Double) in Engine.TDB.offsetSeconds(tt: tt + k * h) }
            let derivative = (offset(-2) - 8 * offset(-1) + 8 * offset(1) - offset(2)) / (12 * h * 86_400)
            let rate = Engine.TDB.rate(tt: tt)
            #expect(abs(rate - 1) < 3.5e-10, "tt \(tt)")
            #expect(abs((rate - 1) - derivative) <= 1e-16, "tt \(tt): \(rate - 1) vs \(derivative)")
        }
    }

    @Test("The series has ERFA's 787 terms in five powers of t")
    func terms() throws {
        #expect(Engine.TDB.terms.map(\.count) == [474, 205, 85, 20, 3])
        // The first and last rows of dtdb.c's table.
        let first = try #require(Engine.TDB.terms.first?.first)
        #expect([first.amplitude, first.frequency, first.phase] == [1656.674564e-6, 6283.075849991, 6.240054195])
        let last = try #require(Engine.TDB.terms.last?.last)
        #expect([last.amplitude, last.frequency, last.phase] == [0.000209e-6, 155.420399434, 1.989815753])
    }

    @Test("A time that is not finite gives NaN", arguments: [Double.nan, .infinity, -.infinity])
    func notFinite(tt: Double) {
        #expect(Engine.TDB.offsetSeconds(tt: tt).isNaN)
        #expect(Engine.TDB.rate(tt: tt).isNaN)
    }
}
