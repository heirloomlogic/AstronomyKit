//
//  EngineEclipseEvents.swift
//  AstronomyKit
//
//  Native lunar-eclipse search.
//

import Foundation

extension Engine.Events {
    enum LunarEclipseKind: String, Sendable {
        case penumbral
        case partial
        case total
    }

    struct LunarEclipse: Sendable {
        let kind: LunarEclipseKind
        let peak: Engine.Time
        let physicalPeak: Engine.Time
        let obscuration: Double
        let penumbralDurationMinutes: Double
        let partialDurationMinutes: Double
        let totalDurationMinutes: Double

        init(
            kind: LunarEclipseKind, peak: Engine.Time, obscuration: Double,
            penumbralDurationMinutes: Double, partialDurationMinutes: Double, totalDurationMinutes: Double,
            physicalPeak: Engine.Time? = nil
        ) {
            self.kind = kind
            self.peak = peak
            self.physicalPeak = physicalPeak ?? peak
            self.obscuration = obscuration
            self.penumbralDurationMinutes = penumbralDurationMinutes
            self.partialDurationMinutes = partialDurationMinutes
            self.totalDurationMinutes = totalDurationMinutes
        }
    }

    static func searchLunarEclipse(after start: Engine.Time) throws -> LunarEclipse {
        try Engine.checkAcceptedTime(start)
        var fullMoonStart = start

        // A lunar eclipse peaks shortly after the phase boundary used to find it. Search backward only over the same
        // interval that bounds peak refinement, then require the refined peak to remain inside the caller's interval.
        let lowerBoundDistance = start.tt + Engine.acceptedTTDays
        let lookbackDays = min(peakWindowDays, lowerBoundDistance)
        if lookbackDays > 0,
            let backwardFullMoon = try searchMoonPhase(180, after: start, limitDays: -lookbackDays)
        {
            let precedingFullMoon = try canonicalFullMoon(backwardFullMoon)
            if let eclipse = try lunarEclipse(near: precedingFullMoon),
                let accepted = resolvedLunarEclipse(eclipse, atOrAfter: start)
            {
                return accepted
            }
            fullMoonStart = precedingFullMoon.adding(days: 10)
            guard fullMoonStart.tt > precedingFullMoon.tt else { throw AstronomyError.badTime }
        }

        for _ in 0..<fullMoonLimit {
            guard let foundFullMoon = try searchMoonPhase(180, after: fullMoonStart, limitDays: 40) else {
                throw AstronomyError.searchFailure
            }
            let fullMoon = try canonicalFullMoon(foundFullMoon)
            if let eclipse = try lunarEclipse(near: fullMoon),
                let accepted = resolvedLunarEclipse(eclipse, atOrAfter: start)
            {
                return accepted
            }
            let nextStart = fullMoon.adding(days: 10)
            guard nextStart.tt > fullMoon.tt else { throw AstronomyError.badTime }
            fullMoonStart = nextStart
        }
        throw AstronomyError.internalError
    }

    // Discovery estimates can depend on the caller's start. Phase signs select an absolute-TT daily bracket so every
    // route to the same full moon refines identical endpoints. The neighboring days cover estimates near midnight.
    static func canonicalFullMoon(
        _ candidate: Engine.Time,
        phaseOffset: (Engine.Time) throws -> Double = {
            Engine.longitudeOffset(try Engine.Events.moonPhaseAngle(at: $0) - 180)
        }
    ) throws -> Engine.Time {
        try canonicalEclipsePhase(candidate, phaseOffset: phaseOffset)
    }

    static func canonicalEclipsePhase(
        _ candidate: Engine.Time, phaseOffset: (Engine.Time) throws -> Double
    ) throws -> Engine.Time {
        try Engine.checkAcceptedTime(candidate)
        guard let model = candidate.deltaTModel else { throw AstronomyError.badTime }
        func offset(_ time: Engine.Time) throws -> Double {
            let value = try phaseOffset(time)
            guard value.isFinite else { throw AstronomyError.badTime }
            return value
        }
        let day = floor(candidate.tt)
        for lower in [day - 1, day, day + 1] {
            let firstTT = max(-Engine.acceptedTTDays, lower)
            let lastTT = min(Engine.acceptedTTDays, lower + 1)
            guard firstTT < lastTT else { continue }
            let first = Engine.Time(tt: firstTT, deltaTModel: model)
            let last = Engine.Time(tt: lastTT, deltaTModel: model)
            let firstOffset = try offset(first)
            let lastOffset = try offset(last)
            if firstOffset == 0 { return first }
            if lastOffset == 0 { return last }
            if firstOffset < 0 && lastOffset > 0 {
                guard
                    let root = try Engine.Search.ascendingRoot(
                        from: first, to: last, toleranceSeconds: 0.1, offset)
                else { throw AstronomyError.searchFailure }
                return root
            }
        }
        throw AstronomyError.searchFailure
    }

