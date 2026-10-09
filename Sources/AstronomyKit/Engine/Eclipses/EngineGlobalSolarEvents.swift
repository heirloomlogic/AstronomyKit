import Foundation

extension Engine.Events {
    enum GlobalSolarKind: String, Sendable { case partial, annular, total }

    struct GlobalSolarEclipse: Sendable {
        let kind: GlobalSolarKind
        let peak: Engine.Time
        let physicalPeak: Engine.Time
        let distanceKilometers: Double
        let obscuration: Double
        let latitude: Double?
        let longitude: Double?
    }

    struct SolarSurface: Sendable {
        let kind: GlobalSolarKind
        let point: Engine.Shadows.Triple
        let obscuration: Double
        let sunRadiusRadians: Double
        let moonRadiusRadians: Double
        let separationRadians: Double
    }

    // The historical Astronomical Ephemeris semidiameter is independently published in NASA's 1968 constants report.
    // This solar-only convention does not change the qualified lunar-shadow radius.
    static let solarEclipseSunRadius = Engine.kilometersPerAU * sin(959.63 / 3600 * Engine.radiansPerDegree)
    static let solarEclipseMoonRadius = Engine.Observers.equatorialRadiusKilometers * 0.272281
    static let solarEclipsePenumbralRadius = Engine.Observers.equatorialRadiusKilometers * 0.272488

    static func canonicalNewMoon(_ candidate: Engine.Time) throws -> Engine.Time {
        try canonicalEclipsePhase(candidate) { Engine.longitudeOffset(try moonPhaseAngle(at: $0)) }
    }

    static func searchGlobalSolarEclipse(after start: Engine.Time) throws -> GlobalSolarEclipse {
        try Engine.checkAcceptedTime(start)
        guard start.isValid else { throw AstronomyError.badTime }
        var seed = start
        let lookback = min(0.03, start.tt + Engine.acceptedTTDays)
        if lookback > 0, let found = try searchMoonPhase(0, after: start, limitDays: -lookback) {
            let phase = try canonicalNewMoon(found)
            if let event = try globalSolarEclipse(near: phase),
                let result = resolvedGlobalSolarEclipse(event, atOrAfter: start)
            {
                return result
            }
            seed = phase.adding(days: 10)
            guard seed.tt > phase.tt else { throw AstronomyError.badTime }
        }
        for _ in 0..<12 {
            guard let found = try searchMoonPhase(0, after: seed, limitDays: 40) else {
                throw AstronomyError.searchFailure
            }
            let phase = try canonicalNewMoon(found)
            if let event = try globalSolarEclipse(near: phase),
                let result = resolvedGlobalSolarEclipse(event, atOrAfter: start)
            {
                return result
            }
            seed = phase.adding(days: 10)
            guard seed.tt > phase.tt else { throw AstronomyError.badTime }
        }
        throw AstronomyError.searchFailure
    }

    static func resolvedGlobalSolarEclipse(
        _ event: GlobalSolarEclipse, atOrAfter start: Engine.Time
    ) -> GlobalSolarEclipse? {
        guard let model = start.deltaTModel, start.tt <= event.physicalPeak.tt + 1 / Engine.secondsPerDay else {
            return nil
        }
        return GlobalSolarEclipse(
            kind: event.kind, peak: Engine.Time(tt: max(start.tt, event.physicalPeak.tt), deltaTModel: model),
            physicalPeak: event.physicalPeak, distanceKilometers: event.distanceKilometers,
            obscuration: event.obscuration, latitude: event.latitude, longitude: event.longitude)
    }

    static func nextGlobalSolarEclipse(after event: GlobalSolarEclipse) throws -> GlobalSolarEclipse {
        let next = try searchGlobalSolarEclipse(after: event.peak.adding(days: 10))
        guard next.peak.tt > event.peak.tt else { throw AstronomyError.internalError }
        return next
    }

    static func moonShadow(at time: Engine.Time) throws -> Engine.Shadows.Shadow<Engine.EQJ> {
        try Engine.checkAcceptedTime(time)
        guard time.isValid else { throw AstronomyError.badTime }
        let sun = try Engine.Positions.geocentricPosition(of: .sun, at: time, aberration: .corrected)
        let moon = try Engine.Moon.geocentricPosition(at: time)
        let target = Engine.Vector<Engine.EQJ>(x: -moon.x, y: -moon.y, z: -moon.z, time: time)
        let direction = Engine.Vector<Engine.EQJ>(x: moon.x - sun.x, y: moon.y - sun.y, z: moon.z - sun.z, time: time)
        return try Engine.Shadows.calculate(
            bodyRadiusKilometers: solarEclipsePenumbralRadius, target: target, direction: direction,
            sunRadiusKilometers: solarEclipseSunRadius)
    }

    static func globalSolarEclipse(near phase: Engine.Time) throws -> GlobalSolarEclipse? {
        guard abs(try Engine.Moon.eclipticPosition(at: phase).latitude) < 1.8 else { return nil }
        func slope(_ time: Engine.Time) throws -> Double {
            let step = 1 / Engine.secondsPerDay
            return try moonShadow(at: time.adding(days: step)).axisDistanceKilometers
                - moonShadow(at: time.adding(days: -step)).axisDistanceKilometers
        }
        guard
            let peak = try Engine.Search.ascendingRoot(
                from: phase.adding(days: -0.03), to: phase.adding(days: 0.03), toleranceSeconds: 1, slope)
        else { throw AstronomyError.searchFailure }
        let shadow = try moonShadow(at: peak)
        return try globalSolarEclipse(at: shadow)
    }

