//
//  EnginePositions.swift
//  AstronomyKit
//
//  Pure-Swift planetary, lunar, solar, barycentric, light-travel, and
//  stateless fixed-star position calculations.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EnginePositions {
    // MARK: - Moon & EMB Positions

    static func geoMoon(at time: AstroTime) throws -> Vector3D {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }
        let moon = EngineMoonCore.calcMoon(centuries: time.terrestrialTime / 36525.0)
        let distCosLat = moon.distanceAU * cos(moon.lat)
        let gx = distCosLat * cos(moon.lon)
        let gy = distCosLat * sin(moon.lon)
        let gz = moon.distanceAU * sin(moon.lat)

        let (mx, my, mz) = EngineRotation.ecl2Equ(at: time, gx, gy, gz)
        let prec = EngineRotation.precessionMatrix(at: time, into2000: true)
        let (x, y, z) = EngineMath.rotate(prec, mx, my, mz)
        return Vector3D(x: x, y: y, z: z, time: time)
    }

    static func eclipticGeoMoon(at time: AstroTime) throws -> Ecliptic {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }
        let moon = EngineMoonCore.calcMoon(centuries: time.terrestrialTime / 36525.0)
        let distCosLat = moon.distanceAU * cos(moon.lat)
        let ecx = distCosLat * cos(moon.lon)
        let ecy = distCosLat * sin(moon.lon)
        let ecz = moon.distanceAU * sin(moon.lat)

        let tilt = EngineRotation.earthTilt(at: time)
        let (eqmx, eqmy, eqmz) = EngineRotation.oblEcl2Equ(
            obliquityDegrees: tilt.mobl,
            ecx,
            ecy,
            ecz
        )
        let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: false)
        let (eqdx, eqdy, eqdz) = EngineMath.rotate(nut, eqmx, eqmy, eqmz)
        let ecl = EngineRotation.rotateEquatorialToEcliptic(
            eqdx,
            eqdy,
            eqdz,
            obliquityRadians: EngineConstants.deg2Rad * tilt.tobl
        )
        return Ecliptic(latitude: ecl.elat, longitude: ecl.elon, distance: moon.distanceAU)
    }

    static func geoMoonState(at time: AstroTime) throws -> StateVector {
        let dt = 1.0e-5
        let t1 = addTerrestrialDays(time, -dt)
        let t2 = addTerrestrialDays(time, dt)
        let r1 = try geoMoon(at: t1)
        let r2 = try geoMoon(at: t2)

        return StateVector(
            position: Vector3D(
                x: (r1.x + r2.x) / 2.0,
                y: (r1.y + r2.y) / 2.0,
                z: (r1.z + r2.z) / 2.0,
                time: time
            ),
            velocity: Vector3D(
                x: (r2.x - r1.x) / (2.0 * dt),
                y: (r2.y - r1.y) / (2.0 * dt),
                z: (r2.z - r1.z) / (2.0 * dt),
                time: time
            ),
            time: time
        )
    }

    static func geoEmbState(at time: AstroTime) throws -> StateVector {
        let s = try geoMoonState(at: time)
        let d = 1.0 + EngineConstants.earthMoonMassRatio
        return StateVector(
            position: Vector3D(
                x: s.position.x / d,
                y: s.position.y / d,
                z: s.position.z / d,
                time: time
            ),
            velocity: Vector3D(
                x: s.velocity.x / d,
                y: s.velocity.y / d,
                z: s.velocity.z / d,
                time: time
            ),
            time: time
        )
    }

    // MARK: - Heliocentric, Barycentric & Geocentric Positions

    @inline(__always)
    static func addTerrestrialDays(_ time: AstroTime, _ days: Double) -> AstroTime {
        time.addingTerrestrialDays(days)
    }

    static func helioXYZ(
        of body: CelestialBody,
        at time: AstroTime
    ) throws -> (x: Double, y: Double, z: Double) {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        switch body {
        case .sun:
            return (0.0, 0.0, 0.0)

        case .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune:
            guard let idx = EngineVsop.bodyIndex(for: body) else {
                throw AstronomyError.invalidBody
            }
            let pos = EngineVsop.calcVsop(bodyIndex: idx, tt: time.terrestrialTime)
            return (pos.x, pos.y, pos.z)

        case .pluto:
            let state = try EngineGravityPluto.calcPluto(at: time, heliocentric: true)
            return (state.r.x, state.r.y, state.r.z)

        case .moon:
            let moon = try geoMoon(at: time)
            let earth = EngineVsop.calcVsop(bodyIndex: 2, tt: time.terrestrialTime)
            return (moon.x + earth.x, moon.y + earth.y, moon.z + earth.z)

        case .earthMoonBarycenter:
            let moon = try geoMoon(at: time)
            let earth = EngineVsop.calcVsop(bodyIndex: 2, tt: time.terrestrialTime)
            let d = 1.0 + EngineConstants.earthMoonMassRatio
            return (earth.x + moon.x / d, earth.y + moon.y / d, earth.z + moon.z / d)

        case .solarSystemBarycenter:
            let ssb = EngineVsop.calcSolarSystemBarycenter(tt: time.terrestrialTime)
            return (ssb.x, ssb.y, ssb.z)

        default:
            throw AstronomyError.invalidBody
        }
    }

    static func helioVector(of body: CelestialBody, at time: AstroTime) throws -> Vector3D {
        let (x, y, z) = try helioXYZ(of: body, at: time)
        return Vector3D(x: x, y: y, z: z, time: time)
    }

    static func helioDistance(of body: CelestialBody, at time: AstroTime) throws -> Double {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        switch body {
        case .sun:
            return 0.0

        case .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune:
            guard let idx = EngineVsop.bodyIndex(for: body) else {
                throw AstronomyError.invalidBody
            }
            return EngineVsop.vsopHelioDistance(bodyIndex: idx, tt: time.terrestrialTime)

        default:
            let (x, y, z) = try helioXYZ(of: body, at: time)
            return sqrt(x * x + y * y + z * z)
        }
    }

    static func correctLightTravel(
        at time: AstroTime,
        _ positionFunction: (AstroTime) throws -> Vector3D
    ) throws -> Vector3D {
        var ltime = time
        var iter = 0
        while iter < 10 {
            let pos = try positionFunction(ltime)
            let distance = sqrt(pos.x * pos.x + pos.y * pos.y + pos.z * pos.z)
            if distance > EngineConstants.cAuday {
                throw AstronomyError.invalidParameter
            }
            let ltime2 = addTerrestrialDays(time, -distance / EngineConstants.cAuday)
            let dt = abs(ltime2.tt - ltime.tt)
            if dt < 1.0e-9 {
                return Vector3D(x: pos.x, y: pos.y, z: pos.z, time: ltime)
            }
            ltime = ltime2
            iter &+= 1
        }
        throw AstronomyError.noConvergence
    }

    static func backdatePosition(
        at time: AstroTime,
        observerBody: CelestialBody,
        targetBody: CelestialBody,
        aberration: Aberration
    ) throws -> Vector3D {
        var ox = 0.0
        var oy = 0.0
        var oz = 0.0
        let fixedObserver = (aberration == .none)
        if fixedObserver {
            (ox, oy, oz) = try helioXYZ(of: observerBody, at: time)
        }

        var ltime = time
        var iter = 0
        while iter < 10 {
            if !fixedObserver {
                (ox, oy, oz) = try helioXYZ(of: observerBody, at: ltime)
            }
            let (tx, ty, tz) = try helioXYZ(of: targetBody, at: ltime)
            let dx = tx - ox
            let dy = ty - oy
            let dz = tz - oz
            let distance = sqrt(dx * dx + dy * dy + dz * dz)
            if distance > EngineConstants.cAuday {
                throw AstronomyError.invalidParameter
            }
            let ltime2 = addTerrestrialDays(time, -distance / EngineConstants.cAuday)
            if abs(ltime2.tt - ltime.tt) < 1.0e-9 {
                return Vector3D(x: dx, y: dy, z: dz, time: ltime)
            }
            ltime = ltime2
            iter &+= 1
        }
        throw AstronomyError.noConvergence
    }

    static func geoVector(
        of body: CelestialBody,
        at time: AstroTime,
        aberration: Aberration
    ) throws -> Vector3D {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        let vec: Vector3D
        switch body {
        case .earth:
            return Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time)
        case .moon:
            vec = try geoMoon(at: time)
        default:
            vec = try backdatePosition(
                at: time,
                observerBody: .earth,
                targetBody: body,
                aberration: aberration
            )
        }
        return Vector3D(x: vec.x, y: vec.y, z: vec.z, time: time)
    }

    static func baryState(of body: CelestialBody, at time: AstroTime) throws -> StateVector {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        let tt = time.terrestrialTime

        if body == .solarSystemBarycenter {
            return StateVector(
                position: Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time),
                velocity: Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time),
                time: time
            )
        }

        if body == .pluto {
            return try EngineGravityPluto.calcPluto(at: time, heliocentric: false)
                .toStateVector(at: time)
        }

        switch body {
        case .sun:
            return EngineVsop.majorBodyBary(tt: tt).sun.toStateVector(at: time)
        case .jupiter:
            return EngineVsop.majorBodyBary(tt: tt).jupiter.toStateVector(at: time)
        case .saturn:
            return EngineVsop.majorBodyBary(tt: tt).saturn.toStateVector(at: time)
        case .uranus:
            return EngineVsop.majorBodyBary(tt: tt).uranus.toStateVector(at: time)
        case .neptune:
            return EngineVsop.majorBodyBary(tt: tt).neptune.toStateVector(at: time)

        case .mercury, .venus, .earth, .mars:
            guard let idx = EngineVsop.bodyIndex(for: body) else {
                throw AstronomyError.invalidBody
            }
            let barySun = EngineVsop.majorBodyBary(tt: tt).sun
            let planet = EngineVsop.calcVsopPosVel(bodyIndex: idx, tt: tt)
            return StateVector(
                position: Vector3D(
                    x: barySun.r.x + planet.r.x,
                    y: barySun.r.y + planet.r.y,
                    z: barySun.r.z + planet.r.z,
                    time: time
                ),
                velocity: Vector3D(
                    x: barySun.v.x + planet.v.x,
                    y: barySun.v.y + planet.v.y,
                    z: barySun.v.z + planet.v.z,
                    time: time
                ),
                time: time
            )

        case .moon, .earthMoonBarycenter:
            let barySun = EngineVsop.majorBodyBary(tt: tt).sun
            let earth = EngineVsop.calcVsopPosVel(bodyIndex: 2, tt: tt)
            let state =
                body == .moon
                ? try geoMoonState(at: time)
                : try geoEmbState(at: time)
            return StateVector(
                position: Vector3D(
                    x: state.position.x + barySun.r.x + earth.r.x,
                    y: state.position.y + barySun.r.y + earth.r.y,
                    z: state.position.z + barySun.r.z + earth.r.z,
                    time: time
                ),
                velocity: Vector3D(
                    x: state.velocity.x + barySun.v.x + earth.v.x,
                    y: state.velocity.y + barySun.v.y + earth.v.y,
                    z: state.velocity.z + barySun.v.z + earth.v.z,
                    time: time
                ),
                time: time
            )

        default:
            throw AstronomyError.invalidBody
        }
    }

    static func helioState(of body: CelestialBody, at time: AstroTime) throws -> StateVector {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        let tt = time.terrestrialTime

        switch body {
        case .sun:
            return StateVector(
                position: Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time),
                velocity: Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time),
                time: time
            )

        case .solarSystemBarycenter:
            let barySun = EngineVsop.majorBodyBary(tt: tt).sun
            return StateVector(
                position: Vector3D(
                    x: -barySun.r.x,
                    y: -barySun.r.y,
                    z: -barySun.r.z,
                    time: time
                ),
                velocity: Vector3D(
                    x: -barySun.v.x,
                    y: -barySun.v.y,
                    z: -barySun.v.z,
                    time: time
                ),
                time: time
            )

        case .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune:
            guard let idx = EngineVsop.bodyIndex(for: body) else {
                throw AstronomyError.invalidBody
            }
            return EngineVsop.calcVsopPosVel(bodyIndex: idx, tt: tt).toStateVector(at: time)

        case .pluto:
            return try EngineGravityPluto.calcPluto(at: time, heliocentric: true)
                .toStateVector(at: time)

        case .moon, .earthMoonBarycenter:
            let earth = EngineVsop.calcVsopPosVel(bodyIndex: 2, tt: tt)
            let state =
                body == .moon
                ? try geoMoonState(at: time)
                : try geoEmbState(at: time)
            return StateVector(
                position: Vector3D(
                    x: state.position.x + earth.r.x,
                    y: state.position.y + earth.r.y,
                    z: state.position.z + earth.r.z,
                    time: time
                ),
                velocity: Vector3D(
                    x: state.velocity.x + earth.v.x,
                    y: state.velocity.y + earth.v.y,
                    z: state.velocity.z + earth.v.z,
                    time: time
                ),
                time: time
            )

        default:
            throw AstronomyError.invalidBody
        }
    }

    // MARK: - Stateless Fixed-Star Positions

    static func validateStar(
        rightAscension ra: Double,
        declination dec: Double,
        distanceLightYears distLY: Double
    ) throws -> Double {
        guard ra.isFinite, ra >= 0.0, ra < 24.0 else {
            throw AstronomyError.invalidParameter
        }
        guard dec.isFinite, dec >= -90.0, dec <= 90.0 else {
            throw AstronomyError.invalidParameter
        }
        guard distLY.isFinite, distLY >= 1.0 else {
            throw AstronomyError.invalidParameter
        }
        return distLY * EngineConstants.auPerLY
    }

    static func starGeoVector(
        rightAscension ra: Double,
        declination dec: Double,
        distanceLightYears distLY: Double,
        at time: AstroTime,
        aberration: Aberration
    ) throws -> Vector3D {
        let distAU = try validateStar(
            rightAscension: ra,
            declination: dec,
            distanceLightYears: distLY
        )
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }
        let tvec = EngineRotation.vectorFromSphere(
            Spherical(latitude: dec, longitude: 15.0 * ra, distance: distAU),
            at: time
        )
        switch aberration {
        case .none:
            let ovec = try helioVector(of: .earth, at: time)
            return Vector3D(
                x: tvec.x - ovec.x,
                y: tvec.y - ovec.y,
                z: tvec.z - ovec.z,
                time: time
            )
        case .corrected:
            let ostate = try helioState(of: .earth, at: time)
            let rx = tvec.x - ostate.position.x
            let ry = tvec.y - ostate.position.y
            let rz = tvec.z - ostate.position.z
            let s = EngineConstants.cAuday / sqrt(rx * rx + ry * ry + rz * rz)
            return Vector3D(
                x: rx + ostate.velocity.x / s,
                y: ry + ostate.velocity.y / s,
                z: rz + ostate.velocity.z / s,
                time: time
            )
        }
    }

    // MARK: - Sun, Ecliptic, AngleFromSun & PairLongitude

    static func sunPosition(at time: AstroTime) throws -> Ecliptic {
        let adjustedTime = addTerrestrialDays(time, -1.0 / EngineConstants.cAuday)
        guard EngineMath.ephemerisTimeOk(adjustedTime) else {
            throw AstronomyError.badTime
        }
        let earth = EngineVsop.calcVsop(bodyIndex: 2, tt: adjustedTime.terrestrialTime)
        let sx = -earth.x
        let sy = -earth.y
        let sz = -earth.z

        let tilt = EngineRotation.earthTilt(at: adjustedTime)
        let prec = EngineRotation.precessionMatrix(at: adjustedTime, into2000: false)
        let (tx, ty, tz) = EngineMath.rotate(prec, sx, sy, sz)
        let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: false)
        let (ox, oy, oz) = EngineMath.rotate(nut, tx, ty, tz)
        let ecl = EngineRotation.rotateEquatorialToEcliptic(
            ox,
            oy,
            oz,
            obliquityRadians: EngineConstants.deg2Rad * tilt.tobl
        )
        let dist = sqrt(ecl.vx * ecl.vx + ecl.vy * ecl.vy + ecl.vz * ecl.vz)
        guard ecl.elat.isFinite, ecl.elon.isFinite, dist.isFinite else {
            throw AstronomyError.badTime
        }
        return Ecliptic(latitude: ecl.elat, longitude: ecl.elon, distance: dist)
    }

    static func ecliptic(of eqj: Vector3D) throws -> Ecliptic {
        let tilt = EngineRotation.earthTilt(at: eqj.time)
        let prec = EngineRotation.precessionMatrix(at: eqj.time, into2000: false)
        let (mx, my, mz) = EngineMath.rotate(prec, eqj.x, eqj.y, eqj.z)
        let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: false)
        let (ex, ey, ez) = EngineMath.rotate(nut, mx, my, mz)
        let ecl = EngineRotation.rotateEquatorialToEcliptic(
            ex,
            ey,
            ez,
            obliquityRadians: tilt.tobl * EngineConstants.deg2Rad
        )
        let dist = sqrt(ecl.vx * ecl.vx + ecl.vy * ecl.vy + ecl.vz * ecl.vz)
        guard ecl.elat.isFinite, ecl.elon.isFinite, dist.isFinite else {
            throw AstronomyError.badTime
        }
        return Ecliptic(latitude: ecl.elat, longitude: ecl.elon, distance: dist)
    }

    static func eclipticLongitude(of body: CelestialBody, at time: AstroTime) throws -> Double {
        if body == .sun {
            throw AstronomyError.invalidBody
        }
        let hv = try helioVector(of: body, at: time)
        let ecl = try ecliptic(of: hv)
        return ecl.longitude
    }

    /// Computes true ecliptic longitudes of two J2000 vectors at the same instant,
    /// computing Earth's nutation and precession frame only once.
    private static func eclipticLongitudePair(
        _ v1: (x: Double, y: Double, z: Double),
        _ v2: (x: Double, y: Double, z: Double),
        at time: AstroTime
    ) throws -> (Double, Double) {
        let tilt = EngineRotation.earthTilt(at: time)
        let prec = EngineRotation.precessionMatrix(at: time, into2000: false)
        let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: false)
        let oblRad = tilt.tobl * EngineConstants.deg2Rad

        let (m1x, m1y, m1z) = EngineMath.rotate(prec, v1.x, v1.y, v1.z)
        let (e1x, e1y, e1z) = EngineMath.rotate(nut, m1x, m1y, m1z)
        let ecl1 = EngineRotation.rotateEquatorialToEcliptic(
            e1x,
            e1y,
            e1z,
            obliquityRadians: oblRad
        )
        let d1 = sqrt(ecl1.vx * ecl1.vx + ecl1.vy * ecl1.vy + ecl1.vz * ecl1.vz)
        guard ecl1.elat.isFinite, ecl1.elon.isFinite, d1.isFinite else {
            throw AstronomyError.badTime
        }

        let (m2x, m2y, m2z) = EngineMath.rotate(prec, v2.x, v2.y, v2.z)
        let (e2x, e2y, e2z) = EngineMath.rotate(nut, m2x, m2y, m2z)
        let ecl2 = EngineRotation.rotateEquatorialToEcliptic(
            e2x,
            e2y,
            e2z,
            obliquityRadians: oblRad
        )
        let d2 = sqrt(ecl2.vx * ecl2.vx + ecl2.vy * ecl2.vy + ecl2.vz * ecl2.vz)
        guard ecl2.elat.isFinite, ecl2.elon.isFinite, d2.isFinite else {
            throw AstronomyError.badTime
        }

        return (ecl1.elon, ecl2.elon)
    }

    static func helioEclipticLongitudePair(
        body1: CelestialBody,
        body2: CelestialBody,
        at time: AstroTime
    ) throws -> (Double, Double) {
        if body1 == .sun || body2 == .sun {
            throw AstronomyError.invalidBody
        }
        let v1 = try helioXYZ(of: body1, at: time)
        let v2 = try helioXYZ(of: body2, at: time)
        return try eclipticLongitudePair(v1, v2, at: time)
    }

    static func angleFromSun(of body: CelestialBody, at time: AstroTime) throws -> Double {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }
        let sv = try geoVector(of: .sun, at: time, aberration: .corrected)
        let bv = try geoVector(of: body, at: time, aberration: .corrected)
        return try EngineMath.angleBetween(sv, bv)
    }

    static func pairLongitude(
        body1: CelestialBody,
        body2: CelestialBody,
        at time: AstroTime
    ) throws -> Double {
        if body1 == .earth || body2 == .earth {
            throw AstronomyError.earthNotAllowed
        }
        let v1 = try geoVector(of: body1, at: time, aberration: .none)
        let v2 = try geoVector(of: body2, at: time, aberration: .none)
        let (lon1, lon2) = try eclipticLongitudePair(
            (v1.x, v1.y, v1.z),
            (v2.x, v2.y, v2.z),
            at: time
        )
        return EngineMath.normalizeLongitude(lon1 - lon2)
    }
}
