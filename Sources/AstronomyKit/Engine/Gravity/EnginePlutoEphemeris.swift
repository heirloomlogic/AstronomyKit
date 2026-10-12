//
//  EnginePlutoEphemeris.swift
//  AstronomyKit
//
//  Pluto's center from JPL DE440 and the PLU060 satellite ephemeris, from
//  the complete verified PLU060 source span.
//

import Foundation

extension Engine {
    /// Pluto's center relative to the Sun's from the three Chebyshev tables
    /// of `plu060.bsp` (NAIF, 3 April 2024), converted from km to AU on ICRS
    /// axes:
    ///
    /// - ``barycenter``: the Pluto system barycenter from the solar system
    ///   barycenter, DE440's, in 32-day records of 6 coefficients;
    /// - ``barycenterFromSun``: the solar system barycenter from the Sun,
    ///   DE440's Sun negated, in 16-day records of 11 coefficients;
    /// - ``center``: Pluto's center from the Pluto system barycenter, from
    ///   PLU060, in 3-day records of 16 coefficients.
    ///
    /// Complete records cover the PLU060 summary interval. Source evaluation and the two interior blends use TDB, so no TT boundary is mistaken for a source boundary.
    enum PlutoEphemeris {}
}

extension Engine.PlutoEphemeris {
    /// Common SPK summary coverage, in TDB days from J2000. Padding in the Sun and barycenter records does not extend this interval.
    static let sourceStartTDB = -73_047.5
    static let sourceEndTDB = 73_046.5
    static let blendDaysTDB = 32.0
    static let fullWeightStartTDB = sourceStartTDB + blendDaysTDB
    static let fullWeightEndTDB = sourceEndTDB - blendDaysTDB

    /// Physical-center weight and its derivative per TDB day. Both tapers stay inside the source interval; position and its first two derivatives meet the outer model continuously.
    static func weight(tdb: Double) -> (weight: Double, rate: Double) {
        guard tdb.isFinite, tdb > sourceStartTDB, tdb < sourceEndTDB else { return (0, 0) }
        if tdb >= fullWeightStartTDB && tdb <= fullWeightEndTDB { return (1, 0) }
        let x: Double
        let sign: Double
        if tdb < fullWeightStartTDB {
            x = (tdb - sourceStartTDB) / blendDaysTDB
            sign = 1
        } else {
            x = (sourceEndTDB - tdb) / blendDaysTDB
            sign = -1
        }
        return (
            x * x * x * (10 + x * (-15 + 6 * x)),
            sign * 30 * x * x * (1 - x) * (1 - x) / blendDaysTDB
        )
    }

    /// The same source weight evaluated at TT, with its derivative per TT day.
    static func weight(tt: Double) -> (weight: Double, rate: Double) {
        guard tt.isFinite else { return (0, 0) }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let result = weight(tdb: tt + conversion.offsetSeconds / Engine.secondsPerDay)
        return (result.weight, result.rate * conversion.rate)
    }

    /// Pluto's position in AU and velocity in AU per TT day relative to the
    /// Sun's center, on EQJ axes, at `tt` days of TT from J2000, or `nil`
    /// where a table has no record or for a TT that is not finite.
    ///
    /// Each table is read at TDB = TT + ``Engine/TDB/offsetSeconds(tt:)``,
    /// its velocity is scaled by ``Engine/TDB/rate(tt:)``, both are rotated
    /// by ``Engine/FrameBias/icrsToEqj``, and the three are added in the
    /// order above, as the Moon's records are read.
    static func heliocentricState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard tdb >= sourceStartTDB, tdb < sourceEndTDB,
            let pluto = barycenter.evaluate(tdb: tdb),
            let sun = barycenterFromSun.evaluate(tdb: tdb),
            let offset = center.evaluate(tdb: tdb)
        else { return nil }
        let rate = conversion.rate
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: pluto.position) + bias.apply(to: sun.position) + bias.apply(to: offset.position),
            bias.apply(to: pluto.velocity * rate) + bias.apply(to: sun.velocity * rate)
                + bias.apply(to: offset.velocity * rate)
        )
    }
}
