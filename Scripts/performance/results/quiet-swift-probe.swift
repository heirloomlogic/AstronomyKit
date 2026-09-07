import Foundation

let bodies: [CelestialBody] = [
    .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .sun,
]

func trial(epochs: [Double]) throws -> (seconds: Double, checksum: Double) {
    var checksum = 0.0
    let start = DispatchTime.now().uptimeNanoseconds
    for ut in epochs {
        let time = AstroTime(ut: ut)
        for body in bodies {
            let vector = try body.geocentricPosition(at: time)
            checksum += vector.x + vector.y + vector.z
        }
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    return (elapsed, checksum)
}

let workloads = [
    "coldStream": (0..<200).map { 9000.0 + Double($0) * 0.125 },
    "hotSameEpoch": Array(repeating: 9000.0, count: 200),
]
var report: [String: Any] = [:]
for (name, epochs) in workloads {
    _ = try trial(epochs: epochs)
    var seconds: [Double] = []
    var checksums: [Double] = []
    for _ in 0..<5 {
        let result = try trial(epochs: epochs)
        seconds.append(result.seconds)
        checksums.append(result.checksum)
    }
    report[name] = ["trialsSeconds": seconds, "checksums": checksums]
}
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
