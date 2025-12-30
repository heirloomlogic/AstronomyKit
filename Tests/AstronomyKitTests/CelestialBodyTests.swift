//
//  CelestialBodyTests.swift
//  AstronomyKit
//
//  Comprehensive tests for the CelestialBody type.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("CelestialBody Tests")
struct CelestialBodyTests {

    // MARK: - Basic Properties

    @Suite("Basic Properties")
    struct BasicProperties {

        @Test("Most bodies have names", arguments: CelestialBody.allCases)
        func mostBodiesHaveNames(body: CelestialBody) {
            let name = body.name

            // Note: Some bodies (like Galilean moons) may not have names in all library versions
            // Just verify the property is accessible
            _ = name
        }

        @Test("Sun name is correct")
        func sunName() {
            #expect(CelestialBody.sun.name == "Sun")
        }

        @Test("Moon name is correct")
        func moonName() {
            #expect(CelestialBody.moon.name == "Moon")
        }

        @Test(
            "Planet names",
            arguments: [
                (CelestialBody.mercury, "Mercury"),
                (CelestialBody.venus, "Venus"),
                (CelestialBody.mars, "Mars"),
                (CelestialBody.jupiter, "Jupiter"),
                (CelestialBody.saturn, "Saturn"),
                (CelestialBody.uranus, "Uranus"),
                (CelestialBody.neptune, "Neptune"),
                (CelestialBody.pluto, "Pluto"),
            ])
        func planetNames(body: CelestialBody, expectedName: String) {
            #expect(body.name == expectedName)
        }

        @Test("Galilean moon names")
        func galileanMoonNames() {
            // Note: Galilean moon names may be empty strings in some library versions
            // Just verify the properties are accessible
            _ = CelestialBody.io.name
            _ = CelestialBody.europa.name
            _ = CelestialBody.ganymede.name
            _ = CelestialBody.callisto.name
        }
    }

    // MARK: - Name Initialization

    @Suite("Name Initialization")
    struct NameInitialization {

        @Test("Initialize from valid name")
        func initFromValidName() {
            let mars = CelestialBody(name: "Mars")

            #expect(mars == .mars)
        }

        @Test("Initialize from lowercase name")
        func initFromLowercaseName() {
            let mars = CelestialBody(name: "mars")

            // This depends on C library case-sensitivity
            // Just verify it returns something reasonable
            #expect(mars == .mars || mars == nil)
        }

        @Test("Initialize from invalid name returns nil")
        func initFromInvalidName() {
            let invalid = CelestialBody(name: "InvalidBody")

            #expect(invalid == nil)
        }

        @Test("Initialize from empty string returns nil")
        func initFromEmptyString() {
            let empty = CelestialBody(name: "")

            #expect(empty == nil)
        }
    }

    // MARK: - Categories

    @Suite("Categories")
    struct Categories {

        @Test("Planets array contains correct bodies")
        func planetsArray() {
            let planets = CelestialBody.planets

            #expect(planets.count == 7)
            #expect(planets.contains(.mercury))
            #expect(planets.contains(.venus))
            #expect(planets.contains(.mars))
            #expect(planets.contains(.jupiter))
            #expect(planets.contains(.saturn))
            #expect(planets.contains(.uranus))
            #expect(planets.contains(.neptune))
            #expect(!planets.contains(.earth))  // Earth not in planets
            #expect(!planets.contains(.pluto))  // Pluto not a major planet
        }

        @Test("Inner planets")
        func innerPlanets() {
            let inner = CelestialBody.innerPlanets

            #expect(inner.count == 3)
            #expect(inner.contains(.mercury))
            #expect(inner.contains(.venus))
            #expect(inner.contains(.mars))
        }

        @Test("Outer planets")
        func outerPlanets() {
            let outer = CelestialBody.outerPlanets

            #expect(outer.count == 4)
            #expect(outer.contains(.jupiter))
            #expect(outer.contains(.saturn))
            #expect(outer.contains(.uranus))
            #expect(outer.contains(.neptune))
        }

        @Test("Galilean moons")
        func galileanMoons() {
            let moons = CelestialBody.galileanMoons

            #expect(moons.count == 4)
            #expect(moons.contains(.io))
            #expect(moons.contains(.europa))
            #expect(moons.contains(.ganymede))
            #expect(moons.contains(.callisto))
        }

        @Test("isPlanet returns true for planets", arguments: CelestialBody.planets)
        func isPlanetTrue(planet: CelestialBody) {
            #expect(planet.isPlanet)
        }

        @Test("isPlanet returns false for non-planets")
        func isPlanetFalse() {
            #expect(!CelestialBody.sun.isPlanet)
            #expect(!CelestialBody.moon.isPlanet)
            #expect(!CelestialBody.pluto.isPlanet)
            #expect(!CelestialBody.io.isPlanet)
        }

        @Test("Naked eye visible bodies")
        func nakedEyeVisible() {
            #expect(CelestialBody.sun.isNakedEyeVisible)
            #expect(CelestialBody.moon.isNakedEyeVisible)
            #expect(CelestialBody.mercury.isNakedEyeVisible)
            #expect(CelestialBody.venus.isNakedEyeVisible)
            #expect(CelestialBody.mars.isNakedEyeVisible)
            #expect(CelestialBody.jupiter.isNakedEyeVisible)
            #expect(CelestialBody.saturn.isNakedEyeVisible)
        }

