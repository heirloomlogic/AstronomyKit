import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Observer event resource observations")
struct EngineObserverMeasurementTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OBSERVER_EVENT_MEASUREMENT"] != nil))
    func measure() throws {
        func peak() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1_024
            #endif
        }
        let observer = Observer(latitude: 35.6, longitude: -82.55)
        let start = Engine.Time(ut: 8_000, deltaTModel: .espenakMeeus)
        let before = peak()
        let coldStart = Date()
        let cold = try #require(
            try Engine.Events.searchRiseSet(of: .sun, direction: .rise, after: start, from: observer, limitDays: 2))
        let coldSeconds = Date().timeIntervalSince(coldStart)
        let afterCold = peak()
        var checksum = cold.tt
        var seconds: [String: Double] = [:]
        for body in [CelestialBody.sun, .moon] {
            let begin = Date()
            for index in 0..<100 {
                let time = start.adding(days: Double(index) * 3)
                let event = try #require(
                    try Engine.Events.searchRiseSet(
                        of: body, direction: .rise, after: time, from: observer, limitDays: 2))
                checksum += event.tt
            }
            seconds[body.name.lowercased() + "Rise"] = Date().timeIntervalSince(begin)
        }
        let begin = Date()
        for index in 0..<100 {
            checksum += try Engine.Events.searchHourAngle(
                of: .sun, hourAngle: 0, after: start.adding(days: Double(index)), from: observer, direction: 1
            ).time.tt
        }
        seconds["sunHourAngle"] = Date().timeIntervalSince(begin)
        let legacyBegin = Date()
        for index in 0..<100 {
            let event = try #require(
                try CelestialBody.sun.searchRiseSet(
                    direction: .rise,
                    after: AstroTime(ut: 8_000 + Double(index) * 3, deltaTModel: .espenakMeeus), from: observer,
                    limitDays: 2))
            checksum += event.terrestrialTime
        }
        seconds["publicCSunRise"] = Date().timeIntervalSince(legacyBegin)
        try EngineObserverSourceTests.write(
            [
                "coldSunRiseSeconds": coldSeconds, "peakBeforeBytes": before, "peakAfterColdBytes": afterCold,
                "peakAfterWorkloadsBytes": peak(), "seconds": seconds, "eventsPerWorkload": 100,
                "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], name: "resources")
    }
}
