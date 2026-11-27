//
//  EngineEvents.swift
//  AstronomyKit
//
//  Pure-Swift solar longitude, seasons, elongation, lunar phases/quarters,
//  relative longitude, hour angle, rise/set, and altitude searches.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineEvents {
    // MARK: - Sun Longitude & Seasons

    private static func sunOffset(targetLon: Double, at time: AstroTime) throws -> Double {
        let ecl = try EnginePositions.sunPosition(at: time)
        return EngineMath.longitudeOffset(ecl.longitude - targetLon)
    }

    static func searchSunLongitude(
        targetLon: Double,
        after startTime: AstroTime,
        limitDays: Double
    ) throws -> AstroTime {
        guard targetLon.isFinite, limitDays.isFinite else {
            throw AstronomyError.invalidParameter
        }

        if abs(limitDays) > 30.0 {
            let initial = try sunOffset(targetLon: targetLon, at: startTime)
            guard limitDays > 0.0 else {
                var delta = initial
                if delta < 0.0 {
                    delta += 360.0
                }
                let estimate = -delta * (EngineConstants.daysPerTropicalYear / 360.0)
                if estimate + 10.0 < limitDays {
                    throw AstronomyError.searchFailure
                }
                let lo = (estimate - 10.0 > limitDays) ? (estimate - 10.0) : limitDays
                let hi = (estimate + 10.0 < 0.0) ? (estimate + 10.0) : 0.0
                let t1 = startTime.addingDays(hi)
                let t2 = startTime.addingDays(lo)
                return try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 0.01) { t in
                    try sunOffset(targetLon: targetLon, at: t)
                }
            }
            var delta = -initial
            if delta < 0.0 {
                delta += 360.0
            }
            let estimate = delta * (EngineConstants.daysPerTropicalYear / 360.0)
            if estimate - 10.0 > limitDays {
                throw AstronomyError.searchFailure
            }
            let lo = (estimate - 10.0 > 0.0) ? (estimate - 10.0) : 0.0
            let hi = (estimate + 10.0 < limitDays) ? (estimate + 10.0) : limitDays
            let t1 = startTime.addingDays(lo)
            let t2 = startTime.addingDays(hi)
            return try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 0.01) { t in
                try sunOffset(targetLon: targetLon, at: t)
            }
        }

        let t2 = startTime.addingDays(limitDays)
        return try EngineSearch.find(t1: startTime, t2: t2, dtToleranceSeconds: 0.01) { t in
            try sunOffset(targetLon: targetLon, at: t)
        }
    }

    static func seasons(year: Int, deltaT: DeltaTModel) throws -> Seasons {
        guard Int32(exactly: year) != nil else {
            throw AstronomyError.invalidParameter
        }
        let mar = try searchSunLongitude(
            targetLon: 0.0,
            after: AstroTime(year: year, month: 3, day: 10, deltaT: deltaT),
            limitDays: 20.0
        )
        let jun = try searchSunLongitude(
            targetLon: 90.0,
            after: AstroTime(year: year, month: 6, day: 10, deltaT: deltaT),
            limitDays: 20.0
        )
        let sep = try searchSunLongitude(
            targetLon: 180.0,
            after: AstroTime(year: year, month: 9, day: 10, deltaT: deltaT),
            limitDays: 20.0
        )
        let dec = try searchSunLongitude(
            targetLon: 270.0,
            after: AstroTime(year: year, month: 12, day: 10, deltaT: deltaT),
            limitDays: 20.0
        )
        return Seasons(
            marchEquinox: mar,
            juneSolstice: jun,
            septemberEquinox: sep,
            decemberSolstice: dec
        )
    }

    // MARK: - Elongation

    static func elongation(of body: CelestialBody, at time: AstroTime) throws -> Elongation {
        let pairLon = try EnginePositions.pairLongitude(body1: body, body2: .sun, at: time)
        let visibility: Visibility
        let eclipticSep: Double
        if pairLon > 180.0 {
            visibility = .morning
            eclipticSep = 360.0 - pairLon
        } else {
            visibility = .evening
            eclipticSep = pairLon
        }
        let angle = try EnginePositions.angleFromSun(of: body, at: time)
        return Elongation(
            time: time,
            visibility: visibility,
            angle: angle,
            eclipticSeparation: eclipticSep
        )
    }

    private static func negElongSlope(of body: CelestialBody, at time: AstroTime) throws -> Double {
        let dt = 0.1
        let t1 = time.addingTerrestrialDays(-dt / 2.0)
        let t2 = time.addingTerrestrialDays(dt / 2.0)
        let e1 = try EnginePositions.angleFromSun(of: body, at: t1)
        let e2 = try EnginePositions.angleFromSun(of: body, at: t2)
        return (e1 - e2) / dt
    }

    static func searchMaxElongation(
        of body: CelestialBody,
        after startTime: AstroTime
    ) throws -> Elongation {
        let s1: Double
        let s2: Double
        switch body {
        case .mercury:
            s1 = 50.0
            s2 = 85.0
        case .venus:
            s1 = 40.0
            s2 = 50.0
        default:
            throw AstronomyError.invalidBody
        }

        let syn = try EngineMath.synodicPeriod(of: body)
        var searchStart = startTime
        var iter = 0
        while iter < 2 {
            iter &+= 1
            let (plon, elon) = try EnginePositions.helioEclipticLongitudePair(
                body1: body,
                body2: .earth,
                at: searchStart
            )
            let rlon = EngineMath.longitudeOffset(plon - elon)

            let adjustDays: Double
            let rlonLo: Double
            let rlonHi: Double
            if rlon >= -s1 && rlon < s1 {
                adjustDays = 0.0
                rlonLo = s1
                rlonHi = s2
            } else if rlon > s2 || rlon < -s2 {
                adjustDays = 0.0
                rlonLo = -s2
                rlonHi = -s1
            } else if rlon >= 0.0 {
                adjustDays = -syn / 4.0
                rlonLo = s1
                rlonHi = s2
            } else {
                adjustDays = -syn / 4.0
                rlonLo = -s2
                rlonHi = -s1
            }

            let tStart = searchStart.addingDays(adjustDays)
            let t1 = try searchRelativeLongitude(of: body, targetRelLon: rlonLo, after: tStart)
            let t2 = try searchRelativeLongitude(of: body, targetRelLon: rlonHi, after: t1)

            let m1 = try negElongSlope(of: body, at: t1)
            if m1 >= 0.0 {
                throw AstronomyError.internalError
            }
            let m2 = try negElongSlope(of: body, at: t2)
            if m2 <= 0.0 {
                throw AstronomyError.internalError
            }

            let tx = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 10.0) { t in
                try negElongSlope(of: body, at: t)
            }
            if tx.terrestrialTime >= searchStart.terrestrialTime {
                return try elongation(of: body, at: tx)
            }
            searchStart = t2.addingDays(1.0)
        }
        throw AstronomyError.searchFailure
    }

    // MARK: - Moon Phase & Quarters

    static func moonPhase(at time: AstroTime) throws -> Double {
        try EnginePositions.pairLongitude(body1: .moon, body2: .sun, at: time)
    }

    private static func moonOffset(targetLon: Double, at time: AstroTime) throws -> Double {
        let phase = try moonPhase(at: time)
        return EngineMath.longitudeOffset(phase - targetLon)
    }

    static func searchMoonPhase(
        targetLon: Double,
        after startTime: AstroTime,
        limitDays: Double
    ) throws -> AstroTime {
        let uncertainty = 1.5
        var ya = try moonOffset(targetLon: targetLon, at: startTime)
        var dt1: Double
        var dt2: Double
        if limitDays < 0.0 {
            if ya < 0.0 {
                ya += 360.0
            }
            let estDt = -(EngineConstants.meanSynodicMonth * ya) / 360.0
            dt1 = estDt - uncertainty
            dt2 = estDt + uncertainty
            if dt2 < limitDays {
                throw AstronomyError.noMoonQuarter
            }
            if dt1 < limitDays {
                dt1 = limitDays
            }
        } else {
            if ya > 0.0 {
                ya -= 360.0
            }
            let estDt = -(EngineConstants.meanSynodicMonth * ya) / 360.0
            dt1 = estDt - uncertainty
            dt2 = estDt + uncertainty
            if dt1 > limitDays {
                throw AstronomyError.noMoonQuarter
            }
            if dt2 > limitDays {
                dt2 = limitDays
            }
        }
        let t1 = startTime.addingDays(dt1)
        let t2 = startTime.addingDays(dt2)
        return try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 0.1) { t in
            try moonOffset(targetLon: targetLon, at: t)
        }
    }

    static func searchMoonQuarter(after startTime: AstroTime) throws -> MoonQuarter {
        let angle = try moonPhase(at: startTime)
        let q = (1 + Int(floor(angle / 90.0))) % 4
        guard let phase = MoonPhase(rawValue: q) else {
            throw AstronomyError.internalError
        }
        let time = try searchMoonPhase(targetLon: 90.0 * Double(q), after: startTime, limitDays: 10.0)
        return MoonQuarter(phase: phase, time: time)
    }

    static func nextMoonQuarter(after mq: MoonQuarter) throws -> MoonQuarter {
        let time = mq.time.addingDays(6.0)
        let next = try searchMoonQuarter(after: time)
        let expected = (1 + mq.phase.rawValue) % 4
        guard next.phase.rawValue == expected else {
            throw AstronomyError.wrongMoonQuarter
        }
        return next
    }

    // MARK: - Relative Longitude

    private static func rlonOffset(
        body: CelestialBody,
        time: AstroTime,
        direction: Double,
        targetRelLon: Double
    ) throws -> Double {
        let (plon, elon) = try EnginePositions.helioEclipticLongitudePair(
            body1: body,
            body2: .earth,
            at: time
        )
        let diff = direction * (elon - plon)
        return EngineMath.longitudeOffset(diff - targetRelLon)
    }

    static func searchRelativeLongitude(
        of body: CelestialBody,
        targetRelLon: Double,
        after startTime: AstroTime
    ) throws -> AstroTime {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }
        if body == .moon || body == .sun {
            throw AstronomyError.invalidBody
        }

        var syn = try EngineMath.synodicPeriod(of: body)
        let direction = EngineMath.isSuperiorPlanet(body) ? 1.0 : -1.0

        var errorAngle = try rlonOffset(
            body: body,
            time: startTime,
            direction: direction,
            targetRelLon: targetRelLon
        )
        if errorAngle > 0.0 {
            errorAngle -= 360.0
        }

        var time = startTime
        var iter = 0
        while iter < 100 {
            let dayAdjust = (-errorAngle / 360.0) * syn
            time = time.addingDays(dayAdjust)
            if abs(dayAdjust) * EngineConstants.secondsPerDay < 1.0 {
                return time
            }

            let prevAngle = errorAngle
            errorAngle = try rlonOffset(
                body: body,
                time: time,
                direction: direction,
                targetRelLon: targetRelLon
            )

            if abs(prevAngle) < 30.0 && prevAngle != errorAngle {
                let ratio = prevAngle / (prevAngle - errorAngle)
                if ratio > 0.5 && ratio < 2.0 {
                    syn *= ratio
                }
            }
            iter &+= 1
        }
        throw AstronomyError.noConvergence
    }

    // MARK: - Hour Angle

    static func hourAngle(
        of body: CelestialBody,
        at time: AstroTime,
        from observer: Observer
    ) throws -> Double {
        let gc = try EnginePositions.geoVector(of: body, at: time, aberration: .corrected)
        let (ofdate, gast) = try EngineObserver.topocentricOfDate(
            geocentric: gc,
            at: time,
            observer: observer
        )

        var value = fmod(observer.longitude / 15.0 + gast - ofdate.rightAscension, 24.0)
        if value < 0.0 {
            value += 24.0
        }
        return value
    }

    static func searchHourAngle(
        of body: CelestialBody,
        hourAngle targetHA: Double,
        after startTime: AstroTime,
        from observer: Observer,
        direction: Int32
    ) throws -> HourAngleEvent {
        if body == .earth {
            throw AstronomyError.earthNotAllowed
        }
        guard targetHA.isFinite, targetHA >= 0.0, targetHA < 24.0, direction != 0 else {
            throw AstronomyError.invalidParameter
        }

        var time = startTime
        var iter = 0
        while iter < 100 {
            iter &+= 1
            let gc = try EnginePositions.geoVector(of: body, at: time, aberration: .corrected)
            let (ofdate, gast) = try EngineObserver.topocentricOfDate(
                geocentric: gc,
                at: time,
                observer: observer
            )

            var deltaSiderealHours = fmod(
                (targetHA + ofdate.rightAscension - observer.longitude / 15.0) - gast,
                24.0
            )
            if iter == 1 {
                if direction > 0 {
                    if deltaSiderealHours < 0.0 {
                        deltaSiderealHours += 24.0
                    }
                } else {
                    if deltaSiderealHours > 0.0 {
                        deltaSiderealHours -= 24.0
                    }
                }
            } else {
                if deltaSiderealHours < -12.0 {
                    deltaSiderealHours += 24.0
                } else if deltaSiderealHours > 12.0 {
                    deltaSiderealHours -= 24.0
                }
            }

            if abs(deltaSiderealHours) * 3600.0 < 0.1 {
                let hor = EngineObserver.horizon(
                    at: time,
                    observer: observer,
                    rightAscension: ofdate.rightAscension,
                    declination: ofdate.declination,
                    refraction: .normal,
                    siderealHours: gast
                )
                return HourAngleEvent(time: time, horizon: hor)
            }

            let deltaDays =
                (deltaSiderealHours / 24.0) * EngineConstants.solarDaysPerSiderealDay
            time = time.addingDays(deltaDays)
        }
        throw AstronomyError.noConvergence
    }

    // MARK: - Rise / Set & Altitude Search

    private static let riseSetDt = 0.42

    private struct AscentResult {
        let tx: AstroTime
        let ty: AstroTime
    }

    private static func altitudeDiff(
        body: CelestialBody,
        direction: Double,
        observer: Observer,
        bodyRadiusAU: Double,
        targetAltitude: Double,
        at time: AstroTime
    ) throws -> Double {
        let gc = try EnginePositions.geoVector(of: body, at: time, aberration: .corrected)
        let (ofdate, gast) = try EngineObserver.topocentricOfDate(
            geocentric: gc,
            at: time,
            observer: observer
        )

        let hor = EngineObserver.horizon(
            at: time,
            observer: observer,
            rightAscension: ofdate.rightAscension,
            declination: ofdate.declination,
            refraction: .none,
            siderealHours: gast
        )
        let altitude = hor.altitude + EngineConstants.rad2Deg * asin(bodyRadiusAU / ofdate.distance)
        return direction * (altitude - targetAltitude)
    }

    private static func findAscent(
        depth: Int,
        budget: inout Int,
        body: CelestialBody,
        direction: Double,
        observer: Observer,
        bodyRadiusAU: Double,
        targetAltitude: Double,
        maxDerivAlt: Double,
        t1: AstroTime,
        t2: AstroTime,
        a1: Double,
        a2: Double
    ) throws -> AscentResult? {
        if a1 < 0.0 && a2 >= 0.0 {
            return AscentResult(tx: t1, ty: t2)
        }
        if a1 >= 0.0 && a2 < 0.0 {
            return nil
        }
        if depth > 17 {
            throw AstronomyError.noConvergence
        }

        let dt = (t2.universalTime - t1.universalTime) / 2.0
        if dt * EngineConstants.secondsPerDay < 1.0 {
            return nil
        }

        let absA1 = abs(a1)
        let absA2 = abs(a2)
        let da = absA1 < absA2 ? absA1 : absA2
        if da > maxDerivAlt * (dt / 2.0) {
            return nil
        }

        budget &-= 1
        if budget <= 0 {
            return nil
        }

        let tm = AstroTime(
            ut: (t1.universalTime + t2.universalTime) / 2.0,
            deltaT: t1.deltaTModel
        )
        let alt: Double
        do {
            alt = try altitudeDiff(
                body: body,
                direction: direction,
                observer: observer,
                bodyRadiusAU: bodyRadiusAU,
                targetAltitude: targetAltitude,
                at: tm
            )
        } catch {
            return nil
        }

        if let left = try findAscent(
            depth: depth &+ 1,
            budget: &budget,
            body: body,
            direction: direction,
            observer: observer,
            bodyRadiusAU: bodyRadiusAU,
            targetAltitude: targetAltitude,
            maxDerivAlt: maxDerivAlt,
            t1: t1,
            t2: tm,
            a1: a1,
            a2: alt
        ) {
            return left
        }

        return try findAscent(
            depth: depth &+ 1,
            budget: &budget,
            body: body,
            direction: direction,
            observer: observer,
            bodyRadiusAU: bodyRadiusAU,
            targetAltitude: targetAltitude,
            maxDerivAlt: maxDerivAlt,
            t1: tm,
            t2: t2,
            a1: alt,
            a2: a2
        )
    }

    private static func maxAltitudeSlope(body: CelestialBody, latitude: Double) throws -> Double {
        guard latitude.isFinite, latitude >= -90.0, latitude <= 90.0 else {
            throw AstronomyError.invalidParameter
        }

        let derivRa: Double
        let derivDec: Double
        switch body {
        case .moon:
            derivRa = 4.5
            derivDec = 8.2
        case .sun:
            derivRa = 0.8
            derivDec = 0.5
        case .mercury:
            derivRa = -1.6
            derivDec = 1.0
        case .venus:
            derivRa = -0.8
            derivDec = 0.6
        case .mars:
            derivRa = -0.5
            derivDec = 0.4
        case .jupiter, .saturn, .uranus, .neptune, .pluto:
            derivRa = -0.2
            derivDec = 0.2
        case .earth:
            throw AstronomyError.earthNotAllowed
        default:
            throw AstronomyError.invalidBody
        }

        let latrad = EngineConstants.deg2Rad * latitude
        let value =
            abs(((360.0 / EngineConstants.solarDaysPerSiderealDay) - derivRa) * cos(latrad))
            + abs(derivDec * sin(latrad))
        guard value.isFinite else {
            throw AstronomyError.internalError
        }
        return value
    }

    private static func horizonDipAngle(observer: Observer, metersAboveGround: Double) -> Double {
        if metersAboveGround == 0.0 {
            return 0.0
        }
        let phi = observer.latitude * EngineConstants.deg2Rad
        let sinphi = sin(phi)
        let cosphi = cos(phi)
        let c = 1.0 / hypot(cosphi, sinphi * EngineConstants.earthFlattening)
        let s = c * (EngineConstants.earthFlattening * EngineConstants.earthFlattening)
        let htKM = (observer.height - metersAboveGround) / 1000.0
        let ach = EngineConstants.earthEquatorialRadiusKM * c + htKM
        let ash = EngineConstants.earthEquatorialRadiusKM * s + htKM
        let radiusM = 1000.0 * hypot(ach * cosphi, ash * sinphi)

        var base = 1.0 - (6.5e-3 / 283.15) * (observer.height - (2.0 / 3.0) * metersAboveGround)
        if base < 0.0 {
            base = 0.0
        }
        let k = 0.175 * pow(base, 3.256)
        return EngineConstants.rad2Deg * -(sqrt(2.0 * (1.0 - k) * metersAboveGround / radiusM) / (1.0 - k))
    }

    private static func internalSearchAltitude(
        body: CelestialBody,
        observer: Observer,
        direction: RiseSetDirection,
        startTime: AstroTime,
        limitDays: Double,
        bodyRadiusAU: Double,
        targetAltitude: Double
    ) throws -> AstroTime? {
        guard targetAltitude.isFinite, targetAltitude >= -90.0, targetAltitude <= 90.0 else {
            throw AstronomyError.invalidParameter
        }
        guard limitDays.isFinite, abs(limitDays) <= 3660.0 else {
            throw AstronomyError.invalidParameter
        }

        let maxDerivAlt = try maxAltitudeSlope(body: body, latitude: observer.latitude)
        let dir: Double
        switch direction {
        case .rise:
            dir = 1.0
        case .set:
            dir = -1.0
        }

        var t1 = startTime
        var t2 = startTime
        var a1 = try altitudeDiff(
            body: body,
            direction: dir,
            observer: observer,
            bodyRadiusAU: bodyRadiusAU,
            targetAltitude: targetAltitude,
            at: t2
        )
        var a2 = a1

        while true {
            if limitDays < 0.0 {
                t1 = t2.addingDays(-riseSetDt)
                guard t1.universalTime < t2.universalTime else {
                    throw AstronomyError.badTime
                }
                a1 = try altitudeDiff(
                    body: body,
                    direction: dir,
                    observer: observer,
                    bodyRadiusAU: bodyRadiusAU,
                    targetAltitude: targetAltitude,
                    at: t1
                )
            } else {
                t2 = t1.addingDays(riseSetDt)
                guard t1.universalTime < t2.universalTime else {
                    throw AstronomyError.badTime
                }
                a2 = try altitudeDiff(
                    body: body,
                    direction: dir,
                    observer: observer,
                    bodyRadiusAU: bodyRadiusAU,
                    targetAltitude: targetAltitude,
                    at: t2
                )
            }

            var budget = 512
            if let ascent = try findAscent(
                depth: 0,
                budget: &budget,
                body: body,
                direction: dir,
                observer: observer,
                bodyRadiusAU: bodyRadiusAU,
                targetAltitude: targetAltitude,
                maxDerivAlt: maxDerivAlt,
                t1: t1,
                t2: t2,
                a1: a1,
                a2: a2
            ) {
                let found: AstroTime
                do {
                    found = try EngineSearch.find(
                        t1: ascent.tx,
                        t2: ascent.ty,
                        dtToleranceSeconds: 0.1
                    ) { t in
                        try altitudeDiff(
                            body: body,
                            direction: dir,
                            observer: observer,
                            bodyRadiusAU: bodyRadiusAU,
                            targetAltitude: targetAltitude,
                            at: t
                        )
                    }
                } catch {
                    throw AstronomyError.internalError
                }

                if limitDays < 0.0 {
                    if found.universalTime < startTime.universalTime + limitDays {
                        return nil
                    }
                } else {
                    if found.universalTime > startTime.universalTime + limitDays {
                        return nil
                    }
                }
                return found
            }

            if limitDays < 0.0 {
                if t1.universalTime < startTime.universalTime + limitDays {
                    return nil
                }
                t2 = t1
                a2 = a1
            } else {
                if t2.universalTime > startTime.universalTime + limitDays {
                    return nil
                }
                t1 = t2
                a1 = a2
            }
        }
    }

    static func searchRiseSet(
        of body: CelestialBody,
        observer: Observer,
        direction: RiseSetDirection,
        after startTime: AstroTime,
        limitDays: Double,
        metersAboveGround: Double
    ) throws -> AstroTime? {
        guard metersAboveGround.isFinite, metersAboveGround >= 0.0 else {
            throw AstronomyError.invalidParameter
        }

        let bodyRadiusAU: Double
        switch body {
        case .sun:
            bodyRadiusAU = EngineConstants.sunRadiusAU
        case .moon:
            bodyRadiusAU = EngineConstants.moonEquatorialRadiusAU
        default:
            bodyRadiusAU = 0.0
        }

        let atmos = try EngineObserver.atmosphere(elevationMeters: observer.height - metersAboveGround)
        let dip = horizonDipAngle(observer: observer, metersAboveGround: metersAboveGround)
        let altitude = dip - (EngineConstants.refractionNearHorizon * atmos.density)

        return try internalSearchAltitude(
            body: body,
            observer: observer,
            direction: direction,
            startTime: startTime,
            limitDays: limitDays,
            bodyRadiusAU: bodyRadiusAU,
            targetAltitude: altitude
        )
    }

    static func searchAltitude(
        of body: CelestialBody,
        observer: Observer,
        direction: RiseSetDirection,
        after startTime: AstroTime,
        limitDays: Double,
        altitude: Double
    ) throws -> AstroTime? {
        try internalSearchAltitude(
            body: body,
            observer: observer,
            direction: direction,
            startTime: startTime,
            limitDays: limitDays,
            bodyRadiusAU: 0.0,
            targetAltitude: altitude
        )
    }
}
