import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Native Pluto measurements")
struct EnginePlutoMeasurementTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PLUTO_MEASUREMENT_OUTPUT"] != nil))
    func measure() throws {
        func peakBytes() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1024
            #endif
        }
        let before = peakBytes()
        let started = Date()
        let first = try Engine.Pluto.heliocentricState(at: PlanetTestSupport.time(tt: -766_524.75))
        let cold = Date().timeIntervalSince(started)
        let after = peakBytes()
        var timings: [String: Double] = [:]
        var checksum = first.x
        let count = 2_000
        for (name, start, step) in [("outer", -766_500.0, 1_533_000.0 / 1_999), ("central", -30_000.0, 30.0)] {
            let began = Date()
            for index in 0..<count {
                let value = try Engine.Pluto.heliocentricState(
                    at: PlanetTestSupport.time(tt: start + Double(index) * step))
                checksum += value.x + value.vy
            }
            timings[name] = Date().timeIntervalSince(began)
        }
        let result: [String: Any] = [
            "coldSeconds": cold, "peakBytesBefore": before, "peakBytesAfterCold": after,
            "peakBytesAfterLoops": peakBytes(), "evaluationsPerWorkload": count, "seconds": timings,
            "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        let path = try #require(ProcessInfo.processInfo.environment["PLUTO_MEASUREMENT_OUTPUT"])
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(
            to: URL(fileURLWithPath: path))
    }
}
