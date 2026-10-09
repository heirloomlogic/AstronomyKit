//
//  EnginePlanetaryEvents.swift
//  AstronomyKit
//
//  Native maximum-elongation, peak-magnitude, and planetary-apsis searches.
//

import Foundation

extension Engine.Events {
    enum PlanetaryApsisKind: Sendable {
        case pericenter
        case apocenter
    }

    struct PlanetaryApsis: Sendable {
        let kind: PlanetaryApsisKind
        let time: Engine.Time
        let distanceAU: Double

        var distanceKilometers: Double { distanceAU * Engine.kilometersPerAU }
    }

    /// Finds the next maximum apparent elongation of Mercury or Venus after `start`.
    static func searchMaximumElongation(
        of body: CelestialBody,
        after start: Engine.Time
    ) throws -> Engine.Elongation {
        let limits: (lower: Double, upper: Double)
        switch body {
        case .mercury: limits = (50, 85)
        case .venus: limits = (40, 50)
        default: throw AstronomyError.invalidBody
        }
        try Engine.checkAcceptedTime(start)
        let time = try searchInferiorPlanetExtremum(
            body: body, after: start, lowerLongitude: limits.lower, upperLongitude: limits.upper,
            upperBoundaryStartsNextWindow: false
        ) { time in
            let step = 0.05
            let first = try Engine.Positions.angleFromSun(of: body, at: time.adding(days: -step))
            let second = try Engine.Positions.angleFromSun(of: body, at: time.adding(days: step))
            let slope = (first - second) / (2 * step)
            guard slope.isFinite else { throw AstronomyError.badTime }
            return slope
        }
        return try Engine.Positions.elongation(of: body, at: time)
    }

    /// Finds the next minimum of Venus's visual-magnitude curve after `start`.
    static func searchPeakMagnitude(
        of body: CelestialBody,
        after start: Engine.Time
    ) throws -> Engine.Illumination {
        guard body == .venus else { throw AstronomyError.invalidBody }
        try Engine.checkAcceptedTime(start)
        let time = try searchInferiorPlanetExtremum(
            body: body, after: start, lowerLongitude: 10, upperLongitude: 30,
            upperBoundaryStartsNextWindow: true
        ) { time in
            let step = 0.005
            let first = try Engine.Positions.illumination(of: body, at: time.adding(days: -step)).magnitude
            let second = try Engine.Positions.illumination(of: body, at: time.adding(days: step)).magnitude
            let slope = (second - first) / (2 * step)
            guard slope.isFinite else { throw AstronomyError.badTime }
            return slope
        }
        return try Engine.Positions.illumination(of: body, at: time)
    }

    /// Finds the next center-to-center heliocentric apsis of `body` at or after `start`.
    static func searchPlanetaryApsis(
        of body: CelestialBody,
        after start: Engine.Time
    ) throws -> PlanetaryApsis {
        let period = try orbitalPeriod(of: body)
        try Engine.checkAcceptedTime(start)
        if body == .neptune || body == .pluto {
            return try searchSampledApsis(of: body, after: start, period: period)
        }

        let increment = period / 6
        var first = start
        var firstSlope = try planetaryDistanceSlope(of: body, at: first, direction: 1)
        for _ in 0..<12 {
            let second = first.adding(days: increment)
            let secondSlope = try planetaryDistanceSlope(of: body, at: second, direction: 1)
            if firstSlope * secondSlope <= 0 {
                let kind: PlanetaryApsisKind
                let direction: Double
                if firstSlope < 0 || secondSlope > 0 {
                    kind = .pericenter
                    direction = 1
                } else if firstSlope > 0 || secondSlope < 0 {
                    kind = .apocenter
                    direction = -1
                } else {
                    throw AstronomyError.internalError
                }
                guard
                    let time = try Engine.Search.ascendingRoot(
                        from: first, to: second, toleranceSeconds: 1,
                        { try planetaryDistanceSlope(of: body, at: $0, direction: direction) })
                else { throw AstronomyError.searchFailure }
                let distance = try Engine.Positions.heliocentricDistance(of: body, at: time)
                guard time.tt >= start.tt else { throw AstronomyError.searchFailure }
                return PlanetaryApsis(kind: kind, time: time, distanceAU: distance)
            }
            guard second.tt > first.tt else { throw AstronomyError.noConvergence }
            first = second
            firstSlope = secondSlope
        }
        throw AstronomyError.noConvergence
    }

    /// Advances an apsis sequence, requiring the result to alternate and move forward.
    static func nextPlanetaryApsis(
        of body: CelestialBody,
        after apsis: PlanetaryApsis
    ) throws -> PlanetaryApsis {
        let start = apsis.time.adding(days: try orbitalPeriod(of: body) / 4)
        let next = try searchPlanetaryApsis(of: body, after: start)
        guard next.kind != apsis.kind, next.time.tt > apsis.time.tt else {
            throw AstronomyError.internalError
        }
        return next
    }