    static func solarSurface(at time: Engine.Time) throws -> SolarSurface {
        guard let result = try surface(of: moonShadow(at: time)) else { throw AstronomyError.searchFailure }
        return result
    }

    private static func globalSolarEclipse(at shadow: Engine.Shadows.Shadow<Engine.EQJ>) throws -> GlobalSolarEclipse? {
        guard let surface = try surface(of: shadow) else { return nil }
        var latitude: Double?
        var longitude: Double?
        if surface.kind != .partial {
            let p = surface.point
            let f = Engine.Observers.polarRatio
            latitude = atan2(p.z, hypot(p.x, p.y) * f * f) * Engine.degreesPerRadian
            let angle =
                atan2(p.y, p.x) * Engine.degreesPerRadian - 15 * Engine.EarthRotation.apparentSiderealTime(shadow.time)
            let wrapped = Engine.longitudeOffset(angle)
            longitude = wrapped == -180 ? 180 : wrapped
        }
        return GlobalSolarEclipse(
            kind: surface.kind, peak: shadow.time, physicalPeak: shadow.time,
            distanceKilometers: shadow.axisDistanceKilometers,
            obscuration: surface.kind == .partial ? .nan : surface.obscuration, latitude: latitude, longitude: longitude
        )
    }

    private static func surface(of shadow: Engine.Shadows.Shadow<Engine.EQJ>) throws -> SolarSurface? {
        typealias Geometry = Engine.Shadows
        let rotation = Engine.FrameRotation.eqjToEqd(shadow.time)
        let target = rotation.apply(to: shadow.target)
        let direction = rotation.apply(to: shadow.direction)
        let au = Engine.kilometersPerAU
        let moon = Geometry.Triple(-target.x, -target.y, -target.z) * au
        let axis = Geometry.Triple(direction.x, direction.y, direction.z) * au
        let sun = moon - axis
        if let intersection = try Geometry.axisIntersection(origin: moon, direction: axis, radii: Geometry.earthRadii) {
            return try solarDiscs(sun: sun, moon: moon, point: intersection)
        }
        let closest = try Geometry.closestPointToMissedAxis(origin: moon, direction: axis, radii: Geometry.earthRadii)
        let initial = try solarDiscs(sun: sun, moon: moon, point: closest)
        if initial.kind != .partial { return initial }
        let length = Geometry.norm(axis)
        let unit = axis / length
        if initial.obscuration == 0 {
            let outerSine = (solarEclipseSunRadius + solarEclipsePenumbralRadius) / length
            guard outerSine > 0, outerSine < 1 else { throw AstronomyError.badVector }
            let outerCosine = sqrt((1 - outerSine) * (1 + outerSine))
            guard
                try Geometry.coneSurfacePoint(
                    origin: moon, unit: unit, radiusAtOrigin: solarEclipsePenumbralRadius / outerCosine,
                    slope: outerSine / outerCosine, radii: Geometry.earthRadii, seed: closest) != nil
            else { return nil }
        }
        let sine = (solarEclipseSunRadius - solarEclipseMoonRadius) / length
        guard sine > 0, sine < 1 else { throw AstronomyError.badVector }
        let cosine = sqrt((1 - sine) * (1 + sine))
        for sign in [1.0, -1.0] {
            if let point = try Geometry.coneSurfacePoint(
                origin: moon, unit: unit, radiusAtOrigin: sign * solarEclipseMoonRadius / cosine,
                slope: -sign * sine / cosine, radii: Geometry.earthRadii, seed: closest)
            {
                let result = try solarDiscs(sun: sun, moon: moon, point: point)
                guard result.kind != .partial else { throw AstronomyError.searchFailure }
                return result
            }
        }
        return initial
    }

    static func solarDiscs(
        sun: Engine.Shadows.Triple, moon: Engine.Shadows.Triple, point: Engine.Shadows.Triple
    ) throws -> SolarSurface {
        typealias Geometry = Engine.Shadows
        let s = sun - point
        let m = moon - point
        let sd = Geometry.norm(s)
        let md = Geometry.norm(m)
        guard sd > solarEclipseSunRadius, md > solarEclipseMoonRadius, sd.isFinite, md.isFinite else {
            throw AstronomyError.badVector
        }
        let su = s / sd
        let mu = m / md
        let cross = Geometry.Triple(su.y * mu.z - su.z * mu.y, su.z * mu.x - su.x * mu.z, su.x * mu.y - su.y * mu.x)
        let separation = atan2(Geometry.norm(cross), Geometry.dot(su, mu))
        let sr = asin(solarEclipseSunRadius / sd)
        let mr = asin(solarEclipseMoonRadius / md)
        let kind: GlobalSolarKind = separation <= abs(sr - mr) ? (mr >= sr ? .total : .annular) : .partial
        let fraction =
            kind == .total ? 1 : Geometry.obscuration(firstRadius: sr, secondRadius: mr, separation: separation)
        guard fraction.isFinite, separation.isFinite else { throw AstronomyError.badVector }
        return SolarSurface(
            kind: kind, point: point, obscuration: fraction, sunRadiusRadians: sr, moonRadiusRadians: mr,
            separationRadians: separation)
    }
}
