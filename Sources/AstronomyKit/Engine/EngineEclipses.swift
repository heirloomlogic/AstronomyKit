//
//  EngineEclipses.swift
//  AstronomyKit
//
//  Pure-Swift lunar, global solar, and local solar eclipse calculations matching
//  Astronomy_SearchLunarEclipse, Astronomy_SearchGlobalSolarEclipse, and
//  Astronomy_SearchLocalSolarEclipse (plus shared shadow geometry).
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct EngineShadow {
    let time: AstroTime
    let u: Double
    let r: Double
    let k: Double
    let p: Double
    let target: Vector3D
    let dir: Vector3D
}

enum EngineEclipses {
    // MARK: - Shared Shadow & Disc Geometry

    static func obscuration(a: Double, b: Double, c: Double) -> Double {
        if a <= 0.0 || b <= 0.0 || c < 0.0 || c >= a + b {
            return 0.0
        }
        if c == 0.0 {
            return (a <= b) ? 1.0 : (b * b) / (a * a)
        }

        let x = (a * a - b * b + c * c) / (2.0 * c)
        let radicand = a * a - x * x
        if radicand <= 0.0 {
            return (a <= b) ? 1.0 : (b * b) / (a * a)
        }

        let y = sqrt(radicand)
        let lens1 = a * a * acos(x / a) - x * y
        let lens2 = b * b * acos((c - x) / b) - (c - x) * y
        return (lens1 + lens2) / (EngineConstants.pi * a * a)
    }

    static func calcShadow(
        bodyRadiusKM: Double,
        time: AstroTime,
        target: Vector3D,
        dir: Vector3D
    ) -> EngineShadow {
        let u =
            (dir.x * target.x + dir.y * target.y + dir.z * target.z)
            / (dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)

        let dx = u * dir.x - target.x
        let dy = u * dir.y - target.y
        let dz = u * dir.z - target.z
        let r = EngineConstants.kmPerAU * sqrt(dx * dx + dy * dy + dz * dz)

        let sunR = EngineConstants.sunRadiusKM
        let k = sunR - (1.0 + u) * (sunR - bodyRadiusKM)
        let p = -sunR + (1.0 + u) * (sunR + bodyRadiusKM)
        return EngineShadow(time: time, u: u, r: r, k: k, p: p, target: target, dir: dir)
    }

    @inline(__always)
    private static func eclipseKindFromUmbra(_ k: Double) -> EclipseKind {
        // 14-meter bias matches Espenak reference data as in Astronomy Engine.
        k > 0.014 ? .total : .annular
    }

    private static func solarEclipseObscuration(hm: Vector3D, lo: Vector3D) -> Double {
        let ho = Vector3D(x: hm.x + lo.x, y: hm.y + lo.y, z: hm.z + lo.z, time: lo.time)
        let sunAU = EngineMath.vectorLength(ho)
        let sunRadius = asin(EngineConstants.sunRadiusAU / sunAU)
        let moonRadius = asin(EngineConstants.moonPolarRadiusAU / EngineMath.vectorLength(lo))

        guard let separation = try? EngineMath.angleBetween(lo, ho) else {
            return -1.0
        }

        var obs = obscuration(a: sunRadius, b: moonRadius, c: separation * EngineConstants.deg2Rad)
        if obs > 0.9999 {
            obs = 0.9999
        }
        return obs
    }

    // MARK: - Lunar Eclipse

    private static func earthShadow(at time: AstroTime) throws -> EngineShadow {
        let sun = try EnginePositions.geoVector(of: .sun, at: time, aberration: .corrected)
        let e = Vector3D(x: -sun.x, y: -sun.y, z: -sun.z, time: time)
        let m = try EnginePositions.geoMoon(at: time)
        return calcShadow(bodyRadiusKM: EngineConstants.earthEclipseRadiusKM, time: time, target: m, dir: e)
    }

