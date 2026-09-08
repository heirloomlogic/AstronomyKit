import Foundation

@main
enum PerformanceProbe {
    enum ArgumentError: Error {
        case invalidTrialCount
        case invalidWorkload
    }

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
        let newEpochs: [Double] = (0..<200).map { 9000.0 + Double($0) * 0.125 }
        let randomEpochs: [Double] = (0..<200).map { i in
            let index = (i * 73) % 200
            return 9000.0 + Double(index) * 0.125
        }
        let refinementEpochs: [Double] = (0..<200).map { i in
            let anchor = 9000.0 + Double(i / 20) * 0.125
            return anchor + Double(i % 20) * 0.00001
        }
        let workloads: [(name: String, epochs: [Double])] = [
            ("new", newEpochs), ("random", randomEpochs),
            ("refinement", refinementEpochs), ("repeated", Array(repeating: 9000.0, count: 200)),
        ]
        let selectedWorkload = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
        if let selectedWorkload,
            !workloads.contains(where: { $0.name == selectedWorkload })
        {
            throw ArgumentError.invalidWorkload
        }
        let trialCount: Int
        if CommandLine.arguments.count > 2 {
            guard let count = Int(CommandLine.arguments[2]), count > 0 else {
                throw ArgumentError.invalidTrialCount
            }
            trialCount = count
        } else {
            trialCount = 5
        }
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
