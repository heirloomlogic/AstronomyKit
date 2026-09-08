import AstronomyKit
import Foundation
@testable import AstrologyKit

@main enum EventProbe {
    struct Row: Encodable {
        let identity: String
        let referenceDate: Double
        let fullTT: Double?
        let result: EventSearchResult
        let overlapping: EventSearchResult
        let coherent: Bool
    }
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        var rows: [Row] = []
        let provider = ProductionElectionEventProvider()
        let policy = try EventNumericalPolicy(timeToleranceSeconds: 0.001,
            angularResidualToleranceDegrees: 0.0001, stationResidualToleranceDegreesPerDay: 1e-6,
            workLimit: 25_000, maximumSubdivisionSeconds: 86_400)
        func evaluate(_ identity: String, _ target: EventTarget, _ date: Date,
                      _ location: ElectionLocation, fullTT: Double? = nil) throws {
            let cache = ChronologyIntervalCache()
            let points = ChronologyPointCache()
            func query(_ offset: Double) throws -> EventQuery {
                try EventQuery(interval: UTCInterval(
                    start: ElectionFactBuilder.referenceInstant(date.addingTimeInterval(-3600 + offset)),
                    end: ElectionFactBuilder.referenceInstant(date.addingTimeInterval(3600 + offset))),
                    location: location, targets: [target], numericalPolicy: policy)
            }
            func search(_ query: EventQuery) -> EventSearchResult {
                ElectionEventSearch.performSearch(query, provider: provider, sharedPointCache: points,
                    intervalCache: ChronologyExperiment.reuse ? cache : nil, isCancelled: { false })
            }
            let result = search(try query(0))
            let overlap = search(try query(300))
            func coherent(_ result: EventSearchResult) -> Bool {
                guard result.chronologicalGroups == EventSearchWorker.groups(for: result.events) else { return false }
                let worker = EventSearchWorker(query: result.query, provider: provider, sharedPointCache: nil)
                for event in result.events {
                    guard event.provenance.queryInterval == result.query.interval,
                        event.pointSamples.allSatisfy({ sample in
                            provider.sample(sample.point, at: event.instant.approximateDate, location: location) == sample
                        }) else { return false }
                    let before = event.bracket.start.timeIntervalSince(result.query.interval.start) - policy.timeToleranceSeconds
                    let after = event.bracket.end.timeIntervalSince(result.query.interval.start) + policy.timeToleranceSeconds
                    for (second, motion) in [(before, event.motionBefore), (after, event.motionAfter)] {
                        if second < 0 || second > result.query.interval.durationSeconds {
                            if motion != nil { return false }
                        } else {
                            guard let expected = worker.scalar(for: event.target, secondsSinceStart: second),
                                let motion, abs(expected.value - motion.residual) < 1e-8,
                                abs(expected.derivative - motion.derivativePerSecond) < 1e-8
                            else { return false }
                        }
                    }
                }
                return true
            }
            rows.append(Row(identity: identity, referenceDate: date.timeIntervalSince1970, fullTT: fullTT,
                            result: result, overlapping: overlap, coherent: coherent(result) && coherent(overlap)))
            if rows.count % 100 == 0 { print("Validated \(rows.count) event queries") }
        }
        if CommandLine.arguments.count > 3 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            let stations = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            let location = try ElectionLocation(latitudeDegrees: 0, longitudeDegrees: 0, elevationMeters: 0)
            for (i, row) in stations.enumerated() {
                let planet = Planet.allCases.first { $0.rawValue.lowercased() == row["body"] as! String }!
                try evaluate("station-\(i)", .station(planet), AstroTime(tt: row["tt"] as! Double).date,
                             location, fullTT: row["fullTT"] as? Double)
            }
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for i in 1...24 {
                let id = String(format: "A%02d", i)
                let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(id+".json"))) as! [String: Any]
                let oracle = fixture["oracleOutput"] as! [String: Any], q = oracle["query"] as! [String: Any]
                let location = try ElectionLocation(latitudeDegrees: q["latitudeDegrees"] as! Double,
                    longitudeDegrees: q["longitudeDegrees"] as! Double, elevationMeters: 0)
                for (j, event) in (oracle["events"] as! [[String: Any]]).enumerated() {
                    let bodies = (event["bodies"] as? [String] ?? []).map { name in
                        Planet.allCases.first { $0.rawValue.lowercased() == name }!
                    }
                    let branch = event["signedBranchDegrees"] as? Double ?? 0
                    let target: EventTarget
                    switch event["kind"] as! String {
                    case "station": target = .station(bodies[0])
                    case "aspect": target = .aspect(first: .planet(bodies[0]), second: .planet(bodies[1]),
                        type: AspectType(rawValue: Int(abs(branch)))!, branchDegrees: Int(branch))
                    case "phaseBoundary": target = .phaseBoundary(first: .planet(bodies[0]), second: .planet(bodies[1]), branchDegrees: Int(branch))
                    case "solarBandCrossing": target = .solarBandCrossing(body: bodies[0], thresholdDegrees: abs(branch), branchDegrees: branch < 0 ? -1 : 1)
                    case "signIngress": target = .signIngress(point: .planet(bodies[0]), boundaryDegrees: event["targetDegrees"] as! Int)
                    case "ascendantIngress": target = .signIngress(point: .angle(.ascendant), boundaryDegrees: 0)
                    case "midheavenIngress": target = .signIngress(point: .angle(.midheaven), boundaryDegrees: 0)
                    case "houseCrossing": target = .houseCrossing(point: .planet(.moon), cusp: 2, system: .placidus)
                    case "angularBandCrossing": target = .angularBandCrossing(point: .planet(.mars), angle: .ascendant, thresholdDegrees: 5, branchDegrees: 1)
                    default: fatalError("Unknown frozen kind")
                    }
                    try evaluate("\(id)/\(j)", target, formatter.date(from: event["instant"] as! String)!, location)
                }
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(rows).write(to: output)
        if let path = ProcessInfo.processInfo.environment["CHRONOLOGY_TRACE_PATH"] { try ChronologyExperiment.writeTrace(path) }
        print("Wrote \(rows.count) event query pairs")
    }
}
