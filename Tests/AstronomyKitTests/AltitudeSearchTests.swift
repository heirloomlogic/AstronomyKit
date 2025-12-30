//
//  AltitudeSearchTests.swift
//  AstronomyKit
//
//  Tests for Altitude Search functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Altitude Search Tests")
struct AltitudeSearchTests {

    let nyc = Observer(latitude: 40.7128, longitude: -74.0060)

    @Test("Find astronomical twilight (Sun at -18°)")
    func astronomicalTwilight() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 12)

        let twilight = try CelestialBody.sun.searchAltitude(
            -18,
            direction: .set,
            after: startTime,
            from: nyc
        )

        #expect(twilight != nil)
        if let t = twilight {
            #expect(t > startTime)
        }
    }

    @Test("Find civil twilight (Sun at -6°)")
    func civilTwilight() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 12)

        let twilight = try CelestialBody.sun.searchAltitude(
            -6,
            direction: .set,
            after: startTime,
            from: nyc
        )

        #expect(twilight != nil)
    }

    @Test("Find when Sun reaches 30° altitude")
    func sunAt30Degrees() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 6)

        let time = try CelestialBody.sun.searchAltitude(
            30,
            direction: .rise,
            after: startTime,
            from: nyc
        )

        #expect(time != nil)
    }

    @Test("Rising vs setting gives different times")
    func risingVsSetting() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 12)

        let rising = try CelestialBody.sun.searchAltitude(
            10,
            direction: .rise,
            after: startTime,
            from: nyc
        )

        let setting = try CelestialBody.sun.searchAltitude(
            10,
            direction: .set,
            after: startTime,
            from: nyc
        )

        #expect(rising != setting)
    }

    @Test("Works for planets")
    func planetsWork() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 0)

        let marsRising = try CelestialBody.mars.searchAltitude(
            10,
            direction: .rise,
            after: startTime,
            from: nyc
        )

        // Should find Mars rising to 10° at some point
        #expect(marsRising != nil)
    }

    @Test("Returns nil when not found in limit")
    func returnsNilWhenNotFound() throws {
        let startTime = AstroTime(year: 2025, month: 6, day: 21, hour: 12)

        // Search for Sun at 90° (impossible from NYC)
        let result = try CelestialBody.sun.searchAltitude(
            90,
            direction: .rise,
            after: startTime,
            from: nyc,
            limitDays: 1
        )

        #expect(result == nil)
    }
}
