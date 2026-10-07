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
    /// over the 32 days between them. Every position starts from the model's
    /// longitude, latitude and distance on the mean ecliptic and equinox of
    /// date, ``coordinates(centuries:)``.
    enum Moon {}

    /// The mean ecliptic and equinox of the vector's time.
    enum ECM: Frame {}
}

extension Engine.Moon {
    /// The Moon's longitude and latitude in radians, on the mean ecliptic
    /// and equinox of date, and its distance in AU, at `t` Julian centuries
    /// of TT from J2000. The longitude is from 0 to 2π.
    ///
    /// The DE440 Moon is read at TT = `t` · 36,525, rotated from EQJ by
    /// precession and the mean obliquity at that TT, and blended with the
    /// series position by ``Engine/MoonEphemeris/weight(tt:)``. A TT outside
    /// the blend, or not finite, gives the series alone.
    static func coordinates(centuries t: Double) -> SIMD3<Double> {
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
        guard let source = Engine.MoonEphemeris.state(tt: tt) else { return nil }
        // The rotations do not read a vector's time.
        let equator = Engine.Precession.rotation(tt: tt).apply(
            to: Engine.Vector<Engine.EQJ>(
                x: source.position.x, y: source.position.y, z: source.position.z, time: .invalid))
        let ecliptic = meanEquatorToEcliptic(tt: tt).apply(to: equator)
        return SIMD3(ecliptic.x, ecliptic.y, ecliptic.z)
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
        let radians = Engine.Precession.meanObliquity(tt: tt) * Engine.radiansPerDegree
        let c = cos(radians)
        let s = sin(radians)
        return Engine.Rotation(rot: ((1, 0, 0), (0, c, -s), (0, s, c)))
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
    static func geocentricPosition(at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
        try checkTime(time)
        let ecliptic = meanEclipticVector(at: time)
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
    /// - Throws: As ``geocentricPosition(at:)``.
    static func eclipticPosition(at time: Engine.Time) throws -> Engine.Spherical {
        try checkTime(time)
        let coordinates = coordinates(centuries: time.tt / 36_525)
        let ecliptic = vector(coordinates, time: time)
        let tilt = Engine.EarthTilt(tt: time.tt)
        let equator = meanEquatorToEcliptic(tt: time.tt).inverse.apply(to: ecliptic)
        let trueEquator = tilt.nutationRotation.apply(to: equator)
        let trueEcliptic = Engine.FrameRotation.eqdToEct(time).apply(to: trueEquator)
        let projected = hypot(trueEcliptic.x, trueEcliptic.y)
        let longitude =
            projected > 0
            ? Engine.normalized(Engine.degreesPerRadian * atan2(trueEcliptic.y, trueEcliptic.x), period: 360) : 0
        let sphere = Engine.Spherical(
            latitude: Engine.degreesPerRadian * atan2(trueEcliptic.z, projected), longitude: longitude,
            distance: coordinates.z)
        guard sphere.latitude.isFinite, sphere.longitude.isFinite, sphere.distance.isFinite else {
            throw AstronomyError.badTime
        }
        return sphere
    }

    // MARK: - Helpers

    private static func checkTime(_ time: Engine.Time) throws {
        guard abs(time.tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
    }

    /// The model's position at `time` as a mean ecliptic vector.
    private static func meanEclipticVector(at time: Engine.Time) -> Engine.Vector<Engine.ECM> {
        vector(coordinates(centuries: time.tt / 36_525), time: time)
    }

    private static func vector(_ coordinates: SIMD3<Double>, time: Engine.Time) -> Engine.Vector<Engine.ECM> {
        let position = rectangular(coordinates)
        return Engine.Vector(x: position.x, y: position.y, z: position.z, time: time)
    }
}
