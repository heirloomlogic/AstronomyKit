//
//  EngineConstants.swift
//  AstronomyKit
//
//  Shared astronomical constants and pure-Swift math helpers for the engine.
//

import CLibAstronomy

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineConstants {
    static let pi = 3.14159265358979323846
    static let pi2 = 2.0 * pi
    static let deg2Rad = 0.017453292519943296
    static let rad2Deg = 57.295779513082321
    static let arc = 3600.0 * 180.0 / pi
    static let secondsPerDay = 24.0 * 3600.0
    static let meanSynodicMonth = 29.530588
    static let earthOrbitalPeriod = 365.256

    static let kmPerAU = 1.4959787069098932e+8
    static let sunRadiusKM = 695700.0
    static let sunRadiusAU = sunRadiusKM / kmPerAU
    static let earthEquatorialRadiusKM = 6378.1366
    static let earthFlattening = 0.996647180302104
    static let earthMeanRadiusKM = 6371.0
    static let earthAtmosphereKM = 88.0
    static let earthEclipseRadiusKM = earthMeanRadiusKM + earthAtmosphereKM
    static let earthEquatorialRadiusAU = earthEquatorialRadiusKM / kmPerAU
    static let moonMeanRadiusKM = 1737.4
    static let moonPolarRadiusKM = 1736.0
    static let moonPolarRadiusAU = moonPolarRadiusKM / kmPerAU
    static let moonAxisInclinationRadians = deg2Rad * 1.543

    static let asec180 = 180.0 * 60.0 * 60.0
    static let auPerParsec = asec180 / pi
    static let ephemerisMaxTTDays = 1_461_000.0
}

enum EngineMath {
    @inline(__always)
    static func ephemerisTimeOk(_ time: AstroTime) -> Bool {
        abs(time.terrestrialTime) <= EngineConstants.ephemerisMaxTTDays
    }

    @inline(__always)
    static func vectorLength(_ x: Double, _ y: Double, _ z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }

    @inline(__always)
    static func vectorLength(_ v: astro_vector_t) -> Double {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    /// Reduces an angle difference into (-180, +180] in constant time for any finite input.
    static func longitudeOffset(_ diff: Double) -> Double {
        var offset = diff
        if offset != 0.0 {
            offset = fmod(offset, 360.0) + 0.0
        }
        while offset <= -180.0 {
            offset += 360.0
        }
        while offset > 180.0 {
            offset -= 360.0
        }
        return offset
    }

    /// Normalizes a longitude into [0, 360) in constant time for any finite input.
    static func normalizeLongitude(_ lon: Double) -> Double {
        var value = lon
        if value != 0.0 {
            value = fmod(value, 360.0) + 0.0
        }
        while value < 0.0 {
            value += 360.0
        }
        while value >= 360.0 {
            value -= 360.0
        }
        return value
    }

    static func angleBetween(_ a: astro_vector_t, _ b: astro_vector_t) throws -> Double {
        let r = vectorLength(a) * vectorLength(b)
        guard r >= 1.0e-8, r.isFinite else {
            throw AstronomyError.badVector
        }
        let dot = (a.x * b.x + a.y * b.y + a.z * b.z) / r
        if dot <= -1.0 {
            return 180.0
        }
        if dot >= 1.0 {
            return 0.0
        }
        return EngineConstants.rad2Deg * acos(dot)
    }

    static func synodicPeriod(of body: CelestialBody) throws -> Double {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }
        if body == .moon {
            return EngineConstants.meanSynodicMonth
        }
        let period = Astronomy_PlanetOrbitalPeriod(body.raw)
        guard period > 0.0 else {
            throw AstronomyError.invalidBody
        }
        return abs(EngineConstants.earthOrbitalPeriod / (EngineConstants.earthOrbitalPeriod / period - 1.0))
    }

    @inline(__always)
    static func rotate(_ r: astro_rotation_t, _ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let rx = r.rot.0.0 * x + r.rot.1.0 * y + r.rot.2.0 * z
        let ry = r.rot.0.1 * x + r.rot.1.1 * y + r.rot.2.1 * z
        let rz = r.rot.0.2 * x + r.rot.1.2 * y + r.rot.2.2 * z
        return (rx, ry, rz)
    }

    static func equatorFromVector(
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) throws -> (ra: Double, dec: Double, dist: Double) {
        let xyproj = x * x + y * y
        let dist = sqrt(xyproj + z * z)
        if xyproj == 0.0 {
            if z == 0.0 {
                throw AstronomyError.invalidParameter
            }
            return (0.0, z < 0.0 ? -90.0 : 90.0, dist)
        }
        var lon = EngineConstants.rad2Deg * atan2(y, x)
        if lon < 0.0 {
            lon += 360.0
        }
        let lat = EngineConstants.rad2Deg * atan2(z, sqrt(xyproj))
        return (lon / 15.0, lat, dist)
    }
}
