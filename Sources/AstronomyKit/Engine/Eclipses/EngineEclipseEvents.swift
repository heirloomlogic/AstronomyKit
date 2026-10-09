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
        let obscuration: Double
        let penumbralDurationMinutes: Double
        let partialDurationMinutes: Double
        let totalDurationMinutes: Double
    }

    static func searchLunarEclipse(after start: Engine.Time) throws -> LunarEclipse {
        try Engine.checkAcceptedTime(start)
        var fullMoonStart = start

        for _ in 0..<fullMoonLimit {
            guard let fullMoon = try searchMoonPhase(180, after: fullMoonStart, limitDays: 40) else {
                throw AstronomyError.searchFailure
            }
            if abs(try Engine.Moon.eclipticPosition(at: fullMoon).latitude) < eclipseLatitudeLimitDegrees {
                let shadow = try peakEarthShadow(near: fullMoon)
                let moonRadius = try moonDiscRadius(in: shadow)
                if shadow.axisDistanceKilometers < shadow.penumbraRadiusKilometers + moonRadius {
                    return try lunarEclipse(from: shadow)
                }
            }
            let nextStart = fullMoon.adding(days: 10)
            guard nextStart.tt > fullMoon.tt else { throw AstronomyError.badTime }
            fullMoonStart = nextStart
        }
        throw AstronomyError.internalError
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
            let peak = try Engine.Search.ascendingRoot(from: first, to: last, toleranceSeconds: 1, shadowDistanceSlope)
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
    private static let fullMoonLimit = 12

    private enum LunarShadowContact {
        case penumbral
        case partial
        case total
    }
}
