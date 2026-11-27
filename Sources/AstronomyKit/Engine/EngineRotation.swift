//
//  EngineRotation.swift
//  AstronomyKit
//
//  Pure-Swift rotation matrices, precession, nutation, obliquity,
//  coordinate-frame conversions, and atmospheric refraction.
//

import CLibAstronomy

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct EngineEarthTilt {
    let tt: Double
    let dpsi: Double
    let deps: Double
    let ee: Double
    let mobl: Double
    let tobl: Double
}

enum EngineRotation {
    // MARK: - Obliquity, Nutation, Precession, Sidereal Time

    static func meanObliquity(tt: Double) -> Double {
        let t = tt / 36525.0
        let asec =
            (((((-0.0000000434 * t
                - 0.000000576) * t
                + 0.00200340) * t
                - 0.0001831) * t
                - 46.836769) * t) + 84381.406
        return asec / 3600.0
    }

    static func earthTilt(at time: inout AstroTime) -> EngineEarthTilt {
        if time.raw.psi.isNaN || time.raw.eps.isNaN {
            _Astronomy_Iau2000b(&time.raw)
        }
        let dpsi = time.raw.psi
        let deps = time.raw.eps
        let mobl = meanObliquity(tt: time.raw.tt)
        let tobl = mobl + (deps / 3600.0)
        let ee = dpsi * cos(mobl * EngineConstants.deg2Rad) / 15.0
        return EngineEarthTilt(
            tt: time.raw.tt,
            dpsi: dpsi,
            deps: deps,
            ee: ee,
            mobl: mobl,
            tobl: tobl
        )
    }

    static func earthTilt(at time: AstroTime) -> EngineEarthTilt {
        var copy = time
        return earthTilt(at: &copy)
    }

    private static func era(ut: Double) -> Double {
        let thet1 = 0.7790572732640 + 0.00273781191135448 * ut
        let thet3 = fmod(ut, 1.0)
        var theta = 360.0 * fmod(thet1 + thet3, 1.0)
        if theta < 0.0 {
            theta += 360.0
        }
        return theta
    }

    static func siderealTime(at time: inout AstroTime, tilt: EngineEarthTilt) -> Double {
        if !time.raw.st.isNaN {
            return time.raw.st
        }
        let t = time.raw.tt / 36525.0
        let eqeq = 15.0 * tilt.ee
        let theta = era(ut: time.raw.ut)
        let st =
            eqeq + 0.014506
            + (((((-0.0000000368 * t
                - 0.000029956) * t
                - 0.00000044) * t
                + 1.3915817) * t
                + 4612.156534) * t)
        var gst = fmod(st / 3600.0 + theta, 360.0) / 15.0
        if gst < 0.0 {
            gst += 24.0
        }
        time.raw.st = gst
        return gst
    }

    static func siderealTime(at time: AstroTime, tilt: EngineEarthTilt) -> Double {
        if !time.raw.st.isNaN {
            return time.raw.st
        }
        var copy = time
        return siderealTime(at: &copy, tilt: tilt)
    }

    static func siderealTime(at time: AstroTime) -> Double {
        siderealTime(at: time, tilt: earthTilt(at: time))
    }

