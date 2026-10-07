//
//  EngineObserver.swift
//  AstronomyKit
//
//  Observer positions and states, their inverse, and surface gravity.
//

import Foundation

extension Engine {
    /// Positions of observers on or near the Earth, on the reference
    /// ellipsoid of the IERS Conventions (2010), Table 1.1. Observers come in
    /// as the public `Observer`; the public layer validates them.
    enum Observers {}
}

extension Engine.Observers {
    /// The ellipsoid's equatorial radius, 6,378.1366 km (IERS Conventions
    /// 2010, Table 1.1).
    static let equatorialRadiusKilometers = 6_378.136_6

    /// The ratio of polar to equatorial radius, 1 − f, with flattening
    /// f = 1/298.25642 (IERS Conventions 2010, Table 1.1).
    static let polarRatio = 1 - 1 / 298.256_42

    /// The nominal mean angular velocity of the Earth, 7.292115e-5 rad/s
    /// (IERS Conventions 2010, Table 1.1).
    static let angularVelocity = 7.292_115e-5

    /// `observer`'s position and velocity in Earth-fixed axes turned by
    /// `siderealTime` hours: x toward the meridian at that sidereal time, z
    /// toward the north pole, in AU and AU per day.
    ///
    /// This is SOFA's `iauGd2gce` on this ellipsoid: with
    /// C = 1/√(cos²φ + (1−f)² sin²φ) and S = (1−f)²·C at geodetic latitude
    /// φ, the distance from the axis is (a·C + h)·cos φ and the height above
    /// the equator plane (a·S + h)·sin φ. The velocity is the angular
    /// velocity crossed into the position.
    private static func terrestrial(
        _ observer: Observer,
        siderealTime: Double
    ) -> (position: (Double, Double, Double), velocity: (Double, Double, Double)) {
        let latitude = observer.latitude * Engine.radiansPerDegree
        let (sinLat, cosLat) = (sin(latitude), cos(latitude))
        let c = 1 / hypot(cosLat, sinLat * polarRatio)
        let s = c * (polarRatio * polarRatio)
        let heightKilometers = observer.height / 1000
        let ach = equatorialRadiusKilometers * c + heightKilometers
        let ash = equatorialRadiusKilometers * s + heightKilometers
        let local = (15 * siderealTime + observer.longitude) * Engine.radiansPerDegree
        let (sinLocal, cosLocal) = (sin(local), cos(local))
        let au = Engine.kilometersPerAU
        let speed = angularVelocity * Engine.secondsPerDay / au
        return (
            (ach * cosLat * cosLocal / au, ach * cosLat * sinLocal / au, ash * sinLat / au),
            (-speed * ach * cosLat * sinLocal, speed * ach * cosLat * cosLocal, 0)
        )
    }

    /// `observer`'s geocentric position on the true equator and equinox of
    /// `time` (`Astronomy_ObserverVector` with `EQUATOR_OF_DATE`).
    static func vectorOfDate(_ observer: Observer, at time: Engine.Time) -> Engine.Vector<Engine.EQD> {
        let p = terrestrial(observer, siderealTime: Engine.EarthRotation.apparentSiderealTime(time)).position
        return Engine.Vector(x: p.0, y: p.1, z: p.2, time: time)
    }

    /// `observer`'s geocentric position on the J2000 equator
    /// (`Astronomy_ObserverVector` with `EQUATOR_J2000`).
    static func vector(_ observer: Observer, at time: Engine.Time) -> Engine.Vector<Engine.EQJ> {
        Engine.FrameRotation.eqdToEqj(time).apply(to: vectorOfDate(observer, at: time))
    }

    /// `observer`'s geocentric position and velocity on the true equator of
    /// `time` (`Astronomy_ObserverState` with `EQUATOR_OF_DATE`). The
    /// velocity is the Earth's rotation alone.
    static func stateOfDate(_ observer: Observer, at time: Engine.Time) -> Engine.State<Engine.EQD> {
        let (p, v) = terrestrial(observer, siderealTime: Engine.EarthRotation.apparentSiderealTime(time))
        return Engine.State(x: p.0, y: p.1, z: p.2, vx: v.0, vy: v.1, vz: v.2, time: time)
    }

