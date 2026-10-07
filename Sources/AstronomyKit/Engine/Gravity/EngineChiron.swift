//
//  EngineChiron.swift
//  AstronomyKit
//
//  2060 Chiron from JPL Horizons states every ten years, carried to the
//  requested time by the gravity simulation.
//

import Foundation

extension Engine {
    /// 2060 Chiron, which no model in the engine covers: the nearest of five
    /// JPL Horizons states, 2000 to 2040, stepped to the requested time with
    /// ``GravitySimulation`` in steps of at most half a day.
    ///
    /// This supplies the heliocentric state. The apparent positions the
    /// public `Chiron` API reports are composed from it in #89.
    enum Chiron {}
}

extension Engine.Chiron {
    /// A Horizons state: heliocentric position in AU and velocity in AU per
    /// day, rotated from ICRF to EQJ, at `tt` days of TT from J2000.
    struct Anchor: Sendable {
        let tt: Double
        let position: SIMD3<Double>
        let velocity: SIMD3<Double>

        /// The anchor for a Horizons row: the Julian date in TDB and the
        /// ICRF position and velocity it lists.
        init(julianDateTDB: Double, position: SIMD3<Double>, velocity: SIMD3<Double>) {
            let tdb = julianDateTDB - 2_451_545
            tt = tdb - Engine.TDB.offsetSeconds(tt: tdb) / Engine.secondsPerDay
            self.position = Engine.FrameBias.icrsToEqj.apply(to: position)
            self.velocity = Engine.FrameBias.icrsToEqj.apply(to: velocity)
        }
    }

    /// Chiron at 00:00 TDB on 1 January 2000, 2010, 2020, 2030 and 2040, as
    /// JPL Horizons gave it when AstronomyKit first recorded these states
    /// (target 2060, center 500@10, ICRF, geometric), and as the public
    /// `Chiron` API still uses them. Horizons' current orbit solution,
    /// recorded in
    /// `Scripts/reference-data/sources/horizons/chiron-anchor-vector.json`,
    /// differs from them by at most 4.1 km.
    static let anchors = [
        Anchor(
            julianDateTDB: 2_451_544.5,
            position: SIMD3(-3.532082802845036, -8.673587566387649, -2.935491685233997),
            velocity: SIMD3(4.970678433106630e-03, -3.627773229067521e-03, -8.262541278709376e-04)),
        Anchor(
            julianDateTDB: 2_455_197.5,
            position: SIMD3(13.19148992863117, -9.058771972133892, -2.018744306999665),
            velocity: SIMD3(3.172737184697467e-03, 2.077241872967885e-03, 8.475052013853388e-04)),
        Anchor(
            julianDateTDB: 2_458_849.5,
            position: SIMD3(18.74979015626275, 0.9060856547258316, 1.445166327129911),
            velocity: SIMD3(-5.188250744254794e-05, 2.988627504002276e-03, 9.318734038577373e-04)),
        Anchor(
            julianDateTDB: 2_462_502.5,
            position: SIMD3(13.13185175469694, 10.45171373019759, 4.086005508618447),
            velocity: SIMD3(-2.967275252793649e-03, 1.899724574528414e-03, 4.099535209360336e-04)),
        Anchor(
            julianDateTDB: 2_466_154.5,
            position: SIMD3(-1.878330124332237, 10.99286850835428, 3.325776674355994),
            velocity: SIMD3(-4.676386182330938e-03, -2.507129241195810e-03, -1.075315590956888e-03)),
    ]

    /// The longest step of the simulation, in TT days: Astronomy Engine's
    /// validation harness steps half a day.
    static let stepDays = 0.5

    /// The earliest supported time: 1900-01-01 00:00 UT.
    static let earliestUT = Engine.Time.days(year: 1_900, month: 1, day: 1, hour: 0, minute: 0, second: 0)

    /// The latest supported time: 2150-01-01 00:00 UTC, as TT.
    static let latestTT =
        Engine.Time.civil(
            utcDays: Engine.Time.days(year: 2_150, month: 1, day: 1, hour: 0, minute: 0, second: 0),
            deltaTModel: .espenakMeeus
        ).time.tt

