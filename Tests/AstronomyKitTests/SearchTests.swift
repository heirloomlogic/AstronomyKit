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
        let equinox = try Sun.searchLongitude(0, after: start)
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(equinox.ut - seasons.marchEquinox.ut) * 86400
        #expect(diffSeconds < 60, "Sun.searchLongitude and Seasons should agree within 60s, got \(diffSeconds)s")
    }

    @Test("Sun.searchLongitude finds June solstice at 90°")
    func sunLongitudeJuneSolstice() throws {
        let start = AstroTime(year: 2025, month: 3, day: 22)
        let solstice = try Sun.searchLongitude(90, after: start)
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(solstice.ut - seasons.juneSolstice.ut) * 86400
        #expect(diffSeconds < 60, "Expected June solstice match within 60s, got \(diffSeconds)s")
    }

    @Test("Generic search finds ascending root")
    func genericSearchFindsRoot() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)

        let result = try AstroSearch.find(from: start, to: end) { time in
            time.ut - start.ut - 15.0
        }

        let expected = start.addingDays(15)
        let diffSeconds = abs(result.ut - expected.ut) * 86400
        #expect(diffSeconds < 1, "Expected root at day 15, got diff of \(diffSeconds)s")
    }

    @Test("Generic search matches Moon phase search")
    func genericSearchMatchesMoonPhase() throws {
        let start = AstroTime(year: 2025, month: 3, day: 1)
        let fullMoon = try Moon.searchPhase(.full, after: start)

        let end = start.addingDays(35)
        let result = try AstroSearch.find(from: start, to: end) { time in
            let phase = try! Moon.phaseAngle(at: time)
            var diff = phase - 180.0
            while diff < -180 { diff += 360 }
            while diff > 180 { diff -= 360 }
            return diff
        }

        let diffSeconds = abs(result.ut - fullMoon.ut) * 86400
        #expect(diffSeconds < 120, "Generic search and Moon.searchPhase should agree within 120s, got \(diffSeconds)s")
    }

    @Test("Generic search throws on no convergence")
    func genericSearchNoConvergence() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(1)

        #expect(throws: AstronomyError.self) {
            // Monotonically increasing function with no root crossing in the window
            try AstroSearch.find(from: start, to: end) { time in
                time.ut - start.ut + 100.0
            }
        }
    }
}
