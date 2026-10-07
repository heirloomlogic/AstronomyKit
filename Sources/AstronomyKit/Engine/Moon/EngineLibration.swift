//
//  EngineLibration.swift
//  AstronomyKit
//
//  The Moon's libration, and the lunar inputs to the phase and event searches.
//

import Foundation

extension Engine {
    /// The Moon's optical and physical libration, with the position it is
    /// computed from.
    struct Libration: Sendable {
        /// Libration in latitude and longitude in degrees: the selenographic
        /// latitude and east longitude of the point at the center of the
        /// Moon's disc as seen from Earth's center.
        var latitude: Double
        var longitude: Double
        /// The Moon's latitude and longitude in degrees on the mean ecliptic
        /// and equinox of date, from the lunar model.
        var moonLatitude: Double
        var moonLongitude: Double
        /// The distance between the centers of Earth and the Moon in km.
        var distanceKilometers: Double
        /// The Moon's apparent diameter in degrees.
        var diameter: Double
    }
}

extension Engine.Moon {
    /// The Moon's mean radius in km, 1,737.4 km (IAU Working Group on
    /// Cartographic Coordinates and Rotational Elements), as in the C engine.
    static let meanRadiusKilometers = 1_737.4

    /// The inclination of the Moon's mean equator to the ecliptic in
    /// degrees: the C engine's 1.543°. Meeus (Astronomical Algorithms,
    /// chapter 53) prints I = 1°32′32.7″, 1.54242°, which moves the
    /// libration latitude further from NASA's published values (#188).
    static let equatorInclination = 1.543

    /// The Moon's libration at `time` (`Astronomy_Libration`).
    ///
    /// Meeus, Astronomical Algorithms, chapter 53: the optical libration
    /// from the model's mean ecliptic coordinates at `time`, read through
    /// `cache`, and the physical libration from the series ρ, σ and τ. The
    /// distance is the model's, in km with the published au.
    ///
    /// Like the C function it never fails: a time that is not finite gives
    /// NaN, and far from J2000 the values are whatever the formulas give.
    static func libration(at time: Engine.Time, cache: Cache = cache) -> Engine.Libration {
        let t = time.tt / 36_525
        let t2 = t * t
        let t3 = t2 * t
        let t4 = t2 * t2
        let model = coordinates(centuries: t, cache: cache)
        let (mlon, mlat) = (model.x, model.y)
        let distance = model.z * Engine.kilometersPerAU
        let radius = meanRadiusKilometers
        let diameter =
            (2 * Engine.degreesPerRadian) * atan(radius / (distance * distance - radius * radius).squareRoot())

        let degrees = Engine.radiansPerDegree
        // The Moon's argument of latitude, its node's mean longitude, the Sun's
        // and the Moon's mean anomalies, and the Moon's mean elongation.
        let fDegrees = 93.2720950 + 483_202.0175233 * t - 0.0036539 * t2 - t3 / 3_526_000 + t4 / 863_310_000
        let omegaDegrees = 125.0445479 - 1_934.1362891 * t + 0.0020754 * t2 + t3 / 467_441 - t4 / 60_616_000
        let mDegrees = 357.5291092 + 35_999.0502909 * t - 0.0001536 * t2 + t3 / 24_490_000
        let mdashDegrees = 134.9633964 + 477_198.8675055 * t + 0.0087414 * t2 + t3 / 69_699 - t4 / 14_712_000
        let dDegrees = 297.8501921 + 445_267.1114034 * t - 0.0018819 * t2 + t3 / 545_868 - t4 / 113_065_000
        let f = degrees * normalizedLongitude(fDegrees)
        let omega = degrees * normalizedLongitude(omegaDegrees)
        let m = degrees * normalizedLongitude(mDegrees)
        let mdash = degrees * normalizedLongitude(mdashDegrees)
        let d = degrees * normalizedLongitude(dDegrees)
        // The eccentricity of Earth's orbit.
        let e = 1 - 0.002516 * t - 0.0000074 * t2

        // Optical libration.
        let sinI = sin(equatorInclination * degrees)
        let cosI = cos(equatorInclination * degrees)
        let w = mlon - omega
        let a = atan2(sin(w) * cos(mlat) * cosI - sin(mlat) * sinI, cos(w) * cos(mlat))
        let ldash = longitudeOffset(Engine.degreesPerRadian * (a - f))
        let bdash = asin(-sin(w) * cos(mlat) * sinI - sin(mlat) * cosI)

        // Physical libration.
        let k1 = degrees * (119.75 + 131.849 * t)
        let k2 = degrees * (72.56 + 20.186 * t)
        let rho = sum([
            -0.02752 * cos(mdash), -0.02245 * sin(f), 0.00684 * cos(mdash - 2 * f), -0.00293 * cos(2 * f),
            -0.00085 * cos(2 * f - 2 * d), -0.00054 * cos(mdash - 2 * d), -0.00020 * sin(mdash + f),
            -0.00020 * cos(mdash + 2 * f), -0.00020 * cos(mdash - f), 0.00014 * cos(mdash + 2 * f - 2 * d),
        ])
        let sigma = sum([
            -0.02816 * sin(mdash), 0.02244 * cos(f), -0.00682 * sin(mdash - 2 * f), -0.00279 * sin(2 * f),
            -0.00083 * sin(2 * f - 2 * d), 0.00069 * sin(mdash - 2 * d), 0.00040 * cos(mdash + f),
            -0.00025 * sin(2 * mdash), -0.00023 * sin(mdash + 2 * f), 0.00020 * cos(mdash - f),
            0.00019 * sin(mdash - f), 0.00013 * sin(mdash + 2 * f - 2 * d), -0.00010 * cos(mdash - 3 * f),
        ])
        let tau = sum([
            0.02520 * e * sin(m), 0.00473 * sin(2 * mdash - 2 * f), -0.00467 * sin(mdash), 0.00396 * sin(k1),
            0.00276 * sin(2 * mdash - 2 * d), 0.00196 * sin(omega), -0.00183 * cos(mdash - f),
            0.00115 * sin(mdash - 2 * d), -0.00096 * sin(mdash - d), 0.00046 * sin(2 * f - 2 * d),
            -0.00039 * sin(mdash - f), -0.00032 * sin(mdash - m - d), 0.00027 * sin(2 * mdash - m - 2 * d),
            0.00023 * sin(k2), -0.00014 * sin(2 * d), 0.00014 * cos(2 * mdash - 2 * f),
            -0.00012 * sin(mdash - 2 * f), -0.00012 * sin(2 * mdash), 0.00011 * sin(2 * mdash - 2 * m - 2 * d),
        ])
        let ldash2 = -tau + (rho * cos(a) + sigma * sin(a)) * tan(bdash)
        let bdash2 = sigma * cos(a) - rho * sin(a)

        return Engine.Libration(
            latitude: Engine.degreesPerRadian * bdash + bdash2,
            longitude: ldash + ldash2,
            moonLatitude: Engine.degreesPerRadian * mlat,
            moonLongitude: Engine.degreesPerRadian * mlon,
            distanceKilometers: distance,
            diameter: diameter
        )
    }