    /// `observer`'s geocentric position and velocity on the J2000 equator
    /// (`Astronomy_ObserverState` with `EQUATOR_J2000`). Like the C engine,
    /// this rotates the velocity of date and leaves out the motion of the
    /// equator itself, which is below 1e-7 of the rotation speed.
    static func state(_ observer: Observer, at time: Engine.Time) -> Engine.State<Engine.EQJ> {
        Engine.FrameRotation.eqdToEqj(time).apply(to: stateOfDate(observer, at: time))
    }

    /// The observer at geocentric position `vector` on the true equator of
    /// its time (`Astronomy_VectorObserver` with `EQUATOR_OF_DATE`).
    ///
    /// Within 1 mm of the axis, latitude is ±90 and longitude 0. Elsewhere,
    /// longitude is in (−180, 180] and latitude comes from Newton's method on
    /// the ellipsoid, as in the C engine.
    ///
    /// All three fields are NaN when a component is not finite, or is too
    /// large to convert to kilometres, and when Newton's method does not
    /// converge in 11 steps. The C engine ends the process when the method
    /// fails (#174), and on the axis gives ±90 for a NaN or infinite z.
    static func observer(atVectorOfDate vector: Engine.Vector<Engine.EQD>) -> Observer {
        let km = Engine.kilometersPerAU
        let (x, y, z) = (vector.x * km, vector.y * km, vector.z * km)
        guard x.isFinite, y.isFinite, z.isFinite else { return Self.undefined }
        let p = hypot(x, y)
        if p < 1e-6 {
            return Observer(
                latitude: z > 0 ? 90 : -90,
                longitude: 0,
                height: 1000 * (abs(z) - equatorialRadiusKilometers * polarRatio)
            )
        }
        let siderealTime = Engine.EarthRotation.apparentSiderealTime(vector.time)
        var longitude = Engine.degreesPerRadian * atan2(y, x) - 15 * siderealTime
        while longitude <= -180 { longitude += 360 }
        while longitude > 180 { longitude -= 360 }

        let f = polarRatio * polarRatio
        let factor = (f - 1) * equatorialRadiusKilometers
        let distance = max(1, vector.length)
        var latitude = atan2(z, p)
        for _ in 0...10 {
            let (s, c) = (sin(latitude), cos(latitude))
            let radicand = c * c + f * s * s
            let denominator = radicand.squareRoot()
            let w = factor * s * c / denominator - z * c + p * s
            if abs(w) < distance * 2e-8 {
                let adjust = equatorialRadiusKilometers / denominator
                let height = abs(s) > abs(c) ? z / s - f * adjust : p / c - adjust
                return Observer(
                    latitude: latitude * Engine.degreesPerRadian,
                    longitude: longitude,
                    height: 1000 * height
                )
            }
            let d =
                factor * ((c * c - s * s) / denominator - s * s * c * c * (f - 1) / (factor * radicand)) + z * s + p * c
            latitude -= w / d
        }
        return Self.undefined
    }

    /// The observer with every field NaN.
    private static let undefined = Observer(latitude: .nan, longitude: .nan, height: .nan)

    /// The observer at geocentric J2000 position `vector`
    /// (`Astronomy_VectorObserver` with `EQUATOR_J2000`).
    static func observer(atVector vector: Engine.Vector<Engine.EQJ>) -> Observer {
        observer(atVectorOfDate: Engine.FrameRotation.eqjToEqd(vector.time).apply(to: vector))
    }

    /// Normal gravity in m/s² at geodetic `latitude` degrees and `height`
    /// metres (`Astronomy_ObserverGravity`): Somigliana's formula on the
    /// WGS 84 ellipsoid with the second-order height correction of NIMA
    /// TR8350.2, equations 4-1 and 4-3.
    static func gravity(latitude: Double, height: Double) -> Double {
        let s = sin(latitude * Engine.radiansPerDegree)
        let s2 = s * s
        let surface = 9.780_325_335_9 * (1 + 0.001_931_852_652_41 * s2) / (1 - 0.006_694_379_990_13 * s2).squareRoot()
        return surface * (1 - (3.157_04e-7 - 2.102_69e-9 * s2) * height + 7.374_52e-14 * height * height)
    }
}
