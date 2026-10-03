import Foundation
import Testing

@testable import AstronomyKit

struct IndependentReferenceArchive: Decodable {
    let schemaVersion: Int
    let provenance: [String: Provenance]
    let observations: [Observation]
    let vectors: [Vector]
    let seasons: [Season]
    let lunarPhases: [LunarPhase]
    let lunarNodes: [LunarNode]
    let lunarApsides: [Apsis]
    let earthApsides: [Apsis]
    let riseSet: [RiseSet]
    let lunarEclipses: [LunarEclipse]
    let globalSolarEclipses: [GlobalSolarEclipse]
    let localSolarEclipses: [LocalSolarEclipse]
    let transits: [Transit]

    struct Provenance: Decodable {
        let version: String?
        let serviceVersion: String?
        let frame: String
        let origin: String
        let units: String
        let timeScale: String
        let aberration: String
        let refraction: String
        let domain: String
        let license: String
        let url: String
        let recipe: String
    }

    struct Observation: Decodable {
        let series: String
        let body: String
        let utc: String
        let rightAscensionDegrees: Double
        let declinationDegrees: Double
        let rightAscensionRateArcsecondsPerHour: Double
        let declinationRateArcsecondsPerHour: Double
        let apparentRangeAU: Double
        let rangeRateKmPerSecond: Double
        let eclipticLongitudeDegrees: Double
        let eclipticLatitudeDegrees: Double
        let angularToleranceArcminutes: Double
    }

    struct Vector: Decodable {
        let body: String
        let origin: String
        let julianDateTDB: Double
        let tdb: String
        let positionAU: [Double]
        let velocityAUPerDay: [Double]
        let relativeTolerance: Double?
        let sanityToleranceAU: Double?
    }

    struct Season: Decodable {
        let event: String
        let utc: String
        let toleranceSeconds: Double
    }

    struct LunarPhase: Decodable {
        let phase: String
        let sourceTime: String
        let toleranceSeconds: Double
    }

    struct LunarNode: Decodable {
        let kind: String
        let utc: String
        let rightAscensionHours: Double
        let declinationDegrees: Double
        let timeToleranceSeconds: Double
        let positionToleranceArcminutes: Double
    }

    struct Apsis: Decodable {
        let kind: String
        let utc: String
        let timeToleranceSeconds: Double
        let distanceAU: Double?
        let distanceKM: Double?
        let distanceToleranceAU: Double?
        let distanceToleranceKM: Double?
    }

    struct RiseSet: Decodable {
        let sourceLine: Int
        let body: String
        let longitudeDegrees: Double
        let latitudeDegrees: Double
        let utc: String
        let direction: String
        let timeToleranceSeconds: Double
    }

    struct RiseSetStream: CustomTestStringConvertible {
        let body: String
        let longitudeDegrees: Double
        let latitudeDegrees: Double
        var events: [RiseSet]

        var testDescription: String {
            "\(body) \(longitudeDegrees)/\(latitudeDegrees), \(events.count) events"
        }
    }

    var riseSetStreams: [RiseSetStream] {
        var streams: [RiseSetStream] = []
        for event in riseSet {
            if let last = streams.indices.last,
                streams[last].body == event.body,
                streams[last].longitudeDegrees == event.longitudeDegrees,
                streams[last].latitudeDegrees == event.latitudeDegrees
            {
                streams[last].events.append(event)
            } else {
                streams.append(
                    RiseSetStream(
                        body: event.body,
                        longitudeDegrees: event.longitudeDegrees,
                        latitudeDegrees: event.latitudeDegrees,
                        events: [event]))
            }
        }
        return streams
    }

    struct LunarEclipse: Decodable {
        let universalTime: String
        let partialSemiDurationMinutes: Double
        let totalSemiDurationMinutes: Double
        let toleranceSeconds: Double
        let durationToleranceMinutes: Double
    }