    /// The Delta T model of `time` if it is from 1900-01-01 00:00 UT through
    /// 2150-01-01 00:00 UTC.
    ///
    /// - Throws: `AstronomyError.badTime` otherwise, including for a time
    ///   that is not valid.
    @discardableResult
    static func checkSupported(_ time: Engine.Time) throws -> DeltaTModel {
        guard let model = time.deltaTModel, time.ut >= earliestUT, time.tt <= latestTT else {
            throw AstronomyError.badTime
        }
        return model
    }

    /// The index of the anchor nearest `tt`; the earlier one at a midpoint.
    static func nearestAnchor(tt: Double) -> Int {
        var best = 0
        for index in anchors.indices.dropFirst() where abs(anchors[index].tt - tt) < abs(anchors[best].tt - tt) {
            best = index
        }
        return best
    }

    /// Chiron's heliocentric state on EQJ axes at `time`, from a reusable simulation
    /// used once.
    ///
    /// - Throws: As ``ReusableSimulation/heliocentricState(at:)``.
    static func heliocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ> {
        try ReusableSimulation().heliocentricState(at: time)
    }
}

extension Engine.Chiron {
    /// A simulation of Chiron reused across nearby times, as a light-time
    /// correction asks for them.
    ///
    /// Each request starts from the nearest anchor, unless the last request
    /// started from the same anchor and the path stepped since that start,
    /// plus this step, stays within twice the distance from the anchor to
    /// this time, or within 365 days if that is more. Then the simulation
    /// steps on from where it is. Otherwise it starts again from the
    /// anchor. It holds mutable state; use one per calculation, on
    /// one thread.
    final class ReusableSimulation {
        private var simulation: Engine.GravitySimulation?
        /// The anchor the current simulation started from.
        private(set) var anchorIndex: Int?
        /// The days stepped since that start, counting the first leg.
        private(set) var pathDays = 0.0

        /// Chiron's heliocentric state on EQJ axes at `time`, with `time` as
        /// its time.
        ///
        /// The simulation steps in equal parts of at most ``stepDays`` TT
        /// days. Each intermediate time is the TT of that part with `time`'s
        /// Delta T model.
        ///
        /// - Throws: `AstronomyError.badTime` outside the supported span
        ///   (see ``checkSupported(_:)``), and the simulation's errors.
        func heliocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ> {
            let model = try Engine.Chiron.checkSupported(time)
            let index = Engine.Chiron.nearestAnchor(tt: time.tt)
            let anchor = Engine.Chiron.anchors[index]
            let freshPath = abs(time.tt - anchor.tt)

            if let simulation, anchorIndex == index {
                let step = abs(time.tt - simulation.time.tt)
                if pathDays + step <= max(2 * freshPath, 365) {
                    let state = try Self.advance(simulation, to: time, model: model)
                    pathDays += step
                    return state
                }
            }

            let start = Engine.Time(tt: anchor.tt, deltaTModel: model)
            let simulation = try Engine.GravitySimulation(
                origin: .sun, time: start,
                states: [Engine.State(position: anchor.position, velocity: anchor.velocity, time: start)])
            let state = try Self.advance(simulation, to: time, model: model)
            self.simulation = simulation
            anchorIndex = index
            pathDays = freshPath
            return state
        }

        /// Steps `simulation` to `time` in equal steps of at most
        /// ``stepDays`` TT days and returns Chiron's state there.
        private static func advance(
            _ simulation: Engine.GravitySimulation, to time: Engine.Time, model: DeltaTModel
        ) throws -> Engine.State<Engine.EQJ> {
            let startTT = simulation.time.tt
            let interval = time.tt - startTT
            let count = max(1, Int((abs(interval) / Engine.Chiron.stepDays).rounded(.up)))
            for step in 1..<count {
                let tt = startTT + interval * Double(step) / Double(count)
                try simulation.update(to: Engine.Time(tt: tt, deltaTModel: model))
            }
            guard let state = try simulation.update(to: time).first else { throw AstronomyError.internalError }
            return state
        }
    }
}
