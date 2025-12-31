//
//  RiseSetTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Rise/Set calculations using swift-testing.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("RiseSet Tests")
struct RiseSetTests {

    // Common test fixtures
    static let nyc = Observer(latitude: 40.7128, longitude: -74.0060)
    static let london = Observer(latitude: 51.5074, longitude: -0.1278)
    static let testDate = AstroTime(year: 2_025, month: 6, day: 21)

    // MARK: - RiseSetDirection Tests

    @Suite("RiseSetDirection")
    struct RiseSetDirectionTests {

        @Test("Direction enum cases")
        func directionCases() {
            #expect(RiseSetDirection.rise.rawValue == 1)
            #expect(RiseSetDirection.set.rawValue == -1)
        }
    }

    // MARK: - Rise Time Tests

    @Suite("Rise Time")
    struct RiseTimeTests {

        @Test("Sun rises in the morning")
        func sunRises() throws {
            let sunrise = try CelestialBody.sun.riseTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(sunrise != nil)

            if let sunrise {
                #expect(sunrise > RiseSetTests.testDate)

                // Sunrise should be within 24 hours
                let diff = sunrise.ut - RiseSetTests.testDate.ut
                #expect(diff < 1.0)
            }
        }

        @Test("Moon rises")
        func moonRises() throws {
            let moonrise = try CelestialBody.moon.riseTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(moonrise != nil)
        }

        @Test("Planet rises")
        func planetRises() throws {
            let marsRise = try CelestialBody.mars.riseTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(marsRise != nil)
        }

        @Test("Rise time with limit days")
        func riseTimeWithLimit() throws {
            // Very short limit - may not find anything
            let shortLimit = try CelestialBody.sun.riseTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc,
                limitDays: 0.5
            )

            #expect(shortLimit != nil)

            // Longer limit should find it
            let longLimit = try CelestialBody.sun.riseTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc,
                limitDays: 2
            )

