//
//  EnginePrecession.swift
//  AstronomyKit
//
//  Long-term precession and mean obliquity.
//

import Foundation

extension Engine {
    /// Vondrák, Capitaine & Wallace (2011), including the 2012 corrigendum,
    /// following ERFA's `eraLtp`, `eraLtpequ` and `eraLtpecl`. Frame bias is
    /// not applied: EQJ is the mean equator and equinox of J2000, not ICRS.
    enum Precession {}
}

extension Engine.Precession {
    /// The fixed J2000 ecliptic anchor, ε0, in arcseconds.
    static let obliquityAtJ2000 = 84_381.406

    private struct Pole {
        let value: SIMD3<Double>
        let rate: SIMD3<Double>
    }

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    /// ERFA's polynomial plus periodic pole coordinates, differentiated
    /// analytically. Coefficients are arcseconds; rates are per TT day.
    private static func pole(tt: Double, polynomial: [[Double]], periodic: [[Double]]) -> Pole {
        let t = tt / 36525
        var x = 0.0
        var y = 0.0
        var dx = 0.0
        var dy = 0.0
        for term in periodic {
            let frequency = 2 * Double.pi / term[0]
            let angle = 2 * Double.pi * t / term[0]
            let s = sin(angle)
            let c = cos(angle)
            x += c * term[1] + s * term[3]
            y += c * term[2] + s * term[4]
            dx += frequency * (-s * term[1] + c * term[3])
            dy += frequency * (-s * term[2] + c * term[4])
        }
        var power = 1.0
        for i in polynomial[0].indices {
            x += polynomial[0][i] * power
            y += polynomial[1][i] * power
            power *= t
        }
        let polynomialDX = polynomial[0].indices.dropFirst().reversed().reduce(0.0) {
            $0 * t + Double($1) * polynomial[0][$1]
        }
        let polynomialDY = polynomial[1].indices.dropFirst().reversed().reduce(0.0) {
            $0 * t + Double($1) * polynomial[1][$1]
        }
        x *= Engine.radiansPerArcsecond
        y *= Engine.radiansPerArcsecond
        dx = (dx + polynomialDX) * Engine.radiansPerArcsecond / 36525
        dy = (dy + polynomialDY) * Engine.radiansPerArcsecond / 36525
        // The qualified interval keeps this radicand strictly positive.
        // Invalid inputs propagate NaN instead of manufacturing a pole.
        let z = sqrt(1 - x * x - y * y)
        return Pole(value: SIMD3(x, y, z), rate: SIMD3(dx, dy, -(x * dx + y * dy) / z))
    }

    private static func poles(tt: Double) -> (equator: Pole, ecliptic: Pole) {
        let equator = pole(tt: tt, polynomial: equatorPolynomial, periodic: equatorPeriodic)
        let local = pole(tt: tt, polynomial: eclipticPolynomial, periodic: eclipticPeriodic)
        let eps0 = obliquityAtJ2000 * Engine.radiansPerArcsecond
        let s = sin(eps0)
        let c = cos(eps0)
        func rotate(_ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(v.x, -v.y * c - v.z * s, -v.y * s + v.z * c)
        }
        return (equator, Pole(value: rotate(local.value), rate: rotate(local.rate)))
    }

    /// The angle between the long-term equator and ecliptic poles, in degrees.
    static func meanObliquity(tt: Double) -> Double {
        let p = poles(tt: tt)
        let v = cross(p.equator.value, p.ecliptic.value)
        return atan2(sqrt(dot(v, v)), dot(p.equator.value, p.ecliptic.value)) / Engine.radiansPerDegree
    }

    /// The analytic rate of mean obliquity, in degrees per TT day.
    static func meanObliquityRate(tt: Double) -> Double {
        let p = poles(tt: tt)
        let v = cross(p.equator.value, p.ecliptic.value)
        let dv = cross(p.equator.rate, p.ecliptic.value) + cross(p.equator.value, p.ecliptic.rate)
        let s = sqrt(dot(v, v))
        let c = dot(p.equator.value, p.ecliptic.value)
        let ds = dot(v, dv) / s
        let dc = dot(p.equator.rate, p.ecliptic.value) + dot(p.equator.value, p.ecliptic.rate)
        return (c * ds - s * dc) / (s * s + c * c) / Engine.radiansPerDegree
    }

    private static func axes(tt: Double) -> (x: Pole, y: Pole, z: Pole) {
        let p = poles(tt: tt)
        let v = cross(p.equator.value, p.ecliptic.value)
        let dv = cross(p.equator.rate, p.ecliptic.value) + cross(p.equator.value, p.ecliptic.rate)
        let norm = sqrt(dot(v, v))
        let x = v / norm
        let dx = (dv - x * dot(x, dv)) / norm
        let y = cross(p.equator.value, x)
        let dy = cross(p.equator.rate, x) + cross(p.equator.value, dx)
        return (Pole(value: x, rate: dx), Pole(value: y, rate: dy), p.equator)
    }

    /// Mean equator/equinox J2000 to mean equator/equinox of date, without bias.
    static func rotation(tt: Double) -> Engine.Rotation<Engine.EQJ, Engine.EQM> {
        let a = axes(tt: tt)
        return Engine.Rotation(
            rot: (
                (a.x.value.x, a.y.value.x, a.z.value.x),
                (a.x.value.y, a.y.value.y, a.z.value.y),
                (a.x.value.z, a.y.value.z, a.z.value.z)
            ))
    }

    /// The analytic derivative of ``rotation(tt:)`` per TT day.
    static func rate(tt: Double) -> Engine.RotationRate<Engine.EQJ, Engine.EQM> {
        let a = axes(tt: tt)
        return Engine.RotationRate(
            rot: (
                (a.x.rate.x, a.y.rate.x, a.z.rate.x),
                (a.x.rate.y, a.y.rate.y, a.z.rate.y),
                (a.x.rate.z, a.y.rate.z, a.z.rate.z)
            ))
    }
}
