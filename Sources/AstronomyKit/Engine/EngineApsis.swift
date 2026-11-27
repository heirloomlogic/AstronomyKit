//
//  EngineApsis.swift
//  AstronomyKit
//
//  Pure-Swift lunar and planetary apsis search matching Astronomy_SearchLunarApsis,
//  Astronomy_NextLunarApsis, Astronomy_SearchPlanetApsis, and Astronomy_NextPlanetApsis.
//

enum EngineApsis {
    // MARK: - Lunar Apsis

    static func searchLunarApsis(after startTime: AstroTime) throws -> Apsis {
        let increment = 5.0
        var t1 = startTime
        var m1 = try moonDistanceSlope(direction: 1.0, at: t1)
        var iter = 0

        while Double(iter) * increment < 2.0 * EngineConstants.meanSynodicMonth {
            let t2 = t1.addingDays(increment)
            let m2 = try moonDistanceSlope(direction: 1.0, at: t2)

            if m1 * m2 <= 0.0 {
                let kind: ApsisKind
                let direction: Double
                if m1 < 0.0 || m2 > 0.0 {
                    kind = .pericenter
                    direction = 1.0
                } else if m1 > 0.0 || m2 < 0.0 {
                    kind = .apocenter
                    direction = -1.0
                } else {
                    throw AstronomyError.internalError
                }

                let tx = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
                    try moonDistanceSlope(direction: direction, at: t)
                }
                let distAU = EngineMoonCore.calcMoon(centuries: tx.terrestrialTime / 36525.0).distanceAU
                return Apsis(
                    kind: kind,
                    time: tx,
                    distanceAU: distAU,
                    distanceKM: distAU * EngineConstants.kmPerAU
                )
            }

            t1 = t2
            m1 = m2
            iter &+= 1
        }

