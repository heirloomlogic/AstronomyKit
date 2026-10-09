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
        let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
        guard let p = pluto.evaluate(tdb: tdb), let s = sun.evaluate(tdb: tdb) else { return nil }
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: p.position - s.position),
            bias.apply(to: (p.velocity - s.velocity) * Engine.TDB.rate(tt: tt))
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
