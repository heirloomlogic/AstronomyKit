import Foundation
@testable import AstrologyKit

@main struct EdictScanProbe {
    static func main() async throws {
        let scenario = CommandLine.arguments.dropFirst().first ?? "nyc-day"
        let days = scenario.hasSuffix("week") ? 7 : 1
        let latitude = scenario.hasPrefix("reykjavik") ? 64.15 : 40.71
        let longitude = scenario.hasPrefix("reykjavik") ? -21.95 : -74.01
        let start = Date(timeIntervalSince1970: 1749945600)
        let clock = ContinuousClock()
        let began = clock.now
        let result = try await ScanService.shared.scan(
            from: start, to: start.addingTimeInterval(Double(days) * 86400),
            location: (latitude: latitude, longitude: longitude), intervalMinutes: 5,
            intent: Intent(domain: .business, mode: .launch)
        )
        let duration = began.duration(to: clock.now).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let windows: [[String: Any]] = result.windows.map { window in
            ["start": window.startTime.timeIntervalSince1970,
             "end": window.endTime.timeIntervalSince1970,
             "sign": window.ascendantSign.rawValue,
             "average": window.averageScore, "peak": window.peakScore,
             "peakTime": window.peakTimestamp.timeIntervalSince1970,
             "flags": window.peakFlagInstances.map(\.id).sorted()]
        }
        let record: [String: Any] = ["scenario": scenario, "intervalMinutes": 5,
            "seconds": seconds, "windows": windows]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let path = ProcessInfo.processInfo.environment["CHRONOLOGY_WINDOWS_PATH"] {
            try encoder.encode(result.windows).write(to: URL(fileURLWithPath: path))
        }
        if let path = ProcessInfo.processInfo.environment["CHRONOLOGY_TRACE_PATH"] { try ChronologyExperiment.writeTrace(path) }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        print()
    }
}
