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
    /// times are TT. From 1900 through 2100 the two differ by less than
    /// 1.7 ms; over the accepted range, by less than 1.85 ms.
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
        fairheadAndJPL(at: tt / 365_250, derivative: false).offsetSeconds
    }

    /// The derivative of TDB with respect to TT at `tt` days of TT.
    ///
    /// It scales a velocity per TDB day to one per TT day. The derivative is
    /// evaluated with the offset in the same pass through the periodic series.
    static func rate(tt: Double) -> Double {
        offsetAndRate(tt: tt).rate
    }

    /// The geocentric TDB − TT offset and TDB/TT rate from one series evaluation.
    static func offsetAndRate(tt: Double) -> (offsetSeconds: Double, rate: Double) {
        let t = tt / 365_250
        let series = fairheadAndJPL(at: t, derivative: true)
        return (series.offsetSeconds, 1 + series.ratePerMillennium / (365_250 * Engine.secondsPerDay))
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

        return wt + fairheadAndJPL(at: t, derivative: false).offsetSeconds
    }

    /// The geocentric periodic offset and its derivative with respect to Julian millennia.
    private static func fairheadAndJPL(
        at t: Double, derivative needsDerivative: Bool
    ) -> (offsetSeconds: Double, ratePerMillennium: Double) {
        // Fairhead and Bretagnon, each power's terms summed last to first, as SOFA does.
        func sum(_ group: [Term]) -> (value: Double, derivative: Double) {
            var value = 0.0
            var derivative = 0.0
            for term in group.reversed() {
                let argument = term.frequency * t + term.phase
                value += term.amplitude * sin(argument)
                if needsDerivative { derivative += term.amplitude * term.frequency * cos(argument) }
            }
            return (value, derivative)
        }
        let s0 = sum(terms[0])
        let s1 = sum(terms[1])
        let s2 = sum(terms[2])
        let s3 = sum(terms[3])
        let s4 = sum(terms[4])
        func include(_ component: (value: Double, derivative: Double), in value: inout Double, rate: inout Double) {
            rate = rate * t + value + component.derivative
            value = value * t + component.value
        }
        var wf = s4.value
        var wfRate = s4.derivative
        include(s3, in: &wf, rate: &wfRate)
        include(s2, in: &wf, rate: &wfRate)
        include(s1, in: &wf, rate: &wfRate)
        include(s0, in: &wf, rate: &wfRate)

        // JPL planetary masses instead of IAU.
        var wj = 0.0
        var wjRate = 0.0
        func addJPL(_ amplitude: Double, _ frequency: Double, _ phase: Double) {
            let argument = frequency * t + phase
            wj += amplitude * sin(argument)
            if needsDerivative { wjRate += amplitude * frequency * cos(argument) }
        }
        addJPL(0.00065e-6, 6069.776754, 4.021194)
        addJPL(0.00033e-6, 213.299095, 5.543132)
        addJPL(-0.00196e-6, 6208.294251, 5.696701)
        addJPL(-0.00173e-6, 74.781599, 2.435900)
        wj += 0.03638e-6 * t * t
        wjRate += 2 * 0.03638e-6 * t
        return (wf + wj, wfRate + wjRate)
    }

    // ERFA's 2π, the same double as 2 * Double.pi.
    private static let twoPi = 6.283185307179586476925287
    private static let radiansPerDegree = Engine.radiansPerDegree
}
