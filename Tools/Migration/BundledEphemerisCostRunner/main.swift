import AstronomyKit
import Foundation

let operation = CommandLine.arguments.dropFirst().first ?? "baseline"
let count = 100_000
var checksum = 0.0
let start = DispatchTime.now().uptimeNanoseconds
if operation != "baseline" {
    for index in 0..<count {
        // Spread calls over the required interval; cache hits cannot hide costs.
        let time = AstroTime(tt: -36_524.5 + Double(index) * 84_370.0 / Double(count))
        switch operation {
        case "moon":
            let state = try Moon.geoState(at: time)
            checksum += state.position.x + state.velocity.y
        case "pluto":
            let state = try CelestialBody.pluto.heliocentricState(at: time)
            checksum += state.position.x + state.velocity.y
        default:
            throw NSError(domain: "BundledEphemerisCostRunner", code: 1)
        }
    }
}
let elapsed = DispatchTime.now().uptimeNanoseconds - start
let data = try JSONSerialization.data(
    withJSONObject: [
        "operation": operation,
        "count": operation == "baseline" ? 0 : count,
        "elapsedNanoseconds": elapsed,
        "checksum": checksum,
    ], options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
