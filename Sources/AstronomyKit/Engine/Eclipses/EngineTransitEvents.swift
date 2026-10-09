import Foundation

extension Engine.Events {
    struct Transit: Sendable {
        let body: CelestialBody
        let start: Engine.Time
        let peak: Engine.Time
        let physicalPeak: Engine.Time
        let finish: Engine.Time
        let separationArcminutes: Double
    }

    struct TransitGeometry {
        let separationRadians: Double
        let sunRadiusRadians: Double
        let planetRadiusRadians: Double
        var exteriorMargin: Double { sunRadiusRadians + planetRadiusRadians - separationRadians }
    }

    static func transitRadius(of body: CelestialBody) throws -> Double {
        switch body {
        case .mercury: return 2_439.7
        case .venus: return 6_051.8
        default: throw AstronomyError.invalidBody
        }
    }

    /// Apparent geocentric discs. The public result exposes external contacts, not internal contacts II and III.
    static func transitGeometry(of body: CelestialBody, at time: Engine.Time) throws -> TransitGeometry {
        let radius = try transitRadius(of: body)
        let sun = try Engine.Positions.geocentricPosition(of: .sun, at: time, aberration: .corrected)
        let planet = try Engine.Positions.geocentricPosition(of: body, at: time, aberration: .corrected)
        let sunDistance = sun.length * Engine.kilometersPerAU
        let planetDistance = planet.length * Engine.kilometersPerAU
        guard sunDistance > Engine.Shadows.sunRadiusKilometers, planetDistance > radius else {
            throw AstronomyError.badVector
        }
        let separation = try sun.angle(to: planet) * Engine.radiansPerDegree
        let result = TransitGeometry(
            separationRadians: separation,
            sunRadiusRadians: asin(Engine.Shadows.sunRadiusKilometers / sunDistance),
            planetRadiusRadians: asin(radius / planetDistance))
        guard result.exteriorMargin.isFinite else { throw AstronomyError.badTime }
        return result
    }

    static func canonicalTransitConjunction(of body: CelestialBody, near candidate: Engine.Time) throws -> Engine.Time {
        _ = try transitRadius(of: body)
        return try canonicalEclipsePhase(candidate) { time in
            let planet = try Engine.Positions.eclipticLongitude(of: body, at: time)
            let earth = try Engine.Positions.eclipticLongitude(of: .earth, at: time)
            return Engine.longitudeOffset(planet - earth)
        }
    }

    static func transitContact(
        of body: CelestialBody, from start: Engine.Time, to end: Engine.Time, ingress: Bool
    ) throws -> Engine.Time {
        let direction = ingress ? 1.0 : -1.0
        guard
            let contact = try Engine.Search.ascendingRoot(
                from: start, to: end, toleranceSeconds: 1,
                { direction * (try transitGeometry(of: body, at: $0).exteriorMargin) })
        else { throw AstronomyError.searchFailure }
        return contact
    }

    static func transit(of body: CelestialBody, near conjunction: Engine.Time) throws -> Transit? {
        _ = try transitRadius(of: body)
        // Retain the established one-day conjunction window and close-conjunction prefilter.
        guard try Engine.Positions.angleFromSun(of: body, at: conjunction) < 0.4 else { return nil }
        guard
            let peak = try Engine.Search.ascendingRoot(
                from: conjunction.adding(days: -1), to: conjunction.adding(days: 1), toleranceSeconds: 1,
                { time in
                    let step = 1 / 86400.0
                    let before = try transitGeometry(of: body, at: time.adding(days: -step)).separationRadians
                    let after = try transitGeometry(of: body, at: time.adding(days: step)).separationRadians
                    return after - before
                })
        else { throw AstronomyError.searchFailure }
        let geometry = try transitGeometry(of: body, at: peak)
        guard geometry.exteriorMargin > 0 else { return nil }
        let start = try transitContact(of: body, from: peak.adding(days: -1), to: peak, ingress: true)
        let finish = try transitContact(of: body, from: peak, to: peak.adding(days: 1), ingress: false)
        guard start.tt < peak.tt, peak.tt < finish.tt else { throw AstronomyError.searchFailure }
        return Transit(
            body: body, start: start, peak: peak, physicalPeak: peak, finish: finish,
            separationArcminutes: geometry.separationRadians / Engine.radiansPerDegree * 60)
    }

    static func resolvedTransit(_ transit: Transit, atOrAfter start: Engine.Time) -> Transit? {
        guard start.tt <= transit.physicalPeak.tt + 1 / 86400.0, let model = start.deltaTModel else { return nil }
        return Transit(
            body: transit.body, start: transit.start,
            peak: Engine.Time(tt: max(start.tt, transit.physicalPeak.tt), deltaTModel: model),
            physicalPeak: transit.physicalPeak, finish: transit.finish,
            separationArcminutes: transit.separationArcminutes)
    }

    static func searchTransit(of body: CelestialBody, after start: Engine.Time) throws -> Transit {
        _ = try transitRadius(of: body)
        try Engine.checkAcceptedTime(start)
        guard let model = start.deltaTModel else { throw AstronomyError.badTime }
        var search = Engine.Time(tt: max(-Engine.acceptedTTDays, start.tt - 1), deltaTModel: model)
        while search.tt <= Engine.acceptedTTDays {
            let found = try searchRelativeLongitude(of: body, targetDegrees: 0, after: search)
            let conjunction = try canonicalTransitConjunction(of: body, near: found)
            if let candidate = try transit(of: body, near: conjunction),
                let accepted = resolvedTransit(candidate, atOrAfter: start)
            {
                return accepted
            }
            let next = conjunction.adding(days: 10)
            guard next.tt > search.tt else { throw AstronomyError.badTime }
            search = next
        }
        throw AstronomyError.badTime
    }

    static func nextTransit(after transit: Transit) throws -> Transit {
        let next = try searchTransit(of: transit.body, after: transit.peak.adding(days: 100))
        guard next.physicalPeak.tt > transit.physicalPeak.tt else { throw AstronomyError.internalError }
        return next
    }
}
