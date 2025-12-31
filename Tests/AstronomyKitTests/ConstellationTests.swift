//
//  ConstellationTests.swift
//  AstronomyKit
//
//  Tests for Constellation functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Constellation Tests")
struct ConstellationTests {

    @Test("Find Orion from Betelgeuse coordinates")
    func findOrion() throws {
        // Betelgeuse RA ~5.92h, Dec ~7.41°
        let constellation = try Constellation.find(ra: 5.92, dec: 7.41)

        #expect(constellation.symbol == "Ori")
        #expect(constellation.name == "Orion")
    }

    @Test("Find Ursa Minor from Polaris coordinates")
    func findUrsaMinor() throws {
        // Polaris RA ~2.53h, Dec ~89.26°
        let constellation = try Constellation.find(ra: 2.53, dec: 89.26)

        #expect(constellation.symbol == "UMi")
        #expect(constellation.name == "Ursa Minor")
    }

    @Test("Constellation has B1875 coordinates")
    func hasB1875Coordinates() throws {
        let constellation = try Constellation.find(ra: 5.92, dec: 7.41)

        // B1875 coordinates should be defined
        #expect(constellation.ra1875 >= 0 && constellation.ra1875 <= 24)
        #expect(constellation.dec1875 >= -90 && constellation.dec1875 <= 90)
    }

    @Test("CelestialBody constellation lookup")
    func bodyConstellation() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let constellation = try CelestialBody.mars.constellation(at: time)

        // Mars should be in some constellation
        #expect(!constellation.symbol.isEmpty)
        #expect(!constellation.name.isEmpty)
    }

    @Test("Constellation is Equatable")
    func equatable() throws {
        let c1 = try Constellation.find(ra: 5.92, dec: 7.41)
        let c2 = try Constellation.find(ra: 5.92, dec: 7.41)

        #expect(c1 == c2)
    }

    @Test("Constellation is Hashable")
    func hashable() throws {
        let c1 = try Constellation.find(ra: 5.92, dec: 7.41)
        let c2 = try Constellation.find(ra: 2.53, dec: 89.26)

        let set: Set<Constellation> = [c1, c2]
        #expect(set.count == 2)
    }

    @Test("CustomStringConvertible")
    func description() throws {
        let constellation = try Constellation.find(ra: 5.92, dec: 7.41)

        #expect(constellation.description.contains("Ori"))
        #expect(constellation.description.contains("Orion"))
    }
}
