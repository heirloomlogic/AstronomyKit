import AstronomyKit
import Foundation

private struct CallbackFailure: Error { let visit: Int }
private func packet(_ x: Double) -> String {
    if x.isNaN { return "nan" }
    if x.isInfinite { return x.sign == .minus ? "-inf" : "+inf" }
    return String(format: "f64:%016llx", x.bitPattern)
}
private func modelName(_ model: DeltaTModel?) -> String {
    switch model {
    case .espenakMeeus: return "espenak-meeus"
    case .jplHorizons: return "jpl-horizons"
    case nil: return "unidentified"
    }
}
private func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
        fatalError("transcript JSON encoding failed")
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
private final class Research: @unchecked Sendable {
    let initial: DeltaTModel
    let operation: String
    let fixture: String
    let baseUT: Double
    let startOffset: Double
    let endOffset: Double
    let tolerance: Double
    let errorVisit: Int
    let stamp: Double
    let cap: Int
    let mutation: String
    let p: [Double]
    var current: DeltaTModel
    var visits = 0
    var firstError = 0
    init(_ args: [String]) {
        initial = args[0] == "jpl-horizons" ? .jplHorizons : .espenakMeeus
        current = initial
        guard let parsedBase = Double(args[3]), let parsedStart = Double(args[4]),
            let parsedEnd = Double(args[5]), let parsedTolerance = Double(args[6]),
            let parsedError = Int(args[7]), let parsedStamp = Double(args[8]), let parsedCap = Int(args[9])
        else { fatalError("invalid frozen argument") }
        operation = args[1]
        fixture = args[2]
        baseUT = parsedBase
        startOffset = parsedStart
        endOffset = parsedEnd
        tolerance = parsedTolerance
        errorVisit = parsedError
        stamp = parsedStamp
        cap = parsedCap
        mutation = args[10]
        p = args[11...14].map { token in
            guard let value = Double(token) else { fatalError("invalid frozen parameter") }
            return value
        }
    }
    func timeObject(_ time: AstroTime) -> [String: Any] {
        [
            "ut": packet(time.universalTime), "tt": packet(time.terrestrialTime), "model": modelName(time.deltaTModel),
            "expectedCapturedTT": packet(AstroTime(ut: time.universalTime, deltaTModel: initial).terrestrialTime),
        ]
    }
    func scalar(_ u: Double) -> Double {
        switch fixture {
        case "linear": return u - (p[0] + (mutation == "event-selection" ? 0.25 : 0))
        case "descending": return p[0] - u
        case "constant": return p[0]
        case "quadratic": return u * u - p[0]
        case "two-roots": return (u - p[0]) * (u - p[1])
        case "cubic": return ((u - p[0]) * (u - p[0])) * (u - p[0])
        case "step": return u < p[0] ? -1 : 1
        case "scaled": return (u - p[0]) * p[1]
        default: fatalError("unknown frozen fixture")
        }
    }
    func visit(_ received: AstroTime, vector: Bool) throws -> (AstroTime, [Double]) {
        visits += 1
        if visits > cap {
            emit(["event": "research-cap", "visit": visits])
            exit(75)
        }
        let time = mutation == "time-default" ? AstroTime(ut: received.universalTime) : received
        let before = modelName(current)
        current = visits % 2 == 1 ? (initial == .espenakMeeus ? .jplHorizons : .espenakMeeus) : initial
        AstronomyConfig.setDeltaTModel(current)
        var result: [String: Any]
        var xyz = [p[0], p[1], p[2]]
        if fixture == "moving" { xyz = [p[0] + p[1] * (time.universalTime - baseUT), p[2], p[3]] }
        if fixture == "alternating" { xyz = [visits % 2 == 1 ? 0 : 1, 0, 0] }
        if visits == errorVisit {
            firstError = visits
            result = ["kind": "raise", "visit": visits]
        } else if vector {
            result = ["kind": "vector", "xyz": xyz.map(packet), "suppliedTime": timeObject(time.addingDays(stamp))]
        } else {
            result = ["kind": "scalar", "value": packet(scalar(time.universalTime - baseUT))]
        }
        emit([
            "event": "callback", "visit": visits, "time": timeObject(time), "defaultBefore": before,
            "defaultAfter": modelName(current), "result": result,
        ])
        if visits == errorVisit && mutation != "swallow-error" { throw CallbackFailure(visit: visits) }
        return (time, xyz)
    }
    func run() {
        AstronomyConfig.setDeltaTModel(initial)
        let base = AstroTime(ut: baseUT, deltaTModel: initial)
        let start = base.addingDays(startOffset)
        let end = base.addingDays(endOffset)
        emit(["event": "begin", "initialModel": modelName(initial), "start": timeObject(start), "end": timeObject(end)])
        var terminal: [String: Any] = ["event": "terminal"]
        do {
            if operation == "root" {
                let result = try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { [self] time in
                    let (sample, _) = try visit(time, vector: false)
                    return scalar(sample.universalTime - baseUT)
                }
                terminal["outcome"] = result == nil ? "absent" : "value"
                terminal["rawStatus"] = result == nil ? "nil" : "value"
                if let result { terminal["time"] = timeObject(result) }
            } else {
                let result = try AstroSearch.correctLightTravel(at: start) { [self] time in
                    let (sample, xyz) = try visit(time, vector: true)
                    return Vector3D(x: xyz[0], y: xyz[1], z: xyz[2], time: sample.addingDays(stamp))
                }
                terminal["outcome"] = "value"
                terminal["rawStatus"] = "value"
                terminal["xyz"] = [result.x, result.y, result.z].map(packet)
                terminal["time"] = timeObject(result.time)
            }
        } catch let error as CallbackFailure {
            terminal["outcome"] = "callback-error"
            terminal["rawStatus"] = "CallbackFailure"
            terminal["errorVisit"] = error.visit
        } catch {
            terminal["outcome"] = "algorithm-error"
            terminal["rawStatus"] = String(describing: error)
        }
        terminal["visits"] = visits
        terminal["firstErrorVisit"] = firstError
        emit(terminal)
    }
}
if CommandLine.arguments.count != 16 { exit(64) }
Research(Array(CommandLine.arguments.dropFirst())).run()
