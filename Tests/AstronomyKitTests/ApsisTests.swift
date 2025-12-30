//
//  ApsisTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Apsis types.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Apsis Tests")
struct ApsisTests {

    // MARK: - ApsisKind Tests

    @Suite("ApsisKind")
    struct ApsisKindTests {

        @Test("Lunar names")
        func lunarNames() {
            #expect(ApsisKind.pericenter.lunarName == "Perigee")
            #expect(ApsisKind.apocenter.lunarName == "Apogee")
        }

        @Test("Solar names")
        func solarNames() {
            #expect(ApsisKind.pericenter.solarName == "Perihelion")
            #expect(ApsisKind.apocenter.solarName == "Aphelion")
        }

        @Test("CustomStringConvertible uses solar name")
        func description() {
            #expect(ApsisKind.pericenter.description == "Perihelion")
            #expect(ApsisKind.apocenter.description == "Aphelion")
        }

        @Test("Equatable")
        func equatable() {
            #expect(ApsisKind.pericenter == ApsisKind.pericenter)
            #expect(ApsisKind.pericenter != ApsisKind.apocenter)
        }

        @Test("Hashable")
        func hashable() {
            let set: Set<ApsisKind> = [.pericenter, .apocenter]
            #expect(set.count == 2)
        }

        @Test("Codable round-trip")
        func codable() throws {
            let original = ApsisKind.pericenter

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ApsisKind.self, from: data)

            #expect(original == decoded)
        }
    }

    // MARK: - Moon Apsis Tests

    @Suite("Moon Apsis")
    struct MoonApsisTests {

        @Test("Search finds next lunar apsis")
        func searchFindsApsis() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            #expect(apsis.time > startTime)
        }

        @Test("Lunar apsis has valid kind")
        func hasValidKind() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            #expect(apsis.kind == .pericenter || apsis.kind == .apocenter)
        }

        @Test("Lunar apsis has distances")
        func hasDistances() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            #expect(apsis.distanceAU > 0)
            #expect(apsis.distanceKM > 0)
        }

        @Test("Moon distance is in expected range")
        func moonDistanceRange() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            // Moon distance ranges from ~356,000 km (perigee) to ~406,000 km (apogee)
            #expect(apsis.distanceKM > 350000)
            #expect(apsis.distanceKM < 410000)
        }

        @Test("Next lunar apsis alternates")
        func nextApsisAlternates() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let first = try Moon.searchApsis(after: startTime)
            let second = try Moon.nextApsis(after: first)

            #expect(second.time > first.time)
            #expect(second.kind != first.kind)
        }

        @Test("Lunar apsides in date range")
        func apsidesInRange() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let endTime = AstroTime(year: 2025, month: 3, day: 1)

            let apsides = try Moon.apsides(from: startTime, to: endTime)

            // Should have about 4 apsides in 2 months (1 perigee + 1 apogee per ~27 days)
            #expect(apsides.count >= 3)
            #expect(apsides.count <= 5)

            // All should be in range
            for apsis in apsides {
                #expect(apsis.time >= startTime)
                #expect(apsis.time < endTime)
            }
        }

        @Test("Perigee is closer than apogee")
        func perigeeCloserThanApogee() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            var current = try Moon.searchApsis(after: startTime)

            var perigee: Apsis?
            var apogee: Apsis?

            // Find one of each
            for _ in 0..<4 {
                if current.kind == .pericenter && perigee == nil {
                    perigee = current
                } else if current.kind == .apocenter && apogee == nil {
                    apogee = current
                }

                if perigee != nil && apogee != nil { break }
                current = try Moon.nextApsis(after: current)
            }

            if let p = perigee, let a = apogee {
                #expect(p.distanceKM < a.distanceKM)
            }
        }
    }

    // MARK: - Planet Apsis Tests

    @Suite("Planet Apsis")
    struct PlanetApsisTests {

        @Test("Search finds next planetary apsis for Earth")
        func earthApsis() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try CelestialBody.earth.searchApsis(after: startTime)

            #expect(apsis.time > startTime)
        }

        @Test("Earth perihelion is in early January")
        func earthPerihelionDate() throws {
            // Earth's perihelion is typically around January 3
            let startTime = AstroTime(year: 2024, month: 12, day: 1)
            let apsis = try CelestialBody.earth.searchApsis(after: startTime)

            if apsis.kind == .pericenter {
                let calendar = Calendar(identifier: .gregorian)
                let month = calendar.component(.month, from: apsis.time.date)
                let day = calendar.component(.day, from: apsis.time.date)

                #expect(month == 1)
                #expect(day >= 1 && day <= 7)
            }
        }

        @Test("Earth distance is about 1 AU")
        func earthDistanceAbout1AU() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try CelestialBody.earth.searchApsis(after: startTime)

            #expect(apsis.distanceAU > 0.98)
            #expect(apsis.distanceAU < 1.02)
        }

        @Test("Next planetary apsis alternates")
        func nextApsisAlternates() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let first = try CelestialBody.earth.searchApsis(after: startTime)
            let second = try CelestialBody.earth.nextApsis(after: first)

            #expect(second.time > first.time)
            #expect(second.kind != first.kind)
        }

        @Test("Mars apsis search")
        func marsApsis() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try CelestialBody.mars.searchApsis(after: startTime)

            #expect(apsis.time > startTime)

            // Mars orbital distance ranges from ~1.38 AU (perihelion) to ~1.67 AU (aphelion)
            #expect(apsis.distanceAU > 1.3)
            #expect(apsis.distanceAU < 1.7)
        }

        @Test("Jupiter apsis search")
        func jupiterApsis() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try CelestialBody.jupiter.searchApsis(after: startTime)

            #expect(apsis.time > startTime)

            // Jupiter distance ~5 AU
            #expect(apsis.distanceAU > 4.9)
            #expect(apsis.distanceAU < 5.5)
        }

        @Test("Planet apsides in date range")
        func apsidesInRange() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let endTime = AstroTime(year: 2027, month: 1, day: 1)

            let apsides = try CelestialBody.earth.apsides(from: startTime, to: endTime)

            // Earth has 1 perihelion and 1 aphelion per year
            #expect(apsides.count >= 3)  // At least 2 full years
            #expect(apsides.count <= 5)

            // All should be in range
            for apsis in apsides {
                #expect(apsis.time >= startTime)
                #expect(apsis.time < endTime)
            }
        }
    }

    // MARK: - Apsis Struct Tests

    @Suite("Apsis Struct")
    struct ApsisStructTests {

        @Test("Apsis has all properties")
        func hasAllProperties() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            _ = apsis.kind
            _ = apsis.time
            _ = apsis.distanceAU
            _ = apsis.distanceKM
        }

        @Test("Distance AU and KM are consistent")
        func distancesConsistent() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try CelestialBody.earth.searchApsis(after: startTime)

            // 1 AU ≈ 149,597,870.7 km
            let expectedKM = apsis.distanceAU * 149_597_870.7
            let diff = abs(apsis.distanceKM - expectedKM)

            // Should be within 0.1%
            #expect(diff / expectedKM < 0.001)
        }

        @Test("Equatable")
        func equatable() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let a1 = try Moon.searchApsis(after: startTime)
            let a2 = try Moon.searchApsis(after: startTime)

            #expect(a1 == a2)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let apsis = try Moon.searchApsis(after: startTime)

            let desc = apsis.description

            #expect(desc.contains("km"))
        }
    }
}