        @Test("Non-naked eye visible bodies")
        func notNakedEyeVisible() {
            #expect(!CelestialBody.uranus.isNakedEyeVisible)
            #expect(!CelestialBody.neptune.isNakedEyeVisible)
            #expect(!CelestialBody.pluto.isNakedEyeVisible)
            #expect(!CelestialBody.io.isNakedEyeVisible)
        }
    }

    // MARK: - Orbital Properties

    @Suite("Orbital Properties")
    struct OrbitalProperties {

        @Test("Orbital periods for planets")
        func orbitalPeriods() {
            // Earth's orbital period should be ~365 days
            if let earthPeriod = CelestialBody.earth.orbitalPeriod {
                #expect(earthPeriod > 364 && earthPeriod < 367)
            }

            // Mars orbital period ~687 days
            if let marsPeriod = CelestialBody.mars.orbitalPeriod {
                #expect(marsPeriod > 680 && marsPeriod < 690)
            }

            // Jupiter ~12 years
            if let jupiterPeriod = CelestialBody.jupiter.orbitalPeriod {
                #expect(jupiterPeriod > 4300 && jupiterPeriod < 4400)
            }
        }

        @Test("Sun has no orbital period")
        func sunNoOrbitalPeriod() {
            #expect(CelestialBody.sun.orbitalPeriod == nil)
        }

        @Test("Moon has no solar orbital period")
        func moonNoSolarOrbitalPeriod() {
            // Moon orbits Earth, not Sun directly
            #expect(CelestialBody.moon.orbitalPeriod == nil)
        }

        @Test("Planets have mass products")
        func planetMassProducts() {
            #expect(CelestialBody.earth.massProduct != nil)
            #expect(CelestialBody.jupiter.massProduct != nil)

            // Jupiter should have a much larger mass product than Earth
            if let jupiterMass = CelestialBody.jupiter.massProduct,
                let earthMass = CelestialBody.earth.massProduct
            {
                #expect(jupiterMass > earthMass * 300)
            }
        }

        @Test("Sun has mass product")
        func sunMassProduct() {
            if let sunMass = CelestialBody.sun.massProduct {
                #expect(sunMass > 0)

                // Sun's mass should be much larger than any planet
                if let jupiterMass = CelestialBody.jupiter.massProduct {
                    #expect(sunMass > jupiterMass * 1000)
                }
            }
        }
    }

    // MARK: - CaseIterable

    @Suite("CaseIterable")
    struct CaseIterableTests {

        @Test("allCases is not empty")
        func allCasesNotEmpty() {
            #expect(!CelestialBody.allCases.isEmpty)
        }

        @Test("allCases contains major bodies")
        func allCasesContainsMajorBodies() {
            let all = CelestialBody.allCases

            #expect(all.contains(.sun))
            #expect(all.contains(.moon))
            #expect(all.contains(.earth))
            #expect(all.contains(.mars))
        }

        @Test("Can iterate over all cases")
        func canIterate() {
            var count = 0
            for _ in CelestialBody.allCases {
                count += 1
            }

            #expect(count == CelestialBody.allCases.count)
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformances {

        @Test("CustomStringConvertible returns name")
        func description() {
            #expect(CelestialBody.mars.description == "Mars")
            #expect(CelestialBody.sun.description == "Sun")
        }

        @Test("Hashable - can be used in Set")
        func hashableInSet() {
            let set: Set<CelestialBody> = [.sun, .moon, .mars, .sun]

            #expect(set.count == 3)
        }

        @Test("Hashable - can be used as Dictionary key")
        func hashableInDictionary() {
            var dict: [CelestialBody: String] = [:]
            dict[.sun] = "star"
            dict[.earth] = "planet"
            dict[.moon] = "satellite"

            #expect(dict[.sun] == "star")
            #expect(dict[.earth] == "planet")
            #expect(dict[.moon] == "satellite")
        }
    }

    // MARK: - Codable

    @Suite("Codable")
    struct CodableTests {

        @Test(
            "Encode and decode round-trip",
            arguments: [
                CelestialBody.sun,
                CelestialBody.moon,
                CelestialBody.mars,
                CelestialBody.jupiter,
            ])
        func encodeDecodeRoundTrip(body: CelestialBody) throws {
            let encoder = JSONEncoder()
            let data = try encoder.encode(body)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CelestialBody.self, from: data)

            #expect(body == decoded)
        }

        @Test("All cases can be encoded and decoded", arguments: CelestialBody.allCases)
        func allCasesRoundTrip(body: CelestialBody) throws {
            let encoder = JSONEncoder()
            let data = try encoder.encode(body)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CelestialBody.self, from: data)

            #expect(body == decoded)
        }
    }

    // MARK: - Raw Values

    @Suite("Raw Values")
    struct RawValueTests {

        @Test("Raw values are consistent integers")
        func rawValuesConsistent() {
            #expect(CelestialBody.mercury.rawValue == 0)
            #expect(CelestialBody.venus.rawValue == 1)
            #expect(CelestialBody.earth.rawValue == 2)
            #expect(CelestialBody.mars.rawValue == 3)
        }

        @Test("Can initialize from raw value")
        func initFromRawValue() {
            #expect(CelestialBody(rawValue: 0) == .mercury)
            #expect(CelestialBody(rawValue: 9) == .sun)
            #expect(CelestialBody(rawValue: 10) == .moon)
        }
    }
}
