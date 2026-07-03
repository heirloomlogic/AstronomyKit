//
//  SearchTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("AstroSearch Tests")
struct SearchTests {
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
}
