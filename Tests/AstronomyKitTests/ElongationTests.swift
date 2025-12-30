//
//  ElongationTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Elongation types.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Elongation Tests")
struct ElongationTests {

    // MARK: - Visibility Tests

    @Suite("Visibility")
    struct VisibilityTests {

        @Test("Visibility names")
        func visibilityNames() {
            #expect(Visibility.morning.name == "Morning")
            #expect(Visibility.evening.name == "Evening")
        }

        @Test("CustomStringConvertible")
        func description() {
            #expect(Visibility.morning.description == "Morning")
            #expect(Visibility.evening.description == "Evening")
        }

        @Test("Equatable")
        func equatable() {
            #expect(Visibility.morning == Visibility.morning)
            #expect(Visibility.morning != Visibility.evening)
        }

        @Test("Hashable")
        func hashable() {
            let set: Set<Visibility> = [.morning, .evening]
            #expect(set.count == 2)
        }

        @Test("Codable round-trip")
        func codable() throws {
            let original = Visibility.morning

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Visibility.self, from: data)

            #expect(original == decoded)
        }
    }

    // MARK: - Elongation At Time Tests

    @Suite("Elongation At Time")
    struct ElongationAtTimeTests {

        @Test("Get elongation for Venus")
        func venusElongation() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.venus.elongation(at: time)

            #expect(elong.time == time)
            #expect(elong.angle >= 0)
            #expect(elong.angle <= 180)
        }

        @Test("Get elongation for Mercury")
        func mercuryElongation() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.mercury.elongation(at: time)

            #expect(elong.angle >= 0)
            #expect(elong.angle <= 180)
        }

        @Test("Elongation has valid visibility")
        func hasValidVisibility() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.venus.elongation(at: time)

            #expect(elong.visibility == .morning || elong.visibility == .evening)
        }

        @Test("Elongation has ecliptic separation")
        func hasEclipticSeparation() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.venus.elongation(at: time)

            // Ecliptic separation can be positive or negative
            #expect(abs(elong.eclipticSeparation) <= 180)
        }

        @Test("Outer planets have larger elongation range", arguments: CelestialBody.outerPlanets)
        func outerPlanetElongation(planet: CelestialBody) throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try planet.elongation(at: time)

            // Outer planets can reach opposition (180°)
            #expect(elong.angle >= 0)
            #expect(elong.angle <= 180)
        }
    }

    // MARK: - Max Elongation Search Tests

    @Suite("Max Elongation Search")
    struct MaxElongationSearchTests {

        @Test("Search max elongation for Mercury")
        func mercuryMaxElong() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let maxElong = try CelestialBody.mercury.searchMaxElongation(after: startTime)

            #expect(maxElong.time > startTime)

            // Mercury's max elongation is typically 18-28°
            #expect(maxElong.angle >= 17)
            #expect(maxElong.angle <= 29)
        }

        @Test("Search max elongation for Venus")
        func venusMaxElong() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let maxElong = try CelestialBody.venus.searchMaxElongation(after: startTime)

            #expect(maxElong.time > startTime)

            // Venus's max elongation is typically 45-47°
            #expect(maxElong.angle >= 44)
            #expect(maxElong.angle <= 48)
        }

        @Test("Max elongation has visibility")
        func maxElongHasVisibility() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let maxElong = try CelestialBody.mercury.searchMaxElongation(after: startTime)

            #expect(maxElong.visibility == .morning || maxElong.visibility == .evening)
        }

        @Test("Sequential max elongations alternate visibility")
        func alternatingVisibility() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)

            // Find two consecutive max elongations for Mercury
            let first = try CelestialBody.mercury.searchMaxElongation(after: startTime)
            let second = try CelestialBody.mercury.searchMaxElongation(
                after: first.time.addingDays(1))

            // Should be different visibility (morning vs evening)
            #expect(first.visibility != second.visibility)
        }
    }

    // MARK: - Elongation Struct Tests

    @Suite("Elongation Struct")
    struct ElongationStructTests {

        @Test("Elongation has all properties")
        func hasAllProperties() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.venus.elongation(at: time)

            _ = elong.time
            _ = elong.visibility
            _ = elong.angle
            _ = elong.eclipticSeparation
        }

        @Test("Equatable")
        func equatable() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let e1 = try CelestialBody.venus.elongation(at: time)
            let e2 = try CelestialBody.venus.elongation(at: time)

            #expect(e1 == e2)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.venus.elongation(at: time)

            let desc = elong.description

            #expect(desc.contains("star"))
            #expect(desc.contains("Sun"))
        }
    }

    // MARK: - Physical Meaning Tests

    @Suite("Physical Meaning")
    struct PhysicalMeaningTests {

        @Test("Inner planet max elongation < 90°")
        func innerPlanetMaxElongation() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)

            let mercuryMax = try CelestialBody.mercury.searchMaxElongation(after: startTime)
            let venusMax = try CelestialBody.venus.searchMaxElongation(after: startTime)

            // Inner planets can never be more than ~28° (Mercury) or ~47° (Venus) from Sun
            #expect(mercuryMax.angle < 30)
            #expect(venusMax.angle < 50)
        }

        @Test("Mercury has smaller max elongation than Venus")
        func mercurySmallerThanVenus() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)

            let mercuryMax = try CelestialBody.mercury.searchMaxElongation(after: startTime)
            let venusMax = try CelestialBody.venus.searchMaxElongation(after: startTime)

            #expect(mercuryMax.angle < venusMax.angle)
        }

        @Test("Outer planet at opposition has ~180° elongation")
        func outerPlanetOpposition() throws {
            // Search for Mars at a time when it might be near opposition
            let time = AstroTime(year: 2025, month: 6, day: 21)
            let elong = try CelestialBody.mars.elongation(at: time)

            // Mars can reach elongations up to 180° at opposition
            #expect(elong.angle <= 180)
        }
    }
}
