//
//  EngineIllumination.swift
//  AstronomyKit
//
//  Pure-Swift visual magnitude, phase angle, Saturn ring tilt, and peak magnitude
//  search matching Astronomy_Illumination and Astronomy_SearchPeakMagnitude.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineIllumination {
    static func illumination(of body: CelestialBody, at time: AstroTime) throws -> Illumination {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }

        let earth = try EnginePositions.helioVector(of: .earth, at: time)
        let gc: Vector3D
        let hc: Vector3D
        let phaseAngle: Double

        if body == .sun {
            gc = Vector3D(x: -earth.x, y: -earth.y, z: -earth.z, time: time)
            hc = Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time)
            phaseAngle = 0.0
        } else {
            if body == .moon {
                gc = try EnginePositions.geoMoon(at: time)
                hc = Vector3D(
                    x: earth.x + gc.x,
                    y: earth.y + gc.y,
                    z: earth.z + gc.z,
                    time: time
                )
            } else {
                hc = try EnginePositions.helioVector(of: body, at: time)
                gc = Vector3D(
                    x: hc.x - earth.x,
                    y: hc.y - earth.y,
                    z: hc.z - earth.z,
                    time: time
                )
            }
            phaseAngle = try EngineMath.angleBetween(gc, hc)
        }

        let geoDist = EngineMath.vectorLength(gc)
        let helioDist = EngineMath.vectorLength(hc)
        let mag: Double
        var ringTilt = 0.0

        switch body {
        case .sun:
            mag = -0.17 + 5.0 * log10(geoDist / EngineConstants.auPerParsec)
        case .moon:
            mag = moonMagnitude(phase: phaseAngle, helioDist: helioDist, geoDist: geoDist)
        case .saturn:
            (mag, ringTilt) = try saturnMagnitude(
                phase: phaseAngle,
                helioDist: helioDist,
                geoDist: geoDist,
                gc: gc,
                time: time
            )
        default:
            mag = try visualMagnitude(
                body: body,
                phase: phaseAngle,
                helioDist: helioDist,
                geoDist: geoDist
            )
        }

        return Illumination(
            time: time,
            magnitude: mag,
            phaseAngle: phaseAngle,
            phaseFraction: (1.0 + cos(EngineConstants.deg2Rad * phaseAngle)) / 2.0,
            helioDistance: helioDist,
            ringTilt: ringTilt
        )
    }

    static func searchPeakMagnitude(of body: CelestialBody, after startTime: AstroTime) throws -> Illumination {
        guard body == .venus else {
            throw AstronomyError.invalidBody
        }

        let s1 = 10.0
        let s2 = 30.0
        var searchStart = startTime

        for _ in 0..<2 {
            let plon = try EnginePositions.eclipticLongitude(of: body, at: searchStart)
            let elon = try EnginePositions.eclipticLongitude(of: .earth, at: searchStart)

            let rlon = EngineMath.longitudeOffset(plon - elon)
            let adjustDays: Double
            let rlonLo: Double
            let rlonHi: Double

            if rlon >= -s1 && rlon < s1 {
                adjustDays = 0.0
                rlonLo = s1
                rlonHi = s2
            } else if rlon >= s2 || rlon < -s2 {
                adjustDays = 0.0
                rlonLo = -s2
                rlonHi = -s1
            } else if rlon >= 0.0 {
                let syn = try EngineMath.synodicPeriod(of: body)
                adjustDays = -syn / 4.0
                rlonLo = s1
                rlonHi = s2
            } else {
                let syn = try EngineMath.synodicPeriod(of: body)
                adjustDays = -syn / 4.0
                rlonLo = -s2
                rlonHi = -s1
            }

            let tStart = searchStart.addingDays(adjustDays)
            let t1 = try EngineEvents.searchRelativeLongitude(of: body, targetRelLon: rlonLo, after: tStart)
            let t2 = try EngineEvents.searchRelativeLongitude(of: body, targetRelLon: rlonHi, after: t1)

            let m1 = try magSlope(of: body, at: t1)
            guard m1 < 0.0 else {
                throw AstronomyError.internalError
            }
            let m2 = try magSlope(of: body, at: t2)
            guard m2 > 0.0 else {
                throw AstronomyError.internalError
            }

            let tx = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 10.0) { t in
                try magSlope(of: body, at: t)
            }

            if tx.terrestrialTime >= searchStart.terrestrialTime {
                return try illumination(of: body, at: tx)
            }

            searchStart = t2.addingDays(1.0)
        }

        throw AstronomyError.searchFailure
    }

    private static func magSlope(of body: CelestialBody, at time: AstroTime) throws -> Double {
        let dt = 0.01
        let t1 = time.addingTerrestrialDays(-dt / 2.0)
        let t2 = time.addingTerrestrialDays(dt / 2.0)
        let y1 = try illumination(of: body, at: t1)
        let y2 = try illumination(of: body, at: t2)
        return (y2.magnitude - y1.magnitude) / dt
    }

    private static func moonMagnitude(phase: Double, helioDist: Double, geoDist: Double) -> Double {
        let rad = phase * EngineConstants.deg2Rad
        let rad2 = rad * rad
        let rad4 = rad2 * rad2
        var mag = -12.717 + 1.49 * abs(rad) + 0.0431 * rad4
        let moonMeanDistanceAU = 385000.6 / EngineConstants.kmPerAU
        let geoAU = geoDist / moonMeanDistanceAU
        mag += 5.0 * log10(helioDist * geoAU)
        return mag
    }

    private static func saturnMagnitude(
        phase: Double,
        helioDist: Double,
        geoDist: Double,
        gc: Vector3D,
        time: AstroTime
    ) throws -> (mag: Double, ringTilt: Double) {
        let eclip = try EnginePositions.ecliptic(of: gc)

        let deg2Rad = EngineConstants.deg2Rad
        let ir = deg2Rad * 28.06
        let nr = deg2Rad * (169.51 + 3.82e-5 * time.terrestrialTime)
        let lat = deg2Rad * eclip.latitude
        let lon = deg2Rad * eclip.longitude
        let tilt = asin(sin(lat) * cos(ir) - cos(lat) * sin(ir) * sin(lon - nr))
        let sinTilt = sin(abs(tilt))

        var mag = -9.0 + 0.044 * phase
        mag += sinTilt * (-2.6 + 1.2 * sinTilt)
        mag += 5.0 * log10(helioDist * geoDist)

        return (mag, EngineConstants.rad2Deg * tilt)
    }

    private static func visualMagnitude(
        body: CelestialBody,
        phase: Double,
        helioDist: Double,
        geoDist: Double
    ) throws -> Double {
        let c0: Double
        var c1 = 0.0
        var c2 = 0.0
        var c3 = 0.0

        switch body {
        case .mercury:
            c0 = -0.60
            c1 = 4.98
            c2 = -4.88
            c3 = 3.02
        case .venus:
            if phase < 163.6 {
                c0 = -4.47
                c1 = 1.03
                c2 = 0.57
                c3 = 0.13
            } else {
                c0 = 0.98
                c1 = -1.02
            }
        case .mars:
            c0 = -1.52
            c1 = 1.60
        case .jupiter:
            c0 = -9.40
            c1 = 0.50
        case .uranus:
            c0 = -7.19
            c1 = 0.25
        case .neptune:
            c0 = -6.87
        case .pluto:
            c0 = -1.00
            c1 = 4.00
        default:
            throw AstronomyError.invalidBody
        }

        let x = phase / 100.0
        return c0 + x * (c1 + x * (c2 + x * c3)) + 5.0 * log10(helioDist * geoDist)
    }
}
