//
//  EngineChiron.swift
//  AstronomyKit
//
//  2060 Chiron from a Chebyshev table fitted to JPL Horizons.
//

import Foundation

extension Engine {
    /// 2060 Chiron, which no model in the engine covers: the generated
    /// ``table``, fitted to JPL Horizons' heliocentric states by
    /// `Scripts/generate-chiron-table.py`.
    ///
    /// This supplies the heliocentric state. The apparent positions the
    /// public `Chiron` API reports are composed from it in
    /// `Engine.Positions`.
    enum Chiron {}
}

extension Engine.Chiron {
    /// The earliest supported time: 1900-01-01 00:00 UT.
    static let earliestUT = Engine.Time.days(year: 1_900, month: 1, day: 1, hour: 0, minute: 0, second: 0)

    /// The latest supported time: 2150-01-01 00:00 UTC, as TT.
    static let latestTT =
        Engine.Time.civil(
            utcDays: Engine.Time.days(year: 2_150, month: 1, day: 1, hour: 0, minute: 0, second: 0),
            deltaTModel: .espenakMeeus
        ).time.tt

    /// The Delta T model of `time` if its TT is from 1900-01-01 00:00 UT,
    /// as TT with that model, through 2150-01-01 00:00 UTC.
    ///
    /// The state depends on TT alone, so `time`'s UT is not checked. For a
    /// pair rebuilt with ``Engine/Time/fromPair(ut:tt:deltaTModel:)`` it
    /// need not agree with the TT.
    ///
    /// - Throws: `AstronomyError.badTime` otherwise, including for a time
    ///   that is not valid.
    @discardableResult
    static func checkSupported(_ time: Engine.Time) throws -> DeltaTModel {
        guard let model = time.deltaTModel,
            time.tt >= Engine.Time(ut: earliestUT, deltaTModel: model).tt,
            time.tt <= latestTT
        else { throw AstronomyError.badTime }
        return model
    }

    /// Chiron's heliocentric state on EQJ axes at `time`, with `time` as its
    /// time.
    ///
    /// - Throws: `AstronomyError.badTime` outside the supported span (see
    ///   ``checkSupported(_:)``).
    static func heliocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ> {
        try checkSupported(time)
        return try tableState(at: time)
    }

    /// Chiron at an internal light-time evaluation for a supported
    /// observation. The evaluation may precede the public span's start, but
    /// it must use the observation's model and be no later than it.
    ///
    /// - Throws: `AstronomyError.badTime` for an unsupported observation, an
    ///   evaluation that breaks those conditions, or one outside the table.
    static func heliocentricState(
        forLightTimeAt time: Engine.Time, observedAt observation: Engine.Time
    ) throws -> Engine.State<Engine.EQJ> {
        let model = try checkSupported(observation)
        guard time.deltaTModel == model,
            time.ut.isFinite,
            time.tt.isFinite,
            time.ut <= observation.ut,
            time.tt <= observation.tt
        else { throw AstronomyError.badTime }
        return try tableState(at: time)
    }

    /// The table at `time`'s TDB, in AU on EQJ axes, with the velocity per
    /// TT day.
    private static func tableState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ> {
        let conversion = Engine.TDB.offsetAndRate(tt: time.tt)
        guard let state = table.evaluate(tdb: time.tt + conversion.offsetSeconds / Engine.secondsPerDay)
        else { throw AstronomyError.badTime }
        let bias = Engine.FrameBias.icrsToEqj
        return Engine.State(
            position: bias.apply(to: state.position / Engine.kilometersPerAU),
            velocity: bias.apply(to: state.velocity * (conversion.rate / Engine.kilometersPerAU)),
            time: time)
    }
}
