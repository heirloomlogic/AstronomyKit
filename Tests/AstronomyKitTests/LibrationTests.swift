//
//  LibrationTests.swift
//  AstronomyKit
//
//  Tests for Libration functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Libration Tests")
struct LibrationTests {

    @Test("Libration returns valid data")
    func librationReturnsData() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let libration = Moon.libration(at: time)

        // Sub-Earth point latitude/longitude should be reasonable
        #expect(libration.subEarthLatitude >= -10 && libration.subEarthLatitude <= 10)
        #expect(libration.subEarthLongitude >= -10 && libration.subEarthLongitude <= 10)
    }

    @Test("Moon latitude and longitude are valid")
    func moonCoordinates() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let libration = Moon.libration(at: time)

        #expect(libration.moonLatitude >= -90 && libration.moonLatitude <= 90)
        #expect(libration.moonLongitude >= 0 && libration.moonLongitude <= 360)
    }

    @Test("Moon distance is in expected range")
    func moonDistance() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let libration = Moon.libration(at: time)

        // Moon distance ~356,000-406,000 km
        #expect(libration.distanceKM > 350000)
        #expect(libration.distanceKM < 410000)
    }

    @Test("Apparent diameter is reasonable")
    func apparentDiameter() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let libration = Moon.libration(at: time)

        // Moon apparent diameter ~0.49° to 0.56°
        #expect(libration.apparentDiameter > 0.48)
        #expect(libration.apparentDiameter < 0.57)
    }

    @Test("Libration changes over time")
    func librationChanges() {
        let time1 = AstroTime(year: 2025, month: 1, day: 1)
        let time2 = AstroTime(year: 2025, month: 1, day: 15)

        let lib1 = Moon.libration(at: time1)
        let lib2 = Moon.libration(at: time2)

        // Libration values should differ over 2 weeks
        #expect(lib1.subEarthLongitude != lib2.subEarthLongitude)
    }

    @Test("Libration is Equatable")
    func equatable() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let lib1 = Moon.libration(at: time)
        let lib2 = Moon.libration(at: time)

        #expect(lib1 == lib2)
    }

    @Test("CustomStringConvertible")
    func description() {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let libration = Moon.libration(at: time)

        #expect(libration.description.contains("Libration"))
        #expect(libration.description.contains("km"))
    }
}
