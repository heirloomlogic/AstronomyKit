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

    private struct PeriodicTerm {
        let frequency: Double
        let cosX: Double
        let cosY: Double
        let sinX: Double
        let sinY: Double
    }

    /// Combined precession rotation, rotation rate, mean obliquity, and mean obliquity rate from a single `poles(tt:)` evaluation.
    struct Frame {
        let rotation: Engine.Rotation<Engine.EQJ, Engine.EQM>
        let rate: Engine.RotationRate<Engine.EQJ, Engine.EQM>
        let meanObliquity: Double
        let meanObliquityRate: Double
    }

    private static let equatorPeriodicTerms: [PeriodicTerm] = equatorPeriodic.map {
        PeriodicTerm(frequency: 2 * Double.pi / $0[0], cosX: $0[1], cosY: $0[2], sinX: $0[3], sinY: $0[4])
    }

    private static let eclipticPeriodicTerms: [PeriodicTerm] = eclipticPeriodic.map {
        PeriodicTerm(frequency: 2 * Double.pi / $0[0], cosX: $0[1], cosY: $0[2], sinX: $0[3], sinY: $0[4])
    }

    private static let sinEps0 = sin(obliquityAtJ2000 * Engine.radiansPerArcsecond)
    private static let cosEps0 = cos(obliquityAtJ2000 * Engine.radiansPerArcsecond)

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    /// ERFA's polynomial plus periodic pole coordinates, value only (skips derivative math).
    private static func poleValue(tt: Double, polynomial: [[Double]], periodic: [PeriodicTerm]) -> SIMD3<Double> {
        let t = tt / 36525
        var x = 0.0
        var y = 0.0
        for term in periodic {
            let angle = term.frequency * t
            let s = sin(angle)
            let c = cos(angle)
            x += c * term.cosX + s * term.sinX
            y += c * term.cosY + s * term.sinY
        }
        let px = polynomial[0]
        let py = polynomial[1]
        var polyX = 0.0
        var polyY = 0.0
        for i in stride(from: px.count - 1, through: 0, by: -1) {
            polyX = polyX * t + px[i]
            polyY = polyY * t + py[i]
        }
        x = (x + polyX) * Engine.radiansPerArcsecond
        y = (y + polyY) * Engine.radiansPerArcsecond
        let z = sqrt(1 - x * x - y * y)
        return SIMD3(x, y, z)
    }

    /// ERFA's polynomial plus periodic pole coordinates, differentiated
    /// analytically. Coefficients are arcseconds; rates are per TT day.
    private static func pole(tt: Double, polynomial: [[Double]], periodic: [PeriodicTerm]) -> Pole {
        let t = tt / 36525
        var x = 0.0
        var y = 0.0
        var dx = 0.0
        var dy = 0.0
        for term in periodic {
            let angle = term.frequency * t
            let s = sin(angle)
            let c = cos(angle)
            x += c * term.cosX + s * term.sinX
            y += c * term.cosY + s * term.sinY
            dx += term.frequency * (-s * term.cosX + c * term.sinX)
            dy += term.frequency * (-s * term.cosY + c * term.sinY)
        }
        let px = polynomial[0]
        let py = polynomial[1]
        var polyX = 0.0
        var polyY = 0.0
        var polyDX = 0.0
        var polyDY = 0.0
        for i in stride(from: px.count - 1, through: 0, by: -1) {
            polyX = polyX * t + px[i]
            polyY = polyY * t + py[i]
            if i > 0 {
                let d = Double(i)
                polyDX = polyDX * t + d * px[i]
                polyDY = polyDY * t + d * py[i]
            }
        }
        x = (x + polyX) * Engine.radiansPerArcsecond
        y = (y + polyY) * Engine.radiansPerArcsecond
        dx = (dx + polyDX) * (Engine.radiansPerArcsecond / 36525)
        dy = (dy + polyDY) * (Engine.radiansPerArcsecond / 36525)
        // The qualified interval keeps this radicand strictly positive.
        // Invalid inputs propagate NaN instead of manufacturing a pole.
        let z = sqrt(1 - x * x - y * y)
        return Pole(value: SIMD3(x, y, z), rate: SIMD3(dx, dy, -(x * dx + y * dy) / z))
    }

    @inline(__always)
    private static func rotateEcliptic(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(v.x, -v.y * cosEps0 - v.z * sinEps0, -v.y * sinEps0 + v.z * cosEps0)
    }

    private static func polesValue(tt: Double) -> (equator: SIMD3<Double>, ecliptic: SIMD3<Double>) {
        let equator = poleValue(tt: tt, polynomial: equatorPolynomial, periodic: equatorPeriodicTerms)
        let local = poleValue(tt: tt, polynomial: eclipticPolynomial, periodic: eclipticPeriodicTerms)
        return (equator, rotateEcliptic(local))
    }

    private static func poles(tt: Double) -> (equator: Pole, ecliptic: Pole) {
        let equator = pole(tt: tt, polynomial: equatorPolynomial, periodic: equatorPeriodicTerms)
        let local = pole(tt: tt, polynomial: eclipticPolynomial, periodic: eclipticPeriodicTerms)
        return (equator, Pole(value: rotateEcliptic(local.value), rate: rotateEcliptic(local.rate)))
    }

    /// The angle between the long-term equator and ecliptic poles, in degrees.
    static func meanObliquity(tt: Double) -> Double {
        let p = polesValue(tt: tt)
        let v = cross(p.equator, p.ecliptic)
        return atan2(sqrt(dot(v, v)), dot(p.equator, p.ecliptic)) * Engine.degreesPerRadian
    }

    /// The analytic rate of mean obliquity, in degrees per TT day.
    static func meanObliquityRate(tt: Double) -> Double {
        meanObliquityAndRate(tt: tt).rate
    }

    /// Mean obliquity (degrees) and its analytic rate (degrees per TT day) from a single `poles(tt:)` pass.
    static func meanObliquityAndRate(tt: Double) -> (obliquity: Double, rate: Double) {
        let p = poles(tt: tt)
        let v = cross(p.equator.value, p.ecliptic.value)
        let dv = cross(p.equator.rate, p.ecliptic.value) + cross(p.equator.value, p.ecliptic.rate)
        let s = sqrt(dot(v, v))
        let c = dot(p.equator.value, p.ecliptic.value)
        let ds = dot(v, dv) / s
        let dc = dot(p.equator.rate, p.ecliptic.value) + dot(p.equator.value, p.ecliptic.rate)
        return (
            atan2(s, c) * Engine.degreesPerRadian,
            (c * ds - s * dc) / (s * s + c * c) * Engine.degreesPerRadian
        )
    }

    /// Precession rotation and mean obliquity (degrees) from a single value-only `polesValue(tt:)` pass.
    static func rotationAndMeanObliquity(
        tt: Double
    ) -> (rotation: Engine.Rotation<Engine.EQJ, Engine.EQM>, meanObliquity: Double) {
        let p = polesValue(tt: tt)
        let v = cross(p.equator, p.ecliptic)
        let norm = sqrt(dot(v, v))
        let x = v / norm
        let y = cross(p.equator, x)
        let z = p.equator
        let obliquity = atan2(norm, dot(p.equator, p.ecliptic)) * Engine.degreesPerRadian
        let rotation = Engine.Rotation<Engine.EQJ, Engine.EQM>(
            rot: (
                (x.x, y.x, z.x),
                (x.y, y.y, z.y),
                (x.z, y.z, z.z)
            ))
        return (rotation, obliquity)
    }

    /// Full precession frame (rotation, rate, mean obliquity, and its rate) from a single `poles(tt:)` pass.
    static func frame(tt: Double) -> Frame {
        let p = poles(tt: tt)
        let v = cross(p.equator.value, p.ecliptic.value)
        let dv = cross(p.equator.rate, p.ecliptic.value) + cross(p.equator.value, p.ecliptic.rate)
        let norm = sqrt(dot(v, v))
        let c = dot(p.equator.value, p.ecliptic.value)
        let ds = dot(v, dv) / norm
        let dc = dot(p.equator.rate, p.ecliptic.value) + dot(p.equator.value, p.ecliptic.rate)
        let obliquity = atan2(norm, c) * Engine.degreesPerRadian
        let obliquityRate = (c * ds - norm * dc) / (norm * norm + c * c) * Engine.degreesPerRadian
        let x = v / norm
        let dx = (dv - x * dot(x, dv)) / norm
        let y = cross(p.equator.value, x)
        let dy = cross(p.equator.rate, x) + cross(p.equator.value, dx)
        let z = p.equator.value
        let dz = p.equator.rate
        return Frame(
            rotation: Engine.Rotation(
                rot: (
                    (x.x, y.x, z.x),
                    (x.y, y.y, z.y),
                    (x.z, y.z, z.z)
                )),
            rate: Engine.RotationRate(
                rot: (
                    (dx.x, dy.x, dz.x),
                    (dx.y, dy.y, dz.y),
                    (dx.z, dy.z, dz.z)
                )),
            meanObliquity: obliquity,
            meanObliquityRate: obliquityRate
        )
    }

    /// Mean equator/equinox J2000 to mean equator/equinox of date, without bias.
    static func rotation(tt: Double) -> Engine.Rotation<Engine.EQJ, Engine.EQM> {
        rotationAndMeanObliquity(tt: tt).rotation
    }

    /// The analytic derivative of ``rotation(tt:)`` per TT day.
    static func rate(tt: Double) -> Engine.RotationRate<Engine.EQJ, Engine.EQM> {
        frame(tt: tt).rate
    }
}
