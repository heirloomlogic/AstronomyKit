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
    /// DE440 supplies 1900 through 2130 TT; compact DE441 supplies the rest of the accepted range, with 32-day blends. Positions and states share the cached mean-ecliptic coordinates.
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
    /// Both tables are read in TDB and rotated from EQJ into the mean ecliptic of date. The DE440 weight preserves its central span and blends into DE441 outside it.
    static func evaluate(centuries t: Double) -> SIMD3<Double> {
        let tt = t * 36_525
        let weight = Engine.MoonEphemeris.weight(tt: tt).weight
        var position: SIMD3<Double>
        if weight == 1 {
            guard let source = meanEclipticPosition(tt: tt) else { return SIMD3(repeating: .nan) }
            position = source
        } else {
            guard let outer = meanEclipticPosition(tt: tt, compact: true) else { return SIMD3(repeating: .nan) }
            position = outer
            if weight > 0, let central = meanEclipticPosition(tt: tt) {
                position += weight * (central - outer)
            }
        }
        let distance = (position.x * position.x + position.y * position.y + position.z * position.z).squareRoot()
        var longitude = atan2(position.y, position.x)
        if longitude < 0 { longitude += 2 * Double.pi }
        let latitude = atan2(position.z, hypot(position.x, position.y))
        return SIMD3(longitude, latitude, distance)
    }

    /// The selected table at `tt` on the mean ecliptic and equinox of date, in AU, or `nil` outside its records.
    static func meanEclipticPosition(tt: Double, compact: Bool = false) -> SIMD3<Double>? {
        guard let source = compact ? Engine.MoonDE441.position(tt: tt) : Engine.MoonEphemeris.position(tt: tt) else {
            return nil
        }
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
        Engine.tilted(by: Engine.Precession.meanObliquity(tt: tt))
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
        let meanTilt: Engine.Rotation<Engine.EQM, Engine.ECM> = Engine.tilted(by: tilt.meanObliquity)
        let trueTilt: Engine.Rotation<Engine.EQD, Engine.ECT> = Engine.tilted(by: tilt.trueObliquity)
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
