//
//  EngineLunarEvents.swift
//  AstronomyKit
//
//  Native lunar phase, quarter, node, and apsis searches.
//

import Foundation

extension Engine.Events {
    enum LunarPhase: Int, CaseIterable, Sendable {
        case new
        case firstQuarter
        case full
        case lastQuarter

        var targetDegrees: Double { Double(rawValue) * 90 }
    }

    struct LunarQuarter: Sendable {
        let phase: LunarPhase
        let time: Engine.Time
    }

    enum LunarNodeKind: Sendable {
        case ascending
        case descending
    }

    struct LunarNode: Sendable {
        let kind: LunarNodeKind
        let time: Engine.Time
    }

    enum LunarApsisKind: Sendable {
        case pericenter
        case apocenter
    }

    struct LunarApsis: Sendable {
        let kind: LunarApsisKind
        let time: Engine.Time
        let distanceAU: Double

        var distanceKilometers: Double { distanceAU * Engine.kilometersPerAU }
    }

    /// The Moon's apparent true-ecliptic longitude east of the apparent geocentric Sun, in degrees from 0 up to 360.
    static func moonPhaseAngle(at time: Engine.Time) throws -> Double {
        let moon = Engine.Ecliptic(
            try Engine.LightTravel.correct(at: time) {
                try Engine.Moon.geocentricPosition(at: $0)
            }
        ).longitude
        let sun = try Engine.Positions.sunPosition(at: time).longitude
        let angle = Engine.normalizedLongitude(moon - sun)
        guard angle.isFinite else { throw AstronomyError.badTime }
        return angle
    }

    /// Searches an inclusive forward or backward window for an ascending lunar phase-angle crossing.
    static func searchMoonPhase(
        _ targetDegrees: Double,
        after start: Engine.Time,
        limitDays: Double
    ) throws -> Engine.Time? {
        guard targetDegrees.isFinite, limitDays.isFinite else { throw AstronomyError.invalidParameter }
        try Engine.checkAcceptedTime(start)

        let searchStart: Engine.Time
        let searchLimit: Double
        if start.tt < earliestApparentTT {
            guard limitDays >= 0, let model = start.deltaTModel else { return nil }
            let requestedEnd = start.adding(days: limitDays)
            guard requestedEnd.tt >= earliestApparentTT else { return nil }
            searchStart = Engine.Time(tt: earliestApparentTT, deltaTModel: model)
            searchLimit = requestedEnd.tt - searchStart.tt
        } else {
            searchStart = start
            searchLimit = limitDays
        }

        var offset = try moonPhaseOffset(targetDegrees, at: searchStart)
        if offset == 0 { return searchStart }
        let estimate: Double
        if searchLimit < 0 {
            if offset < 0 { offset += 360 }
            estimate = -meanSynodicMonth * offset / 360
        } else {
            if offset > 0 { offset -= 360 }
            estimate = -meanSynodicMonth * offset / 360
        }

        var lower = estimate - phaseUncertaintyDays
        var upper = estimate + phaseUncertaintyDays
        if searchLimit < 0 {
            if upper < searchLimit { return nil }
            lower = max(lower, searchLimit)
            upper = min(upper, 0)
        } else {
            if lower > searchLimit { return nil }
            lower = max(lower, 0)
            upper = min(upper, searchLimit)
        }

        let first = searchStart.adding(days: lower)
        let last = searchStart.adding(days: upper)
        try Engine.checkAcceptedTime(first)
        try Engine.checkAcceptedTime(last)
        guard
            let result = try Engine.Search.ascendingRoot(
                from: first, to: last, toleranceSeconds: 0.1,
                {
                    try moonPhaseOffset(targetDegrees, at: $0)
                })
        else { return nil }
        _ = try moonPhaseOffset(targetDegrees, at: result)
        return result
    }

    static func searchMoonQuarter(after start: Engine.Time) throws -> LunarQuarter {
        try Engine.checkAcceptedTime(start)
        let angleTime: Engine.Time
        if start.tt < earliestApparentTT {
            guard let model = start.deltaTModel else { throw AstronomyError.badTime }
            angleTime = Engine.Time(tt: earliestApparentTT, deltaTModel: model)
        } else {
            angleTime = start
        }
        let angle = try moonPhaseAngle(at: angleTime)
        let rawValue = (Int(floor(angle / 90)) + 1) % LunarPhase.allCases.count
        guard let phase = LunarPhase(rawValue: rawValue),
            let time = try searchMoonPhase(phase.targetDegrees, after: start, limitDays: 10)
        else { throw AstronomyError.searchFailure }
        return LunarQuarter(phase: phase, time: time)
    }

