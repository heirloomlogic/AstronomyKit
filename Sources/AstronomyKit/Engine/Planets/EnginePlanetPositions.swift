//
//  EnginePlanetPositions.swift
//  AstronomyKit
//
//  Heliocentric positions, states and distances of the planets, from the
//  polynomial fits where they apply and the full VSOP87B series elsewhere.
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
    /// Saturn uses DE441 plus the SAT441 physical-center offset from 1900 through 2130 TT, with 32-day exterior blends. Other planets, and Saturn outside those blends, retain the polynomial fits and VSOP87B series.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``Engine/acceptedTTDays`` or is not finite, or when a component of the
    ///   result is not finite.
    func heliocentricEclipticPosition(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.Vector<Engine.VSOP87Ecliptic> {
        try Engine.checkAcceptedTime(time)
        if self == .saturn, Engine.SaturnEphemeris.weight(tt: time.tt).weight > 0 {
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
    /// The velocity differentiates the selected trajectory, including Saturn's TT/TDB conversion and blend weight. The position is the same double for double as ``heliocentricEclipticPosition(at:cache:)``.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``, including
    ///   for a velocity component that is not finite.
    func heliocentricEclipticState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.VSOP87Ecliptic> {
        try Engine.checkAcceptedTime(time)
        let (weight, rate) = Engine.SaturnEphemeris.weight(tt: time.tt)
        if self == .saturn, weight > 0 {
            guard var (position, velocity) = Engine.SaturnEphemeris.eclipticState(at: time) else {
                throw AstronomyError.badTime
            }
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

    /// The retained polynomial/VSOP trajectory, used outside Saturn's source window and for model diagnostics.
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
    /// Saturn's corrected path and the polynomial fits give the length of their position. The retained series path returns its radius directly, with its existing cache behavior.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``.
    func heliocentricDistance(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Double {
        try Engine.checkAcceptedTime(time)
        if self == .saturn, Engine.SaturnEphemeris.weight(tt: time.tt).weight > 0 {
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
