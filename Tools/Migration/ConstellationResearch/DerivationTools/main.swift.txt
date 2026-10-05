import AstronomyKit
import Foundation

func model(_ name: String) throws -> DeltaTModel {
    switch name {
    case "espenak-meeus": .espenakMeeus
    case "jpl-horizons": .jplHorizons
    default: throw ResearchError.usage
    }
}

enum ResearchError: Error { case usage }

func lookup(_ id: String, _ ra: Double, _ dec: Double) -> [String: Any] {
    do {
        let result = try Constellation.find(rightAscension: ra, declination: dec)
        return [
            "id": id, "status": "success", "symbol": result.symbol, "name": result.name,
            "ra1875": result.rightAscension1875, "dec1875": result.declination1875,
        ]
    } catch {
        let status: String
        switch error as? AstronomyError {
        case .invalidParameter: status = "invalid-parameter"
        case .internalError: status = "internal-error"
        case .badVector: status = "bad-vector"
        case .badTime: status = "bad-time"
        default: status = "astronomy-error"
        }
        return ["id": id, "status": status]
    }
}

final class ColdResults: @unchecked Sendable {
    let lock = NSLock()
    var storage: [[String: Any]] = Array(repeating: [:], count: 128)

    func put(_ index: Int, _ result: [String: Any]) {
        lock.lock()
        storage[index] = result
        lock.unlock()
    }
}

func emit(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    FileHandle.standardOutput.write(Data([10]))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, arguments[2] == "none" else { throw ResearchError.usage }
let initial = try model(arguments[0])
let after = try model(arguments[1])
AstronomyConfig.setDeltaTModel(initial)
var count = 0
while let line = readLine() {
    let fields = line.split(separator: " ")
    guard fields.count == 4, let ra = Double(fields[2]), let dec = Double(fields[3]) else { throw ResearchError.usage }
    let id = String(fields[0])
    if fields[1] == "cold" {
        let store = ColdResults()
        let anchors = [(2.53, 89.26), (5.92, 7.41), (6.752, -16.716), (18.615, 38.784)]
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            for (offset, anchor) in anchors.enumerated() {
                store.put(index * 4 + offset, lookup("cold-\(index)-\(offset)", anchor.0, anchor.1))
            }
        }
        for result in store.storage { try emit(result) }
    } else if fields[1] == "echo" {
        try emit([
            "id": id, "raBits": String(format: "%016llx", ra.bitPattern),
            "decBits": String(format: "%016llx", dec.bitPattern),
        ])
    } else if fields[1] == "lookup" {
        try emit(lookup(id, ra, dec))
    } else {
        throw ResearchError.usage
    }
    count += 1
    if count == 1 { AstronomyConfig.setDeltaTModel(after) }
}
