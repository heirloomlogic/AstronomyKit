import Foundation

extension Engine.Events {
    struct LocalSolarContact: Sendable {
        let time: Engine.Time
        let altitude: Double
        var isVisible: Bool { altitude > 0 }
    }

    struct LocalSolarEclipse: Sendable {
        let kind: GlobalSolarKind
        let obscuration: Double
        let partialBegin: LocalSolarContact
        let totalBegin: LocalSolarContact?
        let peak: LocalSolarContact
        let physicalPeak: Engine.Time
        let totalEnd: LocalSolarContact?
        let partialEnd: LocalSolarContact
        var isVisible: Bool { partialBegin.isVisible || peak.isVisible || partialEnd.isVisible }
    }

    struct LocalSolarGeometry {
        let discs: SolarSurface
        let axisDistanceKilometers: Double
        let exteriorMargin: Double
        var interiorMargin: Double {
            abs(discs.sunRadiusRadians - discs.moonRadiusRadians) - discs.separationRadians
        }
    }

    static func validateSolarObserver(_ observer: Observer) throws {
        guard observer.latitude.isFinite, abs(observer.latitude) <= 90,
            observer.longitude.isFinite, observer.height.isFinite
        else { throw AstronomyError.invalidParameter }
    }

    static func localSolarGeometry(at time: Engine.Time, from observer: Observer) throws -> LocalSolarGeometry {
        try validateSolarObserver(observer)
        try Engine.checkAcceptedTime(time)
        guard time.isValid else { throw AstronomyError.badTime }
        let shadow = try moonShadow(at: time)
        let site = Engine.Observers.vector(observer, at: time)
        let au = Engine.kilometersPerAU
        let moon = Engine.Shadows.Triple(-shadow.target.x, -shadow.target.y, -shadow.target.z) * au
        let axis = Engine.Shadows.Triple(shadow.direction.x, shadow.direction.y, shadow.direction.z) * au
        let point = Engine.Shadows.Triple(site.x, site.y, site.z) * au
        let discs = try solarDiscs(sun: moon - axis, moon: moon, point: point)
        let distance = Engine.Shadows.norm(moon - point)
        guard distance > solarEclipsePenumbralRadius else { throw AstronomyError.badVector }
        let exterior = discs.sunRadiusRadians + asin(solarEclipsePenumbralRadius / distance) - discs.separationRadians
        let unit = axis / Engine.Shadows.norm(axis)
        let offset = point - moon
        let perpendicular = offset - Engine.Shadows.dot(offset, unit) * unit
        let axisDistance = Engine.Shadows.norm(perpendicular)
        guard exterior.isFinite, axisDistance.isFinite else { throw AstronomyError.badVector }
        return LocalSolarGeometry(discs: discs, axisDistanceKilometers: axisDistance, exteriorMargin: exterior)
    }

    static func localSolarContact(at time: Engine.Time, from observer: Observer) throws -> LocalSolarContact {
        try validateSolarObserver(observer)
        try Engine.checkAcceptedTime(time)
        let horizon = try Engine.Positions.horizontal(of: .sun, at: time, from: observer, refraction: .normal)
        guard horizon.altitude.isFinite else { throw AstronomyError.badTime }
        return LocalSolarContact(time: time, altitude: horizon.altitude)
    }

    static func localSolarTransition(
        from start: Engine.Time, to end: Engine.Time, rising: Bool,
        observer: Observer, interior: Bool
    ) throws -> LocalSolarContact {
        let direction = rising ? 1.0 : -1.0
        guard
            let root = try Engine.Search.ascendingRoot(
                from: start, to: end, toleranceSeconds: 1,
                { time in
                    let geometry = try localSolarGeometry(at: time, from: observer)
                    return direction * (interior ? geometry.interiorMargin : geometry.exteriorMargin)
                })
        else { throw AstronomyError.searchFailure }
        return try localSolarContact(at: root, from: observer)
    }