    @inline(__always)
    static func oblEcl2Equ(
        obliquityDegrees obl: Double,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> (Double, Double, Double) {
        let oblRad = obl * EngineConstants.deg2Rad
        let cosObl = cos(oblRad)
        let sinObl = sin(oblRad)
        return (
            x,
            y * cosObl - z * sinObl,
            y * sinObl + z * cosObl
        )
    }

    @inline(__always)
    static func ecl2Equ(
        at time: AstroTime,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> (Double, Double, Double) {
        oblEcl2Equ(obliquityDegrees: meanObliquity(tt: time.terrestrialTime), x, y, z)
    }

    static func precessionMatrix(at time: AstroTime, into2000: Bool) -> RotationMatrix {
        let eps0Asec = 84381.406
        let t = time.terrestrialTime / 36525.0

        let psiaAsec =
            (((((-0.0000000951 * t
                + 0.000132851) * t
                - 0.00114045) * t
                - 1.0790069) * t
                + 5038.481507) * t)

        let omegaaAsec =
            ((((0.0000003337 * t
                - 0.000000467) * t
                - 0.00772503) * t
                + 0.0512623) * t
                - 0.025754) * t + eps0Asec

        let chiaAsec =
            (((((-0.0000000560 * t
                + 0.000170663) * t
                - 0.00121197) * t
                - 2.3814292) * t
                + 10.556403) * t)

        let eps0 = eps0Asec * EngineConstants.asec2Rad
        let psia = psiaAsec * EngineConstants.asec2Rad
        let omegaa = omegaaAsec * EngineConstants.asec2Rad
        let chia = chiaAsec * EngineConstants.asec2Rad

        let sa = sin(eps0)
        let ca = cos(eps0)
        let sb = sin(-psia)
        let cb = cos(-psia)
        let sc = sin(-omegaa)
        let cc = cos(-omegaa)
        let sd = sin(chia)
        let cd = cos(chia)

        let xx = cd * cb - sb * sd * cc
        let yx = cd * sb * ca + sd * cc * cb * ca - sa * sd * sc
        let zx = cd * sb * sa + sd * cc * cb * sa + ca * sd * sc
        let xy = -sd * cb - sb * cd * cc
        let yy = -sd * sb * ca + cd * cc * cb * ca - sa * cd * sc
        let zy = -sd * sb * sa + cd * cc * cb * sa + ca * cd * sc
        let xz = sb * sc
        let yz = -sc * cb * ca - sa * cc
        let zz = -sc * cb * sa + cc * ca

        guard into2000 else {
            return RotationMatrix(
                r00: xx, r01: xy, r02: xz,
                r10: yx, r11: yy, r12: yz,
                r20: zx, r21: zy, r22: zz
            )
        }
        return RotationMatrix(
            r00: xx, r01: yx, r02: zx,
            r10: xy, r11: yy, r12: zy,
            r20: xz, r21: yz, r22: zz
        )
    }

    static func nutationMatrix(tilt: EngineEarthTilt, into2000: Bool) -> RotationMatrix {
        let oblm = tilt.mobl * EngineConstants.deg2Rad
        let oblt = tilt.tobl * EngineConstants.deg2Rad
        let psi = tilt.dpsi * EngineConstants.asec2Rad

        let cobm = cos(oblm)
        let sobm = sin(oblm)
        let cobt = cos(oblt)
        let sobt = sin(oblt)
        let cpsi = cos(psi)
        let spsi = sin(psi)

        let xx = cpsi
        let yx = -spsi * cobm
        let zx = -spsi * sobm
        let xy = spsi * cobt
        let yy = cpsi * cobm * cobt + sobm * sobt
        let zy = cpsi * sobm * cobt - cobm * sobt
        let xz = spsi * sobt
        let yz = cpsi * cobm * sobt - sobm * cobt
        let zz = cpsi * sobm * sobt + cobm * cobt

        guard into2000 else {
            return RotationMatrix(
                r00: xx, r01: xy, r02: xz,
                r10: yx, r11: yy, r12: yz,
                r20: zx, r21: zy, r22: zz
            )
        }
        return RotationMatrix(
            r00: xx, r01: yx, r02: zx,
            r10: xy, r11: yy, r12: zy,
            r20: xz, r21: yz, r22: zz
        )
    }

    @inline(__always)
    static func spin(
        angle: Double,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> (Double, Double, Double) {
        let angr = angle * EngineConstants.deg2Rad
        let cosang = cos(angr)
        let sinang = sin(angr)
        return (
            cosang * x + sinang * y,
            -sinang * x + cosang * y,
            z
        )
    }

    // MARK: - Matrix Algebra

    static func inverse(_ r: RotationMatrix) -> RotationMatrix {
        RotationMatrix(
            r00: r.r00, r01: r.r10, r02: r.r20,
            r10: r.r01, r11: r.r11, r12: r.r21,
            r20: r.r02, r21: r.r12, r22: r.r22
        )
    }

    static func combine(_ a: RotationMatrix, _ b: RotationMatrix) -> RotationMatrix {
        RotationMatrix(
            r00: b.r00 * a.r00 + b.r10 * a.r01 + b.r20 * a.r02,
            r01: b.r01 * a.r00 + b.r11 * a.r01 + b.r21 * a.r02,
            r02: b.r02 * a.r00 + b.r12 * a.r01 + b.r22 * a.r02,
            r10: b.r00 * a.r10 + b.r10 * a.r11 + b.r20 * a.r12,
            r11: b.r01 * a.r10 + b.r11 * a.r11 + b.r21 * a.r12,
            r12: b.r02 * a.r10 + b.r12 * a.r11 + b.r22 * a.r12,
            r20: b.r00 * a.r20 + b.r10 * a.r21 + b.r20 * a.r22,
            r21: b.r01 * a.r20 + b.r11 * a.r21 + b.r21 * a.r22,
            r22: b.r02 * a.r20 + b.r12 * a.r21 + b.r22 * a.r22
        )
    }

    static func pivot(_ rotation: RotationMatrix, axis: Int, angle: Double) throws -> RotationMatrix {
        guard (0...2).contains(axis), angle.isFinite else {
            throw AstronomyError.invalidParameter
        }
        let radians = angle * EngineConstants.deg2Rad
        let c = cos(radians)
        let s = sin(radians)

        // Maintain right-hand rule: i x j = k where k = axis, i = (axis + 1) % 3, j = (axis + 2) % 3.
        switch axis {
        case 0:
            // i = 1, j = 2, k = 0
            return RotationMatrix(
                r00: rotation.r00,
                r01: c * rotation.r01 - s * rotation.r02,
                r02: s * rotation.r01 + c * rotation.r02,
                r10: rotation.r10,
                r11: c * rotation.r11 - s * rotation.r12,
                r12: s * rotation.r11 + c * rotation.r12,
                r20: rotation.r20,
                r21: c * rotation.r21 - s * rotation.r22,
                r22: s * rotation.r21 + c * rotation.r22
            )
        case 1:
            // i = 2, j = 0, k = 1
            return RotationMatrix(
                r00: s * rotation.r02 + c * rotation.r00,
                r01: rotation.r01,
                r02: c * rotation.r02 - s * rotation.r00,
                r10: s * rotation.r12 + c * rotation.r10,
                r11: rotation.r11,
                r12: c * rotation.r12 - s * rotation.r10,
                r20: s * rotation.r22 + c * rotation.r20,
                r21: rotation.r21,
                r22: c * rotation.r22 - s * rotation.r20
            )
        default:
            // axis == 2: i = 0, j = 1, k = 2
            return RotationMatrix(
                r00: c * rotation.r00 - s * rotation.r01,
                r01: s * rotation.r00 + c * rotation.r01,
                r02: rotation.r02,
                r10: c * rotation.r10 - s * rotation.r11,
                r11: s * rotation.r10 + c * rotation.r11,
                r12: rotation.r12,
                r20: c * rotation.r20 - s * rotation.r21,
                r21: s * rotation.r20 + c * rotation.r21,
                r22: rotation.r22
            )
        }
    }

    static func rotateVector(_ rotation: RotationMatrix, _ vector: Vector3D) -> Vector3D {
        let (x, y, z) = EngineMath.rotate(rotation, vector.x, vector.y, vector.z)
        return Vector3D(x: x, y: y, z: z, time: vector.time)
    }

    static func rotateState(_ rotation: RotationMatrix, _ state: StateVector) -> StateVector {
        let (x, y, z) = EngineMath.rotate(rotation, state.position.x, state.position.y, state.position.z)
        let (vx, vy, vz) = EngineMath.rotate(rotation, state.velocity.x, state.velocity.y, state.velocity.z)
        return StateVector(
            position: Vector3D(x: x, y: y, z: z, time: state.time),
            velocity: Vector3D(x: vx, y: vy, z: vz, time: state.time),
            time: state.time
        )
    }

    // MARK: - Frame Rotation Builders

    static let eqjToEcl = RotationMatrix(
        r00: 1.0, r01: 0.0, r02: 0.0,
        r10: 0.0, r11: EngineConstants.cosObliq2000, r12: -EngineConstants.sinObliq2000,
        r20: 0.0, r21: EngineConstants.sinObliq2000, r22: EngineConstants.cosObliq2000
    )

    static let eclToEqj = RotationMatrix(
        r00: 1.0, r01: 0.0, r02: 0.0,
        r10: 0.0, r11: EngineConstants.cosObliq2000, r12: EngineConstants.sinObliq2000,
        r20: 0.0, r21: -EngineConstants.sinObliq2000, r22: EngineConstants.cosObliq2000
    )

    static let eqjToGal = RotationMatrix(
        r00: -0.0548624779711344, r01: 0.4941095946388765, r02: -0.8676668813529025,
        r10: -0.8734572784246782, r11: -0.4447938112296831, r12: -0.1980677870294097,
        r20: -0.4838000529948520, r21: 0.7470034631630423, r22: 0.4559861124470794
    )

    static let galToEqj = RotationMatrix(
        r00: -0.0548624779711344, r01: -0.8734572784246782, r02: -0.4838000529948520,
        r10: 0.4941095946388765, r11: -0.4447938112296831, r12: 0.7470034631630423,
        r20: -0.8676668813529025, r21: -0.1980677870294097, r22: 0.4559861124470794
    )

    static func eqjToEqd(at time: AstroTime, tilt: EngineEarthTilt) -> RotationMatrix {
        let prec = precessionMatrix(at: time, into2000: false)
        let nut = nutationMatrix(tilt: tilt, into2000: false)
        return combine(prec, nut)
    }

    static func eqjToEqd(at time: AstroTime) -> RotationMatrix {
        eqjToEqd(at: time, tilt: earthTilt(at: time))
    }

    static func eqdToEqj(at time: AstroTime, tilt: EngineEarthTilt) -> RotationMatrix {
        let nut = nutationMatrix(tilt: tilt, into2000: true)
        let prec = precessionMatrix(at: time, into2000: true)
        return combine(nut, prec)
    }

    static func eqdToEqj(at time: AstroTime) -> RotationMatrix {
        eqdToEqj(at: time, tilt: earthTilt(at: time))
    }

    static func ectToEqd(tilt: EngineEarthTilt) -> RotationMatrix {
        let tobl = tilt.tobl * EngineConstants.deg2Rad
        let cosTobl = cos(tobl)
        let sinTobl = sin(tobl)
        return RotationMatrix(
            r00: 1.0, r01: 0.0, r02: 0.0,
            r10: 0.0, r11: cosTobl, r12: sinTobl,
            r20: 0.0, r21: -sinTobl, r22: cosTobl
        )
    }

    static func ectToEqd(at time: AstroTime) -> RotationMatrix {
        ectToEqd(tilt: earthTilt(at: time))
    }

    static func eqdToEct(tilt: EngineEarthTilt) -> RotationMatrix {
        let tobl = tilt.tobl * EngineConstants.deg2Rad
        let cosTobl = cos(tobl)
        let sinTobl = sin(tobl)
        return RotationMatrix(
            r00: 1.0, r01: 0.0, r02: 0.0,
            r10: 0.0, r11: cosTobl, r12: -sinTobl,
            r20: 0.0, r21: sinTobl, r22: cosTobl
        )
    }

    static func eqdToEct(at time: AstroTime) -> RotationMatrix {
        eqdToEct(tilt: earthTilt(at: time))
    }

    static func eqjToEct(at time: AstroTime) -> RotationMatrix {
        let tilt = earthTilt(at: time)
        return combine(eqjToEqd(at: time, tilt: tilt), eqdToEct(tilt: tilt))
    }

    static func ectToEqj(at time: AstroTime) -> RotationMatrix {
        let tilt = earthTilt(at: time)
        return combine(ectToEqd(tilt: tilt), eqdToEqj(at: time, tilt: tilt))
    }

    static func eqdToHor(at time: AstroTime, observer: Observer, tilt: EngineEarthTilt) -> RotationMatrix {
        let sinlat = sin(observer.latitude * EngineConstants.deg2Rad)
        let coslat = cos(observer.latitude * EngineConstants.deg2Rad)
        let sinlon = sin(observer.longitude * EngineConstants.deg2Rad)
        let coslon = cos(observer.longitude * EngineConstants.deg2Rad)

        let spinAngle = -15.0 * siderealTime(at: time, tilt: tilt)
        let (uz0, uz1, uz2) = spin(angle: spinAngle, coslat * coslon, coslat * sinlon, sinlat)
        let (un0, un1, un2) = spin(angle: spinAngle, -sinlat * coslon, -sinlat * sinlon, coslat)
        let (uw0, uw1, uw2) = spin(angle: spinAngle, sinlon, -coslon, 0.0)

        return RotationMatrix(
            r00: un0, r01: uw0, r02: uz0,
            r10: un1, r11: uw1, r12: uz1,
            r20: un2, r21: uw2, r22: uz2
        )
    }

    static func eqdToHor(at time: AstroTime, observer: Observer) -> RotationMatrix {
        eqdToHor(at: time, observer: observer, tilt: earthTilt(at: time))
    }

    static func horToEqd(at time: AstroTime, observer: Observer, tilt: EngineEarthTilt) -> RotationMatrix {
        inverse(eqdToHor(at: time, observer: observer, tilt: tilt))
    }

    static func horToEqd(at time: AstroTime, observer: Observer) -> RotationMatrix {
        inverse(eqdToHor(at: time, observer: observer))
    }

    static func horToEqj(at time: AstroTime, observer: Observer) -> RotationMatrix {
        let tilt = earthTilt(at: time)
        return combine(horToEqd(at: time, observer: observer, tilt: tilt), eqdToEqj(at: time, tilt: tilt))
    }

    static func eqjToHor(at time: AstroTime, observer: Observer) -> RotationMatrix {
        inverse(horToEqj(at: time, observer: observer))
    }

    static func eqdToEcl(at time: AstroTime, tilt: EngineEarthTilt) -> RotationMatrix {
        combine(eqdToEqj(at: time, tilt: tilt), eqjToEcl)
    }

    static func eqdToEcl(at time: AstroTime) -> RotationMatrix {
        eqdToEcl(at: time, tilt: earthTilt(at: time))
    }

    static func eclToEqd(at time: AstroTime, tilt: EngineEarthTilt) -> RotationMatrix {
        inverse(eqdToEcl(at: time, tilt: tilt))
    }

    static func eclToEqd(at time: AstroTime) -> RotationMatrix {
        inverse(eqdToEcl(at: time))
    }

    static func eclToHor(at time: AstroTime, observer: Observer) -> RotationMatrix {
        let tilt = earthTilt(at: time)
        return combine(eclToEqd(at: time, tilt: tilt), eqdToHor(at: time, observer: observer, tilt: tilt))
    }

    static func horToEcl(at time: AstroTime, observer: Observer) -> RotationMatrix {
        inverse(eclToHor(at: time, observer: observer))
    }

    // MARK: - Refraction & Coordinate Conversions

    static func refraction(_ mode: Refraction, altitude: Double) -> Double {
        if altitude < -90.0 || altitude > 90.0 {
            return 0.0
        }
        switch mode {
        case .normal, .jplHorizons:
            var hd = altitude
            if hd < -1.0 {
                hd = -1.0
            }
            var refr = (1.02 / tan((hd + 10.3 / (hd + 5.11)) * EngineConstants.deg2Rad)) / 60.0
            if mode == .normal && altitude < -1.0 {
                refr *= (altitude + 90.0) / 89.0
            }
            return refr
        case .none:
            return 0.0
        }
    }

    static func inverseRefraction(_ mode: Refraction, bentAltitude: Double) -> Double {
        if bentAltitude < -90.0 || bentAltitude > 90.0 || !bentAltitude.isFinite {
            return 0.0
        }
        var altitude = bentAltitude - refraction(mode, altitude: bentAltitude)
        var iter = 0
        while iter < 100 {
            let diff = (altitude + refraction(mode, altitude: altitude)) - bentAltitude
            if abs(diff) < 1.0e-14 {
                return altitude - bentAltitude
            }
            altitude -= diff
            iter &+= 1
        }
        return altitude - bentAltitude
    }

    @inline(__always)
    private static func toggleAzimuthDirection(_ azimuth: Double) -> Double {
        var az = 360.0 - azimuth
        if az >= 360.0 {
            az -= 360.0
        } else if az < 0.0 {
            az += 360.0
        }
        return az
    }

    static func vectorFromSphere(_ sphere: Spherical, at time: AstroTime) -> Vector3D {
        let radlat = sphere.latitude * EngineConstants.deg2Rad
        let radlon = sphere.longitude * EngineConstants.deg2Rad
        let rcoslat = sphere.distance * cos(radlat)
        return Vector3D(
            x: rcoslat * cos(radlon),
            y: rcoslat * sin(radlon),
            z: sphere.distance * sin(radlat),
            time: time
        )
    }

    static func sphereFromVector(_ vector: Vector3D) -> Spherical {
        let xyproj = vector.x * vector.x + vector.y * vector.y
        let dist = sqrt(xyproj + vector.z * vector.z)
        if xyproj == 0.0 {
            if vector.z == 0.0 {
                return Spherical(latitude: .nan, longitude: .nan, distance: .nan)
            }
            return Spherical(latitude: vector.z < 0.0 ? -90.0 : 90.0, longitude: 0.0, distance: dist)
        }
        var lon = EngineConstants.rad2Deg * atan2(vector.y, vector.x)
        if lon < 0.0 {
            lon += 360.0
        }
        let lat = EngineConstants.rad2Deg * atan2(vector.z, sqrt(xyproj))
        return Spherical(latitude: lat, longitude: lon, distance: dist)
    }

    static func equatorFromVector(_ vector: Vector3D) -> Equatorial {
        let sphere = sphereFromVector(vector)
        return Equatorial(
            rightAscension: sphere.longitude / 15.0,
            declination: sphere.latitude,
            distance: sphere.distance,
            time: vector.time
        )
    }

    static func horizonFromVector(_ vector: Vector3D, refraction mode: Refraction) -> Spherical {
        let xyproj = vector.x * vector.x + vector.y * vector.y
        if xyproj == 0.0 && vector.z == 0.0 {
            return Spherical(latitude: .nan, longitude: .nan, distance: .nan)
        }
        let sphere = sphereFromVector(vector)
        let lon = toggleAzimuthDirection(sphere.longitude)
        let lat = sphere.latitude + refraction(mode, altitude: sphere.latitude)
        return Spherical(latitude: lat, longitude: lon, distance: sphere.distance)
    }

    static func vectorFromHorizon(
        _ sphere: Spherical,
        at time: AstroTime,
        refraction mode: Refraction
    ) -> Vector3D {
        let adjusted = Spherical(
            latitude: sphere.latitude + inverseRefraction(mode, bentAltitude: sphere.latitude),
            longitude: toggleAzimuthDirection(sphere.longitude),
            distance: sphere.distance
        )
        return vectorFromSphere(adjusted, at: time)
    }

    static func rotateEquatorialToEcliptic(
        _ x: Double,
        _ y: Double,
        _ z: Double,
        obliquityRadians: Double
    ) -> (vx: Double, vy: Double, vz: Double, elon: Double, elat: Double) {
        let cosOb = cos(obliquityRadians)
        let sinOb = sin(obliquityRadians)
        let vx = x
        let vy = y * cosOb + z * sinOb
        let vz = -y * sinOb + z * cosOb
        let xyproj = hypot(vx, vy)
        var elon: Double
        if xyproj > 0.0 {
            elon = EngineConstants.rad2Deg * atan2(vy, vx)
            if elon < 0.0 {
                elon += 360.0
            }
        } else {
            elon = 0.0
        }
        let elat = EngineConstants.rad2Deg * atan2(vz, xyproj)
        return (vx, vy, vz, elon, elat)
    }
}
