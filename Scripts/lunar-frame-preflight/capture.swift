import Foundation

@testable import AstronomyKit

struct Capture: Codable {
    let schemaVersion: Int
    let captureRevision: String
    let astronomyKitSourceTree: String
    let toolchain: String
    let sourceOrder: [String]
    let rowLayout: [String]
    let rows: [[Double]]
}

enum CaptureError: Error, CustomStringConvertible {
    case usage
    case malformed(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: capture <source-directory> <output> <capture-revision> <source-tree> <toolchain>"
        case let .malformed(message):
            return message
        }
    }
}

let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func captureRows(at directory: URL) throws -> [[Double]] {
    var rows: [[Double]] = []
    for year in 2020 ... 2022 {
        let name = "mooninfo_\(year).txt"
        let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.dropFirst().enumerated() where !line.isEmpty {
            let fields = line.split(separator: " ")
            guard fields.count > 14 else { throw CaptureError.malformed("\(name):\(index + 2): expected at least 15 fields") }
            let clock = fields[3].split(separator: ":").compactMap { Int($0) }
            guard let day = Int(fields[0]), let month = months.firstIndex(of: String(fields[1])), let rowYear = Int(fields[2]), clock.count >= 2 else {
                throw CaptureError.malformed("\(name):\(index + 2): invalid date")
            }
            let ut = Engine.Time.days(year: rowYear, month: month + 1, day: day, hour: clock[0], minute: clock[1], second: 0)
            let time = Engine.Time(ut: ut, deltaTModel: .espenakMeeus)
            let libration = Engine.Moon.libration(at: time)
            let values = [ut, time.tt, libration.longitude, libration.latitude]
            guard values.allSatisfy(\.isFinite) else { throw CaptureError.malformed("\(name):\(index + 2): nonfinite model output") }
            rows.append(values)
        }
    }
    guard rows.count == 26_305 else { throw CaptureError.malformed("expected 26305 rows, found \(rows.count)") }
    return rows
}

do {
    guard CommandLine.arguments.count == 6 else { throw CaptureError.usage }
    let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let capture = try Capture(schemaVersion: 1, captureRevision: CommandLine.arguments[3], astronomyKitSourceTree: CommandLine.arguments[4], toolchain: CommandLine.arguments[5], sourceOrder: (2020 ... 2022).map { "mooninfo_\($0).txt" }, rowLayout: ["universalTime", "terrestrialTime", "longitudeDegrees", "latitudeDegrees"], rows: captureRows(at: sourceDirectory))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(capture) + Data([0x0A])
    try data.write(to: output, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("capture: \(error)\n".utf8))
    exit(1)
}
