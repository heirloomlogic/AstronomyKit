// Adapted from Astronomy Engine; its MIT notice is retained in THIRD_PARTY_NOTICES.
import Foundation

/// Geographic observer coordinates used by the pilot.
public struct PilotObserver: Sendable {
    /// Geographic latitude in degrees north.
    public let latitude: Double
    /// Geographic longitude in degrees east.
    public let longitude: Double
    /// Elevation in meters above mean sea level.
    public let height: Double

    /// Stores observer coordinates without normalization.
    public init(latitude: Double, longitude: Double, height: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.height = height
    }
}

/// Topocentric Sun coordinates and light-time branch diagnostics.
public struct PilotObservation: Sendable {
    /// Geometric altitude in degrees, with no refraction correction.
    public let altitude: Double
    /// Right ascension of date in hours.
    public let rightAscension: Double
    /// Declination of date in degrees.
    public let declination: Double
    /// Topocentric distance in AU.
    public let distance: Double
    /// Backdated geocentric Sun vector in J2000 equatorial AU.
    public let geocentric: PilotVector
    /// The number of light-time iterations executed.
    public let iterations: Int
    /// The number of full-series branches selected during light-time evaluation, including cache replay.
    public let fallbackEvaluations: Int
}

extension SunPilot {
    /// Calculates one observation with a fresh caller-owned evaluator.
    public static func observe(time: PilotTime, observer: PilotObserver) throws -> PilotObservation {
        var evaluator = PilotEvaluator()
        return try evaluator.observe(time: time, observer: observer)
    }
}

/// Caller-owned numerical caches; each evaluator is used serially.
public struct PilotEvaluator {
    var earthCache: [(UInt64, PilotEarth)] = []
    var orientationCache: [(UInt64, PilotOrientation)] = []

    let fullSeriesAmplitudeScale: Double

    /// Creates an evaluator; a nonunit amplitude scale perturbs fallback for development tests.
    public init(fullSeriesAmplitudeScale: Double = 1) {
        self.fullSeriesAmplitudeScale = fullSeriesAmplitudeScale
    }

    mutating func earth(tt: Double) throws -> PilotEarth {
        if let entry = earthCache.first(where: { $0.0 == tt.bitPattern }) { return entry.1 }
        let value = try SunPilot.earth(tt: tt, fullSeriesAmplitudeScale: fullSeriesAmplitudeScale)
        if earthCache.count == 32 { earthCache.removeFirst() }
        earthCache.append((tt.bitPattern, value))
        return value
    }

    mutating func orientation(tt: Double) -> PilotOrientation {
        if let entry = orientationCache.first(where: { $0.0 == tt.bitPattern }) { return entry.1 }
        let value = PilotOrientation(tt: tt)
        if orientationCache.count == 32 { orientationCache.removeFirst() }
        orientationCache.append((tt.bitPattern, value))
        return value
    }

    /// Calculates geometric Sun altitude with aberration, light-time, and observer parallax.
    public mutating func observe(time: PilotTime, observer: PilotObserver) throws -> PilotObservation {
        guard time.tt.isFinite, abs(time.tt) <= 1_461_000 else {
            throw PilotError.badTime
        }
        guard time.ut.isFinite, observer.latitude.isFinite, observer.longitude.isFinite,
            observer.height.isFinite
        else {
            throw PilotError.badTime
        }
        var ltime = time
        var sun = PilotVector(x: 0, y: 0, z: 0)
        var iterations = 0
        var fallbacks = 0
        for iteration in 0..<10 {
            let earth = try earth(tt: ltime.tt)
            if earth.usedFallback { fallbacks += 1 }
            sun = earth.vector.negative
            let distance = sun.length
            guard distance <= 173.1446326846693 else { throw PilotError.invalidParameter }
            let next = time.adding(days: -distance / 173.1446326846693)
            iterations = iteration + 1
            if abs(next.tt - ltime.tt) < 1e-9 { break }
            if iteration == 9 { throw PilotError.noConverge }
            ltime = next
        }
        let orientation = orientation(tt: time.tt)
        let sidereal = orientation.sidereal(time: time)
        let phi = observer.latitude * PilotOrientation.radians
        let sinphi = sin(phi)
        let cosphi = cos(phi)
        let flattening = 0.996647180302104
        let c = 1.0 / hypot(cosphi, sinphi * flattening)
        let s = c * (flattening * flattening)
        let ach = 6378.1366 * c + observer.height / 1000.0
        let ash = 6378.1366 * s + observer.height / 1000.0
        let local = (15.0 * sidereal + observer.longitude) * PilotOrientation.radians
        let siteOfDate = PilotVector(
            x: ach * cosphi * cos(local) / 1.4959787069098932e8,
            y: ach * cosphi * sin(local) / 1.4959787069098932e8,
            z: ash * sinphi / 1.4959787069098932e8)
        let site = orientation.precession.apply(
            orientation.nutation.apply(siteOfDate, inverse: true), inverse: true)
        let topocentric = orientation.nutation.apply(orientation.precession.apply(sun - site))
        let xy = topocentric.x * topocentric.x + topocentric.y * topocentric.y
        let distance = sqrt(xy + topocentric.z * topocentric.z)
        let ra: Double
        let dec: Double
        if xy == 0 {
            guard topocentric.z != 0 else { throw PilotError.badVector }
            ra = 0
            dec = topocentric.z < 0 ? -90 : 90
        } else {
            var angle = (12.0 / Double.pi) * atan2(topocentric.y, topocentric.x)
            if angle < 0 { angle += 24 }
            ra = angle
            dec = (180.0 / Double.pi) * atan2(topocentric.z, sqrt(xy))
        }
        let lat = observer.latitude * PilotOrientation.radians
        let lon = observer.longitude * PilotOrientation.radians
        let rarad = ra * (Double.pi / 12.0)
        let decrad = dec * PilotOrientation.radians
        let sinlat = sin(lat)
        let coslat = cos(lat)
        let sinlon = sin(lon)
        let coslon = cos(lon)
        let p = PilotVector(x: cos(decrad) * cos(rarad), y: cos(decrad) * sin(rarad), z: sin(decrad))
        let angle = -15.0 * sidereal * PilotOrientation.radians
        let cosang = cos(angle)
        let sinang = sin(angle)
        func projection(_ x: Double, _ y: Double, _ z: Double) -> Double {
            let rotatedX = cosang * x + sinang * y
            let rotatedY = -sinang * x + cosang * y
            return p.x * rotatedX + p.y * rotatedY + p.z * z
        }
        let pn = projection(-sinlat * coslon, -sinlat * sinlon, coslat)
        let pw = projection(sinlon, -coslon, 0)
        let pz = projection(coslat * coslon, coslat * sinlon, sinlat)
        let altitude = 90.0 - atan2(hypot(pn, pw), pz) * (180.0 / Double.pi)
        guard altitude.isFinite, ra.isFinite, dec.isFinite, distance.isFinite else {
            throw PilotError.badTime
        }
        return PilotObservation(
            altitude: altitude, rightAscension: ra, declination: dec, distance: distance,
            geocentric: sun, iterations: iterations, fallbackEvaluations: fallbacks)
    }
}
