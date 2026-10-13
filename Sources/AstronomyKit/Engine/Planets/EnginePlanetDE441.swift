import Foundation

extension Engine {
    /// DE-backed source components for selected-window planet trajectories.
    enum PlanetDE441 {}
}

extension Engine.PlanetDE441 {
    /// The selected 1900–2131 window and its 32-day exterior blends.
    static func weight(tt: Double) -> (weight: Double, rate: Double) { Engine.MoonEphemeris.weight(tt: tt) }

    /// The second TT derivative of the selected-window blend weight.
    static func weightAcceleration(tt: Double) -> Double {
        let start = Engine.MoonEphemeris.fullWeightStart
        let end = Engine.MoonEphemeris.fullWeightEnd
        let days = Engine.MoonEphemeris.blendDays
        guard tt.isFinite, tt > start - days, tt < end + days, tt < start || tt > end else { return 0 }
        let x = tt < start ? (tt - (start - days)) / days : (end + days - tt) / days
        return 60 * x * (1 - x) * (1 - 2 * x) / (days * days)
    }

    /// The shared DE441 Sun table used by every selected-window planet trajectory.
    static let sun = direct(Engine.SaturnEphemeris.sun)

    private static func direct(_ table: Engine.SaturnEphemeris.Table) -> Engine.DirectChebyshevTable {
        Engine.DirectChebyshevTable(
            start: table.start, days: table.days, recordCount: table.recordCount,
            coefficientCount: table.coefficientCount, scalarBytes: table.scalarBytes, data: table.data)
    }

    /// Generated tables owned by the planet generator, plus Saturn's separately qualified tables.
    static var components: [String: Engine.DirectChebyshevTable] {
        [
            "mercuryBarycenter": mercuryBarycenter,
            "venusBarycenter": venusBarycenter,
            "earthBarycenter": earthBarycenter,
            "earthOffset": earthOffset,
            "marsBarycenter": marsBarycenter,
            "jupiterBarycenter": jupiterBarycenter,
            "jupiterOffset": jupiterOffset,
            "uranusBarycenter": uranusBarycenter,
            "uranusOffset": uranusOffset,
            "neptuneBarycenter": neptuneBarycenter,
            "neptuneOffset": neptuneOffset,
            "sun": sun,
        ]
    }

    /// A single epoch's immutable clock conversion, shared by a gravity evaluation's planet requests.
    struct Evaluation: Sendable {
        let time: Engine.Time
        private let clock: (tdb: Double, rate: Double)?

        init(at time: Engine.Time) throws {
            try Engine.checkAcceptedTime(time)
            self.time = time
            if weight(tt: time.tt).weight > 0 {
                let conversion = Engine.TDB.offsetAndRate(tt: time.tt)
                clock = (time.tt + conversion.offsetSeconds / Engine.secondsPerDay, conversion.rate)
            } else {
                clock = nil
            }
        }

        func state(
            of planet: Engine.Planet, physicalCenter: Bool
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
            guard let clock else { return nil }
            return Engine.PlanetDE441.state(
                of: planet, tdb: clock.tdb, rate: clock.rate, physicalCenter: physicalCenter)
        }
    }

    /// Composes a selected-window source state. Position is in AU on EQJ axes and velocity is its derivative per TT day.
    static func state(
        of planet: Engine.Planet, tt: Double, physicalCenter: Bool
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        return state(of: planet, tdb: tdb, rate: conversion.rate, physicalCenter: physicalCenter)
    }

    private static func state(
        of planet: Engine.Planet, tdb: Double, rate: Double, physicalCenter: Bool
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        if planet == .saturn {
            guard
                let barycenter = Engine.SaturnEphemeris.barycenter.evaluate(tdb: tdb),
                let solar = Engine.SaturnEphemeris.sun.evaluate(tdb: tdb)
            else { return nil }
            var position = barycenter.position - solar.position
            var velocity = barycenter.velocity - solar.velocity
            if physicalCenter {
                guard let offset = Engine.SaturnEphemeris.offset.evaluate(tdb: tdb) else { return nil }
                position += offset.position
                velocity += offset.velocity
            }
            let bias = Engine.FrameBias.icrsToEqj
            return (
                bias.apply(to: position / Engine.kilometersPerAU),
                bias.apply(to: velocity * rate / Engine.kilometersPerAU)
            )
        }
        guard let tables = tables(of: planet), let barycenter = tables.barycenter.evaluate(tdb: tdb),
            let solar = sun.evaluate(tdb: tdb)
        else { return nil }
        var position = barycenter.position - solar.position
        var velocity = barycenter.velocity - solar.velocity
        if physicalCenter, let offsetTable = tables.offset {
            guard let offset = offsetTable.evaluate(tdb: tdb) else { return nil }
            position += offset.position
            velocity += offset.velocity
        }
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: position / Engine.kilometersPerAU),
            bias.apply(to: velocity * rate / Engine.kilometersPerAU)
        )
    }

    /// The selected Earth trajectory's second derivative in AU per TT day squared on EQJ axes.
    static func earthAcceleration(tt: Double, tdbAcceleration: Double) -> SIMD3<Double>? {
        guard tt.isFinite, tdbAcceleration.isFinite else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let barycenter = earthBarycenter.evaluate(tdb: tdb),
            let barycenterAcceleration = earthBarycenter.acceleration(tdb: tdb),
            let solar = sun.evaluate(tdb: tdb), let solarAcceleration = sun.acceleration(tdb: tdb),
            let offset = earthOffset.evaluate(tdb: tdb), let offsetAcceleration = earthOffset.acceleration(tdb: tdb)
        else { return nil }
        let velocity = barycenter.velocity - solar.velocity + offset.velocity
        let acceleration = barycenterAcceleration - solarAcceleration + offsetAcceleration
        return Engine.FrameBias.icrsToEqj.apply(
            to: (acceleration * (conversion.rate * conversion.rate) + velocity * tdbAcceleration)
                / Engine.kilometersPerAU)
    }

    private static func tables(
        of planet: Engine.Planet
    ) -> (barycenter: Engine.DirectChebyshevTable, offset: Engine.DirectChebyshevTable?)? {
        switch planet {
        case .mercury: (mercuryBarycenter, nil)
        case .venus: (venusBarycenter, nil)
        case .earth: (earthBarycenter, earthOffset)
        case .mars: (marsBarycenter, nil)
        case .jupiter: (jupiterBarycenter, jupiterOffset)
        case .saturn: nil
        case .uranus: (uranusBarycenter, uranusOffset)
        case .neptune: (neptuneBarycenter, neptuneOffset)
        }
    }
}
