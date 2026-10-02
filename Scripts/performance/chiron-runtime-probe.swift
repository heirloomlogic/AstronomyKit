@testable import AstronomyKit
import Foundation

/// Measures the cold, reused, and light-time Chiron paths without imposing a gate.
@main
struct ChironRuntimeProbe {
    static func main() throws {
        let clock = ContinuousClock()
        let edge = AstroTime(year: 2_100, month: 1, day: 1)
        let nearby = AstroTime(year: 2_099, month: 12, day: 31, hour: 18)
        var checksum = 0.0

        for trial in 1...5 {
            let cold = try clock.measure {
                let position = try Chiron.heliocentricPosition(at: edge)
                checksum += position.x + position.y + position.z
            }

            let reusable = Chiron.ReusableSimulation()
            _ = try reusable.state(at: edge)
            let warm = try clock.measure {
                let position = try reusable.state(at: nearby).position
                checksum += position.x + position.y + position.z
            }

            let lightTime = try clock.measure {
                let position = try Chiron.geocentricPosition(at: edge)
                checksum += position.x + position.y + position.z
            }

            print("trial=\(trial) cold=\(cold) warm=\(warm) lightTime=\(lightTime)")
        }

        print("checksum=\(checksum)")
    }
}
