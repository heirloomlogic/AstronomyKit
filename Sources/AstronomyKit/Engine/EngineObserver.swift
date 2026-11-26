//
//  EngineObserver.swift
//  AstronomyKit
//
//  Pure-Swift observer geometry (WGS84 terra/inverse_terra, gravity),
//  topocentric equatorial/horizontal coordinates, and U.S. Standard Atmosphere.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineObserver {
    private static let earthAngVel = 7.2921150e-5

    // MARK: - WGS84 Terra & Inverse Terra

    static func terraPosition(
        observer: Observer,
        siderealHours st: Double
    ) -> (Double, Double, Double) {
        let phi = observer.latitude * EngineConstants.deg2Rad
        let sinphi = sin(phi)
        let cosphi = cos(phi)
        let c = 1.0 / hypot(cosphi, sinphi * EngineConstants.earthFlattening)
        let s = c * (EngineConstants.earthFlattening * EngineConstants.earthFlattening)
        let htKM = observer.height / 1000.0
        let ach = EngineConstants.earthEquatorialRadiusKM * c + htKM
        let ash = EngineConstants.earthEquatorialRadiusKM * s + htKM
        let stlocl = (15.0 * st + observer.longitude) * EngineConstants.deg2Rad
        let sinst = sin(stlocl)
        let cosst = cos(stlocl)
        return (
            ach * cosphi * cosst / EngineConstants.kmPerAU,
            ach * cosphi * sinst / EngineConstants.kmPerAU,
            ash * sinphi / EngineConstants.kmPerAU
        )
    }

    static func terraPosVel(
        observer: Observer,
        siderealHours st: Double
    ) -> (px: Double, py: Double, pz: Double, vx: Double, vy: Double, vz: Double) {
        let phi = observer.latitude * EngineConstants.deg2Rad
        let sinphi = sin(phi)
        let cosphi = cos(phi)
        let c = 1.0 / hypot(cosphi, sinphi * EngineConstants.earthFlattening)
        let s = c * (EngineConstants.earthFlattening * EngineConstants.earthFlattening)
        let htKM = observer.height / 1000.0
        let ach = EngineConstants.earthEquatorialRadiusKM * c + htKM
        let ash = EngineConstants.earthEquatorialRadiusKM * s + htKM
        let stlocl = (15.0 * st + observer.longitude) * EngineConstants.deg2Rad
        let sinst = sin(stlocl)
        let cosst = cos(stlocl)
        let velScale = earthAngVel * 86400.0 / EngineConstants.kmPerAU
        return (
            ach * cosphi * cosst / EngineConstants.kmPerAU,
            ach * cosphi * sinst / EngineConstants.kmPerAU,
            ash * sinphi / EngineConstants.kmPerAU,
            -velScale * ach * cosphi * sinst,
            velScale * ach * cosphi * cosst,
            0.0
        )
    }

    static func inverseTerra(
        x ox: Double,
        y oy: Double,
        z oz: Double,
        siderealHours st: Double
    ) -> Observer {
        let x = ox * EngineConstants.kmPerAU
        let y = oy * EngineConstants.kmPerAU
        let z = oz * EngineConstants.kmPerAU
        guard x.isFinite, y.isFinite, z.isFinite else {
            return Observer(latitude: .nan, longitude: .nan, height: .nan)
        }

        let p = hypot(x, y)
        let lonDeg: Double
        let latDeg: Double
        let heightKM: Double

        if p < 1.0e-6 {
            lonDeg = 0.0
            latDeg = z > 0.0 ? 90.0 : -90.0
            heightKM = abs(z) - EngineConstants.earthPolarRadiusKM
        } else {
            guard st.isFinite else {
                return Observer(latitude: .nan, longitude: .nan, height: .nan)
            }
            let stlocl = atan2(y, x)
            var lon = EngineConstants.rad2Deg * stlocl - (15.0 * st)
            while lon <= -180.0 {
                lon += 360.0
            }
            while lon > 180.0 {
                lon -= 360.0
            }
            lonDeg = lon

            let f = EngineConstants.earthFlattening * EngineConstants.earthFlattening
            var lat = atan2(z, p)
            var distanceAU = sqrt(ox * ox + oy * oy + oz * oz)
            if distanceAU < 1.0 {
                distanceAU = 1.0
            }

            var c = 0.0
            var s = 0.0
            var denom = 0.0
            var count = 0
            while true {
                if count > 10 {
                    return Observer(latitude: .nan, longitude: .nan, height: .nan)
                }
                c = cos(lat)
                s = sin(lat)
                let factor = (f - 1.0) * EngineConstants.earthEquatorialRadiusKM
                let c2 = c * c
                let s2 = s * s
                let radicand = c2 + f * s2
                denom = sqrt(radicand)
                let w = (factor * s * c) / denom - z * c + p * s
                if abs(w) < distanceAU * 2.0e-8 {
                    break
                }
                let d =
                    factor * ((c2 - s2) / denom - s2 * c2 * (f - 1.0) / (denom * radicand))
                    + z * s + p * c
                lat -= w / d
                count &+= 1
            }

            latDeg = lat * EngineConstants.rad2Deg
            let adjust = EngineConstants.earthEquatorialRadiusKM / denom
            if abs(s) > abs(c) {
                heightKM = z / s - f * adjust
            } else {
                heightKM = p / c - adjust
            }
        }

        return Observer(latitude: latDeg, longitude: lonDeg, height: 1000.0 * heightKM)
    }

    // MARK: - Observer Vectors, State & Gravity

    static func geoPos(
        at time: AstroTime,
        observer: Observer,
        tilt: EngineEarthTilt
    ) -> (Double, Double, Double) {
        let gast = EngineRotation.siderealTime(at: time, tilt: tilt)
        let (p1x, p1y, p1z) = terraPosition(observer: observer, siderealHours: gast)
        let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: true)
        let (p2x, p2y, p2z) = EngineMath.rotate(nut, p1x, p1y, p1z)
        let prec = EngineRotation.precessionMatrix(at: time, into2000: true)
        return EngineMath.rotate(prec, p2x, p2y, p2z)
    }

    static func observerVector(
        at time: AstroTime,
        observer: Observer,
        equator: EquatorDate
    ) -> Vector3D {
        var cachedTime = time
        let tilt = EngineRotation.earthTilt(at: &cachedTime)
        let gast = EngineRotation.siderealTime(at: &cachedTime, tilt: tilt)
        let (px, py, pz) = terraPosition(observer: observer, siderealHours: gast)
        switch equator {
        case .ofDate:
            return Vector3D(x: px, y: py, z: pz, time: cachedTime)
        case .j2000:
            let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: true)
            let (tx, ty, tz) = EngineMath.rotate(nut, px, py, pz)
            let prec = EngineRotation.precessionMatrix(at: cachedTime, into2000: true)
            let (jx, jy, jz) = EngineMath.rotate(prec, tx, ty, tz)
            return Vector3D(x: jx, y: jy, z: jz, time: cachedTime)
        }
    }

    static func observerState(
        at time: AstroTime,
        observer: Observer,
        equator: EquatorDate
    ) -> StateVector {
        var cachedTime = time
        let tilt = EngineRotation.earthTilt(at: &cachedTime)
        let gast = EngineRotation.siderealTime(at: &cachedTime, tilt: tilt)
        let pv = terraPosVel(observer: observer, siderealHours: gast)
        switch equator {
        case .ofDate:
            return StateVector(
                position: Vector3D(x: pv.px, y: pv.py, z: pv.pz, time: cachedTime),
                velocity: Vector3D(x: pv.vx, y: pv.vy, z: pv.vz, time: cachedTime),
                time: cachedTime
            )
        case .j2000:
            let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: true)
            let (ptx, pty, ptz) = EngineMath.rotate(nut, pv.px, pv.py, pv.pz)
            let (vtx, vty, vtz) = EngineMath.rotate(nut, pv.vx, pv.vy, pv.vz)
            let prec = EngineRotation.precessionMatrix(at: cachedTime, into2000: true)
            let (px, py, pz) = EngineMath.rotate(prec, ptx, pty, ptz)
            let (vx, vy, vz) = EngineMath.rotate(prec, vtx, vty, vtz)
            return StateVector(
                position: Vector3D(x: px, y: py, z: pz, time: cachedTime),
                velocity: Vector3D(x: vx, y: vy, z: vz, time: cachedTime),
                time: cachedTime
            )
        }
    }

    static func vectorObserver(vector: Vector3D, equatorDate: EquatorDate) -> Observer {
        let tilt = EngineRotation.earthTilt(at: vector.time)
        let gast = EngineRotation.siderealTime(at: vector.time, tilt: tilt)
        let x: Double
        let y: Double
        let z: Double
        switch equatorDate {
        case .ofDate:
            x = vector.x
            y = vector.y
            z = vector.z
        case .j2000:
            let prec = EngineRotation.precessionMatrix(at: vector.time, into2000: false)
            let (tx, ty, tz) = EngineMath.rotate(prec, vector.x, vector.y, vector.z)
            let nut = EngineRotation.nutationMatrix(tilt: tilt, into2000: false)
            (x, y, z) = EngineMath.rotate(nut, tx, ty, tz)
        }
        return inverseTerra(x: x, y: y, z: z, siderealHours: gast)
    }

    static func observerGravity(latitude: Double, height: Double) -> Double {
        let s = sin(latitude * EngineConstants.deg2Rad)
        let s2 = s * s
        let g0 =
            9.7803253359 * (1.0 + 0.00193185265241 * s2)
            / sqrt(1.0 - 0.00669437999013 * s2)
        return g0
            * (1.0 - (3.15704e-07 - 2.10269e-09 * s2) * height + 7.37452e-14 * height * height)
    }

    // MARK: - Topocentric Equatorial & Horizontal Coordinates

    static func vectorToRaDec(
        _ x: Double,
        _ y: Double,
        _ z: Double,
        time: AstroTime
    ) throws -> Equatorial {
        let xyproj = x * x + y * y
        let dist = sqrt(xyproj + z * z)
        if xyproj == 0.0 {
            if z == 0.0 {
                throw AstronomyError.badVector
            }
            return Equatorial(
                rightAscension: 0.0,
                declination: z < 0.0 ? -90.0 : 90.0,
                distance: dist,
                time: time
            )
        }
        var ra = EngineConstants.rad2Hour * atan2(y, x)
        if ra < 0.0 {
            ra += 24.0
        }
        let dec = EngineConstants.rad2Deg * atan2(z, sqrt(xyproj))
        return Equatorial(rightAscension: ra, declination: dec, distance: dist, time: time)
    }

    static func topocentricOfDate(
        geocentric gc: Vector3D,
        at time: AstroTime,
        observer: Observer
    ) throws -> (equatorial: Equatorial, siderealHours: Double) {
        let tilt = EngineRotation.earthTilt(at: time)
        let gast = EngineRotation.siderealTime(at: time, tilt: tilt)
        let (p1x, p1y, p1z) = terraPosition(observer: observer, siderealHours: gast)
        let nutTo2000 = EngineRotation.nutationMatrix(tilt: tilt, into2000: true)
        let (p2x, p2y, p2z) = EngineMath.rotate(nutTo2000, p1x, p1y, p1z)
        let precTo2000 = EngineRotation.precessionMatrix(at: time, into2000: true)
        let (ox, oy, oz) = EngineMath.rotate(precTo2000, p2x, p2y, p2z)
        let (tx, ty, tz) = EngineMath.rotate(
            EngineRotation.inverse(precTo2000),
            gc.x - ox,
            gc.y - oy,
            gc.z - oz
        )
        let (dx, dy, dz) = EngineMath.rotate(EngineRotation.inverse(nutTo2000), tx, ty, tz)
        let equ = try vectorToRaDec(dx, dy, dz, time: time)
        return (equ, gast)
    }

    static func equatorialFromGeocentric(
        gc: Vector3D,
        at time: AstroTime,
        observer: Observer,
        equatorDate: EquatorDate
    ) throws -> Equatorial {
        switch equatorDate {
        case .ofDate:
            return try topocentricOfDate(geocentric: gc, at: time, observer: observer).equatorial
        case .j2000:
            let tilt = EngineRotation.earthTilt(at: time)
            let (ox, oy, oz) = geoPos(at: time, observer: observer, tilt: tilt)
            return try vectorToRaDec(gc.x - ox, gc.y - oy, gc.z - oz, time: time)
        }
    }

    static func horizon(
        geocentric gc: Vector3D,
        at time: AstroTime,
        observer: Observer,
        refraction mode: Refraction
    ) throws -> Horizon {
        let (equ, gast) = try topocentricOfDate(geocentric: gc, at: time, observer: observer)
        return horizon(
            at: time,
            observer: observer,
            rightAscension: equ.rightAscension,
            declination: equ.declination,
            refraction: mode,
            siderealHours: gast
        )
    }

    static func equator(
        of body: CelestialBody,
        at time: AstroTime,
        observer: Observer,
        equatorDate: EquatorDate,
        aberration: Aberration
    ) throws -> Equatorial {
        let gc = try EnginePositions.geoVector(of: body, at: time, aberration: aberration)
        return try equatorialFromGeocentric(
            gc: gc,
            at: time,
            observer: observer,
            equatorDate: equatorDate
        )
    }

    static func horizon(
        at time: AstroTime,
        observer: Observer,
        rightAscension ra: Double,
        declination dec: Double,
        refraction mode: Refraction,
        siderealHours: Double? = nil
    ) -> Horizon {
        let latrad = observer.latitude * EngineConstants.deg2Rad
        let lonrad = observer.longitude * EngineConstants.deg2Rad
        let decrad = dec * EngineConstants.deg2Rad
        let rarad = ra * EngineConstants.hour2Rad

        let sinlat = sin(latrad)
        let coslat = cos(latrad)
        let sinlon = sin(lonrad)
        let coslon = cos(lonrad)
        let sindc = sin(decrad)
        let cosdc = cos(decrad)
        let sinra = sin(rarad)
        let cosra = cos(rarad)

        let gast = siderealHours ?? EngineRotation.siderealTime(at: time)
        let spinAngle = -15.0 * gast
        let (uz0, uz1, uz2) = EngineRotation.spin(
            angle: spinAngle,
            coslat * coslon,
            coslat * sinlon,
            sinlat
        )
        let (un0, un1, un2) = EngineRotation.spin(
            angle: spinAngle,
            -sinlat * coslon,
            -sinlat * sinlon,
            coslat
        )
        let (uw0, uw1, uw2) = EngineRotation.spin(
            angle: spinAngle,
            sinlon,
            -coslon,
            0.0
        )

        let p0 = cosdc * cosra
        let p1 = cosdc * sinra
        let p2 = sindc

        let pn = p0 * un0 + p1 * un1 + p2 * un2
        let pw = p0 * uw0 + p1 * uw1 + p2 * uw2
        let pz = p0 * uz0 + p1 * uz1 + p2 * uz2

        let proj = hypot(pn, pw)
        var az: Double
        if proj > 0.0 {
            az = -atan2(pw, pn) * EngineConstants.rad2Deg
            if az < 0.0 {
                az += 360.0
            }
        } else {
            az = 0.0
        }

        var zd = atan2(proj, pz) * EngineConstants.rad2Deg
        var outRa = ra
        var outDec = dec

        if mode == .normal || mode == .jplHorizons {
            let zd0 = zd
            let refr = EngineRotation.refraction(mode, altitude: 90.0 - zd)
            zd -= refr

            if refr > 0.0 && zd > 3.0e-4 && zd0 < 180.0 - 3.0e-4 {
                let sinzd = sin(zd * EngineConstants.deg2Rad)
                let coszd = cos(zd * EngineConstants.deg2Rad)
                let sinzd0 = sin(zd0 * EngineConstants.deg2Rad)
                let coszd0 = cos(zd0 * EngineConstants.deg2Rad)

                let pr0 = ((p0 - coszd0 * uz0) / sinzd0) * sinzd + uz0 * coszd
                let pr1 = ((p1 - coszd0 * uz1) / sinzd0) * sinzd + uz1 * coszd
                let pr2 = ((p2 - coszd0 * uz2) / sinzd0) * sinzd + uz2 * coszd

                let rproj = hypot(pr0, pr1)
                if rproj > 0.0 {
                    outRa = EngineConstants.rad2Hour * atan2(pr1, pr0)
                    if outRa < 0.0 {
                        outRa += 24.0
                    }
                } else {
                    outRa = 0.0
                }
                outDec = EngineConstants.rad2Deg * atan2(pr2, rproj)
            }
        }

        return Horizon(
            altitude: 90.0 - zd,
            azimuth: az,
            rightAscension: outRa,
            declination: outDec
        )
    }

    // MARK: - U.S. Standard Atmosphere (1976)

    static func atmosphere(elevationMeters: Double) throws -> Atmosphere {
        guard elevationMeters.isFinite, elevationMeters >= -500.0, elevationMeters <= 100000.0 else {
            throw AstronomyError.invalidParameter
        }
        let p0 = 101325.0
        let t0 = 288.15
        let t1 = 216.65

        let tempK: Double
        let pressPa: Double
        if elevationMeters <= 11000.0 {
            tempK = t0 - 0.0065 * elevationMeters
            pressPa = p0 * pow(t0 / tempK, -5.25577)
        } else if elevationMeters <= 20000.0 {
            tempK = t1
            pressPa = 22632.0 * exp(-0.00015768832 * (elevationMeters - 11000.0))
        } else {
            tempK = t1 + 0.001 * (elevationMeters - 20000.0)
            pressPa = 5474.87 * pow(t1 / tempK, 34.16319)
        }
        let density = (pressPa / tempK) / (p0 / t0)
        return Atmosphere(
            pressure: pressPa / 100.0,
            temperature: tempK - 273.15,
            density: density
        )
    }
}
