//
//  EngineObserverEvents.swift
//  AstronomyKit
//
//  Native hour-angle, airless-altitude, and apparent upper-limb rise/set searches.
//

import Foundation

extension Engine.Events {
    struct HourAngleEvent: Sendable {
        let time: Engine.Time
        let horizon: Engine.Horizontal
    }

    /// Immutable source identity; fixed stars use the same finite-window and ascent machinery as solar-system bodies.
    enum ObserverTarget: Sendable {
        case body(CelestialBody)
        case star(Engine.Star)

        func equatorial(at time: Engine.Time, from observer: Observer) throws -> Engine.Equatorial {
            switch self {
            case .body(let body):
                guard body != .earth else { throw AstronomyError.earthNotAllowed }
                return try Engine.Positions.equatorial(
                    of: body, at: time, from: observer, equatorDate: .ofDate, aberration: .corrected)
            case .star(let star):
                return try star.equatorial(at: time, from: observer, equatorDate: .ofDate)
            }
        }
    }

    static func hourAngle(of body: CelestialBody, at time: Engine.Time, from observer: Observer) throws -> Double {
        try hourAngle(of: .body(body), at: time, from: observer)
    }

    static func searchHourAngle(
        of body: CelestialBody, hourAngle: Double, after start: Engine.Time, from observer: Observer, direction: Int
    ) throws -> HourAngleEvent {
        try searchHourAngle(of: .body(body), hourAngle: hourAngle, after: start, from: observer, direction: direction)
    }

    static func altitudeResidual(
        of body: CelestialBody, at time: Engine.Time, from observer: Observer, bodyRadiusAU: Double,
        targetDegrees: Double
    ) throws -> Double {
        try altitudeResidual(
            of: .body(body), at: time, from: observer, bodyRadiusAU: bodyRadiusAU, targetDegrees: targetDegrees)
    }

    static func searchAltitude(
        of body: CelestialBody, direction: RiseSetDirection, after start: Engine.Time, from observer: Observer,
        limitDays: Double, altitudeDegrees: Double
    ) throws -> Engine.Time? {
        try searchAltitude(
            of: .body(body), direction: direction, after: start, from: observer, limitDays: limitDays,
            altitudeDegrees: altitudeDegrees)
    }

    static func searchRiseSet(
        of body: CelestialBody, direction: RiseSetDirection, after start: Engine.Time, from observer: Observer,
        limitDays: Double, heightAboveGround: Double = 0
    ) throws -> Engine.Time? {
        try searchRiseSet(
            of: .body(body), direction: direction, after: start, from: observer, limitDays: limitDays,
            heightAboveGround: heightAboveGround)
    }

    private static let siderealDay = 0.9972695717592592

    private static func validateObserver(_ observer: Observer) throws {
        guard observer.latitude.isFinite, abs(observer.latitude) <= 90,
            observer.longitude.isFinite, observer.height.isFinite
        else { throw AstronomyError.invalidParameter }
    }

    static func hourAngle(of source: ObserverTarget, at time: Engine.Time, from observer: Observer) throws -> Double {
        try validateObserver(observer)
        let equatorial = try source.equatorial(at: time, from: observer)
        return try apparentHourAngle(equatorial, at: time, from: observer)
    }

    private static func apparentHourAngle(
        _ equatorial: Engine.Equatorial, at time: Engine.Time, from observer: Observer
    ) throws -> Double {
        let angle = Engine.normalized(
            observer.longitude / 15 + Engine.EarthRotation.apparentSiderealTime(time) - equatorial.rightAscension,
            period: 24)
        guard angle.isFinite else { throw AstronomyError.badTime }
        return angle
    }

    /// Finds the requested hour angle in the indicated direction, retaining the original 0.1 sidereal-second stopping criterion.
    static func searchHourAngle(
        of source: ObserverTarget, hourAngle target: Double, after start: Engine.Time,
        from observer: Observer, direction: Int
    ) throws -> HourAngleEvent {
        guard target.isFinite, (0..<24).contains(target), direction != 0 else {
            throw AstronomyError.invalidParameter
        }
        try validateObserver(observer)
        if case .body(.earth) = source { throw AstronomyError.earthNotAllowed }
        try Engine.checkAcceptedTime(start)
        var time = start
        for iteration in 0..<100 {
            let equatorial = try source.equatorial(at: time, from: observer)
            let current = try apparentHourAngle(equatorial, at: time, from: observer)
            var delta = (target - current).truncatingRemainder(dividingBy: 24)
            if iteration == 0 {
                if direction > 0 && delta < 0 { delta += 24 }
                if direction < 0 && delta > 0 { delta -= 24 }
            } else {
                if delta < -12 { delta += 24 }
                if delta > 12 { delta -= 24 }
            }
            if abs(delta) * 3_600 < 0.1 {
                return HourAngleEvent(
                    time: time,
                    horizon: Engine.Horizontal(
                        time: time, observer: observer, rightAscension: equatorial.rightAscension,
                        declination: equatorial.declination, refraction: .normal))
            }
            let next = time.adding(days: delta / 24 * siderealDay)
            try Engine.checkAcceptedTime(next)
            guard next.ut != time.ut else { throw AstronomyError.noConvergence }
            time = next
        }
        throw AstronomyError.noConvergence
    }

