//
//  EngineEquationOfEquinoxesTests.swift
//  AstronomyKit
//
//  The complementary terms of the equation of the equinoxes against SOFA.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Nutation complementary terms")
struct EngineEquationOfEquinoxesTests {
    typealias Published = PublishedOrientation

    static func complementary(tt: Double) -> Double {
        Engine.Nutation.complementaryEquationOfEquinoxes(centuries: tt / 36525)
    }

    @Test("The tables hold the 33 constant terms and the one term in t, largest first")
    func table() {
        #expect(Engine.Nutation.complementaryConstantTerms.count == 33)
        #expect(Engine.Nutation.complementaryLinearTerms.count == 1)
        let first = Engine.Nutation.complementaryConstantTerms[0]
        let multipliers = [first.l, first.lp, first.f, first.d, first.om, first.ve, first.e, first.pa]
        #expect(multipliers == [0, 0, 0, 0, 1, 0, 0, 0])
        #expect([first.s, first.c] == [2640.96e-6, -0.39e-6])
        let venus = Engine.Nutation.complementaryConstantTerms[23]
        #expect([venus.ve, venus.e, venus.pa] == [8, -13, -1])
        #expect(Engine.Nutation.complementaryLinearTerms[0].s == -0.87e-6)
    }

    @Test("ERFA t_eect00 reference")
    func erfaComplementaryTerms() {
        let value = Self.complementary(tt: Published.days(mjd: Published.eect00.mjd))
        #expect(abs(value - Published.eect00.value) <= 1e-20)
    }

    @Test("SOFA eect00 from 1600 to 2500", arguments: Published.references)
    func sofaComplementaryTerms(reference: Published.Reference) {
        #expect(abs(Self.complementary(tt: reference.tt) - reference.eect00) <= 1e-20)
    }

    /// The tolerance is 5e-12 rad. An argument reaches thousands of radians
    /// before reduction, so a fused multiply-add in one polynomial and not the
    /// other moves it by about 1e-12; a mistyped coefficient moves it by
    /// 1e-7 or more at these epochs. The effect on `eect00` stays below 1e-20.
    @Test("The fundamental arguments are the IERS 2003 ones", arguments: Published.references)
    func arguments(reference: Published.Reference) {
        let fa = Engine.Nutation.ComplementaryArguments(centuries: reference.tt / 36525)
        let arguments = [fa.l, fa.lp, fa.f, fa.d, fa.om, fa.ve, fa.e, fa.pa]
        #expect(arguments.count == reference.arguments.count)
        for (index, expected) in reference.arguments.enumerated() {
            #expect(abs(Published.wrapped(arguments[index] - expected)) <= 5e-12, "argument \(index)")
        }
    }

    /// The published figure is about 2.65 mas between 1950 and 2050 (IERS
    /// Conventions 2010, Table 5.2e, the 2640.96 μas term in sin Ω).
    @Test("The terms reach 2.65 mas between 1950 and 2050")
    func magnitude() {
        let start = Published.days(mjd: 33_282)
        let largest = stride(from: start, to: start + 36_525, by: 10).map { abs(Self.complementary(tt: $0)) }.max()
        let milliarcseconds = (largest ?? 0) / Published.radiansPerMilliarcsecond
        #expect(milliarcseconds > 2.64 && milliarcseconds < 2.66)
    }

    @Test("Input that is not finite gives NaN", arguments: [Double.nan, .infinity, -.infinity])
    func nonfinite(tt: Double) {
        #expect(Self.complementary(tt: tt).isNaN)
    }
}