    static func nextMoonQuarter(after quarter: LunarQuarter) throws -> LunarQuarter {
        let next = try searchMoonQuarter(after: quarter.time.adding(days: 6))
        guard next.phase.rawValue == (quarter.phase.rawValue + 1) % LunarPhase.allCases.count,
            next.time.tt > quarter.time.tt
        else { throw AstronomyError.internalError }
        return next
    }

    static func searchLunarNode(after start: Engine.Time) throws -> LunarNode {
        try Engine.checkAcceptedTime(start)
        var first = start
        var firstLatitude = try lunarLatitude(at: first)
        for _ in 0..<nodeStepLimit {
            let last = first.adding(days: nodeStepDays)
            guard last.ut > first.ut else { throw AstronomyError.badTime }
            let lastLatitude = try lunarLatitude(at: last)
            if firstLatitude * lastLatitude <= 0 {
                let kind: LunarNodeKind = lastLatitude > firstLatitude ? .ascending : .descending
                let direction = kind == .ascending ? 1.0 : -1.0
                guard
                    let time = try Engine.Search.ascendingRoot(
                        from: first, to: last, toleranceSeconds: 1,
                        { direction * (try lunarLatitude(at: $0)) })
                else { throw AstronomyError.searchFailure }
                _ = try lunarLatitude(at: time)
                return LunarNode(kind: kind, time: time)
            }
            first = last
            firstLatitude = lastLatitude
        }
        throw AstronomyError.noConvergence
    }

    static func nextLunarNode(after node: LunarNode) throws -> LunarNode {
        let next = try searchLunarNode(after: node.time.adding(days: nodeStepDays))
        guard next.kind != node.kind, next.time.tt > node.time.tt else { throw AstronomyError.internalError }
        return next
    }

    static func searchLunarApsis(after start: Engine.Time) throws -> LunarApsis {
        try Engine.checkAcceptedTime(start)
        var first = start
        var firstSlope = try lunarDistanceSlope(at: first)
        for _ in 0..<apsisStepLimit {
            let last = first.adding(days: apsisStepDays)
            guard last.ut > first.ut else { throw AstronomyError.badTime }
            let lastSlope = try lunarDistanceSlope(at: last)
            if firstSlope * lastSlope <= 0 {
                let kind: LunarApsisKind
                let direction: Double
                if firstSlope < 0 || lastSlope > 0 {
                    kind = .pericenter
                    direction = 1
                } else if firstSlope > 0 || lastSlope < 0 {
                    kind = .apocenter
                    direction = -1
                } else {
                    throw AstronomyError.internalError
                }
                guard
                    let time = try Engine.Search.ascendingRoot(
                        from: first, to: last, toleranceSeconds: 1,
                        { direction * (try lunarDistanceSlope(at: $0)) })
                else { throw AstronomyError.searchFailure }
                let distance = try Engine.Moon.distance(at: time)
                return LunarApsis(kind: kind, time: time, distanceAU: distance)
            }
            first = last
            firstSlope = lastSlope
        }
        throw AstronomyError.noConvergence
    }

    static func nextLunarApsis(after apsis: LunarApsis) throws -> LunarApsis {
        let next = try searchLunarApsis(after: apsis.time.adding(days: 11))
        guard next.kind != apsis.kind, next.time.tt > apsis.time.tt else { throw AstronomyError.internalError }
        return next
    }

    private static let meanSynodicMonth = 29.530588
    private static let phaseUncertaintyDays = 1.5
    private static let earliestApparentTT = (-Engine.acceptedTTDays + 1 / Engine.speedOfLightAUPerDay).nextUp
    private static let nodeStepDays = 10.0
    private static let nodeStepLimit = 4
    private static let apsisStepDays = 5.0
    private static let apsisStepLimit = 12

    private static func moonPhaseOffset(_ targetDegrees: Double, at time: Engine.Time) throws -> Double {
        let offset = Engine.longitudeOffset(try moonPhaseAngle(at: time) - targetDegrees)
        guard offset.isFinite else { throw AstronomyError.badTime }
        return offset
    }

    private static func lunarLatitude(at time: Engine.Time) throws -> Double {
        let latitude = try Engine.Moon.eclipticPosition(at: time).latitude
        guard latitude.isFinite else { throw AstronomyError.badTime }
        return latitude
    }

    private static func lunarDistanceSlope(at time: Engine.Time) throws -> Double {
        let state = try Engine.Moon.geocentricState(at: time)
        let position = SIMD3(state.x, state.y, state.z)
        let velocity = SIMD3(state.vx, state.vy, state.vz)
        let length = (position * position).sum().squareRoot()
        let slope = (position * velocity).sum() / length
        guard slope.isFinite else { throw AstronomyError.badTime }
        return slope
    }
}
