//
//  EnginePlutoLightTime.swift
//  AstronomyKit
//
//  Pluto states used only by light-time iteration for a validated observation.
//

import Foundation

extension Engine.PlutoDE441 {
    /// The heliocentric system-barycenter state wherever both compiled source tables cover `tt`.
    private static func sourceState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let p = pluto.evaluate(tdb: tdb), let s = sun.evaluate(tdb: tdb) else { return nil }
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: p.position - s.position),
            bias.apply(to: (p.velocity - s.velocity) * conversion.rate)
        )
    }

    /// The source-backed state before the accepted observation range, for Pluto's light-time evaluator only.
    fileprivate static func lightTimeState(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt < -acceptedTTDays else { return nil }
        return sourceState(tt: tt)
    }
}

extension Engine.Pluto {
    /// Pluto's heliocentric state at an internal light-time evaluation for a supported observation.
    ///
    /// The evaluation may precede the accepted observation range, but only inside the joint coverage of the compiled Pluto and Sun source tables. It keeps the observation's Delta T model and cannot follow the observation on either time scale.
    static func heliocentricState(
        forLightTimeAt time: Engine.Time, observedAt observation: Engine.Time
    ) throws -> Engine.State<Engine.EQJ> {
        guard let model = observation.deltaTModel,
            abs(observation.tt) <= Engine.PlutoDE441.acceptedTTDays,
            time.deltaTModel == model,
            time.ut.isFinite,
            time.tt.isFinite,
            time.ut <= observation.ut,
            time.tt <= observation.tt
        else { throw AstronomyError.badTime }

        if time.tt >= -Engine.PlutoDE441.acceptedTTDays {
            return try heliocentricState(at: time)
        }
        guard let source = Engine.PlutoDE441.lightTimeState(tt: time.tt),
            source.position.x.isFinite,
            source.position.y.isFinite,
            source.position.z.isFinite,
            source.velocity.x.isFinite,
            source.velocity.y.isFinite,
            source.velocity.z.isFinite
        else { throw AstronomyError.badTime }
        return Engine.State(position: source.position, velocity: source.velocity, time: time)
    }

    /// The position of ``heliocentricState(forLightTimeAt:observedAt:)``.
    static func heliocentricPosition(
        forLightTimeAt time: Engine.Time, observedAt observation: Engine.Time
    ) throws -> Engine.Vector<Engine.EQJ> {
        try heliocentricState(forLightTimeAt: time, observedAt: observation).position
    }
}

extension Engine.Pluto {
    /// Earth's state for Pluto's corrected-aberration iteration, including one day before the public lower endpoint.
    ///
    /// The exterior evaluation uses the same VSOP87B series and analytic derivative as Earth's public trajectory. It is confined to a validated Pluto observation with matching time scales and Delta T model.
    static func earthState(
        forLightTimeAt time: Engine.Time, observedAt observation: Engine.Time
    ) throws -> Engine.State<Engine.EQJ> {
        guard let model = observation.deltaTModel,
            abs(observation.tt) <= Engine.acceptedTTDays,
            time.deltaTModel == model,
            time.ut.isFinite, time.tt.isFinite,
            time.ut <= observation.ut, time.tt <= observation.tt,
            time.tt >= -Engine.acceptedTTDays - 1
        else { throw AstronomyError.badTime }
        if time.tt >= -Engine.acceptedTTDays {
            return try Engine.Planet.earth.heliocentricState(at: time)
        }
        let t = time.tt / Engine.VSOP87B.daysPerMillennium
        let sphere = Engine.VSOP87B.coordinates(.earth, millennia: t)
        let rates = Engine.VSOP87B.derivatives(.earth, millennia: t)
        let state = Engine.State<Engine.VSOP87Ecliptic>(
            position: Engine.VSOP87B.rectangular(sphere),
            velocity: Engine.VSOP87B.velocity(sphere, rates: rates), time: time)
        guard [state.x, state.y, state.z, state.vx, state.vy, state.vz].allSatisfy(\.isFinite) else {
            throw AstronomyError.badTime
        }
        return Engine.VSOP87B.toEquatorial.apply(to: state)
    }
}