        throw AstronomyError.internalError
    }

    static func nextLunarApsis(after apsis: Apsis) throws -> Apsis {
        let next = try searchLunarApsis(after: apsis.time.addingDays(11.0))
        guard next.kind != apsis.kind else {
            throw AstronomyError.internalError
        }
        return next
    }

    private static func moonDistanceSlope(direction: Double, at time: AstroTime) throws -> Double {
        let dt = 0.001
        let t1 = time.addingTerrestrialDays(-dt / 2.0)
        let t2 = time.addingTerrestrialDays(dt / 2.0)
        guard EngineMath.ephemerisTimeOk(t1), EngineMath.ephemerisTimeOk(t2) else {
            throw AstronomyError.badTime
        }
        let d1 = EngineMoonCore.calcMoon(centuries: t1.terrestrialTime / 36525.0).distanceAU
        let d2 = EngineMoonCore.calcMoon(centuries: t2.terrestrialTime / 36525.0).distanceAU
        return direction * (d2 - d1) / dt
    }

    // MARK: - Planetary Apsis

    static func searchPlanetApsis(of body: CelestialBody, after startTime: AstroTime) throws -> Apsis {
        if body == .neptune || body == .pluto {
            return try bruteSearchPlanetApsis(of: body, after: startTime)
        }

        let orbitPeriodDays = EngineMath.planetOrbitalPeriod(of: body)
        guard orbitPeriodDays != 0.0 else {
            throw AstronomyError.invalidBody
        }

        let increment = orbitPeriodDays / 6.0
        var t1 = startTime
        var m1 = try planetDistanceSlope(body: body, direction: 1.0, at: t1)
        var iter = 0

        while Double(iter) * increment < 2.0 * orbitPeriodDays {
            let t2 = t1.addingDays(increment)
            let m2 = try planetDistanceSlope(body: body, direction: 1.0, at: t2)

            if m1 * m2 <= 0.0 {
                let kind: ApsisKind
                let direction: Double
                if m1 < 0.0 || m2 > 0.0 {
                    kind = .pericenter
                    direction = 1.0
                } else if m1 > 0.0 || m2 < 0.0 {
                    kind = .apocenter
                    direction = -1.0
                } else {
                    throw AstronomyError.internalError
                }

                let tx = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
                    try planetDistanceSlope(body: body, direction: direction, at: t)
                }
                let dist = try EnginePositions.helioDistance(of: body, at: tx)
                return Apsis(
                    kind: kind,
                    time: tx,
                    distanceAU: dist,
                    distanceKM: dist * EngineConstants.kmPerAU
                )
            }

            t1 = t2
            m1 = m2
            iter &+= 1
        }

        throw AstronomyError.internalError
    }

    static func nextPlanetApsis(of body: CelestialBody, after apsis: Apsis) throws -> Apsis {
        let skip = 0.25 * EngineMath.planetOrbitalPeriod(of: body)
        guard skip > 0.0 else {
            throw AstronomyError.invalidBody
        }

        let next = try searchPlanetApsis(of: body, after: apsis.time.addingDays(skip))
        guard next.kind != apsis.kind else {
            throw AstronomyError.internalError
        }
        return next
    }

    private static func planetDistanceSlope(
        body: CelestialBody,
        direction: Double,
        at time: AstroTime
    ) throws -> Double {
        let dt = 0.001
        let t1 = time.addingTerrestrialDays(-dt / 2.0)
        let t2 = time.addingTerrestrialDays(dt / 2.0)
        let dist1 = try EnginePositions.helioDistance(of: body, at: t1)
        let dist2 = try EnginePositions.helioDistance(of: body, at: t2)
        return direction * (dist2 - dist1) / dt
    }

    private static func planetExtreme(
        body: CelestialBody,
        kind: ApsisKind,
        startTime initialStart: AstroTime,
        dayspan initialSpan: Double
    ) throws -> Apsis {
        let direction = (kind == .apocenter) ? 1.0 : -1.0
        let npoints = 10
        var startTime = initialStart
        var dayspan = initialSpan

        while true {
            let interval = dayspan / Double(npoints - 1)
            if interval < 1.0 / 1440.0 {
                let apsisTime = startTime.addingDays(interval / 2.0)
                let dist = try EnginePositions.helioDistance(of: body, at: apsisTime)
                return Apsis(
                    kind: kind,
                    time: apsisTime,
                    distanceAU: dist,
                    distanceKM: dist * EngineConstants.kmPerAU
                )
            }

            var bestIdx = -1
            var bestDist = 0.0
            var i = 0
            while i < npoints {
                let sampleTime = startTime.addingDays(Double(i) * interval)
                let dist = direction * (try EnginePositions.helioDistance(of: body, at: sampleTime))
                if i == 0 || dist > bestDist {
                    bestIdx = i
                    bestDist = dist
                }
                i &+= 1
            }

            startTime = startTime.addingDays(Double(bestIdx - 1) * interval)
            dayspan = 2.0 * interval
        }
    }

    private static func bruteSearchPlanetApsis(
        of body: CelestialBody,
        after startTime: AstroTime
    ) throws -> Apsis {
        guard startTime.universalTime.isFinite else {
            throw AstronomyError.badTime
        }

        let npoints = 100
        let period = EngineMath.planetOrbitalPeriod(of: body)
        let t1 = startTime.addingDays(period * (-30.0 / 360.0))
        let t2 = startTime.addingDays(period * (270.0 / 360.0))
        var tMin = t1
        var tMax = t1
        var minDist = -1.0
        var maxDist = -1.0
        let interval = (t2.universalTime - t1.universalTime) / Double(npoints - 1)

        var i = 0
        while i < npoints {
            let ut = t1.universalTime + Double(i) * interval
            let sampleTime = AstroTime(ut: ut)
            let dist = try EnginePositions.helioDistance(of: body, at: sampleTime)
            if i == 0 {
                maxDist = dist
                minDist = dist
            } else {
                if dist > maxDist {
                    maxDist = dist
                    tMax = sampleTime
                }
                if dist < minDist {
                    minDist = dist
                    tMin = sampleTime
                }
            }
            i &+= 1
        }

        let perihelion = try? planetExtreme(
            body: body,
            kind: .pericenter,
            startTime: tMin.addingDays(-2.0 * interval),
            dayspan: 4.0 * interval
        )
        let aphelion = try? planetExtreme(
            body: body,
            kind: .apocenter,
            startTime: tMax.addingDays(-2.0 * interval),
            dayspan: 4.0 * interval
        )

        if let perihelion, perihelion.time.terrestrialTime >= startTime.terrestrialTime {
            if let aphelion, aphelion.time.terrestrialTime >= startTime.terrestrialTime,
                aphelion.time.terrestrialTime < perihelion.time.terrestrialTime
            {
                return aphelion
            }
            return perihelion
        }

        if let aphelion, aphelion.time.terrestrialTime >= startTime.terrestrialTime {
            return aphelion
        }

        throw AstronomyError.failApsis
    }
}