    struct GlobalSolarEclipse: Decodable {
        let terrestrialTime: String
        let kind: String
        let latitudeDegrees: Double
        let longitudeDegrees: Double
        let timeToleranceSeconds: Double
        let locationToleranceDegrees: Double
    }

    struct LocalSolarEclipse: Decodable {
        let latitudeDegrees: Double
        let longitudeDegrees: Double
        let kind: String
        let partialBeginUTC: String
        let partialBeginAltitudeDegrees: Double
        let totalBeginUTC: String?
        let totalBeginAltitudeDegrees: Double?
        let peakUTC: String
        let peakAltitudeDegrees: Double
        let totalEndUTC: String?
        let totalEndAltitudeDegrees: Double?
        let partialEndUTC: String
        let partialEndAltitudeDegrees: Double
        let timeToleranceSeconds: Double
        let altitudeToleranceDegrees: Double
    }

    struct Transit: Decodable {
        let body: String
        let startUTC: String
        let peakUTC: String
        let finishUTC: String
        let separationArcminutes: Double
        let timeToleranceSeconds: Double
        let separationToleranceArcminutes: Double
    }

    static let shared: IndependentReferenceArchive = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/IndependentReferences/reference-fixtures.json")
        do {
            return try JSONDecoder().decode(IndependentReferenceArchive.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Independent reference fixture is invalid: \(error)")
        }
    }()
}

enum IndependentReferenceDate {
    static func civil(_ text: String) -> AstroTime {
        AstroTime(date(text))
    }

    static func universal(_ text: String, deltaTModel: DeltaTModel) -> AstroTime {
        AstroTime(ut: AstroTime.civilDays(of: date(text)), deltaTModel: deltaTModel)
    }

    private static func date(_ text: String) -> Date {
        let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        let isoMinuteFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        let minuteFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
            return formatter
        }()

        let horizonsFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MMM-dd HH:mm:ss.SSS"
            return formatter
        }()
        if let date = isoFormatter.date(from: text) ?? isoMinuteFormatter.date(from: text)
            ?? minuteFormatter.date(from: text) ?? horizonsFormatter.date(from: text)
        {
            return date
        }
        fatalError("invalid reference date: \(text)")
    }

    static func terrestrial(julianDateTDB: Double) -> AstroTime {
        AstroTime(tt: julianDateTDB - 2_451_545.0)
    }

    static func terrestrialCalendar(_ text: String) -> AstroTime {
        AstroTime(tt: civil(text).universalTime)
    }

    static func seconds(_ lhs: AstroTime, _ rhs: AstroTime) -> Double {
        abs(lhs.date.timeIntervalSince(rhs.date))
    }

    static func universalSeconds(_ lhs: AstroTime, _ rhs: AstroTime) -> Double {
        abs(lhs.universalTime - rhs.universalTime) * 86_400
    }

    static func terrestrialSeconds(_ lhs: AstroTime, _ rhs: AstroTime) -> Double {
        abs(lhs.terrestrialTime - rhs.terrestrialTime) * 86_400
    }
}

enum IndependentReferenceMath {
    static func angularSeparationArcminutes(
        raDegrees1: Double, decDegrees1: Double, raDegrees2: Double, decDegrees2: Double
    ) -> Double {
        let ra1 = raDegrees1 * .pi / 180
        let ra2 = raDegrees2 * .pi / 180
        let dec1 = decDegrees1 * .pi / 180
        let dec2 = decDegrees2 * .pi / 180
        let cosine = sin(dec1) * sin(dec2) + cos(dec1) * cos(dec2) * cos(ra1 - ra2)
        return acos(min(1, max(-1, cosine))) * 180 / .pi * 60
    }

    static func wrappedDifference(_ lhs: Double, _ rhs: Double) -> Double {
        var difference = lhs - rhs
        while difference < -180 { difference += 360 }
        while difference > 180 { difference -= 360 }
        return difference
    }

