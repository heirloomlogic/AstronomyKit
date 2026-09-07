import Foundation

@main
enum PerformanceProbe {
    static let bodies: [CelestialBody] = [
        .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .sun,
    ]

    static func trial(epochs: [Double]) throws -> (seconds: Double, checksum: Double) {
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

    static func main() throws {
        let workloads: [(name: String, epochs: [Double])] = [
            ("coldStream", (0..<200).map { 9000.0 + Double($0) * 0.125 }),
            ("hotSameEpoch", Array(repeating: 9000.0, count: 200)),
        ]
        let selectedWorkload = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
        let trialCount = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 5
        var report: [String: Any] = [:]
        for workload in workloads where selectedWorkload == nil || selectedWorkload == workload.name {
            let (name, epochs) = workload
            _ = try trial(epochs: epochs)
            var seconds: [Double] = []
            var checksums: [Double] = []
            for _ in 0..<trialCount {
                let result = try trial(epochs: epochs)
                seconds.append(result.seconds)
                checksums.append(result.checksum)
            }
            report[name] = ["trialsSeconds": seconds, "checksums": checksums]
        }
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
