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

    /// The records as an ``Engine/ChebyshevTable``.
    static let table = Engine.ChebyshevTable(
        start: start, recordDays: recordDays, recordCount: recordCount, degreeCount: degreeCount,
        coefficients: coefficients)

    /// The position in AU and velocity in AU per TDB day, on ICRS axes, at
    /// `tdb` days of TDB from J2000, or `nil` outside the records or for a
    /// time that is not finite: ``table`` evaluated at `tdb`. Record `k`
    /// holds `start + 4k ≤ tdb < start + 4(k + 1)`.
    static func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        table.evaluate(tdb: tdb)
    }

    /// The Moon's position in AU and velocity in AU per TT day relative to
    /// Earth's center, on EQJ axes, at `tt` days of TT from J2000, or `nil`
    /// where ``evaluate(tdb:)`` is.
    ///
    /// The records are read at TDB = TT + ``Engine/TDB/offsetSeconds(tt:)``,
    /// the velocity is scaled by ``Engine/TDB/rate(tt:)``, and both are
    /// rotated by ``Engine/FrameBias/icrsToEqj``.
    static func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard let (position, velocity) = evaluate(tt: tt) else { return nil }
        let rate = Engine.TDB.rate(tt: tt)
        let bias = Engine.FrameBias.icrsToEqj
        return (bias.apply(to: position), bias.apply(to: velocity * rate))
    }

    /// The position of ``state(tt:)`` alone, without the TDB rate it needs
    /// for the velocity.
    static func position(tt: Double) -> SIMD3<Double>? {
        evaluate(tt: tt).map { Engine.FrameBias.icrsToEqj.apply(to: $0.position) }
    }

    /// The records at TDB = TT + ``Engine/TDB/offsetSeconds(tt:)``.
    private static func evaluate(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        return evaluate(tdb: tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay)
    }
}