    // MARK: - Inputs to the phase and event searches

    /// The Moon's longitude in degrees on the true ecliptic and equinox of
    /// date, from ``geocentricPosition(at:cache:)`` with no light time: the
    /// Moon's side of `Astronomy_MoonPhase`, which subtracts the Sun's
    /// longitude found the same way. #92 owns the phase and its searches.
    ///
    /// - Throws: As ``geocentricPosition(at:cache:)``.
    static func eclipticLongitude(at time: Engine.Time, cache: Cache = cache) throws -> Double {
        Engine.Ecliptic(try geocentricPosition(at: time, cache: cache)).longitude
    }

    /// The model's distance in AU at `time`, the quantity the lunar apsis
    /// search follows (the C engine's `MoonDistance`). The node search reads
    /// the latitude of ``eclipticPosition(at:cache:)``.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``Engine/acceptedTTDays`` or is not finite, or when the distance is
    ///   not finite.
    static func distance(at time: Engine.Time, cache: Cache = cache) throws -> Double {
        try Engine.checkAcceptedTime(time)
        let distance = coordinates(centuries: time.tt / 36_525, cache: cache).z
        guard distance.isFinite else { throw AstronomyError.badTime }
        return distance
    }

    // MARK: - Helpers

    /// `values` added from first to last, as the C engine's sums are.
    private static func sum(_ values: [Double]) -> Double {
        values.dropFirst().reduce(values[0], +)
    }

    /// `longitude` in degrees moved into [0, 360), as the C engine's
    /// `NormalizeLongitude` does it: a remainder, then whole turns.
    static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        if value != 0 { value = value.truncatingRemainder(dividingBy: 360) + 0 }
        while value < 0 { value += 360 }
        while value >= 360 { value -= 360 }
        return value
    }

    /// `difference` in degrees moved into (−180, 180], as the C engine's
    /// `LongitudeOffset` does it.
    static func longitudeOffset(_ difference: Double) -> Double {
        var value = difference
        if value != 0 { value = value.truncatingRemainder(dividingBy: 360) + 0 }
        while value <= -180 { value += 360 }
        while value > 180 { value -= 360 }
        return value
    }
}
