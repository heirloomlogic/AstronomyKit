import AstronomyKit
import Foundation

struct Workload: Codable {
    let operations: Int
    let elapsedNanoseconds: UInt64
    let checksum: Double
}

@main
enum PerformanceRunner {
    static let bodies: [CelestialBody] = [
        .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .sun,
    ]

    static func measured(operations: Int, _ work: () throws -> Double) rethrows -> Workload {
        let start = DispatchTime.now().uptimeNanoseconds
        let checksum = try work()
        return Workload(
            operations: operations,
            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
            checksum: checksum
        )
    }

    static func representativeLatency() throws -> Workload {
        let iterations = 8
        return try measured(operations: iterations * 5) {
            var checksum = 0.0
            for index in 0..<iterations {
                let time = AstroTime(ut: 8_000.0 + Double(index) * 41.25)
                let position = try CelestialBody.mercury.heliocentricPosition(at: time)
                let state = try CelestialBody.jupiter.heliocentricState(at: time)
                let moon = try Moon.geoState(at: time)
                let pluto = try CelestialBody.pluto.heliocentricPosition(at: time)
                let seasons = try Seasons.forYear(2000 + index)
                checksum += position.x + state.position.y + moon.velocity.z + pluto.z
                checksum += seasons.allEvents.reduce(0.0) { $0 + $1.time.universalTime }
            }
            return checksum
        }
    }

    static func positionThroughput(repeatedEpoch: Bool) throws -> Workload {
        let epochCount = 200
        let epochs = (0..<epochCount).map { index in
            repeatedEpoch ? 9_000.0 : 9_000.0 + Double(index) * 0.125
        }
        if repeatedEpoch {
            for body in bodies {
                _ = try body.heliocentricPosition(at: AstroTime(ut: epochs[0]))
            }
        }
        return try measured(operations: epochCount * bodies.count) {
            var checksum = 0.0
            for epoch in epochs {
                let time = AstroTime(ut: epoch)
                for body in bodies {
                    let vector = try body.heliocentricPosition(at: time)
                    checksum += vector.x + vector.y + vector.z
                }
            }
            return checksum
        }
    }

    static func main() throws {
        _ = try CelestialBody.earth.heliocentricPosition(at: AstroTime(ut: -12_345.0))
        let report = [
            "representativeLatency": try representativeLatency(),
            "coldThroughput": try positionThroughput(repeatedEpoch: false),
            "warmThroughput": try positionThroughput(repeatedEpoch: true),
        ]
        let data = try JSONEncoder.sorted.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
