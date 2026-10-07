//
//  EngineMoon.swift
//  AstronomyKit
//
//  The geocentric Moon: the lunar model and the Moon's positions.
//

import Foundation

extension Engine {
    /// The Moon relative to Earth's center.
    ///
    /// The lunar model is the DE440 Moon (``MoonEphemeris``) from 1900
    /// through 2130 TT and the lunar series (``LunarSeries``) beyond, blended
    /// over the 32 days between them. Every position and state starts from
    /// the model's longitude, latitude and distance on the mean ecliptic and
    /// equinox of date, ``coordinates(centuries:cache:)``, read through
    /// ``cache``.
    enum Moon {}

    /// The mean ecliptic and equinox of the vector's time.
    enum ECM: Frame {}
}

extension Engine.Moon {
    /// The lunar model's results shared by every engine caller: 32 entries
    /// keyed by the exact Julian centuries the model reads.
    static let cache = Cache(capacity: 32, registry: .shared)

    /// A cache of the model's longitude, latitude and distance.
    typealias Cache = Engine.BoundedCache<Engine.ExactKey, SIMD3<Double>>

    /// ``evaluate(centuries:)`` read through `cache`, keyed by the exact bits
    /// of `t`, so `0.0` and `-0.0` are different keys. A `t` that is not
    /// finite has no key: the model runs and nothing is stored.
    static func coordinates(
        centuries t: Double, cache: Cache = cache
    ) -> SIMD3<Double> {
        guard let key = Engine.ExactKey(t) else { return evaluate(centuries: t) }
        return cache.value(for: key) { evaluate(centuries: t) }
    }

    /// The Moon's longitude and latitude in radians, on the mean ecliptic
    /// and equinox of date, and its distance in AU, at `t` Julian centuries
    /// of TT from J2000, without the cache. The longitude is from 0 to 2π.
    ///
    /// The DE440 Moon is read at TT = `t` · 36,525, rotated from EQJ by
    /// precession and the mean obliquity at that TT, and blended with the
    /// series position by ``Engine/MoonEphemeris/weight(tt:)``. A TT outside
    /// the blend, or not finite, gives the series alone.
    static func evaluate(centuries t: Double) -> SIMD3<Double> {
        let tt = t * 36_525
        let weight = Engine.MoonEphemeris.weight(tt: tt).weight
        guard weight > 0, var position = meanEclipticPosition(tt: tt) else {
            return Engine.LunarSeries.coordinates(centuries: t)
        }
        if weight < 1 {
            let legacy = rectangular(Engine.LunarSeries.coordinates(centuries: t))
            position = legacy + weight * (position - legacy)
        }
        let distance = (position.x * position.x + position.y * position.y + position.z * position.z).squareRoot()
        var longitude = atan2(position.y, position.x)
        if longitude < 0 { longitude += 2 * Double.pi }
        let latitude = atan2(position.z, hypot(position.x, position.y))
        return SIMD3(longitude, latitude, distance)
    }

    /// The DE440 Moon at `tt` on the mean ecliptic and equinox of date, in
    /// AU, or `nil` outside its records.
    static func meanEclipticPosition(tt: Double) -> SIMD3<Double>? {
        guard let source = Engine.MoonEphemeris.position(tt: tt) else { return nil }
        return meanEquatorToEcliptic(tt: tt).apply(to: Engine.Precession.rotation(tt: tt).apply(to: source))
    }

    /// Rectangular coordinates from longitude and latitude in radians and
    /// a distance.
    static func rectangular(_ sphere: SIMD3<Double>) -> SIMD3<Double> {
        let distanceCosLatitude = sphere.z * cos(sphere.y)
        return SIMD3(distanceCosLatitude * cos(sphere.x), distanceCosLatitude * sin(sphere.x), sphere.z * sin(sphere.y))
    }

    /// R1(εA): from the mean equator to the mean ecliptic of date, with the
    /// IAU 2006 mean obliquity at `tt`.
    static func meanEquatorToEcliptic(tt: Double) -> Engine.Rotation<Engine.EQM, Engine.ECM> {
        tilted(by: Engine.Precession.meanObliquity(tt: tt))
    }

    /// R1(ε): from an equator to an ecliptic `obliquity` degrees from it,
    /// built as ``Engine/FrameRotation`` builds its ecliptic rotations.
    static func tilted<From, To>(by obliquity: Double) -> Engine.Rotation<From, To> {
        let radians = obliquity * Engine.radiansPerDegree
        let c = cos(radians)
        let s = sin(radians)
        return Engine.Rotation(rot: ((1, 0, 0), (0, c, -s), (0, s, c)))
    }