    private static func lunarEclipse(near fullMoon: Engine.Time) throws -> LunarEclipse? {
        guard abs(try Engine.Moon.eclipticPosition(at: fullMoon).latitude) < eclipseLatitudeLimitDegrees else {
            return nil
        }
        let shadow = try peakEarthShadow(near: fullMoon)
        let moonRadius = try moonDiscRadius(in: shadow)
        guard shadow.axisDistanceKilometers < shadow.penumbraRadiusKilometers + moonRadius else {
            return nil
        }
        return try lunarEclipse(from: shadow)
    }

    static func resolvedLunarEclipse(
        _ eclipse: LunarEclipse, atOrAfter start: Engine.Time
    ) -> LunarEclipse? {
        let physicalPeak = eclipse.physicalPeak
        guard start.tt <= physicalPeak.tt + peakSearchResolutionDays else { return nil }
        guard let model = start.deltaTModel else { return nil }
        let reportedTT = max(physicalPeak.tt, start.tt)
        if reportedTT == eclipse.peak.tt { return eclipse }

        // Compare the represented endpoint directly: subtraction can move an exact +1-second input outside it.
        // Retain the physical peak when clamping presentation, so resolving a clamped result cannot extend the window.
        return LunarEclipse(
            kind: eclipse.kind, peak: Engine.Time(tt: reportedTT, deltaTModel: model), obscuration: eclipse.obscuration,
            penumbralDurationMinutes: eclipse.penumbralDurationMinutes,
            partialDurationMinutes: eclipse.partialDurationMinutes, totalDurationMinutes: eclipse.totalDurationMinutes,
            physicalPeak: physicalPeak)
    }

    static func nextLunarEclipse(after eclipse: LunarEclipse) throws -> LunarEclipse {
        let next = try searchLunarEclipse(after: eclipse.peak.adding(days: 10))
        guard next.peak.tt > eclipse.peak.tt else { throw AstronomyError.internalError }
        return next
    }

    static func lunarEclipseKind(
        axisDistanceKilometers: Double,
        umbraRadiusKilometers: Double,
        penumbraRadiusKilometers: Double,
        moonRadiusKilometers: Double = Engine.Shadows.moonMeanRadiusKilometers
    ) -> LunarEclipseKind? {
        guard axisDistanceKilometers < penumbraRadiusKilometers + moonRadiusKilometers else {
            return nil
        }
        guard axisDistanceKilometers < umbraRadiusKilometers + moonRadiusKilometers else {
            return .penumbral
        }
        return axisDistanceKilometers + moonRadiusKilometers < umbraRadiusKilometers ? .total : .partial
    }

    private static func lunarEclipse(from shadow: Engine.Shadows.Shadow<Engine.EQJ>) throws -> LunarEclipse {
        let moonRadius = try moonDiscRadius(in: shadow)
        let penumbralDuration = try shadowSemiDurationMinutes(
            at: shadow.time, contact: .penumbral, windowMinutes: 200)
        guard
            let kind = lunarEclipseKind(
                axisDistanceKilometers: shadow.axisDistanceKilometers,
                umbraRadiusKilometers: shadow.umbraRadiusKilometers,
                penumbraRadiusKilometers: shadow.penumbraRadiusKilometers,
                moonRadiusKilometers: moonRadius)
        else { throw AstronomyError.internalError }
        var obscuration = 0.0
        var partialDuration = 0.0
        var totalDuration = 0.0

        if shadow.axisDistanceKilometers < shadow.umbraRadiusKilometers + moonRadius {
            partialDuration = try shadowSemiDurationMinutes(
                at: shadow.time, contact: .partial, windowMinutes: penumbralDuration)
            if kind == .total {
                obscuration = 1
                totalDuration = try shadowSemiDurationMinutes(
                    at: shadow.time, contact: .total, windowMinutes: partialDuration)
            } else {
                obscuration = Engine.Shadows.obscuration(
                    firstRadius: moonRadius, secondRadius: shadow.umbraRadiusKilometers,
                    separation: shadow.axisDistanceKilometers)
            }
        }

        guard obscuration.isFinite, penumbralDuration > 0, partialDuration.isFinite, totalDuration.isFinite else {
            throw AstronomyError.searchFailure
        }
        return LunarEclipse(
            kind: kind, peak: shadow.time, obscuration: obscuration, penumbralDurationMinutes: penumbralDuration,
            partialDurationMinutes: partialDuration, totalDurationMinutes: totalDuration)
    }