    /// Geometric candidate around a canonical new Moon, including candidates entirely below the horizon.
    static func localSolarEclipse(near phase: Engine.Time, from observer: Observer) throws -> LocalSolarEclipse? {
        try validateSolarObserver(observer)
        try Engine.checkAcceptedTime(phase)
        guard abs(try Engine.Moon.eclipticPosition(at: phase).latitude) < 1.8 else { return nil }
        guard
            let peakTime = try Engine.Search.ascendingRoot(
                from: phase.adding(days: -0.2), to: phase.adding(days: 0.2), toleranceSeconds: 1,
                { time in
                    let step = 1 / Engine.secondsPerDay
                    return try localSolarGeometry(at: time.adding(days: step), from: observer).axisDistanceKilometers
                        - localSolarGeometry(at: time.adding(days: -step), from: observer).axisDistanceKilometers
                })
        else { throw AstronomyError.searchFailure }
        let geometry = try localSolarGeometry(at: peakTime, from: observer)
        guard geometry.exteriorMargin > 0 else { return nil }
        let begin = try localSolarTransition(
            from: peakTime.adding(days: -0.2), to: peakTime, rising: true, observer: observer, interior: false)
        let end = try localSolarTransition(
            from: peakTime, to: peakTime.adding(days: 0.2), rising: false, observer: observer, interior: false)
        let peak = try localSolarContact(at: peakTime, from: observer)
        var centralBegin: LocalSolarContact?
        var centralEnd: LocalSolarContact?
        let central = geometry.interiorMargin > 0
        if central {
            centralBegin = try localSolarTransition(
                from: peakTime.adding(days: -0.01), to: peakTime, rising: true, observer: observer, interior: true)
            centralEnd = try localSolarTransition(
                from: peakTime, to: peakTime.adding(days: 0.01), rising: false, observer: observer, interior: true)
        }
        guard begin.time.tt < peakTime.tt, peakTime.tt < end.time.tt,
            centralBegin.map({ begin.time.tt < $0.time.tt && $0.time.tt <= peakTime.tt }) ?? true,
            centralEnd.map({ peakTime.tt <= $0.time.tt && $0.time.tt < end.time.tt }) ?? true
        else { throw AstronomyError.searchFailure }
        return LocalSolarEclipse(
            kind: central ? geometry.discs.kind : .partial, obscuration: geometry.discs.obscuration,
            partialBegin: begin, totalBegin: centralBegin, peak: peak, physicalPeak: peakTime,
            totalEnd: centralEnd, partialEnd: end)
    }

    static func resolvedLocalSolarEclipse(
        _ event: LocalSolarEclipse, atOrAfter start: Engine.Time, from observer: Observer
    ) throws -> LocalSolarEclipse? {
        guard start.isValid else { throw AstronomyError.badTime }
        guard start.tt <= event.physicalPeak.tt + 1 / Engine.secondsPerDay else { return nil }
        let peak = start.tt > event.physicalPeak.tt ? try localSolarContact(at: start, from: observer) : event.peak
        return LocalSolarEclipse(
            kind: event.kind, obscuration: event.obscuration, partialBegin: event.partialBegin,
            totalBegin: event.totalBegin, peak: peak, physicalPeak: event.physicalPeak,
            totalEnd: event.totalEnd, partialEnd: event.partialEnd)
    }

    static func searchLocalSolarEclipse(after start: Engine.Time, from observer: Observer) throws -> LocalSolarEclipse {
        try validateSolarObserver(observer)
        try Engine.checkAcceptedTime(start)
        guard start.isValid else { throw AstronomyError.badTime }
        var seed = start
        let lookback = min(0.2, start.tt + Engine.acceptedTTDays)
        if lookback > 0, let found = try searchMoonPhase(0, after: start, limitDays: -lookback) {
            let phase = try canonicalNewMoon(found)
            if let event = try localSolarEclipse(near: phase, from: observer),
                event.partialBegin.isVisible || event.partialEnd.isVisible,
                let resolved = try resolvedLocalSolarEclipse(event, atOrAfter: start, from: observer)
            {
                return resolved
            }
            seed = phase.adding(days: 10)
            guard seed.tt > phase.tt else { throw AstronomyError.badTime }
        }
        // Unlike a global search, a site's next visible eclipse can be many years away.
        // The accepted time domain and strict phase advancement bound this iteration.
        while seed.tt <= Engine.acceptedTTDays {
            guard let found = try searchMoonPhase(0, after: seed, limitDays: 40) else {
                throw AstronomyError.searchFailure
            }
            let phase = try canonicalNewMoon(found)
            if let event = try localSolarEclipse(near: phase, from: observer),
                event.partialBegin.isVisible || event.partialEnd.isVisible,
                let resolved = try resolvedLocalSolarEclipse(event, atOrAfter: start, from: observer)
            {
                return resolved
            }
            let next = phase.adding(days: 10)
            guard next.tt > seed.tt else { throw AstronomyError.badTime }
            seed = next
        }
        throw AstronomyError.badTime
    }

    static func nextLocalSolarEclipse(
        after event: LocalSolarEclipse, from observer: Observer
    ) throws -> LocalSolarEclipse {
        let next = try searchLocalSolarEclipse(after: event.peak.time.adding(days: 10), from: observer)
        guard next.peak.time.tt > event.peak.time.tt else { throw AstronomyError.internalError }
        return next
    }
}