    /// Airless center altitude plus the body's angular radius, less the requested horizon.
    static func altitudeResidual(
        of source: ObserverTarget, at time: Engine.Time, from observer: Observer,
        bodyRadiusAU: Double, targetDegrees: Double
    ) throws -> Double {
        let equatorial = try source.equatorial(at: time, from: observer)
        let horizon = Engine.Horizontal(
            time: time, observer: observer, rightAscension: equatorial.rightAscension,
            declination: equatorial.declination, refraction: .none)
        let result =
            horizon.altitude + asin(bodyRadiusAU / equatorial.distance) * Engine.degreesPerRadian - targetDegrees
        guard result.isFinite else { throw AstronomyError.badTime }
        return result
    }

    private static func maximumAltitudeSlope(of source: ObserverTarget, latitude: Double) throws -> Double {
        let rates: (Double, Double)
        switch source {
        case .star: rates = (-0.008, 0.008)
        case .body(.moon): rates = (4.5, 8.2)
        case .body(.sun): rates = (0.8, 0.5)
        case .body(.mercury): rates = (-1.6, 1)
        case .body(.venus): rates = (-0.8, 0.6)
        case .body(.mars): rates = (-0.5, 0.4)
        case .body(.jupiter), .body(.saturn), .body(.uranus), .body(.neptune), .body(.pluto): rates = (-0.2, 0.2)
        case .body(.earth): throw AstronomyError.earthNotAllowed
        default: throw AstronomyError.invalidBody
        }
        let angle = latitude * Engine.radiansPerDegree
        return abs((360 / siderealDay - rates.0) * cos(angle)) + abs(rates.1 * sin(angle))
    }

    /// Original ascent subdivision, including its one-second minimum span and seventeen subdivision levels.
    static func altitudeAscent(
        lower: Engine.Time, upper: Engine.Time, lowValue: Double, highValue: Double,
        maximumSlope: Double, depth: Int = 0, evaluate: (Engine.Time) throws -> Double
    ) throws -> (Engine.Time, Engine.Time)? {
        if lowValue < 0 && highValue >= 0 { return (lower, upper) }
        if lowValue >= 0 && highValue < 0 { return nil }
        guard depth <= 17 else { throw AstronomyError.noConvergence }
        let halfSpan = (upper.ut - lower.ut) / 2
        if halfSpan * Engine.secondsPerDay < 1 { return nil }
        // A same-sign excursion must reach zero and return within the full interval.
        if min(abs(lowValue), abs(highValue)) > maximumSlope * halfSpan { return nil }
        let middle = lower.derived(ut: lower.ut + halfSpan)
        guard middle.ut > lower.ut, middle.ut < upper.ut else { throw AstronomyError.noConvergence }
        let middleValue = try evaluate(middle)
        if let left = try altitudeAscent(
            lower: lower, upper: middle, lowValue: lowValue, highValue: middleValue,
            maximumSlope: maximumSlope, depth: depth + 1, evaluate: evaluate)
        {
            return left
        }
        return try altitudeAscent(
            lower: middle, upper: upper, lowValue: middleValue, highValue: highValue,
            maximumSlope: maximumSlope, depth: depth + 1, evaluate: evaluate)
    }

    /// Searches an ascending or descending altitude crossing. The bracket requires a negative value at its earlier endpoint and a nonnegative value at its later endpoint, preserving the original discovery rule. A zero-length window has no crossing.
    static func searchAltitude(
        of source: ObserverTarget, direction: RiseSetDirection, after start: Engine.Time,
        from observer: Observer, limitDays: Double, altitudeDegrees: Double
    ) throws -> Engine.Time? {
        try searchAltitude(
            of: source, direction: direction, after: start, from: observer, limitDays: limitDays,
            altitudeDegrees: altitudeDegrees, bodyRadiusAU: 0)
    }