    private static func earthShadow(at time: Engine.Time) throws -> Engine.Shadows.Shadow<Engine.EQJ> {
        var direction = try Engine.Positions.geocentricPosition(of: .sun, at: time, aberration: .corrected)
        direction.x = -direction.x
        direction.y = -direction.y
        direction.z = -direction.z
        return try Engine.Shadows.lunarEarthShadow(
            target: Engine.Moon.geocentricPosition(at: time), direction: direction)
    }

    private static func moonDiscRadius(in shadow: Engine.Shadows.Shadow<Engine.EQJ>) throws -> Double {
        try Engine.Shadows.projectedDiscRadius(
            physicalRadiusKilometers: Engine.Shadows.moonMeanRadiusKilometers,
            distanceKilometers: shadow.target.length * Engine.kilometersPerAU)
    }

    private static func shadowDistanceSlope(at time: Engine.Time) throws -> Double {
        let step = 1 / Engine.secondsPerDay
        let before = try earthShadow(at: time.adding(days: -step))
        let after = try earthShadow(at: time.adding(days: step))
        let slope = (after.axisDistanceKilometers - before.axisDistanceKilometers) / step
        guard slope.isFinite else { throw AstronomyError.badTime }
        return slope
    }

    private static func peakEarthShadow(near time: Engine.Time) throws -> Engine.Shadows.Shadow<Engine.EQJ> {
        let first = time.adding(days: -peakWindowDays)
        let last = time.adding(days: peakWindowDays)
        guard
            let peak = try Engine.Search.ascendingRoot(
                from: first, to: last, toleranceSeconds: peakSearchResolutionSeconds, shadowDistanceSlope)
        else {
            throw AstronomyError.searchFailure
        }
        return try earthShadow(at: peak)
    }

    private static func shadowContactDistance(at time: Engine.Time, contact: LunarShadowContact) throws -> Double {
        let shadow = try earthShadow(at: time)
        let moonRadius = try moonDiscRadius(in: shadow)
        let radiusLimit =
            switch contact {
            case .penumbral: shadow.penumbraRadiusKilometers + moonRadius
            case .partial: shadow.umbraRadiusKilometers + moonRadius
            case .total: shadow.umbraRadiusKilometers - moonRadius
            }
        let distance = shadow.axisDistanceKilometers - radiusLimit
        guard distance.isFinite else { throw AstronomyError.badTime }
        return distance
    }

    private static func shadowSemiDurationMinutes(
        at center: Engine.Time, contact: LunarShadowContact, windowMinutes: Double
    ) throws -> Double {
        guard windowMinutes > 0, windowMinutes.isFinite else {
            throw AstronomyError.searchFailure
        }
        let windowDays = windowMinutes / 1_440
        let before = center.adding(days: -windowDays)
        let after = center.adding(days: windowDays)
        guard
            let ingress = try Engine.Search.ascendingRoot(
                from: before, to: center, toleranceSeconds: 1,
                { time in
                    -(try shadowContactDistance(at: time, contact: contact))
                }),
            let egress = try Engine.Search.ascendingRoot(
                from: center, to: after, toleranceSeconds: 1,
                { time in
                    try shadowContactDistance(at: time, contact: contact)
                })
        else {
            throw AstronomyError.searchFailure
        }
        let duration = (egress.ut - ingress.ut) * 720
        guard duration > 0, duration.isFinite else { throw AstronomyError.searchFailure }
        return duration
    }

    private static let eclipseLatitudeLimitDegrees = 1.8
    private static let peakWindowDays = 0.03
    static let peakSearchResolutionSeconds = 1.0
    private static let peakSearchResolutionDays = peakSearchResolutionSeconds / Engine.secondsPerDay
    private static let fullMoonLimit = 12

    private enum LunarShadowContact {
        case penumbral
        case partial
        case total
    }
}
