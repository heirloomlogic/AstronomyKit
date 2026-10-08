//
//  EngineMoonStates.swift
//  AstronomyKit
//
//  The Moon's position and velocity, and the Earth-Moon barycenter.
//

import Foundation

extension Engine.Moon {
    /// The half-width in TT days of the central difference that gives the
    /// series' velocity, about 43 seconds, as in the C engine.
    static let stateStepDays = 5.0e-4

    /// The Earth/Moon mass ratio the barycenter uses, the C engine's
    /// `EARTH_MOON_MASS_RATIO`.
    static let earthMoonMassRatio = 81.30056

    /// The model's position and velocity on the mean ecliptic and equinox of
    /// date at `time`, and its distance and the distance's rate.
    ///
    /// The position is ``coordinates(centuries:cache:)`` at `time` in
    /// rectangular form. Where DE440 has weight, the velocity is its
    /// analytic derivative carried through precession and the mean
    /// obliquity at TT = (`time.tt` / 36,525) · 36,525. In a blend it is
    /// mixed with a central difference of the series over
    /// ±``stateStepDays``, plus the weight's rate times the difference of
    /// the two positions; those series samples bypass the cache, as in the C
    /// engine. Elsewhere the velocity and the distance's rate are central
    /// differences of the model over ±``stateStepDays``, read through
    /// `cache`, so a repeated state reads three cached epochs.
    static func meanEclipticState(
        at time: Engine.Time, cache: Cache = cache
    ) -> (state: Engine.State<Engine.ECM>, distance: Double, distanceRate: Double) {
        let center = coordinates(centuries: time.tt / 36_525, cache: cache)
        let position = rectangular(center)
        let velocity: SIMD3<Double>
        let distanceRate: Double
        let sourceTT = time.tt / 36_525 * 36_525
        let (weight, weightRate) = Engine.MoonEphemeris.weight(tt: sourceTT)
        if weight > 0, let source = meanEclipticSourceState(tt: sourceTT) {
            let series = { (tt: Double) in rectangular(Engine.LunarSeries.coordinates(centuries: tt / 36_525)) }
            if weight < 1 {
                let difference =
                    (series(sourceTT + stateStepDays) - series(sourceTT - stateStepDays)) / (2 * stateStepDays)
                velocity =
                    difference + weight * (source.velocity - difference) + weightRate
                    * (source.position - series(sourceTT))
            } else {
                velocity = source.velocity
            }
            distanceRate =
                (position.x * velocity.x + position.y * velocity.y + position.z * velocity.z) / center.z
        } else {
            let plus = coordinates(centuries: (time.tt + stateStepDays) / 36_525, cache: cache)
            let minus = coordinates(centuries: (time.tt - stateStepDays) / 36_525, cache: cache)
            velocity = (rectangular(plus) - rectangular(minus)) / (2 * stateStepDays)
            distanceRate = (plus.z - minus.z) / (2 * stateStepDays)
        }
        let state = Engine.State<Engine.ECM>(
            x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z, time: time)
        return (state, center.z, distanceRate)
    }