    private static func searchInferiorPlanetExtremum(
        body: CelestialBody,
        after originalStart: Engine.Time,
        lowerLongitude: Double,
        upperLongitude: Double,
        upperBoundaryStartsNextWindow: Bool,
        slope: (Engine.Time) throws -> Double
    ) throws -> Engine.Time {
        let synodicPeriod = abs(365.256 / (365.256 / (try orbitalPeriod(of: body)) - 1))
        var start = originalStart
        for _ in 0..<2 {
            let planet = try Engine.Positions.eclipticLongitude(of: body, at: start)
            let earth = try Engine.Positions.eclipticLongitude(of: .earth, at: start)
            let longitude = Engine.longitudeOffset(planet - earth)
            let adjustment: Double
            let firstTarget: Double
            let secondTarget: Double
            if longitude >= -lowerLongitude && longitude < lowerLongitude {
                adjustment = 0
                firstTarget = lowerLongitude
                secondTarget = upperLongitude
            } else if longitude > upperLongitude
                || (upperBoundaryStartsNextWindow && longitude == upperLongitude)
                || longitude < -upperLongitude
            {
                adjustment = 0
                firstTarget = -upperLongitude
                secondTarget = -lowerLongitude
            } else if longitude >= 0 {
                adjustment = -synodicPeriod / 4
                firstTarget = lowerLongitude
                secondTarget = upperLongitude
            } else {
                adjustment = -synodicPeriod / 4
                firstTarget = -upperLongitude
                secondTarget = -lowerLongitude
            }

            let first = try searchRelativeLongitude(
                of: body, targetDegrees: firstTarget, after: start.adding(days: adjustment))
            let second = try searchRelativeLongitude(of: body, targetDegrees: secondTarget, after: first)
            guard try slope(first) < 0, try slope(second) > 0 else {
                throw AstronomyError.internalError
            }
            guard
                let event = try Engine.Search.ascendingRoot(
                    from: first, to: second, toleranceSeconds: 10, slope)
            else { throw AstronomyError.searchFailure }
            _ = try Engine.Positions.eclipticLongitude(of: body, at: event)
            if event.tt >= originalStart.tt { return event }
            start = second.adding(days: 1)
        }
        throw AstronomyError.searchFailure
    }

    private static func planetaryDistanceSlope(
        of body: CelestialBody,
        at time: Engine.Time,
        direction: Double
    ) throws -> Double {
        let step = 0.0005
        let first = try Engine.Positions.heliocentricDistance(of: body, at: time.adding(days: -step))
        let second = try Engine.Positions.heliocentricDistance(of: body, at: time.adding(days: step))
        let slope = direction * (second - first) / (2 * step)
        guard slope.isFinite else { throw AstronomyError.badTime }
        return slope
    }

    private static func searchSampledApsis(
        of body: CelestialBody,
        after start: Engine.Time,
        period: Double
    ) throws -> PlanetaryApsis {
        let first = start.adding(days: -period / 12)
        let last = start.adding(days: 3 * period / 4)
        let interval = (last.ut - first.ut) / 99
        guard interval.isFinite, interval > 0 else { throw AstronomyError.badTime }
        var minimum = (distance: Double.infinity, time: first)
        var maximum = (distance: -Double.infinity, time: first)
        for index in 0..<100 {
            let time = first.adding(days: Double(index) * interval)
            let distance = try Engine.Positions.heliocentricDistance(of: body, at: time)
            if distance < minimum.distance { minimum = (distance, time) }
            if distance > maximum.distance { maximum = (distance, time) }
        }

        let pericenter = try refinePlanetaryExtreme(
            of: body, kind: .pericenter, around: minimum.time, initialSpan: 4 * interval)
        let apocenter = try refinePlanetaryExtreme(
            of: body, kind: .apocenter, around: maximum.time, initialSpan: 4 * interval)
        let candidates = [pericenter, apocenter].filter { $0.time.tt >= start.tt }.sorted { $0.time.tt < $1.time.tt }
        guard let result = candidates.first else { throw AstronomyError.searchFailure }
        _ = try Engine.Positions.heliocentricDistance(of: body, at: result.time)
        return result
    }

    private static func refinePlanetaryExtreme(
        of body: CelestialBody,
        kind: PlanetaryApsisKind,
        around estimate: Engine.Time,
        initialSpan: Double
    ) throws -> PlanetaryApsis {
        var first = estimate.adding(days: -initialSpan / 2)
        var span = initialSpan
        let direction = kind == .apocenter ? 1.0 : -1.0
        for _ in 0..<20 {
            let interval = span / 9
            guard interval.isFinite, interval > 0 else { throw AstronomyError.badTime }
            // The remaining uncertainty is the entire retained span, not one sampling interval.
            if span < 1 / 1_440 {
                let time = first.adding(days: span / 2)
                let distance = try Engine.Positions.heliocentricDistance(of: body, at: time)
                return PlanetaryApsis(kind: kind, time: time, distanceAU: distance)
            }
            var bestIndex = 0
            var bestValue = -Double.infinity
            for index in 0..<10 {
                let time = first.adding(days: Double(index) * interval)
                let value = direction * (try Engine.Positions.heliocentricDistance(of: body, at: time))
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            first = first.adding(days: Double(bestIndex - 1) * interval)
            span = 2 * interval
        }
        throw AstronomyError.noConvergence
    }
}
