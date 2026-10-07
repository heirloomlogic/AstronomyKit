//
//  EngineEarthRotation.swift
//  AstronomyKit
//
//  Earth rotation angle and Greenwich sidereal time.
//

import Foundation

extension Engine {
    /// Earth's rotation: the Earth rotation angle (IAU 2000 Resolution B1.8)
    /// and Greenwich sidereal time on the IAU 2006 precession (Capitaine,
    /// Guinot and McCarthy 2000; Capitaine, Wallace and Chapront 2005).
    enum EarthRotation {}
}

extension Engine.EarthRotation {
    /// The Earth rotation angle in degrees, from 0 up to 360, at `ut` days of
    /// UT1 from J2000 (SOFA `iauEra00`).
    ///
    /// The whole days of `ut` and its fraction enter separately, so the angle
    /// keeps the fraction's precision at any date.
    static func angle(ut: Double) -> Double {
        let turns = 0.779_057_273_264_0 + 0.002_737_811_911_354_48 * ut + fmod(ut, 1.0)
        return normalized(360 * fmod(turns, 1.0), period: 360)
    }

    /// Greenwich mean sidereal time in sidereal hours, from 0 up to 24
    /// (SOFA `iauGmst06`): the Earth rotation angle at `time.ut` plus the
    /// accumulated precession in right ascension at `time.tt`.
    static func meanSiderealTime(_ time: Engine.Time) -> Double {
        siderealTime(time, equationOfEquinoxes: 0)
    }

    /// Greenwich apparent sidereal time in sidereal hours, from 0 up to 24:
    /// mean sidereal time plus the equation of the equinoxes of
    /// ``Engine/EarthTilt/equationOfEquinoxes``, with nutation read through
    /// `cache`.
    static func apparentSiderealTime(
        _ time: Engine.Time,
        cache: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> = Engine.Nutation.cache
    ) -> Double {
        siderealTime(time, equationOfEquinoxes: Engine.EarthTilt(tt: time.tt, cache: cache).equationOfEquinoxes)
    }

    /// Sidereal hours for an equation of the equinoxes in degrees.
    private static func siderealTime(_ time: Engine.Time, equationOfEquinoxes: Double) -> Double {
        let t = time.tt / 36525
        // Capitaine et al. (2005) polynomial, in arcseconds.
        let precession =
            0.014_506
            + ((((-0.000_000_036_8 * t - 0.000_029_956) * t - 0.000_000_44) * t + 1.391_581_7) * t + 4_612.156_534) * t
        let degrees = equationOfEquinoxes + precession / 3600 + angle(ut: time.ut)
        return normalized(fmod(degrees, 360) / 15, period: 24)
    }

    /// `value`, which lies in (−period, period), moved into [0, period).
    private static func normalized(_ value: Double, period: Double) -> Double {
        guard value < 0 else { return value }
        let shifted = value + period
        // A tiny negative value rounds up to the period itself.
        return shifted < period ? shifted : 0
    }
}