    static func relativeVectorError(actual: Vector3D, expected: [Double]) -> Double {
        let dx = actual.x - expected[0]
        let dy = actual.y - expected[1]
        let dz = actual.z - expected[2]
        let difference = (dx * dx + dy * dy + dz * dz).squareRoot()
        let magnitude =
            (expected[0] * expected[0] + expected[1] * expected[1] + expected[2] * expected[2])
            .squareRoot()
        return difference / magnitude
    }

    static func maximumComponentError(actual: Vector3D, expected: [Double]) -> Double {
        max(abs(actual.x - expected[0]), abs(actual.y - expected[1]), abs(actual.z - expected[2]))
    }

    static func sphericalDistanceDegrees(
        latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double
    ) -> Double {
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let deltaLongitude = (longitude1 - longitude2) * .pi / 180
        let cosine = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaLongitude)
        return acos(min(1, max(-1, cosine))) * 180 / .pi
    }
}

// Rate residuals are sampled diagnostics; this archive supplies no rate accuracy allowance.
struct IndependentRangeRateArchive: Decodable {
    let status: String
    let results: [Record]

    struct Record: Decodable {
        let body: String
        let mode: String
        let julianDateTT: Double
        let classification: String
        let reference: Reference
        let production: Production
        let referenceRateKmPerSecond: Double

        struct Reference: Decodable {
            let positionAU: [Double]
            let velocityAUPerDay: [Double]
            let rangeRateAUPerDay: Double
        }

        struct Production: Decodable {
            let rateAUPerTTDay: Double
            let correctedRateAUPerTTDay: Double
        }
    }

    static func load() throws -> Self {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Documentation/Migration/range-rate-investigation.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

@Suite("Independent radial-rate diagnostic replay")
struct IndependentRangeRateTests {
    @Test("Reference radial projections preserve units and signed motion")
    func referenceProjection() throws {
        let archive = try IndependentRangeRateArchive.load()
        #expect(archive.status == "sampled-diagnostic-without-accuracy-allowance")
        #expect(archive.results.count == 5_035)
        #expect(archive.results.filter { $0.classification == "geometric-state-matched" }.count == 2_650)
        #expect(
            archive.results.filter { $0.classification == "received-light-unmatched-derivative-and-origin" }.count
                == 2_385)
        for row in archive.results {
            let p = row.reference.positionAU
            let v = row.reference.velocityAUPerDay
            let radius = hypot(hypot(p[0], p[1]), p[2])
            let projection = (p[0] * v[0] + p[1] * v[1] + p[2] * v[2]) / radius
            // Integrity at the raw table's rounding scale, not independent model accuracy.
            #expect(abs(projection - row.reference.rangeRateAUPerDay) <= 1e-14)
            #expect(
                abs(row.referenceRateKmPerSecond - row.reference.rangeRateAUPerDay * 149_597_870.7 / 86_400) <= 1e-12)
        }
    }

    @Test("Public state rates reproduce the recorded production diagnostics")
    func publicStateReplay() throws {
        for row in try IndependentRangeRateArchive.load().results {
            let body = try #require(CelestialBody.allCases.first { $0.name == row.body })
            let time = AstroTime(tt: row.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
            let rate: Double
            if row.mode == "heliocentric" {
                let state = try body.heliocentricState(at: time)
                let p = state.position
                let v = state.velocity
                rate = (p.x * v.x + p.y * v.y + p.z * v.z) / hypot(hypot(p.x, p.y), p.z)
            } else {
                rate = try body.geocentricEclipticState(at: time, aberration: .none).distanceRate
                let corrected = try body.geocentricEclipticState(at: time, aberration: .corrected).distanceRate
                #expect(abs(corrected - row.production.correctedRateAUPerTTDay) <= 1e-12)
            }
            // Production replay tolerance is separate from the unbounded independent residual.
            #expect(abs(rate - row.production.rateAUPerTTDay) <= 1e-12)
        }
    }
}
