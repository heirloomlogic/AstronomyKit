//
//  EngineLibration.swift
//  AstronomyKit
//
//  Pure-Swift lunar optical and physical libration matching Astronomy_Libration.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineLibration {
    static func libration(at time: AstroTime) -> Libration {
        let sinI = sin(EngineConstants.moonAxisInclinationRadians)
        let cosI = cos(EngineConstants.moonAxisInclinationRadians)
        let deg2Rad = EngineConstants.deg2Rad
        let rad2Deg = EngineConstants.rad2Deg
        let moonMeanRadius = EngineConstants.moonMeanRadiusKM

        let t = time.terrestrialTime / 36525.0
        let t2 = t * t
        let t3 = t2 * t
        let t4 = t2 * t2

        let moon = EngineMoonCore.calcMoon(centuries: t)
        let mlon = moon.lon
        let mlat = moon.lat
        let distKM = moon.distanceAU * EngineConstants.kmPerAU
        let diamDeg =
            (2.0 * rad2Deg) * atan(moonMeanRadius / sqrt(distKM * distKM - moonMeanRadius * moonMeanRadius))

        let f =
            deg2Rad
            * EngineMath.normalizeLongitude(
                93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000.0 + t4 / 863310000.0
            )
        let omega =
            deg2Rad
            * EngineMath.normalizeLongitude(
                125.0445479 - 1934.1362891 * t + 0.0020754 * t2 + t3 / 467441.0 - t4 / 60616000.0
            )
        let m =
            deg2Rad
            * EngineMath.normalizeLongitude(
                357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000.0
            )
        let mdash =
            deg2Rad
            * EngineMath.normalizeLongitude(
                134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699.0 - t4 / 14712000.0
            )
        let d =
            deg2Rad
            * EngineMath.normalizeLongitude(
                297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868.0 - t4 / 113065000.0
            )

        let e = 1.0 - 0.002516 * t - 0.0000074 * t2

        // Optical librations
        let w = mlon - omega
        let cosMlat = cos(mlat)
        let sinMlat = sin(mlat)
        let sinW = sin(w)
        let a = atan2(sinW * cosMlat * cosI - sinMlat * sinI, cos(w) * cosMlat)
        let ldash = EngineMath.longitudeOffset(rad2Deg * (a - f))
        let bdashRad = asin(-sinW * cosMlat * sinI - sinMlat * cosI)

        // Physical librations
        let k1 = deg2Rad * (119.75 + 131.849 * t)
        let k2 = deg2Rad * (72.56 + 20.186 * t)

        let rho =
            -0.02752 * cos(mdash)
            - 0.02245 * sin(f)
            + 0.00684 * cos(mdash - 2.0 * f)
            - 0.00293 * cos(2.0 * f)
            - 0.00085 * cos(2.0 * f - 2.0 * d)
            - 0.00054 * cos(mdash - 2.0 * d)
            - 0.00020 * sin(mdash + f)
            - 0.00020 * cos(mdash + 2.0 * f)
            - 0.00020 * cos(mdash - f)
            + 0.00014 * cos(mdash + 2.0 * f - 2.0 * d)

        let sigma =
            -0.02816 * sin(mdash)
            + 0.02244 * cos(f)
            - 0.00682 * sin(mdash - 2.0 * f)
            - 0.00279 * sin(2.0 * f)
            - 0.00083 * sin(2.0 * f - 2.0 * d)
            + 0.00069 * sin(mdash - 2.0 * d)
            + 0.00040 * cos(mdash + f)
            - 0.00025 * sin(2.0 * mdash)
            - 0.00023 * sin(mdash + 2.0 * f)
            + 0.00020 * cos(mdash - f)
            + 0.00019 * sin(mdash - f)
            + 0.00013 * sin(mdash + 2.0 * f - 2.0 * d)
            - 0.00010 * cos(mdash - 3.0 * f)

        let tau =
            0.02520 * e * sin(m)
            + 0.00473 * sin(2.0 * mdash - 2.0 * f)
            - 0.00467 * sin(mdash)
            + 0.00396 * sin(k1)
            + 0.00276 * sin(2.0 * mdash - 2.0 * d)
            + 0.00196 * sin(omega)
            - 0.00183 * cos(mdash - f)
            + 0.00115 * sin(mdash - 2.0 * d)
            - 0.00096 * sin(mdash - d)
            + 0.00046 * sin(2.0 * f - 2.0 * d)
            - 0.00039 * sin(mdash - f)
            - 0.00032 * sin(mdash - m - d)
            + 0.00027 * sin(2.0 * mdash - m - 2.0 * d)
            + 0.00023 * sin(k2)
            - 0.00014 * sin(2.0 * d)
            + 0.00014 * cos(2.0 * mdash - 2.0 * f)
            - 0.00012 * sin(mdash - 2.0 * f)
            - 0.00012 * sin(2.0 * mdash)
            + 0.00011 * sin(2.0 * mdash - 2.0 * m - 2.0 * d)

        let cosA = cos(a)
        let sinA = sin(a)
        let ldash2 = -tau + (rho * cosA + sigma * sinA) * tan(bdashRad)
        let bdashDeg = bdashRad * rad2Deg
        let bdash2 = sigma * cosA - rho * sinA

        return Libration(
            subEarthLatitude: bdashDeg + bdash2,
            subEarthLongitude: ldash + ldash2,
            moonLatitude: rad2Deg * mlat,
            moonLongitude: rad2Deg * mlon,
            distanceKM: distKM,
            apparentDiameter: diamDeg
        )
    }
}
