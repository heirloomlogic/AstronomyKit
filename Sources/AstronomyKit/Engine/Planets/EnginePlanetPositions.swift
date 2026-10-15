//
//  EnginePlanetPositions.swift
//  AstronomyKit
//
//  Heliocentric positions, states and distances of the planets, from the
//  DE-backed tables in the selected window and the retained model elsewhere.
//

import Foundation

extension Engine {
    /// The dynamical ecliptic and equinox of J2000, the frame of VSOP87.
    ///
    /// It is not ``ECL``. Its rotation to EQJ, ``VSOP87B/toEquatorial``, is a
    /// tilt by an obliquity 0.003″ larger than the IAU 2006 value that ECL
    /// uses, combined with small rotations of up to 0.1″.
    enum VSOP87Ecliptic: Frame {}
}

extension Engine.VSOP87B {
    /// The rotation from the VSOP87 frame to the FK5 equator and equinox of
    /// J2000, as Bretagnon and Francou give it in the VSOP87 documentation
    /// (IMCCE, `vsop87.doc`). The engine takes FK5 J2000 as EQJ, as the C
    /// engine does.
    static let toEquatorial = Engine.Rotation<Engine.VSOP87Ecliptic, Engine.EQJ>(
        rot: (
            (1, -0.000_000_479_966, 0),
            (0.000_000_440_360, 0.917_482_137_087, 0.397_776_982_902),
            (-0.000_000_190_919, -0.397_776_982_902, 0.917_482_137_087)
        )
    )
}

