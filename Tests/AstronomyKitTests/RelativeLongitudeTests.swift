//
//  RelativeLongitudeTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Relative Longitude Tests")
struct RelativeLongitudeTests {

    // MARK: - Pair Longitude

    @Suite("Pair Longitude")
    struct PairLongitudeTests {
        @Test("Pair longitude returns value in 0-360 range")
        func pairLongitudeRange() throws {
            let time = AstroTime(year: 2025, month: 6, day: 15)
            let angle = try CelestialBody.mars.pairLongitude(with: .sun, at: time)
            #expect(angle >= 0 && angle < 360)
        }

        @Test("Pair longitude between same body is 0")
        func pairLongitudeSameBody() throws {
            let time = AstroTime(year: 2025, month: 6, day: 15)
            let angle = try CelestialBody.mars.pairLongitude(with: .mars, at: time)
            #expect(angle < 0.001 || angle > 359.999)
        }
    }

    // MARK: - Opposition Search

    @Suite("Opposition Search")
    struct OppositionTests {
        @Test("Mars opposition: planet appears opposite Sun in sky")
        func marsOpposition() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let opposition = try CelestialBody.mars.searchOpposition(after: start)
            #expect(opposition > start)

            // At opposition, the geocentric ecliptic longitude difference is ~180°
            let angle = try CelestialBody.mars.pairLongitude(with: .sun, at: opposition)
            #expect(abs(angle - 180) < 1.0, "Geocentric pair longitude at opposition should be ~180°, got \(angle)°")
        }

        @Test("Jupiter opposition search finds result")
        func jupiterOpposition() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let opposition = try CelestialBody.jupiter.searchOpposition(after: start)
            #expect(opposition > start)

            let angle = try CelestialBody.jupiter.pairLongitude(with: .sun, at: opposition)
            #expect(abs(angle - 180) < 1.0, "Geocentric pair longitude at opposition should be ~180°, got \(angle)°")
        }

        @Test("Saturn opposition search finds result")
        func saturnOpposition() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let opposition = try CelestialBody.saturn.searchOpposition(after: start)
            #expect(opposition > start)
        }
    }

    // MARK: - Superior Conjunction Search

    @Suite("Superior Conjunction Search")
    struct ConjunctionTests {
        @Test("Jupiter superior conjunction: planet appears near Sun")
        func jupiterSuperiorConjunction() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let conjunction = try CelestialBody.jupiter.searchSuperiorConjunction(after: start)
            #expect(conjunction > start)

            // At superior conjunction, geocentric pair longitude is ~0° (or ~360°)
            let angle = try CelestialBody.jupiter.pairLongitude(with: .sun, at: conjunction)
            let nearZero = angle < 1.0 || angle > 359.0
            #expect(nearZero, "Pair longitude at superior conjunction should be ~0°, got \(angle)°")
        }

        @Test("Venus superior conjunction search finds result")
        func venusSuperiorConjunction() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let conjunction = try CelestialBody.venus.searchSuperiorConjunction(after: start)
            #expect(conjunction > start)
        }
    }

    // MARK: - Relative Longitude Search

    @Suite("Relative Longitude Search")
    struct RelativeLongitudeSearchTests {
        @Test("Search for arbitrary relative longitude")
        func arbitraryAngle() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let result = try CelestialBody.mars.searchRelativeLongitude(90, after: start)
            #expect(result > start)
        }

        @Test("Sequential oppositions are spaced by roughly the synodic period")
        func sequentialOppositions() throws {
            let start = AstroTime(year: 2025, month: 1, day: 1)
            let first = try CelestialBody.jupiter.searchOpposition(after: start)
            let second = try CelestialBody.jupiter.searchOpposition(after: first.addingDays(30))
            let daysBetween = second.ut - first.ut
            // Jupiter's synodic period is ~398.88 days
            #expect(daysBetween > 380 && daysBetween < 420,
                    "Expected ~399 days between Jupiter oppositions, got \(daysBetween)")
        }
    }
}
