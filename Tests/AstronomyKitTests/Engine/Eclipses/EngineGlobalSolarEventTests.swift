import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Native global solar eclipses")
struct EngineGlobalSolarEventTests {
    typealias Events = Engine.Events

    @Test("Published TD calendar fields are epoch arithmetic without UTC conversion")
    func terrestrialReferenceEpochs() {
        for (text, expected) in [
            ("1800-04-24T00:24:00Z", -72935.48333333334),
            ("2024-04-08T18:18:29Z", 8864.262835648147),
            ("2099-03-21T22:54:32Z", 36239.45453703704),
        ] {
            #expect(IndependentReferenceDate.terrestrialCalendar(text).terrestrialTime == expected)
        }
    }

    @Test("Published non-central annular and total events retain their kind")
    func noncentral() throws {
        for (tt, kind) in [(5231.753159722222, "annular"), (15804.290150462963, "total")] {
            let event = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: tt - 10, deltaTModel: .espenakMeeus))
            #expect(event.kind.rawValue == kind)
            #expect(abs(event.peak.tt - tt) * 86400 < 453.6)
            #expect(event.latitude != nil && event.longitude != nil)
            #expect(event.obscuration > 0 && event.obscuration <= 1)
        }
    }

    @Test("Geoid axis intersections distinguish contact from representable misses")
    func geoid() throws {
        let time = Engine.Time(tt: 0, deltaTModel: .espenakMeeus)
        func point(_ y: Double) throws -> SIMD3<Double>? {
            try Engine.Shadows.axisIntersection(
                origin: SIMD3(-3, y, 0), direction: SIMD3(1, 0, 0), radii: SIMD3(1, 1, 0.5))
        }
        #expect(try point(1) == SIMD3(0, 1, 0))
        #expect(try point(1.nextUp) == nil)
        #expect(try point(1.nextDown) != nil)
        #expect(try point(0) == SIMD3(-1, 0, 0))
        #expect(time.isValid)
    }
    struct Reference: Decodable {
        let events: [Event]
        let rp1301: Report
        struct Event: Decodable {
            let date: String
            let tt: Double
            let pathType: String
            let kindAtPeak: String
            let latitude: Double
            let longitude: Double
            let timeToleranceSeconds: Double
            let locationToleranceDegrees: Double
        }
        struct Report: Decodable {
            let greatestTT: Double
            let ratioLower: Double
            let ratioUpper: Double
            let samples: [Sample]
        }
        struct Sample: Decodable {
            let ut: Double
            let tt: Double
            let lower: Double
            let upper: Double
        }
    }

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func write(_ value: Any, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["GLOBAL_SOLAR_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url.appendingPathComponent(name + ".json"))
    }

    static func separation(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat1 - lat2) * r / 2), 2) + cos(lat1 * r) * cos(lat2 * r) * pow(sin((lon1 - lon2) * r / 2), 2)
        return 2 * asin(sqrt(min(1, max(0, a)))) / r
    }

    @Test("NASA global kinds, TD peaks, and locations retain existing allowances")
    func published() throws {
        let references = try JSONDecoder().decode(
            Reference.self,
            from: Data(contentsOf: Self.root.appendingPathComponent("Scripts/eclipse-data/global-references.json")))
        var rows: [[String: Any]] = []
        func check(
            _ label: String, _ tt: Double, _ kind: String, _ lat: Double, _ lon: Double, _ seconds: Double,
            _ degrees: Double
        ) throws {
            let event = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: tt - 10, deltaTModel: .espenakMeeus))
            #expect(event.kind.rawValue == kind)
            #expect(abs(event.peak.tt - tt) * 86400 <= seconds)
            var row: [String: Any] = [
                "id": label, "sourceTT": tt, "tt": event.peak.tt, "ut": event.peak.ut, "kind": event.kind.rawValue,
                "distanceKm": event.distanceKilometers, "physicalTT": event.physicalPeak.tt,
            ]
            if kind == "partial" {
                #expect(event.latitude == nil && event.longitude == nil && event.obscuration.isNaN)
                row["obscuration"] = NSNull()
                row["latitude"] = NSNull()
                row["longitude"] = NSNull()
            } else {
                let latitude = try #require(event.latitude)
                let longitude = try #require(event.longitude)
                #expect(Self.separation(latitude, longitude, lat, lon) <= degrees)
                #expect((-90...90).contains(latitude) && longitude > -180 && longitude <= 180)
                #expect(event.obscuration > 0 && event.obscuration <= 1)
                if kind == "total" { #expect(event.obscuration == 1) } else { #expect(event.obscuration < 1) }
                row["obscuration"] = event.obscuration
                row["latitude"] = latitude
                row["longitude"] = longitude
            }
            rows.append(row)
        }
        for row in IndependentReferenceArchive.shared.globalSolarEclipses {
            let time = IndependentReferenceDate.terrestrialCalendar(row.terrestrialTime)
            try check(
                row.terrestrialTime, time.terrestrialTime, row.kind, row.latitudeDegrees, row.longitudeDegrees,
                row.timeToleranceSeconds, row.locationToleranceDegrees)
        }
        for row in references.events {
            try check(
                row.date, row.tt, row.kindAtPeak, row.latitude, row.longitude, row.timeToleranceSeconds,
                row.locationToleranceDegrees)
        }
        try Self.write(rows, name: "published")
    }

    @Test("RP1301 direct annular area samples retain their UT plus fixed Delta T meaning")
    func annularArea() throws {
        let references = try JSONDecoder().decode(
            Reference.self,
            from: Data(contentsOf: Self.root.appendingPathComponent("Scripts/eclipse-data/global-references.json")))
        var rows: [[String: Any]] = []
        for sample in references.rp1301.samples {
            let time = Engine.Time(ut: sample.ut, tt: sample.tt, deltaTModel: .espenakMeeus)
            let surface = try Events.solarSurface(at: time)
            #expect(surface.kind == .annular)
            #expect(surface.obscuration >= sample.lower && surface.obscuration <= sample.upper)
            #expect(surface.separationRadians < 1e-12)
            rows.append([
                "tt": time.tt, "ut": time.ut, "obscuration": surface.obscuration,
                "sunRadiusRadians": surface.sunRadiusRadians, "moonRadiusRadians": surface.moonRadiusRadians,
                "separationRadians": surface.separationRadians,
            ])
        }
        let time = Engine.Time(tt: references.rp1301.greatestTT, deltaTModel: .espenakMeeus)
        let surface = try Events.solarSurface(at: time)
        // Record the finer G0 discrepancy separately; the two-k report does not disclose its modified magnitude algebra.
        rows.append([
            "tt": time.tt, "ut": time.ut, "obscuration": surface.obscuration,
            "sunRadiusRadians": surface.sunRadiusRadians, "moonRadiusRadians": surface.moonRadiusRadians,
            "separationRadians": surface.separationRadians,
        ])
        try Self.write(rows, name: "area")
    }

    @Test("Canonical new moons retain identity across callers and midnight")
    func canonicalIdentity() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            for seed in [-100000.0, -2062, 0, 8863, 100000] {
                let found = try #require(
                    try Events.searchMoonPhase(0, after: Engine.Time(tt: seed, deltaTModel: model), limitDays: 40))
                let canonical = try Events.canonicalNewMoon(found)
                for delta in [-0.0001, -1e-9, 0, 1e-9, 0.0001] {
                    let other = try Events.canonicalNewMoon(Engine.Time(tt: found.tt + delta, deltaTModel: model))
                    #expect(other.tt.bitPattern == canonical.tt.bitPattern)
                }
            }
            for seed in [4.nextDown, 4, 4.nextUp] {
                let result = try Events.canonicalEclipsePhase(Engine.Time(tt: seed, deltaTModel: model)) { $0.tt - 4 }
                #expect(result.tt == 4)
            }
            for endpoint in [-Engine.acceptedTTDays, Engine.acceptedTTDays] {
                let result = try Events.canonicalEclipsePhase(Engine.Time(tt: endpoint, deltaTModel: model)) {
                    $0.tt - endpoint
                }
                #expect(result.tt == endpoint)
            }
        }
    }

    @Test("Global peak inclusion uses the canonical physical peak and represented cutoff")
    func boundaryAndProgress() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let first = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: 8850, deltaTModel: model))
            let peak = first.physicalPeak.tt
            let cutoff = peak + 1 / 86400
            for start in [peak - 1 / 86400, peak, cutoff.nextDown, cutoff] {
                let event = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: start, deltaTModel: model))
                #expect(event.physicalPeak.tt.bitPattern == peak.bitPattern)
                #expect(event.peak.tt >= start && event.peak.deltaTModel == model)
            }
            let clamped = try #require(
                Events.resolvedGlobalSolarEclipse(first, atOrAfter: Engine.Time(tt: cutoff, deltaTModel: model)))
            #expect(
                Events.resolvedGlobalSolarEclipse(
                    clamped, atOrAfter: Engine.Time(tt: cutoff.nextUp, deltaTModel: model)) == nil)
            for start in [cutoff.nextUp, peak + 2 / 86400] {
                let next = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: start, deltaTModel: model))
                #expect(next.physicalPeak.tt > cutoff)
            }
            let next = try Events.nextGlobalSolarEclipse(after: first)
            #expect(next.peak.tt > first.peak.tt && next.peak.deltaTModel == model)
        }
    }

    @Test("Global domain and phase callback failures propagate")
    func errors() throws {
        for tt in [Double.nan, .infinity, -.infinity, Engine.acceptedTTDays.nextUp, -Engine.acceptedTTDays.nextUp] {
            #expect(throws: AstronomyError.badTime) {
                try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: tt, deltaTModel: .espenakMeeus))
            }
        }
        let lower = try Events.searchGlobalSolarEclipse(
            after: Engine.Time(tt: -Engine.acceptedTTDays, deltaTModel: .espenakMeeus))
        #expect(lower.peak.tt >= -Engine.acceptedTTDays && lower.peak.tt <= Engine.acceptedTTDays)
        #expect(throws: AstronomyError.badTime) {
            try Events.searchGlobalSolarEclipse(
                after: Engine.Time(tt: Engine.acceptedTTDays, deltaTModel: .espenakMeeus))
        }
        let valid = Engine.Time(tt: 0, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.searchFailure) { try Events.canonicalEclipsePhase(valid) { _ in 1 } }
        #expect(throws: AstronomyError.badTime) { try Events.canonicalEclipsePhase(valid) { _ in .nan } }
        #expect(throws: AstronomyError.invalidParameter) {
            try Events.canonicalEclipsePhase(valid) { _ in throw AstronomyError.invalidParameter }
        }
    }

    @Test("Ellipsoid and finite-cone geometry has independent analytic controls")
    func analyticGeometry() throws {
        typealias G = Engine.Shadows
        let radii = SIMD3<Double>(1, 1, 0.5)
        #expect(
            try G.axisIntersection(origin: SIMD3(0, 0, 3), direction: SIMD3(0, 0, -1), radii: radii) == SIMD3(0, 0, 0.5)
        )
        #expect(try G.axisIntersection(origin: SIMD3(-3, 0, 0), direction: SIMD3(-1, 0, 0), radii: radii) == nil)
        for origin in [SIMD3<Double>(.nan, 0, 0), SIMD3(.infinity, 0, 0)] {
            #expect(throws: AstronomyError.badVector) {
                try G.axisIntersection(origin: origin, direction: SIMD3(1, 0, 0), radii: radii)
            }
        }
        #expect(throws: AstronomyError.badVector) {
            try G.axisIntersection(origin: SIMD3(1, 0, 0), direction: .zero, radii: radii)
        }
        let closest = try G.closestPointToMissedAxis(origin: SIMD3(-3, 2, 0), direction: SIMD3(1, 0, 0), radii: radii)
        #expect(G.norm(closest - SIMD3(0, 1, 0)) < 1e-15)
        let hit = try G.coneSurfacePoint(
            origin: SIMD3(-3, 2, 0), unit: SIMD3(1, 0, 0), radiusAtOrigin: 1, slope: 0, radii: radii, seed: closest)
        #expect(hit == closest)
        #expect(
            try G.coneSurfacePoint(
                origin: SIMD3(-3, 2, 0), unit: SIMD3(1, 0, 0), radiusAtOrigin: 0.5, slope: 0, radii: radii,
                seed: closest) == nil)
    }

    @Test("A finite cone can hit away from the point closest to its axis")
    func tiltedCone() throws {
        typealias G = Engine.Shadows
        let seed = SIMD3<Double>(0, 1, 0)
        let radii = SIMD3<Double>(1, 1, 1)
        let threshold = 2 - 3 * 0.5 - sqrt(1.25)
        let point = try #require(
            try G.coneSurfacePoint(
                origin: SIMD3(-3, 2, 0), unit: SIMD3(1, 0, 0), radiusAtOrigin: threshold + 0.01, slope: 0.5,
                radii: radii, seed: seed))
        #expect(G.norm(point - SIMD3(0.5, 1, 0) / sqrt(1.25)) < 1e-14)
        #expect(
            try G.coneSurfacePoint(
                origin: SIMD3(-3, 2, 0), unit: SIMD3(1, 0, 0), radiusAtOrigin: threshold - 0.01, slope: 0.5,
                radii: radii, seed: seed) == nil)
        #expect(throws: AstronomyError.badVector) {
            try G.coneSurfacePoint(origin: .zero, unit: .zero, radiusAtOrigin: 1, slope: 0, radii: radii, seed: seed)
        }
    }

    @Test("Concentric angular discs produce area, not diameter magnitude")
    func angularDiscs() throws {
        let sunDistance = 150_000_000.0
        let sunAngle = asin(Events.solarEclipseSunRadius / sunDistance)
        let moonDistance = Events.solarEclipseMoonRadius / sin(sunAngle / 2)
        let result = try Events.solarDiscs(sun: SIMD3(sunDistance, 0, 0), moon: SIMD3(moonDistance, 0, 0), point: .zero)
        #expect(result.kind == .annular && abs(result.obscuration - 0.25) < 1e-15)
        #expect(throws: AstronomyError.badVector) {
            try Events.solarDiscs(sun: .zero, moon: SIMD3(moonDistance, 0, 0), point: .zero)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLOBAL_SOLAR_MEASUREMENT"] != nil))
    func resources() throws {
        func peakBytes() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1024
            #endif
        }
        let before = peakBytes()
        let cold = Date()
        var event = try Events.searchGlobalSolarEclipse(after: Engine.Time(tt: -36524.5, deltaTModel: .espenakMeeus))
        let coldSeconds = Date().timeIntervalSince(cold)
        let afterCold = peakBytes()
        var checksum = event.peak.tt
        let repeated = Date()
        for _ in 0..<99 {
            event = try Events.nextGlobalSolarEclipse(after: event)
            checksum += event.peak.tt
        }
        try Self.write(
            [
                "coldSeconds": coldSeconds, "nextSeconds": Date().timeIntervalSince(repeated), "nextCount": 99,
                "peakBeforeBytes": before, "peakAfterColdBytes": afterCold, "peakAfterWorkloadBytes": peakBytes(),
                "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], name: "resources")
    }
}