    private static func searchAltitude(
        of source: ObserverTarget, direction: RiseSetDirection, after start: Engine.Time,
        from observer: Observer, limitDays: Double, altitudeDegrees: Double, bodyRadiusAU: Double
    ) throws -> Engine.Time? {
        try validateObserver(observer)
        guard limitDays.isFinite, altitudeDegrees.isFinite, abs(altitudeDegrees) <= 90 else {
            throw AstronomyError.invalidParameter
        }
        let slope = try maximumAltitudeSlope(of: source, latitude: observer.latitude)
        try Engine.checkAcceptedTime(start)
        let end = start.adding(days: limitDays)
        try Engine.checkAcceptedTime(end)
        func evaluate(_ time: Engine.Time) throws -> Double {
            try Double(direction.rawValue)
                * altitudeResidual(
                    of: source, at: time, from: observer, bodyRadiusAU: bodyRadiusAU, targetDegrees: altitudeDegrees)
        }
        var lower = start
        var upper = start
        var lowValue = try evaluate(start)
        var highValue = lowValue
        if limitDays == 0 { return nil }
        while true {
            // Never sample beyond the declared window, including a short window adjacent to the source domain.
            if limitDays < 0 {
                lower = upper.derived(ut: max(end.ut, upper.ut - 0.42))
                guard lower.ut < upper.ut else { throw AstronomyError.noConvergence }
                lowValue = try evaluate(lower)
            } else {
                upper = lower.derived(ut: min(end.ut, lower.ut + 0.42))
                guard upper.ut > lower.ut else { throw AstronomyError.noConvergence }
                highValue = try evaluate(upper)
            }
            if let bracket = try altitudeAscent(
                lower: lower, upper: upper, lowValue: lowValue, highValue: highValue,
                maximumSlope: slope, evaluate: evaluate)
            {
                guard
                    let root = try Engine.Search.ascendingRoot(
                        from: bracket.0, to: bracket.1, toleranceSeconds: 0.1, evaluate)
                else { throw AstronomyError.searchFailure }
                if limitDays < 0 ? root.ut < end.ut : root.ut > end.ut { return nil }
                return root
            }
            if limitDays < 0 {
                if lower.ut <= end.ut { return nil }
                upper = lower
                highValue = lowValue
            } else {
                if upper.ut >= end.ut { return nil }
                lower = upper
                lowValue = highValue
            }
        }
    }

    static func searchRiseSet(
        of source: ObserverTarget, direction: RiseSetDirection, after start: Engine.Time,
        from observer: Observer, limitDays: Double, heightAboveGround: Double = 0
    ) throws -> Engine.Time? {
        try validateObserver(observer)
        guard heightAboveGround.isFinite, heightAboveGround >= 0 else { throw AstronomyError.invalidParameter }
        let atmosphere = try Engine.Atmosphere(elevation: observer.height - heightAboveGround)
        let latitude = observer.latitude * Engine.radiansPerDegree
        let polarRatio = Engine.Observers.polarRatio
        let c = 1 / hypot(cos(latitude), sin(latitude) * polarRatio)
        let s = c * polarRatio * polarRatio
        let groundHeightKM = (observer.height - heightAboveGround) / 1_000
        let radius =
            1_000
            * hypot(
                (Engine.Observers.equatorialRadiusKilometers * c + groundHeightKM) * cos(latitude),
                (Engine.Observers.equatorialRadiusKilometers * s + groundHeightKM) * sin(latitude))
        let k = 0.175 * pow(1 - (6.5e-3 / 283.15) * (observer.height - (2.0 / 3) * heightAboveGround), 3.256)
        let dip = -Engine.degreesPerRadian * sqrt(2 * (1 - k) * heightAboveGround / radius) / (1 - k)
        let radiusAU: Double
        switch source {
        // Apparent optical limb convention supported by archived USNO semidiameters.
        // The IAU nominal solar-radius conversion constant is not this event definition.
        case .body(.sun): radiusAU = 696_000 / Engine.kilometersPerAU
        case .body(.moon): radiusAU = 1_738.1 / Engine.kilometersPerAU
        default: radiusAU = 0
        }
        return try searchAltitude(
            of: source, direction: direction, after: start, from: observer, limitDays: limitDays,
            altitudeDegrees: dip - (34.0 / 60) * atmosphere.density, bodyRadiusAU: radiusAU)
    }
}
