//
//  EnginePrecession.swift
//  AstronomyKit
//
//  IAU 2006 precession and mean obliquity.
//

import Foundation

extension Engine {
    /// The IAU 2006 precession (Capitaine, Wallace and Chapront 2003), with
    /// the angles of SOFA's `iauP06e` and the matrix of IERS Conventions
    /// (2010) equation 5.39. Frame bias is not applied: J2000 means the mean
    /// equator and equinox of J2000.
    enum Precession {}
}

extension Engine.Precession {
    /// The obliquity of the ecliptic at J2000, ε0, in arcseconds.
    static let obliquityAtJ2000 = 84_381.406

    /// A polynomial in Julian centuries, coefficients from t⁰ upward.
    private struct Polynomial {
        let coefficients: [Double]

        func value(_ t: Double) -> Double {
            coefficients.reversed().reduce(0) { $0 * t + $1 }
        }

        func derivative(_ t: Double) -> Double {
            coefficients.indices.dropFirst().reversed().reduce(0) { $0 * t + Double($1) * coefficients[$1] }
        }
    }

    // Capitaine et al. (2003), in arcseconds.
    private static let obliquity = Polynomial(
        coefficients: [obliquityAtJ2000, -46.836_769, -0.000_183_1, 0.002_003_40, -0.000_000_576, -0.000_000_043_4]
    )
    private static let psi = Polynomial(
        coefficients: [0, 5_038.481_507, -1.079_006_9, -0.001_140_45, 0.000_132_851, -0.000_000_095_1]
    )
    private static let omega = Polynomial(
        coefficients: [obliquityAtJ2000, -0.025_754, 0.051_262_3, -0.007_725_03, -0.000_000_467, 0.000_000_333_7]
    )
    private static let chi = Polynomial(
        coefficients: [0, 10.556_403, -2.381_429_2, -0.001_211_97, 0.000_170_663, -0.000_000_056_0]
    )

    /// The mean obliquity of the ecliptic, εA, in degrees at `tt` days of TT
    /// from J2000 (SOFA `iauObl06`).
    static func meanObliquity(tt: Double) -> Double {
        obliquity.value(tt / 36525) / 3600
    }

    /// The rate of ``meanObliquity(tt:)`` in degrees per TT day.
    static func meanObliquityRate(tt: Double) -> Double {
        obliquity.derivative(tt / 36525) / 3600 / 36525
    }

    /// The precession angles ψA, ωA and χA in degrees, and their rates in
    /// degrees per TT day.
    struct Angles: Sendable {
        var psi: Double
        var omega: Double
        var chi: Double
        var psiRate: Double
        var omegaRate: Double
        var chiRate: Double
    }

    /// The precession angles at `tt` days of TT from J2000.
    static func angles(tt: Double) -> Angles {
        let t = tt / 36525
        let perDay = 1 / (3600 * 36525.0)
        return Angles(
            psi: psi.value(t) / 3600,
            omega: omega.value(t) / 3600,
            chi: chi.value(t) / 3600,
            psiRate: psi.derivative(t) * perDay,
            omegaRate: omega.derivative(t) * perDay,
            chiRate: chi.derivative(t) * perDay
        )
    }

    /// The precession matrix P = R3(χA)·R1(−ωA)·R3(−ψA)·R1(ε0) at `tt` days of
    /// TT, from the mean equator and equinox of J2000 to those of date.
    static func rotation(tt: Double) -> Engine.Rotation<Engine.EQJ, Engine.EQM> {
        let t = Terms(angles(tt: tt))
        // Element (i, j) of P is rot[j][i]: rot[0] holds P's first column.
        return Engine.Rotation(
            rot: (
                (t.cd * t.cb - t.sb * t.sd * t.cc, -t.sd * t.cb - t.sb * t.cd * t.cc, t.sb * t.sc),
                (
                    t.cd * t.sb * t.ca + t.sd * t.cc * t.cb * t.ca - t.sa * t.sd * t.sc,
                    -t.sd * t.sb * t.ca + t.cd * t.cc * t.cb * t.ca - t.sa * t.cd * t.sc,
                    -t.sc * t.cb * t.ca - t.sa * t.cc
                ),
                (
                    t.cd * t.sb * t.sa + t.sd * t.cc * t.cb * t.sa + t.ca * t.sd * t.sc,
                    -t.sd * t.sb * t.sa + t.cd * t.cc * t.cb * t.sa + t.ca * t.cd * t.sc,
                    -t.sc * t.cb * t.sa + t.cc * t.ca
                )
            )
        )
    }

    /// The derivative of ``rotation(tt:)`` per TT day, element by element.
    static func rate(tt: Double) -> Engine.RotationRate<Engine.EQJ, Engine.EQM> {
        let a = angles(tt: tt)
        let t = Terms(a)
        // ε0 is constant. The b and c angles are −ψA and −ωA; d is χA.
        let psiRate = a.psiRate * Engine.radiansPerDegree
        let omegaRate = a.omegaRate * Engine.radiansPerDegree
        let chiRate = a.chiRate * Engine.radiansPerDegree
        let dsb = -t.cb * psiRate
        let dcb = t.sb * psiRate
        let dsc = -t.cc * omegaRate
        let dcc = t.sc * omegaRate
        let dsd = t.cd * chiRate
        let dcd = -t.sd * chiRate
        let cdsb = dcd * t.sb + t.cd * dsb
        let sdcccb = dsd * t.cc * t.cb + t.sd * dcc * t.cb + t.sd * t.cc * dcb
        let sdsb = dsd * t.sb + t.sd * dsb
        let cdcccb = dcd * t.cc * t.cb + t.cd * dcc * t.cb + t.cd * t.cc * dcb
        let sccb = dsc * t.cb + t.sc * dcb
        return Engine.RotationRate(
            rot: (
                (
                    dcd * t.cb + t.cd * dcb - (dsb * t.sd * t.cc + t.sb * dsd * t.cc + t.sb * t.sd * dcc),
                    -(dsd * t.cb + t.sd * dcb) - (dsb * t.cd * t.cc + t.sb * dcd * t.cc + t.sb * t.cd * dcc),
                    dsb * t.sc + t.sb * dsc
                ),
                (
                    cdsb * t.ca + sdcccb * t.ca - t.sa * (dsd * t.sc + t.sd * dsc),
                    -sdsb * t.ca + cdcccb * t.ca - t.sa * (dcd * t.sc + t.cd * dsc),
                    -sccb * t.ca - t.sa * dcc
                ),
                (
                    cdsb * t.sa + sdcccb * t.sa + t.ca * (dsd * t.sc + t.sd * dsc),
                    -sdsb * t.sa + cdcccb * t.sa + t.ca * (dcd * t.sc + t.cd * dsc),
                    -sccb * t.sa + dcc * t.ca
                )
            )
        )
    }

    /// Sines and cosines of ε0 (a), −ψA (b), −ωA (c) and χA (d).
    private struct Terms {
        let sa, ca, sb, cb, sc, cc, sd, cd: Double

        private static let a = obliquityAtJ2000 * Engine.radiansPerArcsecond
        private static let (sinA, cosA) = (sin(a), cos(a))

        init(_ angles: Angles) {
            let b = -angles.psi * Engine.radiansPerDegree
            let c = -angles.omega * Engine.radiansPerDegree
            let d = angles.chi * Engine.radiansPerDegree
            (sa, ca) = (Self.sinA, Self.cosA)
            (sb, cb) = (sin(b), cos(b))
            (sc, cc) = (sin(c), cos(c))
            (sd, cd) = (sin(d), cos(d))
        }
    }
}