    /// The DE440 Moon's position and velocity at `tt` on the mean ecliptic
    /// and equinox of date, with the rates of precession and of the mean
    /// obliquity, or `nil` outside its records.
    static func meanEclipticSourceState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard let source = Engine.MoonEphemeris.state(tt: tt) else { return nil }
        let precession = Engine.Precession.rotation(tt: tt)
        let equator = precession.apply(to: source.position)
        let equatorVelocity =
            precession.apply(to: source.velocity) + Engine.Precession.rate(tt: tt).apply(to: source.position)
        let (tilt, tiltRate) = meanTilt(tt: tt)
        return (tilt.apply(to: equator), tilt.apply(to: equatorVelocity) + tiltRate.apply(to: equator))
    }

    /// The Moon's position in AU and velocity in AU per TT day relative to
    /// Earth's center, on EQJ axes, with no light-time correction
    /// (`Astronomy_GeoMoonState`).
    ///
    /// ``meanEclipticState(at:cache:)`` carried through the mean obliquity
    /// and precession and their rates. The position is the same double for
    /// double as ``geocentricPosition(at:cache:)``.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``Engine/acceptedTTDays`` or is not finite, or when a component of
    ///   the result is not finite.
    static func geocentricState(
        at time: Engine.Time, cache: Cache = cache
    ) throws -> Engine.State<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        let ecliptic = meanEclipticState(at: time, cache: cache).state
        let (tilt, tiltRate) = meanTilt(tt: time.tt)
        let equator = tilt.inverse.apply(to: ecliptic, rate: tiltRate.inverse)
        let state = Engine.Precession.rotation(tt: time.tt).inverse.apply(
            to: equator, rate: Engine.Precession.rate(tt: time.tt).inverse)
        return try checked(state)
    }

    /// The Earth-Moon barycenter relative to Earth's center, on EQJ axes:
    /// ``geocentricState(at:cache:)`` divided by one plus
    /// ``earthMoonMassRatio`` (`Astronomy_GeoEmbState`).
    ///
    /// - Throws: As ``geocentricState(at:cache:)``.
    static func barycenterState(
        at time: Engine.Time, cache: Cache = cache
    ) throws -> Engine.State<Engine.EQJ> {
        let moon = try geocentricState(at: time, cache: cache)
        let d = 1 + earthMoonMassRatio
        return Engine.State(
            x: moon.x / d, y: moon.y / d, z: moon.z / d, vx: moon.vx / d, vy: moon.vy / d, vz: moon.vz / d,
            time: moon.time)
    }

    /// The Moon's position and velocity on the true ecliptic and equinox of
    /// date, with its longitude, latitude and distance and their rates
    /// (`Astronomy_MoonEclipticState`).
    ///
    /// ``meanEclipticState(at:cache:)`` carried through the mean obliquity,
    /// nutation and the true obliquity and their rates. The longitude,
    /// latitude and distance are the same doubles as
    /// ``eclipticPosition(at:cache:)``'s, and the distance and its rate are
    /// the model's.
    ///
    /// - Throws: As ``geocentricState(at:cache:)``, and
    ///   `AstronomyError.badVector` when the position has no component in the
    ///   ecliptic plane.
    static func eclipticState(
        at time: Engine.Time, cache: Cache = cache
    ) throws -> Engine.EclipticState {
        try Engine.checkAcceptedTime(time)
        let (ecliptic, distance, distanceRate) = meanEclipticState(at: time, cache: cache)
        let tilt = Engine.EarthTilt(tt: time.tt)
        let (meanTilt, meanTiltRate) = tiltAndRate(
            by: tilt.meanObliquity, rate: tilt.meanObliquityRate, from: Engine.EQM.self, to: Engine.ECM.self)
        let equator = meanTilt.inverse.apply(to: ecliptic, rate: meanTiltRate.inverse)
        let trueEquator = tilt.nutationRotation.apply(to: equator, rate: tilt.nutationRate)
        let (trueTilt, trueTiltRate) = tiltAndRate(
            by: tilt.trueObliquity, rate: tilt.trueObliquityRate, from: Engine.EQD.self, to: Engine.ECT.self)
        let state = try checked(trueTilt.apply(to: trueEquator, rate: trueTiltRate))
        let angles = eclipticAngles(state.position)
        return try Engine.EclipticState(
            state: state, longitude: angles.longitude, latitude: angles.latitude, distance: distance,
            distanceRate: distanceRate)
    }

    /// The mean obliquity's rotation from the mean equator to the mean
    /// ecliptic of date at `tt`, and its rate.
    private static func meanTilt(
        tt: Double
    ) -> (Engine.Rotation<Engine.EQM, Engine.ECM>, Engine.RotationRate<Engine.EQM, Engine.ECM>) {
        tiltAndRate(
            by: Engine.Precession.meanObliquity(tt: tt), rate: Engine.Precession.meanObliquityRate(tt: tt),
            from: Engine.EQM.self, to: Engine.ECM.self)
    }

    private static func tiltAndRate<From, To>(
        by obliquity: Double, rate: Double, from: From.Type, to: To.Type
    ) -> (Engine.Rotation<From, To>, Engine.RotationRate<From, To>) {
        (Engine.tilted(by: obliquity), Engine.tiltRate(by: obliquity, rate: rate))
    }

    private static func checked<F>(_ state: Engine.State<F>) throws -> Engine.State<F> {
        try checkFinite(state.x, state.y, state.z, state.vx, state.vy, state.vz)
        return state
    }

    private static func checkFinite(_ values: Double...) throws {
        guard values.allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
    }
}