    private static func peakEarthShadow(near centerTime: AstroTime) throws -> EngineShadow {
        let dt = 1.0 / 86400.0
        let window = 0.03
        let t1 = centerTime.addingDays(-window)
        let t2 = centerTime.addingDays(window)

        let peakTime = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let s1 = try earthShadow(at: t.addingTerrestrialDays(-dt))
            let s2 = try earthShadow(at: t.addingTerrestrialDays(dt))
            return (s2.r - s1.r) / dt
        }
        return try earthShadow(at: peakTime)
    }

    private static func shadowSemiDurationMinutes(
        centerTime: AstroTime,
        radiusLimit: Double,
        windowMinutes: Double
    ) -> Double {
        let window = windowMinutes / (24.0 * 60.0)
        let before = centerTime.addingDays(-window)
        let after = centerTime.addingDays(window)

        guard
            let s1 = try? EngineSearch.find(
                t1: before,
                t2: centerTime,
                dtToleranceSeconds: 1.0,
                { t in
                    let shadow = try earthShadow(at: t)
                    return -(shadow.r - radiusLimit)
                }
            ),
            let s2 = try? EngineSearch.find(
                t1: centerTime,
                t2: after,
                dtToleranceSeconds: 1.0,
                { t in
                    let shadow = try earthShadow(at: t)
                    return shadow.r - radiusLimit
                }
            )
        else {
            return -1.0
        }

        return (s2.universalTime - s1.universalTime) * ((24.0 * 60.0) / 2.0)
    }

    static func searchLunar(after startTime: AstroTime) throws -> LunarEclipse {
        let pruneLatitude = 1.8
        let moonRadius = EngineConstants.moonMeanRadiusKM
        var fmTime = startTime

        for _ in 0..<12 {
            let fullMoonTime = try EngineEvents.searchMoonPhase(
                targetLon: 180.0,
                after: fmTime,
                limitDays: 40.0
            )

            let moon = EngineMoonCore.calcMoon(centuries: fullMoonTime.terrestrialTime / 36525.0)
            if EngineConstants.rad2Deg * abs(moon.lat) < pruneLatitude {
                let shadow = try peakEarthShadow(near: fullMoonTime)
                if shadow.r < shadow.p + moonRadius {
                    var kind: EclipseKind = .penumbral
                    var obs = 0.0
                    var sdTotal = 0.0
                    var sdPartial = 0.0
                    let sdPenum = shadowSemiDurationMinutes(
                        centerTime: shadow.time,
                        radiusLimit: shadow.p + moonRadius,
                        windowMinutes: 200.0
                    )
                    guard sdPenum > 0.0 else {
                        throw AstronomyError.searchFailure
                    }

                    if shadow.r < shadow.k + moonRadius {
                        kind = .partial
                        sdPartial = shadowSemiDurationMinutes(
                            centerTime: shadow.time,
                            radiusLimit: shadow.k + moonRadius,
                            windowMinutes: sdPenum
                        )
                        guard sdPartial > 0.0 else {
                            throw AstronomyError.searchFailure
                        }

                        if shadow.r + moonRadius < shadow.k {
                            kind = .total
                            obs = 1.0
                            sdTotal = shadowSemiDurationMinutes(
                                centerTime: shadow.time,
                                radiusLimit: shadow.k - moonRadius,
                                windowMinutes: sdPartial
                            )
                            guard sdTotal > 0.0 else {
                                throw AstronomyError.searchFailure
                            }
                        } else {
                            obs = obscuration(a: moonRadius, b: shadow.k, c: shadow.r)
                        }
                    }

                    return LunarEclipse(
                        kind: kind,
                        peak: shadow.time,
                        obscuration: obs,
                        penumbralDuration: sdPenum,
                        partialDuration: sdPartial,
                        totalDuration: sdTotal
                    )
                }
            }

            fmTime = fullMoonTime.addingDays(10.0)
        }

        throw AstronomyError.internalError
    }

    static func nextLunar(after prevEclipseTime: AstroTime) throws -> LunarEclipse {
        try searchLunar(after: prevEclipseTime.addingDays(10.0))
    }

    // MARK: - Global Solar Eclipse

    private static func moonShadow(at time: AstroTime) throws -> EngineShadow {
        let s = try EnginePositions.geoVector(of: .sun, at: time, aberration: .corrected)
        let m = try EnginePositions.geoMoon(at: time)
        let e = Vector3D(x: -m.x, y: -m.y, z: -m.z, time: time)
        let dir = Vector3D(x: m.x - s.x, y: m.y - s.y, z: m.z - s.z, time: time)
        return calcShadow(bodyRadiusKM: EngineConstants.moonMeanRadiusKM, time: time, target: e, dir: dir)
    }

    private static func peakMoonShadow(near centerTime: AstroTime) throws -> EngineShadow {
        let dt = 1.0 / 86400.0
        let window = 0.03
        let t1 = centerTime.addingDays(-window)
        let t2 = centerTime.addingDays(window)

        let peakTime = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let s1 = try moonShadow(at: t.addingTerrestrialDays(-dt))
            let s2 = try moonShadow(at: t.addingTerrestrialDays(dt))
            return (s2.r - s1.r) / dt
        }
        return try moonShadow(at: peakTime)
    }

    private static func geoidIntersect(_ shadow: EngineShadow) throws -> GlobalSolarEclipse {
        let tilt = EngineRotation.earthTilt(at: shadow.time)
        let rot = EngineRotation.eqjToEqd(at: shadow.time, tilt: tilt)

        let (vx0, vy0, vz0) = EngineMath.rotate(rot, shadow.dir.x, shadow.dir.y, shadow.dir.z)
        let (ex0, ey0, ez0) = EngineMath.rotate(rot, shadow.target.x, shadow.target.y, shadow.target.z)

        let kmPerAU = EngineConstants.kmPerAU
        let flattening = EngineConstants.earthFlattening
        let vx = vx0 * kmPerAU
        let vy = vy0 * kmPerAU
        let vz = vz0 * (kmPerAU / flattening)
        let ex = ex0 * kmPerAU
        let ey = ey0 * kmPerAU
        let ez = ez0 * (kmPerAU / flattening)

        let earthR = EngineConstants.earthEquatorialRadiusKM
        let a = vx * vx + vy * vy + vz * vz
        let b = -2.0 * (vx * ex + vy * ey + vz * ez)
        let c = (ex * ex + ey * ey + ez * ez) - earthR * earthR
        let radic = b * b - 4.0 * a * c

        if radic > 0.0 {
            let u = (-b - sqrt(radic)) / (2.0 * a)
            let px = u * vx - ex
            let py = u * vy - ey
            let pz = (u * vz - ez) * flattening

            let proj = hypot(px, py) * (flattening * flattening)
            let latitude: Double
            if proj == 0.0 {
                latitude = pz > 0.0 ? 90.0 : -90.0
            } else {
                latitude = EngineConstants.rad2Deg * atan(pz / proj)
            }

            let gast = EngineRotation.siderealTime(at: shadow.time, tilt: tilt)
            var longitude = fmod((EngineConstants.rad2Deg * atan2(py, px)) - (15.0 * gast), 360.0)
            if longitude <= -180.0 {
                longitude += 360.0
            } else if longitude > 180.0 {
                longitude -= 360.0
            }

            let inv = EngineRotation.inverse(rot)
            let (ox0, oy0, oz0) = EngineMath.rotate(inv, px / kmPerAU, py / kmPerAU, pz / kmPerAU)
            let obsLunacentric = Vector3D(
                x: ox0 + shadow.target.x,
                y: oy0 + shadow.target.y,
                z: oz0 + shadow.target.z,
                time: shadow.time
            )

            let surface = calcShadow(
                bodyRadiusKM: EngineConstants.moonPolarRadiusKM,
                time: shadow.time,
                target: obsLunacentric,
                dir: shadow.dir
            )
            if surface.r > 1.0e-9 || surface.r < 0.0 {
                throw AstronomyError.internalError
            }

            let kind = eclipseKindFromUmbra(surface.k)
            let obs = (kind == .total) ? 1.0 : solarEclipseObscuration(hm: shadow.dir, lo: obsLunacentric)

            return GlobalSolarEclipse(
                kind: kind,
                peak: shadow.time,
                obscuration: obs,
                distance: shadow.r,
                latitude: latitude,
                longitude: longitude
            )
        }

        return GlobalSolarEclipse(
            kind: .partial,
            peak: shadow.time,
            obscuration: .nan,
            distance: shadow.r,
            latitude: nil,
            longitude: nil
        )
    }

    static func searchGlobalSolar(after startTime: AstroTime) throws -> GlobalSolarEclipse {
        let pruneLatitude = 1.8
        let earthMeanRadius = EngineConstants.earthMeanRadiusKM
        var nmTime = startTime

        for _ in 0..<12 {
            let newMoonTime = try EngineEvents.searchMoonPhase(
                targetLon: 0.0,
                after: nmTime,
                limitDays: 40.0
            )

            let moon = EngineMoonCore.calcMoon(centuries: newMoonTime.terrestrialTime / 36525.0)
            if EngineConstants.rad2Deg * abs(moon.lat) < pruneLatitude {
                let shadow = try peakMoonShadow(near: newMoonTime)
                if shadow.r < shadow.p + earthMeanRadius {
                    return try geoidIntersect(shadow)
                }
            }

            nmTime = newMoonTime.addingDays(10.0)
        }

        throw AstronomyError.internalError
    }

    static func nextGlobalSolar(after prevEclipseTime: AstroTime) throws -> GlobalSolarEclipse {
        try searchGlobalSolar(after: prevEclipseTime.addingDays(10.0))
    }

    // MARK: - Local Solar Eclipse

    private static func localMoonShadow(
        at time: AstroTime,
        observer: Observer
    ) throws -> EngineShadow {
        let obsVec = EngineObserver.observerVector(at: time, observer: observer, equator: .j2000)
        let s = try EnginePositions.geoVector(of: .sun, at: time, aberration: .corrected)
        let m = try EnginePositions.geoMoon(at: time)

        let o = Vector3D(x: obsVec.x - m.x, y: obsVec.y - m.y, z: obsVec.z - m.z, time: time)
        let dir = Vector3D(x: m.x - s.x, y: m.y - s.y, z: m.z - s.z, time: time)

        return calcShadow(
            bodyRadiusKM: EngineConstants.moonMeanRadiusKM,
            time: time,
            target: o,
            dir: dir
        )
    }

    private static func peakLocalMoonShadow(
        near centerTime: AstroTime,
        observer: Observer
    ) throws -> EngineShadow {
        let dt = 1.0 / 86400.0
        let window = 0.2
        let t1 = centerTime.addingDays(-window)
        let t2 = centerTime.addingDays(window)

        let peakTime = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let s1 = try localMoonShadow(at: t.addingTerrestrialDays(-dt), observer: observer)
            let s2 = try localMoonShadow(at: t.addingTerrestrialDays(dt), observer: observer)
            return (s2.r - s1.r) / dt
        }
        return try localMoonShadow(at: peakTime, observer: observer)
    }

    private static func calcSunAltitudeEvent(
        observer: Observer,
        at time: AstroTime
    ) throws -> EclipseEvent {
        let gc = try EnginePositions.geoVector(of: .sun, at: time, aberration: .corrected)
        let hor = try EngineObserver.horizon(
            geocentric: gc,
            at: time,
            observer: observer,
            refraction: .normal
        )
        return EclipseEvent(time: time, altitude: hor.altitude)
    }

    private static func localEclipseTransition(
        observer: Observer,
        direction: Double,
        isTotal: Bool,
        t1: AstroTime,
        t2: AstroTime
    ) throws -> EclipseEvent {
        let crossing = try EngineSearch.find(t1: t1, t2: t2, dtToleranceSeconds: 1.0) { t in
            let shadow = try localMoonShadow(at: t, observer: observer)
            let dist = isTotal ? (abs(shadow.k) - shadow.r) : (shadow.p - shadow.r)
            return direction * dist
        }
        return try calcSunAltitudeEvent(observer: observer, at: crossing)
    }

    private static func localEclipse(
        shadow: EngineShadow,
        observer: Observer
    ) throws -> LocalSolarEclipse {
        let partialWindow = 0.2
        let totalWindow = 0.01

        let peak = try calcSunAltitudeEvent(observer: observer, at: shadow.time)
        let pStart = shadow.time.addingDays(-partialWindow)
        let pEnd = shadow.time.addingDays(partialWindow)

        let partialBegin = try localEclipseTransition(
            observer: observer,
            direction: 1.0,
            isTotal: false,
            t1: pStart,
            t2: shadow.time
        )
        let partialEnd = try localEclipseTransition(
            observer: observer,
            direction: -1.0,
            isTotal: false,
            t1: shadow.time,
            t2: pEnd
        )

        let totalBegin: EclipseEvent?
        let totalEnd: EclipseEvent?
        let kind: EclipseKind
        let obs: Double

        if shadow.r < abs(shadow.k) {
            let tStart = shadow.time.addingDays(-totalWindow)
            let tEnd = shadow.time.addingDays(totalWindow)
            totalBegin = try localEclipseTransition(
                observer: observer,
                direction: 1.0,
                isTotal: true,
                t1: tStart,
                t2: shadow.time
            )
            totalEnd = try localEclipseTransition(
                observer: observer,
                direction: -1.0,
                isTotal: true,
                t1: shadow.time,
                t2: tEnd
            )
            kind = eclipseKindFromUmbra(shadow.k)
            obs = (kind == .total) ? 1.0 : solarEclipseObscuration(hm: shadow.dir, lo: shadow.target)
        } else {
            totalBegin = nil
            totalEnd = nil
            kind = .partial
            obs = solarEclipseObscuration(hm: shadow.dir, lo: shadow.target)
        }

        return LocalSolarEclipse(
            kind: kind,
            obscuration: obs,
            partialBegin: partialBegin,
            totalBegin: totalBegin,
            peak: peak,
            totalEnd: totalEnd,
            partialEnd: partialEnd
        )
    }

    static func searchLocalSolar(
        after startTime: AstroTime,
        observer: Observer
    ) throws -> LocalSolarEclipse {
        guard observer.height.isFinite, (-6_378_136.6...100_000.0).contains(observer.height) else {
            throw AstronomyError.invalidParameter
        }

        let pruneLatitude = 1.8
        var nmTime = startTime

        for _ in 0..<2000 {
            let newMoonTime = try EngineEvents.searchMoonPhase(
                targetLon: 0.0,
                after: nmTime,
                limitDays: 40.0
            )

            let moon = EngineMoonCore.calcMoon(centuries: newMoonTime.terrestrialTime / 36525.0)
            if EngineConstants.rad2Deg * abs(moon.lat) < pruneLatitude {
                let shadow = try peakLocalMoonShadow(near: newMoonTime, observer: observer)
                if shadow.r < shadow.p {
                    let eclipse = try localEclipse(shadow: shadow, observer: observer)
                    if eclipse.partialBegin.altitude > 0.0
                        || eclipse.peak.altitude > 0.0
                        || eclipse.partialEnd.altitude > 0.0
                    {
                        return eclipse
                    }
                }
            }

            nmTime = newMoonTime.addingDays(10.0)
        }

        throw AstronomyError.searchFailure
    }

    static func nextLocalSolar(
        after prevEclipseTime: AstroTime,
        observer: Observer
    ) throws -> LocalSolarEclipse {
        try searchLocalSolar(after: prevEclipseTime.addingDays(10.0), observer: observer)
    }
}
