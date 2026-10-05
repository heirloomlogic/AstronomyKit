import AstronomyKit
import Foundation

/// Development-only streaming access to public APIs for independent qualification.
func runAccuracyBatch() throws {
    AstronomyConfig.setDeltaTModel(.jplHorizons)
    while let line = readLine() {
        let data = Data(line.utf8)
        var output: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let operation = request["operation"] as? String
            else { throw RunnerError.usage }
            let deltaTModel: DeltaTModel
            switch request["deltaTModel"] as? String ?? "jpl-horizons" {
            case "jpl-horizons": deltaTModel = .jplHorizons
            case "espenak-meeus": deltaTModel = .espenakMeeus
            default: throw RunnerError.usage
            }
            AstronomyConfig.setDeltaTModel(deltaTModel)
            switch operation {
            case "position":
                guard let code = request["body"] as? Int32,
                    let celestialBody = CelestialBody(rawValue: code),
                    let mode = request["mode"] as? String,
                    let jd = request["julianDateTT"] as? Double,
                    jd.isFinite
                else { throw RunnerError.usage }
                let instant = AstroTime(tt: jd - 2_451_545, deltaTModel: .jplHorizons)
                let position: Vector3D
                switch mode {
                case "heliocentric": position = try celestialBody.heliocentricPosition(at: instant)
                case "geocentric-none":
                    position = try celestialBody.geocentricPosition(at: instant, aberration: .none)
                case "geocentric-default":
                    position = try celestialBody.geocentricPosition(at: instant)
                default: throw RunnerError.usage
                }
                output = [
                    "status": "success",
                    "julianDateTT": position.time.terrestrialTime + 2_451_545,
                    "positionAU": [position.x, position.y, position.z],
                ]
            case "lunar-apsides":
                guard let start = request["startJulianDateTT"] as? Double,
                    let stop = request["stopJulianDateTT"] as? Double,
                    start.isFinite, stop.isFinite, stop > start, stop - start <= 32
                else { throw RunnerError.usage }
                let events = try Moon.apsides(
                    from: AstroTime(tt: start - 2_451_545, deltaTModel: .jplHorizons),
                    to: AstroTime(tt: stop - 2_451_545, deltaTModel: .jplHorizons)
                )
                output = [
                    "status": "success",
                    "events": events.map {
                        [
                            "julianDateTT": $0.time.terrestrialTime + 2_451_545,
                            "kind": $0.kind == .pericenter ? "pericenter" : "apocenter",
                            "distanceAU": $0.distanceAU,
                        ] as [String: Any]
                    },
                ]
            case "planetary-apsides":
                guard let code = request["body"] as? Int32,
                    let celestialBody = CelestialBody(rawValue: code),
                    let start = request["startJulianDateTT"] as? Double,
                    let stop = request["stopJulianDateTT"] as? Double,
                    code >= 0, code <= 8,
                    start.isFinite, stop.isFinite, stop > start, stop - start <= 85_000
                else { throw RunnerError.usage }
                let startTime = AstroTime(tt: start - 2_451_545, deltaTModel: .jplHorizons)
                var event = try celestialBody.searchApsis(after: startTime)
                var events: [[String: Any]] = []
                for iteration in 0..<4_000 {
                    let jd = event.time.terrestrialTime + 2_451_545
                    if jd >= stop { break }
                    guard jd >= start, iteration < 3_999 else { throw RunnerError.usage }
                    events.append([
                        "julianDateTT": jd,
                        "kind": event.kind == .pericenter ? "pericenter" : "apocenter",
                        "distanceAU": event.distanceAU,
                    ])
                    event = try celestialBody.nextApsis(after: event)
                }
                output = ["status": "success", "events": events]
            case "lunar-nodes":
                guard let start = request["startJulianDateTT"] as? Double,
                    let stop = request["stopJulianDateTT"] as? Double,
                    start.isFinite, stop.isFinite, stop > start, stop - start <= 32
                else { throw RunnerError.usage }
                let events = try Moon.nodeCrossings(
                    from: AstroTime(tt: start - 2_451_545, deltaTModel: .jplHorizons),
                    to: AstroTime(tt: stop - 2_451_545, deltaTModel: .jplHorizons)
                )
                output = [
                    "status": "success",
                    "events": events.map {
                        [
                            "julianDateTT": $0.time.terrestrialTime + 2_451_545,
                            "kind": $0.kind == .ascending ? "ascending" : "descending",
                        ] as [String: Any]
                    },
                ]
            case "heliocentric-alignments":
                guard let code = request["body"] as? Int32,
                    let celestialBody = CelestialBody(rawValue: code),
                    let start = request["startJulianDateTT"] as? Double,
                    let stop = request["stopJulianDateTT"] as? Double,
                    start.isFinite, stop.isFinite, stop > start, stop - start <= 367,
                    code >= 0, code <= 8, code != 2
                else { throw RunnerError.usage }
                var events: [[String: Any]] = []
                for target in [0.0, 180.0] {
                    var cursor = AstroTime(tt: start - 2_451_545, deltaTModel: .jplHorizons)
                    for iteration in 0..<20 {
                        let event = try celestialBody.searchRelativeLongitude(target, after: cursor)
                        let jd = event.terrestrialTime + 2_451_545
                        if jd >= stop { break }
                        guard jd >= start, event.terrestrialTime >= cursor.terrestrialTime,
                            iteration < 19
                        else { throw RunnerError.usage }
                        events.append([
                            "julianDateTT": jd, "kind": target == 0 ? "relative-0" : "relative-180",
                        ])
                        cursor = AstroTime(tt: event.terrestrialTime + 1, deltaTModel: .jplHorizons)
                    }
                }
                events.sort { ($0["julianDateTT"] as! Double) < ($1["julianDateTT"] as! Double) }
                output = ["status": "success", "events": events]
            case "seasonal-roots":
                guard let year = request["year"] as? Int, (1900...2130).contains(year)
                else { throw RunnerError.usage }
                let seasons = try Seasons.forYear(year)
                output = [
                    "status": "success",
                    "events": [
                        ["kind": "marchEquinox", "julianDateTT": seasons.marchEquinox.terrestrialTime + 2_451_545],
                        ["kind": "juneSolstice", "julianDateTT": seasons.juneSolstice.terrestrialTime + 2_451_545],
                        ["kind": "septemberEquinox", "julianDateTT": seasons.septemberEquinox.terrestrialTime + 2_451_545],
                        ["kind": "decemberSolstice", "julianDateTT": seasons.decemberSolstice.terrestrialTime + 2_451_545],
                    ],
                ]
            case "seasons":
                guard let year = request["year"] as? Int,
                    let referenceJulianDatesUT = request["referenceJulianDatesUT"] as? [Double],
                    referenceJulianDatesUT.count == 4,
                    referenceJulianDatesUT.allSatisfy(\.isFinite)
                else { throw RunnerError.usage }
                let seasons = try Seasons.forYear(year)
                let events: [[String: Any]] = [
                    ["kind": "marchEquinox", "julianDateTT": seasons.marchEquinox.terrestrialTime + 2_451_545],
                    ["kind": "juneSolstice", "julianDateTT": seasons.juneSolstice.terrestrialTime + 2_451_545],
                    ["kind": "septemberEquinox", "julianDateTT": seasons.septemberEquinox.terrestrialTime + 2_451_545],
                    ["kind": "decemberSolstice", "julianDateTT": seasons.decemberSolstice.terrestrialTime + 2_451_545],
                ]
                output = [
                    "status": "success",
                    "events": events,
                    "referenceJulianDatesTT": referenceJulianDatesUT.map {
                        AstroTime(ut: $0 - 2_451_545, deltaTModel: deltaTModel).terrestrialTime + 2_451_545
                    },
                ]
            case "lunar-phases":
                guard let start = request["startJulianDateUT"] as? Double,
                    let stop = request["stopJulianDateUT"] as? Double,
                    let referenceJulianDatesUT = request["referenceJulianDatesUT"] as? [Double],
                    start.isFinite, stop.isFinite, stop > start, stop - start <= 367,
                    referenceJulianDatesUT.count <= 60,
                    referenceJulianDatesUT.allSatisfy(\.isFinite)
                else { throw RunnerError.usage }
                let quarters = try Moon.quarters(
                    from: AstroTime(ut: start - 2_451_545, deltaTModel: deltaTModel),
                    to: AstroTime(ut: stop - 2_451_545, deltaTModel: deltaTModel)
                )
                output = [
                    "status": "success",
                    "events": quarters.map {
                        [
                            "kind": phaseName($0.phase),
                            "julianDateTT": $0.time.terrestrialTime + 2_451_545,
                        ] as [String: Any]
                    },
                    "referenceJulianDatesTT": referenceJulianDatesUT.map {
                        AstroTime(ut: $0 - 2_451_545, deltaTModel: deltaTModel).terrestrialTime + 2_451_545
                    },
                ]
            default: throw RunnerError.usage
            }
            output["request"] = request
        } catch {
            output = ["status": statusName(error), "message": String(describing: error)]
        }
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        FileHandle.standardOutput.write(encoded)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

func phaseName(_ phase: MoonPhase) -> String {
    switch phase {
    case .new: "new"
    case .firstQuarter: "firstQuarter"
    case .full: "full"
    case .thirdQuarter: "lastQuarter"
    }
}

enum RunnerError: Error {
    case usage
}

func statusName(_ error: Error) -> String {
    guard let error = error as? AstronomyError else { return "runner-error" }
    switch error {
    case .badTime: return "bad-time"
    case .invalidBody: return "invalid-body"
    case .invalidParameter: return "invalid-parameter"
    default: return "astronomy-error"
    }
}

do {
    guard Array(CommandLine.arguments.dropFirst()) == ["accuracy-batch"] else {
        throw RunnerError.usage
    }
    try runAccuracyBatch()
} catch {
    FileHandle.standardError.write(Data("invalid accuracy batch request\n".utf8))
    exit(64)
}
