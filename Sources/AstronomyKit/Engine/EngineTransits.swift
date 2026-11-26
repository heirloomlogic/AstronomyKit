//
//  EngineTransits.swift
//  AstronomyKit
//
//  Pure-Swift Mercury and Venus transit search matching Astronomy_SearchTransit
//  and Astronomy_NextTransit.
//

import CLibAstronomy

enum EngineTransits {
    private static func planetShadow(
        body: CelestialBody,
        planetRadiusKM: Double,
        at time: AstroTime
    ) throws -> EngineShadow {
        let g = Astronomy_GeoVector(body.raw, time.raw, ABERRATION)
        if let error = AstronomyError(status: g.status) {
            throw error
        }
        let s = Astronomy_GeoVector(BODY_SUN, time.raw, ABERRATION)
        if let error = AstronomyError(status: s.status) {
            throw error
        }

        let p = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: g.x - s.x,
            y: g.y - s.y,
            z: g.z - s.z,
            t: time.raw
        )
        let e = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: -g.x,
            y: -g.y,
            z: -g.z,
            t: time.raw
        )

        return EngineEclipses.calcShadow(bodyRadiusKM: planetRadiusKM, time: time, target: e, dir: p)
    }

    private static func peakPlanetShadow(
        body: CelestialBody,
        planetRadiusKM: Double,
        near centerTime: AstroTime
    ) throws -> EngineShadow {
        let dt = 1.0 / 86400.0
        let window = 1.0
        let t1 = centerTime.addingDays(-window)
        let t2 = centerTime.addingDays(window)

        let peakTime = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let s1 = try planetShadow(body: body, planetRadiusKM: planetRadiusKM, at: t.addingTerrestrialDays(-dt))
            let s2 = try planetShadow(body: body, planetRadiusKM: planetRadiusKM, at: t.addingTerrestrialDays(dt))
            return (s2.r - s1.r) / dt
        }
        return try planetShadow(body: body, planetRadiusKM: planetRadiusKM, at: peakTime)
    }

    private static func planetTransitBoundary(
        body: CelestialBody,
        planetRadiusKM: Double,
        t1: AstroTime,
        t2: AstroTime,
        direction: Double
    ) throws -> AstroTime {
        try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let shadow = try planetShadow(body: body, planetRadiusKM: planetRadiusKM, at: t)
            return direction * (shadow.r - shadow.p)
        }
    }

    static func search(body: CelestialBody, after startTime: AstroTime) throws -> Transit {
        let planetRadiusKM: Double
        switch body {
        case .mercury:
            planetRadiusKM = 2439.7
        case .venus:
            planetRadiusKM = 6051.8
        default:
            throw AstronomyError.invalidBody
        }

        let thresholdAngle = 0.4
        let dtDays = 1.0
        var searchTime = startTime

        while true {
            let conj = Astronomy_SearchRelativeLongitude(body.raw, 0.0, searchTime.raw)
            if let error = AstronomyError(status: conj.status) {
                throw error
            }
            let conjTime = AstroTime(raw: conj.time)

            let conjSep = Astronomy_AngleFromSun(body.raw, conj.time)
            if let error = AstronomyError(status: conjSep.status) {
                throw error
            }

            if conjSep.angle < thresholdAngle {
                let shadow = try peakPlanetShadow(
                    body: body,
                    planetRadiusKM: planetRadiusKM,
                    near: conjTime
                )
                if shadow.r < shadow.p {
                    let start = try planetTransitBoundary(
                        body: body,
                        planetRadiusKM: planetRadiusKM,
                        t1: shadow.time.addingDays(-dtDays),
                        t2: shadow.time,
                        direction: -1.0
                    )
                    let finish = try planetTransitBoundary(
                        body: body,
                        planetRadiusKM: planetRadiusKM,
                        t1: shadow.time,
                        t2: shadow.time.addingDays(dtDays),
                        direction: 1.0
                    )
                    let minSep = Astronomy_AngleFromSun(body.raw, shadow.time.raw)
                    if let error = AstronomyError(status: minSep.status) {
                        throw error
                    }
                    return Transit(
                        body: body,
                        start: start,
                        peak: shadow.time,
                        finish: finish,
                        separation: 60.0 * minSep.angle
                    )
                }
            }

            searchTime = conjTime.addingDays(10.0)
        }
    }

    static func next(body: CelestialBody, after prevTransitTime: AstroTime) throws -> Transit {
        try search(body: body, after: prevTransitTime.addingDays(100.0))
    }
}
