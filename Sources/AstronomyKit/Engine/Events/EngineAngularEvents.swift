//
//  EngineAngularEvents.swift
//  AstronomyKit
//
//  Native solar-longitude, season, and planetary relative-longitude searches.
//

import Foundation

extension Engine {
    /// Native event searches. Public event facades remain on the C engine until the native cutover.
    enum Events {}
}

extension Engine.Events {
    /// The four seasonal longitude crossings in calendar order.
    struct Seasons: Sendable {
        let marchEquinox: Engine.Time
        let juneSolstice: Engine.Time
        let septemberEquinox: Engine.Time
        let decemberSolstice: Engine.Time

        var all: [Engine.Time] {
            [marchEquinox, juneSolstice, septemberEquinox, decemberSolstice]
        }
    }

    /// Searches an inclusive window for the Sun's apparent geocentric longitude on the true ecliptic and equinox of date.
    ///
    /// The target wraps by whole turns. A missing ascending crossing returns `nil`; invalid numeric inputs and position failures throw.
    static func searchSunLongitude(
        _ targetDegrees: Double,
        after start: Engine.Time,
        limitDays: Double
    ) throws -> Engine.Time? {
        guard targetDegrees.isFinite, limitDays.isFinite else { throw AstronomyError.invalidParameter }
        try Engine.checkAcceptedTime(start)
        let end = start.adding(days: limitDays)
        try Engine.checkAcceptedTime(end)
        return try Engine.Search.ascendingRoot(from: start, to: end, toleranceSeconds: 0.01) { time in
            let longitude = try Engine.Positions.sunPosition(at: time).longitude
            let offset = Engine.longitudeOffset(longitude - targetDegrees)
            guard offset.isFinite else { throw AstronomyError.badTime }
            return offset
        }
    }

    /// The March equinox, June solstice, September equinox, and December solstice of `year`.
    ///
    /// Each search starts at modeled UT midnight on the tenth day of its event month and uses the one supplied Delta T model throughout.
    static func seasons(year: Int, deltaTModel: DeltaTModel) throws -> Seasons {
        guard Int32(exactly: year) != nil else { throw AstronomyError.invalidParameter }

        func event(month: Int, target: Double) throws -> Engine.Time {
            let start = Engine.Time(
                ut: Engine.Time.days(year: year, month: month, day: 10, hour: 0, minute: 0, second: 0),
                deltaTModel: deltaTModel)
            guard let result = try searchSunLongitude(target, after: start, limitDays: 20) else {
                throw AstronomyError.searchFailure
            }
            return result
        }

        return try Seasons(
            marchEquinox: event(month: 3, target: 0),
            juneSolstice: event(month: 6, target: 90),
            septemberEquinox: event(month: 9, target: 180),
            decemberSolstice: event(month: 12, target: 270))
    }

    /// Searches forward for the next heliocentric relative-longitude event of a planet other than Earth.
    ///
    /// The signed direction follows the original event definition: outer planets advance in the positive direction and Mercury and Venus in the negative direction. The iteration stops within one second and preserves the input time's Delta T model.
    static func searchRelativeLongitude(
        of body: CelestialBody,
        targetDegrees: Double,
        after start: Engine.Time
    ) throws -> Engine.Time {
        guard targetDegrees.isFinite else { throw AstronomyError.invalidParameter }
        guard body != .earth else { throw AstronomyError.earthNotAllowed }
        let period = try orbitalPeriod(of: body)
        try Engine.checkAcceptedTime(start)

        let direction = isOuterPlanet(body) ? 1.0 : -1.0
        let earthPeriod = 365.256
        var synodicPeriod = abs(earthPeriod / (earthPeriod / period - 1))
        var error = try relativeLongitudeOffset(
            body: body, time: start, direction: direction, targetDegrees: targetDegrees)
        if error > 0 { error -= 360 }

        var time = start
        for _ in 0..<100 {
            let adjustment = (-error / 360) * synodicPeriod
            guard adjustment.isFinite else { throw AstronomyError.badTime }
            let next = time.adding(days: adjustment)
            try Engine.checkAcceptedTime(next)
            if abs(adjustment) * Engine.secondsPerDay < 1 {
                return next
            }
            guard next.ut != time.ut else { throw AstronomyError.noConvergence }

            let previous = error
            time = next
            error = try relativeLongitudeOffset(
                body: body, time: time, direction: direction, targetDegrees: targetDegrees)
            if abs(previous) < 30, previous != error {
                let ratio = previous / (previous - error)
                if ratio > 0.5, ratio < 2 {
                    synodicPeriod *= ratio
                }
            }
        }
        throw AstronomyError.noConvergence
    }

    private static func relativeLongitudeOffset(
        body: CelestialBody,
        time: Engine.Time,
        direction: Double,
        targetDegrees: Double
    ) throws -> Double {
        let planet = try Engine.Positions.eclipticLongitude(of: body, at: time)
        let earth = try Engine.Positions.eclipticLongitude(of: .earth, at: time)
        let offset = Engine.longitudeOffset(direction * (earth - planet) - targetDegrees)
        guard offset.isFinite else { throw AstronomyError.badTime }
        return offset
    }

    private static func orbitalPeriod(of body: CelestialBody) throws -> Double {
        switch body {
        case .mercury: 87.969
        case .venus: 224.701
        case .mars: 686.980
        case .jupiter: 4_332.589
        case .saturn: 10_759.22
        case .uranus: 30_685.4
        case .neptune: 60_189.0
        case .pluto: 90_560.0
        default: throw AstronomyError.invalidBody
        }
    }

    private static func isOuterPlanet(_ body: CelestialBody) -> Bool {
        switch body {
        case .mars, .jupiter, .saturn, .uranus, .neptune, .pluto: true
        default: false
        }
    }
}
