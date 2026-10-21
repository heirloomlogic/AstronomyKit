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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)

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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)

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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 6)

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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)

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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 0)

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
        let startTime = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)

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

    // MARK: - Extreme Inputs (#57)

    @Test(
        "Non-finite limitDays throws invalidParameter when the altitude is never reached",
        arguments: [Double.infinity, -.infinity, .nan]
    )
    func nonFiniteLimit(limitDays: Double) {
        // The Sun never climbs to 89° at 80° N, so the old loop searched forever.
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try CelestialBody.sun.searchAltitude(
                89,
                direction: .rise,
                after: AstroTime(ut: 9_500),
                from: Observer(latitude: 80, longitude: 0),
                limitDays: limitDays
            )
        }
    }

    @Test(
        "A window that runs into 2^52 days throws badTime instead of stalling there",
        arguments: [(1.0, 10.0), (-1.0, -10.0)]
    )
    func windowReachingStallPoint(sign: Double, limitDays: Double) {
        // The start itself steps normally (0.5 days just below 2^52), so a
        // start-only check would miss this. An altitude of exactly 90° is never
        // crossed, so the search keeps stepping until adding the step stops
        // changing the time, and must then give up. Since #62 the accepted time
        // range rejects this start at the first altitude evaluation, before the
        // step check is reached; the test still pins the outcome.
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.moon.searchAltitude(
                90,
                direction: .rise,
                after: AstroTime(ut: sign * (0x1p52 - 3)),
                from: .primeMeridian,
                limitDays: limitDays
            )
        }
    }
}
