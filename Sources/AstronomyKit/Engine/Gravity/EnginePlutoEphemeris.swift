//
//  EnginePlutoEphemeris.swift
//  AstronomyKit
//
//  Pluto's center from JPL DE440 and the PLU060 satellite ephemeris, from
//  1900 through 2130 TT.
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
    /// Their records start between 1899-11-02 and 1899-11-22 and end between
    /// 2131-02-12 and 2131-02-19 TDB, so they cover the 32-day blends either
    /// side of the DE440 span that ``Engine/Pluto`` uses.
    enum PlutoEphemeris {}
}

extension Engine.PlutoEphemeris {
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
        let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
        guard let pluto = barycenter.evaluate(tdb: tdb),
            let sun = barycenterFromSun.evaluate(tdb: tdb),
            let offset = center.evaluate(tdb: tdb)
        else { return nil }
        let rate = Engine.TDB.rate(tt: tt)
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: pluto.position) + bias.apply(to: sun.position) + bias.apply(to: offset.position),
            bias.apply(to: pluto.velocity * rate) + bias.apply(to: sun.velocity * rate)
                + bias.apply(to: offset.velocity * rate)
        )
    }
}
