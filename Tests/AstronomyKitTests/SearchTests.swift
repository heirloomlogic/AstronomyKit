//
//  SearchTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("AstroSearch Tests")
struct SearchTests {
    @Test(
        "Descending and constant callbacks have no ascending event",
        arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func rejectsFalseRoots(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        for days in [1.0, 1e-10, 0.0] {
            for tolerance in [0.001, 1.0, -0.001, Double.infinity] {
                let end = start.addingDays(days)
                let descending = try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { time in
                    20000 + days / 2 - time.universalTime
                }
                #expect(descending == nil, "Descending window \(days), tolerance \(tolerance)")
                for value in [-1.0, 0.0, 1.0, -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude] {
                    let constant = try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { _ in value
                    }
                    #expect(constant == nil, "Constant \(value), window \(days), tolerance \(tolerance)")
                }
            }
        }
    }

    @Test("Reported false-positive reproductions return nil", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func reportedFalsePositives(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let descending = try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) {
            20000.375 - $0.universalTime
        }
        let absent = try AstroSearch.find(from: start, to: start.addingDays(1e-10), toleranceSeconds: 0.001) { _ in 1 }
        #expect(descending == nil)
        #expect(absent == nil)
    }

    @Test(
        "Ascending interpolation and short brackets still succeed", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func ascendingSuccessPaths(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        for days in [1.0, 1e-10] {
            let target = start.universalTime + days / 2
            let root = try #require(
                try AstroSearch.find(from: start, to: start.addingDays(days), toleranceSeconds: 0.001) {
                    $0.universalTime - target
                })
            #expect(abs(root.universalTime - target) * 86400 < 0.001)
            #expect(root.deltaTModel == model)
        }
        let quadratic = try #require(
            try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) { time in
                let u = time.universalTime - 20000
                return u * u - 0.140625
            })
        #expect(abs(quadratic.universalTime - 20000.375) * 86400 < 0.001)
    }

    @Test("Reversed ordinary windows retain ascending direction", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func reversedWindow(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let end = start.addingDays(1)
        let ascending = try #require(
            try AstroSearch.find(from: end, to: start, toleranceSeconds: 0.001) {
                $0.universalTime - 20000.375
            })
        #expect(abs(ascending.universalTime - 20000.375) * 86400 < 0.001)
        let descending = try AstroSearch.find(from: end, to: start, toleranceSeconds: 0.001) {
            20000.375 - $0.universalTime
        }
        #expect(descending == nil)
    }

    @Test("An internal ascending bracket remains discoverable", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func internalAscendingBracket(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        // The equal-sign outer endpoints must not cause an immediate rejection.
        // This finite example observes existing subdivision, not completeness for multiple roots.
        let result = try #require(
            try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) { time in
                let u = time.universalTime - 20000
                return (u - 0.25) * (u - 0.75)
            })
        #expect(abs(result.universalTime - 20000.75) * 86400 < 0.001)
    }

    @Test(
        "Observed ordinary endpoint searches retain their results", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func ordinaryEndpoints(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let end = start.addingDays(1)
        let lower = try AstroSearch.find(from: start, to: end, toleranceSeconds: 0.001) { $0.universalTime - 20000 }
        // Retain the reviewed legacy model-sensitive observation without imposing a new endpoint policy.
        if model == .espenakMeeus {
            #expect(lower == nil)
        } else {
            #expect(abs(try #require(lower).universalTime - 20000) * 86400 < 0.001)
        }
        let upper = try #require(
            try AstroSearch.find(from: start, to: end, toleranceSeconds: 0.001) { $0.universalTime - 20001 })
        #expect(abs(upper.universalTime - 20001) * 86400 < 0.001)
    }

    @Test("Sun.searchLongitude finds March equinox near Seasons result")
    func sunLongitudeMatchesSeasons() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let equinox = try #require(try Sun.searchLongitude(0, after: start))
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(equinox.universalTime - seasons.marchEquinox.universalTime) * 86400
        #expect(diffSeconds < 60, "Sun.searchLongitude and Seasons should agree within 60s, got \(diffSeconds)s")
    }

    @Test("Sun.searchLongitude finds June solstice at 90°")
    func sunLongitudeJuneSolstice() throws {
        let start = AstroTime(year: 2025, month: 3, day: 22)
        let solstice = try #require(try Sun.searchLongitude(90, after: start))
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(solstice.universalTime - seasons.juneSolstice.universalTime) * 86400
        #expect(diffSeconds < 60, "Expected June solstice match within 60s, got \(diffSeconds)s")
    }

    @Test("Sun.searchLongitude returns nil when the window is too short")
    func sunLongitudeShortWindow() throws {
        // The Sun cannot travel ~90° of ecliptic longitude in one day.
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let result = try Sun.searchLongitude(180, after: start, limitDays: 1)

        #expect(result == nil)
    }

    @Test("Moon.searchPhase returns nil when the window is too short")
    func moonPhaseShortWindow() throws {
        let start = AstroTime(year: 2025, month: 3, day: 1)
        let fullMoon = try #require(try Moon.searchPhase(.full, after: start))

        // Searching for the next full moon right after one just occurred
        // cannot succeed within 3 days.
        let result = try Moon.searchPhase(.full, after: fullMoon.addingDays(1), limitDays: 3)
        #expect(result == nil)
    }

    @Test("Generic search finds ascending root")
    func genericSearchFindsRoot() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)

        let result = try #require(
            try AstroSearch.find(from: start, to: end) { time in
                time.universalTime - start.universalTime - 15.0
            }
        )

        let expected = start.addingDays(15)
        let diffSeconds = abs(result.universalTime - expected.universalTime) * 86400
        #expect(diffSeconds < 1, "Expected root at day 15, got diff of \(diffSeconds)s")
    }

    @Test("Generic search matches Moon phase search")
    func genericSearchMatchesMoonPhase() throws {
        let start = AstroTime(year: 2025, month: 3, day: 1)
        let fullMoon = try #require(try Moon.searchPhase(.full, after: start))

        let end = start.addingDays(35)
        let result = try #require(
            try AstroSearch.find(from: start, to: end) { time in
                let phase = try Moon.phaseAngle(at: time)
                var diff = phase - 180.0
                while diff < -180 { diff += 360 }
                while diff > 180 { diff -= 360 }
                return diff
            }
        )

        let diffSeconds = abs(result.universalTime - fullMoon.universalTime) * 86400
        #expect(diffSeconds < 120, "Generic search and Moon.searchPhase should agree within 120s, got \(diffSeconds)s")
    }

    @Test("Generic search returns nil when no root crossing exists")
    func genericSearchNoRoot() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(1)

        // Monotonically increasing function with no root crossing in the window
        let result = try AstroSearch.find(from: start, to: end) { time in
            time.universalTime - start.universalTime + 100.0
        }

        #expect(result == nil)
    }

    @Test("Generic search rethrows closure errors")
    func genericSearchRethrows() {
        struct TestError: Error, Equatable {}

        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)

        #expect(throws: TestError.self) {
            try AstroSearch.find(from: start, to: end) { _ in
                throw TestError()
            }
        }
    }

    @Test("Generic search stops calling the closure after it throws")
    func genericSearchAbortsAfterThrow() {
        struct TestError: Error {}
        final class CallCounter: @unchecked Sendable {
            var count = 0
        }

        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)
        let counter = CallCounter()

        #expect(throws: TestError.self) {
            try AstroSearch.find(from: start, to: end) { _ in
                counter.count += 1
                throw TestError()
            }
        }
        #expect(counter.count == 1, "C search must abort on the first thrown error")
    }

    @Test(
        "Sun.searchLongitude throws invalidParameter for a non-finite target",
        arguments: [Double.nan, .infinity, -.infinity]
    )
    func sunLongitudeNonFiniteTarget(target: Double) {
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try Sun.searchLongitude(target, after: AstroTime(year: 2025, month: 1, day: 1))
        }
    }

    @Test("Sun.searchLongitude wraps a target far outside 0-360 in constant time")
    func sunLongitudeWrappedTarget() throws {
        // 90 + 360 * 10^9 used to take 10^9 loop steps per function evaluation.
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let direct = try #require(try Sun.searchLongitude(90, after: start))
        let wrapped = try #require(try Sun.searchLongitude(90 + 360 * 1e9, after: start))
        #expect(abs(wrapped.universalTime - direct.universalTime) * 86_400 < 60)
    }
}
