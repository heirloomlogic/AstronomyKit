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
    /// The largest |TT| in days that the planet functions accept: 4,000
    /// Julian years either side of J2000, the span over which VSOP87 states
    /// 1″ precision for Mercury to Mars.
    static let acceptedTTDays = 1_461_000.0

    /// The position in AU relative to the Sun's center, on the VSOP87 axes.
    ///
    /// From 1900 through 2100 TT, outside the excluded segments, it comes
    /// from the polynomial fits, without the series or the cache. Elsewhere
    /// it comes from the series coordinates, read through `cache`.
    ///
    /// - Throws: `AstronomyError.badTime` when |TT| is above
    ///   ``acceptedTTDays`` or is not finite, or when a component of the
    ///   result is not finite.
    func heliocentricEclipticPosition(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.Vector<Engine.VSOP87Ecliptic> {
        try Self.checkTime(time)
        let position =
            Engine.PlanetPolynomial.position(self, tt: time.tt)
            ?? Self.rectangular(Engine.VSOP87B.coordinates(self, millennia: Self.millennia(time), cache: cache))
        return try Self.checked(Engine.Vector(x: position.x, y: position.y, z: position.z, time: time))
    }

    /// The position in AU and velocity in AU per TT day relative to the
    /// Sun's center, on the VSOP87 axes.
    ///
    /// The polynomial fits give the velocity as the derivative of their
    /// position. Elsewhere the series give the coordinates and their
    /// derivatives, and the velocity is their chain-rule combination. The
    /// position is the same double for double as
    /// ``heliocentricEclipticPosition(at:cache:)``.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``, including
    ///   for a velocity component that is not finite.
    func heliocentricEclipticState(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Engine.State<Engine.VSOP87Ecliptic> {
        try Self.checkTime(time)
        let position: SIMD3<Double>
        let velocity: SIMD3<Double>
        if let state = Engine.PlanetPolynomial.state(self, tt: time.tt) {
            (position, velocity) = (state.position, state.velocity)
        } else {
            let t = Self.millennia(time)
            let sphere = Engine.VSOP87B.coordinates(self, millennia: t, cache: cache)
            let rates = Engine.VSOP87B.derivatives(self, millennia: t, cache: cache)
            position = Self.rectangular(sphere)
            let (cosLongitude, sinLongitude) = (cos(sphere[0]), sin(sphere[0]))
            let (cosLatitude, sinLatitude) = (cos(sphere[1]), sin(sphere[1]))
            let r = sphere[2]
            let perMillennium = SIMD3(
                rates[2] * cosLatitude * cosLongitude - r * sinLatitude * cosLongitude * rates[1]
                    - r * cosLatitude * sinLongitude * rates[0],
                rates[2] * cosLatitude * sinLongitude - r * sinLatitude * sinLongitude * rates[1]
                    + r * cosLatitude * cosLongitude * rates[0],
                rates[2] * sinLatitude + r * cosLatitude * rates[1]
            )
            velocity = perMillennium * (1 / Engine.VSOP87B.daysPerMillennium)
        }
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
    /// The polynomial fits give the length of their position. Elsewhere it is
    /// the series radius, read through `cache` with the other coordinates, so
    /// a position at the same instant reuses it.
    ///
    /// - Throws: As ``heliocentricEclipticPosition(at:cache:)``.
    func heliocentricDistance(
        at time: Engine.Time, cache: Engine.VSOP87B.Cache = Engine.VSOP87B.cache
    ) throws -> Double {
        try Self.checkTime(time)
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

    private static func checkTime(_ time: Engine.Time) throws {
        guard abs(time.tt) <= acceptedTTDays else { throw AstronomyError.badTime }
    }

    private static func millennia(_ time: Engine.Time) -> Double {
        time.tt / Engine.VSOP87B.daysPerMillennium
    }

    /// Rectangular coordinates from longitude, latitude and radius.
    static func rectangular(_ sphere: SIMD3<Double>) -> SIMD3<Double> {
        let radialProjection = sphere[2] * cos(sphere[1])
        return SIMD3(radialProjection * cos(sphere[0]), radialProjection * sin(sphere[0]), sphere[2] * sin(sphere[1]))
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
