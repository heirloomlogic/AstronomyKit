import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Saturn resource measurements")
struct EngineSaturnMeasurementTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SATURN_MEASUREMENT_OUTPUT"] != nil))
    func measure() throws {
        func peak() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1024
            #endif
        }
        let time = Engine.Time(tt: 0, deltaTModel: .jplHorizons)
        let before = peak()
        let oldStart = Date()
        let old = try Engine.Planet.saturn.retainedEclipticState(at: time)
        let oldCold = Date().timeIntervalSince(oldStart)
        let afterOld = peak()
        let newStart = Date()
        let new = try Engine.Planet.saturn.heliocentricEclipticState(at: time)
        let newCold = Date().timeIntervalSince(newStart)
        let afterNew = peak()
        var timings: [String: Double] = [:]
        var checksum = old.x + new.x
        for legacy in [true, false] {
            let start = Date()
            for index in 0..<2_000 {
                let epoch = Engine.Time(tt: -30_000 + Double(index) * 35, deltaTModel: .jplHorizons)
                let state =
                    try legacy
                    ? Engine.Planet.saturn.retainedEclipticState(at: epoch)
                    : Engine.Planet.saturn.heliocentricEclipticState(at: epoch)
                checksum += state.x + state.vy
            }
            timings[legacy ? "retained" : "center"] = Date().timeIntervalSince(start)
        }
        let eventStart = Date()
        for _ in 0..<100 {
            checksum += try Engine.Events.searchPlanetaryApsis(of: .saturn, after: time).distanceAU
        }
        let eventSeconds = Date().timeIntervalSince(eventStart)
        try EnginePlanetaryEventTests.write(
            [
                "retainedColdSeconds": oldCold, "centerColdSeconds": newCold,
                "peakBeforeBytes": before, "peakAfterRetainedBytes": afterOld, "peakAfterCenterBytes": afterNew,
                "peakAfterWorkloadsBytes": peak(), "evaluationsPerModel": 2_000,
                "seconds": timings, "eventCount": 100, "eventSeconds": eventSeconds,
                "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], environment: "SATURN_MEASUREMENT_OUTPUT")
    }
}