    /// The derivative per TT day of ``tilted(by:)`` when the obliquity
    /// changes by `rate` degrees per TT day.
    static func tiltRate<From, To>(by obliquity: Double, rate: Double) -> Engine.RotationRate<From, To> {
        let radians = obliquity * Engine.radiansPerDegree
        let radiansRate = rate * Engine.radiansPerDegree
        let c = cos(radians) * radiansRate
        let s = sin(radians) * radiansRate
        return Engine.RotationRate(rot: ((0, 0, 0), (0, -s, -c), (0, c, -s)))
    }

    /// The Moon's position in AU relative to Earth's center, on EQJ axes,
    /// with no light-time correction (`Astronomy_GeoMoon`).
    ///
    /// The model's mean ecliptic coordinates at `time` are rotated to the
    /// mean equator of date by the mean obliquity, then to J2000 by
    /// precession.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``Engine/acceptedTTDays`` or is not finite, or when a component of
    ///   the result is not finite.
    static func geocentricPosition(
        at time: Engine.Time, cache: Cache = cache
    ) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        let ecliptic = vector(coordinates(centuries: time.tt / 36_525, cache: cache), time: time)
        let equator = meanEquatorToEcliptic(tt: time.tt).inverse.apply(to: ecliptic)
        let vector = Engine.Precession.rotation(tt: time.tt).inverse.apply(to: equator)
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else { throw AstronomyError.badTime }
        return vector
    }

    /// The Moon's latitude and longitude in degrees on the true ecliptic and
    /// equinox of date, and its distance in AU (`Astronomy_EclipticGeoMoon`).
    ///
    /// The model's mean ecliptic vector is rotated to the mean equator of
    /// date, then by nutation to the true equator, then by the true obliquity
    /// to the true ecliptic. The distance is the model's. The longitude is in
    /// [0, 360), and 0 where the vector has no component in the ecliptic
    /// plane.
    ///
    /// - Throws: As ``geocentricPosition(at:cache:)``.
    static func eclipticPosition(
        at time: Engine.Time, cache: Cache = cache
    ) throws -> Engine.Spherical {
        try Engine.checkAcceptedTime(time)
        let coordinates = coordinates(centuries: time.tt / 36_525, cache: cache)
        let ecliptic = vector(coordinates, time: time)
        let tilt = Engine.EarthTilt(tt: time.tt)
        let meanTilt: Engine.Rotation<Engine.EQM, Engine.ECM> = tilted(by: tilt.meanObliquity)
        let trueTilt: Engine.Rotation<Engine.EQD, Engine.ECT> = tilted(by: tilt.trueObliquity)
        let trueEquator = tilt.nutationRotation.apply(to: meanTilt.inverse.apply(to: ecliptic))
        let trueEcliptic = trueTilt.apply(to: trueEquator)
        let angles = eclipticAngles(trueEcliptic)
        let sphere = Engine.Spherical(latitude: angles.latitude, longitude: angles.longitude, distance: coordinates.z)
        guard sphere.latitude.isFinite, sphere.longitude.isFinite, sphere.distance.isFinite else {
            throw AstronomyError.badTime
        }
        return sphere
    }

    // MARK: - Helpers

    /// Longitude in [0, 360), 0 where `vector` has no component in the
    /// plane, and latitude, in degrees.
    static func eclipticAngles(_ vector: Engine.Vector<Engine.ECT>) -> (longitude: Double, latitude: Double) {
        let projected = hypot(vector.x, vector.y)
        let longitude =
            projected > 0 ? Engine.normalized(Engine.degreesPerRadian * atan2(vector.y, vector.x), period: 360) : 0
        return (longitude, Engine.degreesPerRadian * atan2(vector.z, projected))
    }

    private static func vector(_ coordinates: SIMD3<Double>, time: Engine.Time) -> Engine.Vector<Engine.ECM> {
        let position = rectangular(coordinates)
        return Engine.Vector(x: position.x, y: position.y, z: position.z, time: time)
    }
}

extension Engine.Rotation {
    /// `vector`'s components rotated into frame `To`, with the arithmetic of
    /// ``apply(to:)-(Engine.Vector<From>)`` for values that carry no time.
    func apply(to vector: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            rot.0.0 * vector.x + rot.1.0 * vector.y + rot.2.0 * vector.z,
            rot.0.1 * vector.x + rot.1.1 * vector.y + rot.2.1 * vector.z,
            rot.0.2 * vector.x + rot.1.2 * vector.y + rot.2.2 * vector.z)
    }
}

extension Engine.RotationRate {
    /// The rate applied to `vector`'s components, with the arithmetic of a
    /// rotation's ``Engine/Rotation/apply(to:)-(SIMD3<Double>)``.
    func apply(to vector: SIMD3<Double>) -> SIMD3<Double> {
        Engine.Rotation<From, To>(rot: rot).apply(to: vector)
    }

    /// The rate of the inverse rotation: the transpose, since the inverse
    /// is the transpose.
    var inverse: Engine.RotationRate<To, From> {
        Engine.RotationRate<To, From>(rot: Engine.Rotation<From, To>(rot: rot).inverse.rot)
    }
}
