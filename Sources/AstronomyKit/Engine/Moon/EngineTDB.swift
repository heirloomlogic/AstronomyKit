//
//  EngineTDB.swift
//  AstronomyKit
//
//  Barycentric Dynamical Time from Terrestrial Time.
//

import Foundation

extension Engine {
    /// TDB − TT, the periodic difference between Barycentric Dynamical Time
    /// and Terrestrial Time, as SOFA's `iauDtdb` computes it: the series of
    /// Fairhead and Bretagnon (1990), 787 terms, with JPL's planetary mass
    /// adjustments and the topocentric terms of Moyer (1981) and Murray (1983).
    ///
    /// The JPL ephemerides take TDB as their time argument; the engine's
    /// times are TT. The two never differ by more than about 1.7 ms.
    enum TDB {}
}

extension Engine.TDB {
    /// One term `amplitude · sin(frequency · t + phase)`, with t in Julian
    /// millennia from J2000.
    struct Term: Sendable {
        let amplitude: Double
        let frequency: Double
        let phase: Double

        init(_ amplitude: Double, _ frequency: Double, _ phase: Double) {
            self.amplitude = amplitude
            self.frequency = frequency
            self.phase = phase
        }
    }

    /// TDB − TT in seconds at the geocenter, `tt` days of TT from J2000.
    ///
    /// The time argument is TT, not TDB; the difference this makes is below
    /// a picosecond.
    static func offsetSeconds(tt: Double) -> Double {
        offsetSeconds(date1: 2_451_545, date2: tt, ut: 0, longitude: 0, u: 0, v: 0)
    }

    /// The derivative of TDB with respect to TT at `tt` days of TT: one plus
    /// the change of ``offsetSeconds(tt:)`` across ±0.01 day, divided by
    /// 0.02 day in seconds.
    ///
    /// It scales a velocity per TDB day to one per TT day. The largest term
    /// has a period of a year, so the 0.01-day step loses less than 1e-16 of
    /// the rate to truncation.
    static func rate(tt: Double) -> Double {
        let step = 0.01
        return 1 + (offsetSeconds(tt: tt + step) - offsetSeconds(tt: tt - step)) / (2 * step * 86_400)
    }

    /// TDB − TT in seconds, `iauDtdb` in full.
    ///
    /// - Parameters:
    ///   - date1: With `date2`, the date as a two-part Julian date. SOFA
    ///     takes TDB; TT gives the same result to well below a picosecond.
    ///   - date2: The second part of the date.
    ///   - ut: Universal Time as a fraction of a day.
    ///   - longitude: East longitude of the observer in radians.
    ///   - u: Distance of the observer from Earth's spin axis in km.
    ///   - v: Distance of the observer north of the equatorial plane in km.
    /// - Returns: TDB − TT in seconds.
    static func offsetSeconds(
        date1: Double, date2: Double, ut: Double, longitude: Double, u: Double, v: Double
    ) -> Double {
        // Julian millennia from J2000.
        let t = ((date1 - 2_451_545) + date2) / 365_250

        // Local solar time in radians, and Simon et al. (1994)'s mean
        // longitudes and anomaly; `w` combines millennia with arcseconds per degree.
        let tsol = ut.truncatingRemainder(dividingBy: 1) * twoPi + longitude
        let w = t / 3600
        let elsun = (280.46645683 + 1_296_027_711.03429 * w).truncatingRemainder(dividingBy: 360) * radiansPerDegree
        let emsun = (357.52910918 + 1_295_965_810.481 * w).truncatingRemainder(dividingBy: 360) * radiansPerDegree
        let d = (297.85019547 + 16_029_616_012.090 * w).truncatingRemainder(dividingBy: 360) * radiansPerDegree
        let elj = (34.35151874 + 109_306_899.89453 * w).truncatingRemainder(dividingBy: 360) * radiansPerDegree
        let els = (50.07744430 + 44_046_398.47038 * w).truncatingRemainder(dividingBy: 360) * radiansPerDegree

        // Topocentric terms: Moyer (1981) and Murray (1983).
        var wt = 0.00029e-10 * u * sin(tsol + elsun - els)
        wt += 0.00100e-10 * u * sin(tsol - 2 * emsun)
        wt += 0.00133e-10 * u * sin(tsol - d)
        wt += 0.00133e-10 * u * sin(tsol + elsun - elj)
        wt -= 0.00229e-10 * u * sin(tsol + 2 * elsun + emsun)
        wt -= 0.02200e-10 * v * cos(elsun + emsun)
        wt += 0.05312e-10 * u * sin(tsol - emsun)
        wt -= 0.13677e-10 * u * sin(tsol + 2 * elsun)
        wt -= 1.31840e-10 * v * cos(elsun)
        wt += 3.17679e-10 * u * sin(tsol)

        // Fairhead and Bretagnon, each power's terms summed last to first, as SOFA does.
        let sums = terms.map { group in
            group.reversed().reduce(0.0) { $0 + $1.amplitude * sin($1.frequency * t + $1.phase) }
        }
        let wf = t * (t * (t * (t * sums[4] + sums[3]) + sums[2]) + sums[1]) + sums[0]

        // JPL planetary masses instead of IAU.
        var wj = 0.00065e-6 * sin(6069.776754 * t + 4.021194)
        wj += 0.00033e-6 * sin(213.299095 * t + 5.543132)
        wj += -0.00196e-6 * sin(6208.294251 * t + 5.696701)
        wj += -0.00173e-6 * sin(74.781599 * t + 2.435900)
        wj += 0.03638e-6 * t * t

        return wt + wf + wj
    }

    // ERFA's constants, which equal 2π and π/180 as doubles.
    private static let twoPi = 6.283185307179586476925287
    private static let radiansPerDegree = 1.745329251994329576923691e-2
}
