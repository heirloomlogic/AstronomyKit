//
//  EngineTransits.swift
//  AstronomyKit
//
//  Pure-Swift Mercury and Venus transit search matching Astronomy_SearchTransit
//  and Astronomy_NextTransit.
//

enum EngineTransits {
    private static func planetShadow(
        body: CelestialBody,
        planetRadiusKM: Double,
        at time: AstroTime
    ) throws -> EngineShadow {
        let g = try EnginePositions.geoVector(of: body, at: time, aberration: .corrected)
        let s = try EnginePositions.geoVector(of: .sun, at: time, aberration: .corrected)
        let p = Vector3D(x: g.x - s.x, y: g.y - s.y, z: g.z - s.z, time: time)
        let e = Vector3D(x: -g.x, y: -g.y, z: -g.z, time: time)
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
            let s1 = try planetShadow(
                body: body,
                planetRadiusKM: planetRadiusKM,
                at: t.addingTerrestrialDays(-dt)
            )
            let s2 = try planetShadow(
                body: body,
                planetRadiusKM: planetRadiusKM,
                at: t.addingTerrestrialDays(dt)
            )
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
            let conjTime = try EngineEvents.searchRelativeLongitude(
                of: body,
                targetRelLon: 0.0,
                after: searchTime
            )
            let conjSep = try EnginePositions.angleFromSun(of: body, at: conjTime)

            if conjSep < thresholdAngle {
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
                    let minSep = try EnginePositions.angleFromSun(of: body, at: shadow.time)
                    return Transit(
                        body: body,
                        start: start,
                        peak: shadow.time,
                        finish: finish,
                        separation: 60.0 * minSep
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