extension Engine.Planet {
    /// The position in AU relative to the Sun's center, on the VSOP87 axes.
    ///
    /// Every planet uses its selected DE-backed physical-center trajectory from 1900 through 2130 TT, with 32-day exterior blends. The polynomial fits and VSOP87B series remain outside those blends.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``Engine/acceptedTTDays`` or is not finite, or when a component of the
    ///   result is not finite.
    func heliocentricEclipticPosition(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.Vector<Engine.VSOP87Ecliptic> {
        try Engine.checkAcceptedTime(time)
        if Engine.PlanetDE441.weight(tt: time.tt).weight > 0 {
            return try heliocentricEclipticState(at: time, cache: cache).position
        }
        let position =
            Engine.PlanetPolynomial.position(self, tt: time.tt)
            ?? Engine.VSOP87B.rectangular(
                Engine.VSOP87B.coordinates(self, millennia: Self.millennia(time), cache: cache))
        return try Self.checked(Engine.Vector(x: position.x, y: position.y, z: position.z, time: time))
    }

    /// The position in AU and velocity in AU per TT day relative to the
    /// Sun's center, on the VSOP87 axes.
    ///
    /// The velocity differentiates the selected trajectory, including TT/TDB conversion and blend weight. The position is the same double for double as ``heliocentricEclipticPosition(at:cache:)``.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``, including
    ///   for a velocity component that is not finite.
    func heliocentricEclipticState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.VSOP87Ecliptic> {
        try eclipticState(
            evaluation: Engine.PlanetDE441.Evaluation(at: time), cache: cache, physicalCenter: true)
    }

    /// System-mass trajectory for gravity and GM-weighted origins. Earth and the giant planets exclude their physical-center offsets inside the selected window.
    func systemHeliocentricState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.EQJ> {
        try systemHeliocentricState(evaluation: Engine.PlanetDE441.Evaluation(at: time), cache: cache)
    }

    func systemHeliocentricState(
        evaluation: Engine.PlanetDE441.Evaluation, cache: Engine.VSOP87B.Cache
    ) throws -> Engine.State<Engine.EQJ> {
        Engine.VSOP87B.toEquatorial.apply(
            to: try eclipticState(evaluation: evaluation, cache: cache, physicalCenter: false))
    }

    func heliocentricState(
        evaluation: Engine.PlanetDE441.Evaluation, cache: Engine.VSOP87B.Cache
    ) throws -> Engine.State<Engine.EQJ> {
        Engine.VSOP87B.toEquatorial.apply(
            to: try eclipticState(evaluation: evaluation, cache: cache, physicalCenter: true))
    }

    private func eclipticState(
        evaluation: Engine.PlanetDE441.Evaluation, cache: Engine.VSOP87B.Cache, physicalCenter: Bool
    ) throws -> Engine.State<Engine.VSOP87Ecliptic> {
        let time = evaluation.time
        let (weight, rate) = Engine.PlanetDE441.weight(tt: time.tt)
        if weight > 0 {
            guard let source = evaluation.state(of: self, physicalCenter: physicalCenter) else {
                throw AstronomyError.badTime
            }
            let state = Engine.State<Engine.EQJ>(
                x: source.position.x, y: source.position.y, z: source.position.z,
                vx: source.velocity.x, vy: source.velocity.y, vz: source.velocity.z, time: time)
            let ecliptic = Engine.VSOP87B.toEquatorial.inverse.apply(to: state)
            var position = SIMD3(ecliptic.x, ecliptic.y, ecliptic.z)
            var velocity = SIMD3(ecliptic.vx, ecliptic.vy, ecliptic.vz)
            if weight < 1 {
                let legacy = try retainedEclipticState(at: time, cache: cache)
                let lp = SIMD3(legacy.x, legacy.y, legacy.z)
                let lv = SIMD3(legacy.vx, legacy.vy, legacy.vz)
                velocity = lv + weight * (velocity - lv) + rate * (position - lp)
                position = lp + weight * (position - lp)
            }
            return try Self.checked(
                Engine.State(
                    x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z,
                    time: time))
        }
        return try retainedEclipticState(at: time, cache: cache)
    }

    /// The retained polynomial/VSOP trajectory, used outside the selected source window and for model diagnostics.
    func retainedEclipticState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.VSOP87Ecliptic> {
        try Engine.checkAcceptedTime(time)
        let (position, velocity) =
            Engine.PlanetPolynomial.state(self, tt: time.tt)
            ?? seriesState(millennia: Self.millennia(time), cache: cache)
        return try Self.checked(
            Engine.State(
                x: position.x, y: position.y, z: position.z,
                vx: velocity.x, vy: velocity.y, vz: velocity.z, time: time))
    }

    /// ``heliocentricEclipticPosition(at:cache:)`` rotated to EQJ.
    func heliocentricPosition(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.Vector<Engine.EQJ> {
        Engine.VSOP87B.toEquatorial.apply(to: try heliocentricEclipticPosition(at: time, cache: cache))
    }

    /// ``heliocentricEclipticState(at:cache:)`` rotated to EQJ.
    func heliocentricState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.EQJ> {
        Engine.VSOP87B.toEquatorial.apply(to: try heliocentricEclipticState(at: time, cache: cache))
    }

    /// The distance in AU between the planet's center and the Sun's.
    ///
    /// The selected source path and polynomial fits give the length of their position. The retained series path returns its radius directly, with its existing cache behavior.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``.
    func heliocentricDistance(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Double {
        try Engine.checkAcceptedTime(time)
        if Engine.PlanetDE441.weight(tt: time.tt).weight > 0 {
            return try heliocentricEclipticPosition(at: time, cache: cache).length
        }
        let distance: Double
        if let position = Engine.PlanetPolynomial.position(self, tt: time.tt) {
            distance = (position.x * position.x + position.y * position.y + position.z * position.z).squareRoot()
        } else {
            distance = Engine.VSOP87B.coordinates(self, millennia: Self.millennia(time), cache: cache)[2]
        }
        guard distance.isFinite else { throw AstronomyError.badTime }
        return distance
    }

    // MARK: - Helpers

    private static func millennia(_ time: Engine.Time) -> Double {
        time.tt / Engine.VSOP87B.daysPerMillennium
    }

    private func seriesState(
        millennia t: Double, cache: Engine.VSOP87B.Cache
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let sphere = Engine.VSOP87B.coordinates(self, millennia: t, cache: cache)
        let rates = Engine.VSOP87B.derivatives(self, millennia: t, cache: cache)
        return (Engine.VSOP87B.rectangular(sphere), Engine.VSOP87B.velocity(sphere, rates: rates))
    }

    private static func checked<F>(_ vector: Engine.Vector<F>) throws -> Engine.Vector<F> {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else { throw AstronomyError.badTime }
        return vector
    }

    private static func checked<F>(_ state: Engine.State<F>) throws -> Engine.State<F> {
        guard state.x.isFinite, state.y.isFinite, state.z.isFinite,
            state.vx.isFinite, state.vy.isFinite, state.vz.isFinite
        else { throw AstronomyError.badTime }
        return state
    }
}
