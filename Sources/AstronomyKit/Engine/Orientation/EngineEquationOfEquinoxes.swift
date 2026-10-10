//
//  EngineEquationOfEquinoxes.swift
//  AstronomyKit
//
//  The complementary terms of the equation of the equinoxes.
//

import Foundation

extension Engine.Nutation {
    /// One term of the complementary series.
    ///
    /// The argument is `l·l + l′·l′ + f·F + d·D + om·Ω + ve·LVe + e·LE + pa·pA`:
    /// the five Delaunay arguments, the mean longitudes of Venus and Earth,
    /// and the general precession in longitude. The term adds
    /// `s·sin + c·cos` arcseconds.
    struct ComplementaryTerm: Sendable {
        let l, lp, f, d, om, ve, e, pa: Double
        let s, c: Double

        init(
            _ l: Double, _ lp: Double, _ f: Double, _ d: Double, _ om: Double,
            _ ve: Double, _ e: Double, _ pa: Double, _ s: Double, _ c: Double
        ) {
            (self.l, self.lp, self.f, self.d, self.om) = (l, lp, f, d, om)
            (self.ve, self.e, self.pa) = (ve, e, pa)
            (self.s, self.c) = (s, c)
        }
    }

    /// The eight arguments of ``ComplementaryTerm`` in radians.
    struct ComplementaryArguments: Sendable {
        let l, lp, f, d, om, ve, e, pa: Double

        /// The arguments at `t` Julian centuries of TT from J2000 (SOFA
        /// `iauFal03`, `iauFalp03`, `iauFaf03`, `iauFad03`, `iauFaom03`,
        /// `iauFave03`, `iauFae03` and `iauFapa03`; IERS Conventions 2003).
        ///
        /// ``evaluate(centuries:)`` reads the same polynomials for l, F and
        /// Ω, but MHB2000's for l′ and D, whose constant terms differ from
        /// these in the last digit, as `iauNut00a` does.
        init(centuries t: Double) {
            // The polynomial in arcseconds, reduced to one turn.
            func turn(_ c0: Double, _ c1: Double, _ c2: Double, _ c3: Double, _ c4: Double) -> Double {
                fmod(c0 + t * (c1 + t * (c2 + t * (c3 + t * c4))), 1_296_000) * Engine.radiansPerArcsecond
            }
            l = turn(485_868.249_036, 1_717_915_923.217_8, 31.879_2, 0.051_635, -0.000_244_70)
            lp = turn(1_287_104.793_048, 129_596_581.048_1, -0.553_2, 0.000_136, -0.000_011_49)
            f = turn(335_779.526_232, 1_739_527_262.847_8, -12.751_2, -0.001_037, 0.000_004_17)
            d = turn(1_072_260.703_692, 1_602_961_601.209_0, -6.370_6, 0.006_593, -0.000_031_69)
            om = turn(450_160.398_036, -6_962_890.543_1, 7.472_2, 0.007_702, -0.000_059_39)
            ve = fmod(3.176_146_697 + 1_021.328_554_621_1 * t, 2 * Double.pi)
            e = fmod(1.753_470_314 + 628.307_584_999_1 * t, 2 * Double.pi)
            pa = (0.024_381_750 + 0.000_005_386_91 * t) * t
        }
    }

    /// The complementary terms of the equation of the equinoxes, in radians,
    /// at `t` Julian centuries of TT from J2000 (SOFA `iauEect00`).
    ///
    /// These are the terms IAU 1994 Resolution C7 added to Δψ·cos εA, in the
    /// form IERS Conventions (2003), Table 5.2e, gives them: 33 terms and
    /// one multiplied by `t`. They reach about 2.65 mas between 1950 and
    /// 2050. Each series is summed smallest term first, as SOFA does.
    static func complementaryEquationOfEquinoxes(centuries t: Double) -> Double {
        let fa = ComplementaryArguments(centuries: t)
        func sum(_ terms: [ComplementaryTerm]) -> Double {
            var total = 0.0
            for term in terms.reversed() {
                let argument =
                    term.l * fa.l + term.lp * fa.lp + term.f * fa.f + term.d * fa.d + term.om * fa.om
                    + term.ve * fa.ve + term.e * fa.e + term.pa * fa.pa
                total += term.s * sin(argument) + term.c * cos(argument)
            }
            return total
        }
        return (sum(complementaryConstantTerms) + sum(complementaryLinearTerms) * t) * Engine.radiansPerArcsecond
    }
}