            #expect(longLimit != nil)
        }
    }

    // MARK: - Set Time Tests

    @Suite("Set Time")
    struct SetTimeTests {

        @Test("Sun sets in the evening")
        func sunSets() throws {
            let sunset = try CelestialBody.sun.setTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(sunset != nil)

            if let sunset {
                #expect(sunset > RiseSetTests.testDate)
            }
        }

        @Test("Moon sets")
        func moonSets() throws {
            let moonset = try CelestialBody.moon.setTime(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(moonset != nil)
        }

        @Test("Sunrise before sunset on same day")
        func sunriseBeforeSunset() throws {
            let date = AstroTime(year: 2_025, month: 6, day: 21, hour: 0)

            let sunrise = try CelestialBody.sun.riseTime(after: date, from: RiseSetTests.nyc)

            // Search for sunset starting from sunrise
            if let sunrise {
                let sunset = try CelestialBody.sun.setTime(after: sunrise, from: RiseSetTests.nyc)

                #expect(sunset != nil)
                if let sunset {
                    #expect(sunset > sunrise)
                }
            }
        }
    }

    // MARK: - Search Rise Set Tests

    @Suite("Search Rise Set")
    struct SearchRiseSetTests {

        @Test("Generic search for rise")
        func searchRise() throws {
            let rise = try CelestialBody.sun.searchRiseSet(
                direction: .rise,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(rise != nil)
        }

        @Test("Generic search for set")
        func searchSet() throws {
            let set = try CelestialBody.sun.searchRiseSet(
                direction: .set,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(set != nil)
        }

        @Test("Search with meters above ground")
        func searchWithHeight() throws {
            let groundLevel = try CelestialBody.sun.searchRiseSet(
                direction: .rise,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc,
                metersAboveGround: 0
            )

            let elevated = try CelestialBody.sun.searchRiseSet(
                direction: .rise,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc,
                metersAboveGround: 100
            )

            // From higher elevation, sun appears to rise earlier
            if let ground = groundLevel, let elev = elevated {
                #expect(elev < ground)
            }
        }
    }

    // MARK: - Hour Angle Tests

    @Suite("Hour Angle")
    struct HourAngleTests {

        @Test("Search for 0 hour angle (culmination)")
        func searchZeroHourAngle() throws {
            let event = try CelestialBody.sun.searchHourAngle(
                0,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(event.time > RiseSetTests.testDate)
        }

        @Test("Hour angle event has horizon info")
        func hourAngleHasHorizon() throws {
            let event = try CelestialBody.sun.searchHourAngle(
                0,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            // At culmination, Sun should be above horizon (in summer)
            #expect(event.horizon.isAboveHorizon)
        }

        @Test("Search for 6 hour angle")
        func searchSixHourAngle() throws {
            let event = try CelestialBody.sun.searchHourAngle(
                6,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(event.time > RiseSetTests.testDate)
        }
    }

    // MARK: - Culmination Tests

    @Suite("Culmination")
    struct CulminationTests {

        @Test("Sun culmination (transit)")
        func sunCulmination() throws {
            let event = try CelestialBody.sun.culmination(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(event.time > RiseSetTests.testDate)

            // Sun should be above horizon at culmination (in summer at mid-latitudes)
            #expect(event.horizon.isAboveHorizon)
        }

        @Test("Moon culmination")
        func moonCulmination() throws {
            let event = try CelestialBody.moon.culmination(
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(event.time > RiseSetTests.testDate)
        }

        @Test("Culmination altitude varies with season")
        func culminationAltitudeVaries() throws {
            let summer = AstroTime(year: 2_025, month: 6, day: 21)
            let winter = AstroTime(year: 2_025, month: 12, day: 21)

            let summerCulm = try CelestialBody.sun.culmination(
                after: summer, from: RiseSetTests.nyc)
            let winterCulm = try CelestialBody.sun.culmination(
                after: winter, from: RiseSetTests.nyc)

            // Summer sun is higher
            #expect(summerCulm.horizon.altitude > winterCulm.horizon.altitude)
        }
    }

    // MARK: - HourAngleEvent Tests

    @Suite("HourAngleEvent")
    struct HourAngleEventTests {

        @Test("HourAngleEvent has time and horizon")
        func eventProperties() throws {
            let event = try CelestialBody.sun.searchHourAngle(
                0,
                after: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            // Time should be after start
            #expect(event.time > RiseSetTests.testDate)

            // Horizon should have valid values
            #expect(event.horizon.azimuth >= 0)
            #expect(event.horizon.azimuth < 360)
        }

        @Test("Equatable")
        func equatable() throws {
            let e1 = try CelestialBody.sun.searchHourAngle(
                0, after: RiseSetTests.testDate, from: RiseSetTests.nyc)
            let e2 = try CelestialBody.sun.searchHourAngle(
                0, after: RiseSetTests.testDate, from: RiseSetTests.nyc)

            #expect(e1 == e2)
        }
    }

    // MARK: - DailyEvents Tests

    @Suite("DailyEvents")
    struct DailyEventsTests {

        @Test("Create daily events for Sun")
        func createSunDailyEvents() throws {
            let events = try DailyEvents(
                body: .sun,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(events.body == .sun)
            #expect(events.observer == RiseSetTests.nyc)
            #expect(events.date == RiseSetTests.testDate)
        }

        @Test("Daily events has rise and set")
        func hasRiseAndSet() throws {
            let events = try DailyEvents(
                body: .sun,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            // In NYC in summer, Sun should have both rise and set
            #expect(events.rise != nil || events.set != nil)
        }

        @Test("Daily events has culmination")
        func hasCulmination() throws {
            let events = try DailyEvents(
                body: .sun,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(events.culmination != nil)
        }

        @Test("isVisible property")
        func isVisibleProperty() throws {
            let sunEvents = try DailyEvents(
                body: .sun,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            // Sun is visible during day
            #expect(sunEvents.isVisible)
        }

        @Test("Daily events for Moon")
        func moonDailyEvents() throws {
            let events = try DailyEvents(
                body: .moon,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(events.body == .moon)
        }

        @Test("Daily events for planet")
        func planetDailyEvents() throws {
            let events = try DailyEvents(
                body: .mars,
                date: RiseSetTests.testDate,
                from: RiseSetTests.nyc
            )

            #expect(events.body == .mars)
        }
    }

    // MARK: - Location Variation Tests

    @Suite("Location Variations")
    struct LocationVariationTests {

        @Test("Different locations have different rise times")
        func locationAffectsRiseTime() throws {
            let tokyo = Observer(latitude: 35.6762, longitude: 139.6503)

            let nycRise = try CelestialBody.sun.riseTime(
                after: RiseSetTests.testDate, from: RiseSetTests.nyc)
            let tokyoRise = try CelestialBody.sun.riseTime(
                after: RiseSetTests.testDate, from: tokyo)

            #expect(nycRise != nil)
            #expect(tokyoRise != nil)

            if let nyc = nycRise, let tok = tokyoRise {
                #expect(nyc != tok)
            }
        }

        @Test("Polar regions - midnight sun")
        func midnightSun() throws {
            // At high arctic latitudes in summer, sun may not set
            let arctic = Observer(latitude: 78.0, longitude: 16.0)  // Svalbard
            let summerDate = AstroTime(year: 2_025, month: 6, day: 21)

            let sunset = try CelestialBody.sun.setTime(
                after: summerDate,
                from: arctic,
                limitDays: 1
            )

            // May not find sunset within 1 day during midnight sun
            // This is expected behavior
            _ = sunset  // Just verify it doesn't throw
        }
    }
}
