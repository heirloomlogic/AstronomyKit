//
//  EngineMoonEphemeris.swift
//  AstronomyKit
//
//  The geocentric Moon of JPL DE440, from 1900 through 2130 TT.
//

import Foundation

extension Engine {
    /// The Moon's center relative to Earth's from the JPL planetary and lunar
    /// ephemeris DE440 (Park et al. 2021): DE440's Chebyshev records for the
    /// Moon minus those for Earth, both relative to the Earth-Moon
    /// barycenter, converted from km to AU. Each record spans four TDB days
    /// with 13 coefficients per axis on ICRS axes.
    ///
    /// The engine uses it from 1900-01-01 00:00 TT up to 2131-01-01 00:00 TT
    /// and blends it into the lunar series over the 32 days outside each end
    /// (see ``weight(tt:)``). The records reach a few days further, so the
    /// blend never reads past them.
    enum MoonEphemeris {}
}

extension Engine.MoonEphemeris {
    /// The first TT, in days from J2000, at full weight: 1900-01-01 00:00 TT.
    static let fullWeightStart = -36_524.5

    /// The last TT at full weight: 2131-01-01 00:00 TT.
    static let fullWeightEnd = 47_846.5

    /// The length in TT days of the blend outside each end.
    static let blendDays = 32.0

    /// The weight of the DE440 Moon at `tt` days of TT, and its rate per TT
    /// day.
    ///
    /// The weight is 1 from ``fullWeightStart`` through ``fullWeightEnd``
    /// and 0 from ``blendDays`` beyond them, or for a TT that is not finite.
    /// In between it is the quintic smoothstep x³(10 − 15x + 6x²), with x
    /// running from 0 at the outer end of the blend to 1 at the inner, so
    /// the weight and its first and second derivatives are continuous.
    static func weight(tt: Double) -> (weight: Double, rate: Double) {
        guard tt.isFinite, tt > fullWeightStart - blendDays, tt < fullWeightEnd + blendDays else { return (0, 0) }
        if tt >= fullWeightStart && tt <= fullWeightEnd { return (1, 0) }
        let x: Double
        let sign: Double
        if tt < fullWeightStart {
            x = (tt - (fullWeightStart - blendDays)) / blendDays
            sign = 1
        } else {
            x = (fullWeightEnd + blendDays - tt) / blendDays
            sign = -1
        }
        let rate = sign * 30 * x * x * (1 - x) * (1 - x) / blendDays
        return (x * x * x * (10 + x * (-15 + 6 * x)), rate)
    }

    /// The position in AU and velocity in AU per TDB day, on ICRS axes, at
    /// `tdb` days of TDB from J2000, or `nil` outside the records or for a
    /// time that is not finite.
    ///
    /// Record `k` holds `start + 4k ≤ tdb < start + 4(k + 1)`. Clenshaw's
    /// recurrence gives the series and its derivative together.
    static func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tdb.isFinite, tdb >= start else { return nil }
        let interval = (tdb - start) / recordDays
        guard interval >= 0, interval < Double(recordCount) else { return nil }
        let record = Int(interval.rounded(.down))
        let x = 2 * ((tdb - start) - Double(record) * recordDays) / recordDays - 1
        var position = SIMD3<Double>()
        var velocity = SIMD3<Double>()
        for axis in 0..<3 {
            let base = (3 * record + axis) * degreeCount
            var (b1, b2, d1, d2) = (0.0, 0.0, 0.0, 0.0)
            for k in stride(from: degreeCount - 1, to: 0, by: -1) {
                let b = 2 * x * b1 - b2 + coefficients[base + k]
                let d = 2 * b1 + 2 * x * d1 - d2
                (b2, b1) = (b1, b)
                (d2, d1) = (d1, d)
            }
            position[axis] = coefficients[base] + x * b1 - b2
            velocity[axis] = (b1 + x * d1 - d2) * (2 / recordDays)
        }
        return (position, velocity)
    }

    /// The Moon's position in AU and velocity in AU per TT day relative to
    /// Earth's center, on EQJ axes, at `tt` days of TT from J2000, or `nil`
    /// where ``evaluate(tdb:)`` is.
    ///
    /// The records are read at TDB = TT + ``Engine/TDB/offsetSeconds(tt:)``,
    /// the velocity is scaled by ``Engine/TDB/rate(tt:)``, and both are
    /// rotated by ``Engine/FrameBias/icrsToEqj``.
    static func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / 86_400
        guard let (position, velocity) = evaluate(tdb: tdb) else { return nil }
        let rate = Engine.TDB.rate(tt: tt)
        return (Engine.FrameBias.toEqj(position), Engine.FrameBias.toEqj(velocity * rate))
    }
}
