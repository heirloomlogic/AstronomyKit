//
//  EngineConstants.swift
//  AstronomyKit
//
//  Shared astronomical constants and pure-Swift math helpers for the engine.
//

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
    static let hour2Rad = 0.2617993877991494365
    static let rad2Hour = 3.819718634205488
    static let asec2Rad = 4.848136811095359935899141e-6
    static let arc = 3600.0 * 180.0 / pi
    static let secondsPerDay = 24.0 * 3600.0
    static let daysPerTropicalYear = 365.24217
    static let solarDaysPerSiderealDay = 0.9972695717592592
    static let meanSynodicMonth = 29.530588
    static let earthOrbitalPeriod = 365.256
    static let neptuneOrbitalPeriod = 60189.0
    static let refractionNearHorizon = 34.0 / 60.0

    static let cAuday = 173.1446326846693
    static let kmPerAU = 1.4959787069098932e+8
    static let auPerLY = 63241.07708807546
    static let sunRadiusKM = 695700.0
    static let sunRadiusAU = sunRadiusKM / kmPerAU
    static let earthEquatorialRadiusKM = 6378.1366
    static let earthFlattening = 0.996647180302104
    static let earthPolarRadiusKM = earthEquatorialRadiusKM * earthFlattening
    static let earthMeanRadiusKM = 6371.0
    static let earthAtmosphereKM = 88.0
    static let earthEclipseRadiusKM = earthMeanRadiusKM + earthAtmosphereKM
    static let earthEquatorialRadiusAU = earthEquatorialRadiusKM / kmPerAU
    static let moonMeanRadiusKM = 1737.4
    static let moonEquatorialRadiusKM = 1738.1
    static let moonEquatorialRadiusAU = moonEquatorialRadiusKM / kmPerAU
    static let moonPolarRadiusKM = 1736.0
    static let moonPolarRadiusAU = moonPolarRadiusKM / kmPerAU
    static let moonAxisInclinationRadians = deg2Rad * 1.543

    static let asec180 = 180.0 * 60.0 * 60.0
    static let auPerParsec = asec180 / pi
    static let ephemerisMaxTTDays = 1_461_000.0
    static let earthMoonMassRatio = 81.30056

    static let obliq2000 = 0.40909260059599012
    static let cosObliq2000 = 0.9174821430670688
    static let sinObliq2000 = 0.3977769691083922

    static let sunGM = 0.2959122082855911e-03
    static let mercuryGM = 0.4912547451450812e-10
    static let venusGM = 0.7243452486162703e-09
    static let earthGM = 0.8887692390113509e-09
    static let moonGM = earthGM / earthMoonMassRatio
    static let marsGM = 0.9549535105779258e-10
    static let jupiterGM = 0.2825345909524226e-06
    static let saturnGM = 0.8459715185680659e-07
    static let uranusGM = 0.1292024916781969e-07
    static let neptuneGM = 0.1524358900784276e-07
    static let plutoGM = 0.2188699765425970e-11
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
    static func vectorLength(_ v: Vector3D) -> Double {
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

    static func angleBetween(_ a: Vector3D, _ b: Vector3D) throws -> Double {
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

    static func isSuperiorPlanet(_ body: CelestialBody) -> Bool {
        switch body {
        case .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
            return true
        default:
            return false
        }
    }

    static func planetOrbitalPeriod(of body: CelestialBody) -> Double {
        switch body {
        case .mercury: return 87.969
        case .venus: return 224.701
        case .earth: return EngineConstants.earthOrbitalPeriod
        case .mars: return 686.980
        case .jupiter: return 4332.589
        case .saturn: return 10759.22
        case .uranus: return 30685.4
        case .neptune: return EngineConstants.neptuneOrbitalPeriod
        case .pluto: return 90560.0
        default: return 0.0
        }
    }

    static func massProduct(of body: CelestialBody) -> Double {
        switch body {
        case .sun: return EngineConstants.sunGM
        case .mercury: return EngineConstants.mercuryGM
        case .venus: return EngineConstants.venusGM
        case .earth: return EngineConstants.earthGM
        case .moon: return EngineConstants.moonGM
        case .earthMoonBarycenter: return EngineConstants.earthGM + EngineConstants.moonGM
        case .mars: return EngineConstants.marsGM
        case .jupiter: return EngineConstants.jupiterGM
        case .saturn: return EngineConstants.saturnGM
        case .uranus: return EngineConstants.uranusGM
        case .neptune: return EngineConstants.neptuneGM
        case .pluto: return EngineConstants.plutoGM
        default: return 0.0
        }
    }

    static func synodicPeriod(of body: CelestialBody) throws -> Double {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }
        if body == .moon {
            return EngineConstants.meanSynodicMonth
        }
        let period = planetOrbitalPeriod(of: body)
        guard period > 0.0 else {
            throw AstronomyError.invalidBody
        }
        return abs(
            EngineConstants.earthOrbitalPeriod
                / (EngineConstants.earthOrbitalPeriod / period - 1.0)
        )
    }

    @inline(__always)
    static func rotate(
        _ r: RotationMatrix,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> (Double, Double, Double) {
        let rx = r.r00 * x + r.r10 * y + r.r20 * z
        let ry = r.r01 * x + r.r11 * y + r.r21 * z
        let rz = r.r02 * x + r.r12 * y + r.r22 * z
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
