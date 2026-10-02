import Foundation

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
        let utc: String
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
        let body: String
        let longitudeDegrees: Double
        let latitudeDegrees: Double
        let utc: String
        let direction: String
        let timeToleranceSeconds: Double
    }

    struct LunarEclipse: Decodable {
        let utc: String
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
            return AstroTime(date)
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
