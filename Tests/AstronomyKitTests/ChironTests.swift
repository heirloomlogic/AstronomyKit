//
//  ChironTests.swift
//  AstronomyKit
//
//  Tests for Chiron position calculations.
//

import Testing

@testable import AstronomyKit

@Suite("Chiron Tests")
struct ChironTests {

    // MARK: - Basic Position Tests

    @Suite("Position Calculations")
    struct PositionTests {

        @Test("Heliocentric position returns valid vector")
        func helioPositionValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let position = try Chiron.helioPosition(at: time)

            // Chiron should be 8-18 AU from the Sun (it varies as a centaur)
            let distance = position.magnitude
            #expect(
                distance > 8.0 && distance < 20.0,
                "Chiron distance \(distance) AU should be between 8 and 20 AU"
            )
        }

        @Test("Geocentric position returns valid vector")
        func geoPositionValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let position = try Chiron.geoPosition(at: time)

            // Geocentric distance should be roughly heliocentric ± 1 AU
            let distance = position.magnitude
            #expect(
                distance > 7.0 && distance < 21.0,
                "Chiron geocentric distance \(distance) AU is reasonable"
            )
        }

        @Test("Equatorial coordinates are valid")
        func equatorialValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let eq = try Chiron.equatorial(at: time)

            #expect(
                eq.rightAscension >= 0 && eq.rightAscension < 24,
                "RA should be in [0, 24) hours"
            )
            #expect(eq.declination >= -90 && eq.declination <= 90, "Dec should be in [-90, 90]°")
            #expect(eq.distance > 0, "Distance should be positive")
        }

        @Test("Ecliptic longitude is in valid range")
        func eclipticLongitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let longitude = try Chiron.eclipticLongitude(at: time)

            #expect(longitude >= 0 && longitude < 360, "Ecliptic longitude should be in [0, 360)°")
        }

        @Test("Ecliptic latitude is in valid range")
        func eclipticLatitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let latitude = try Chiron.eclipticLatitude(at: time)

            // Chiron's orbit has ~7° inclination, so latitude should be modest
            #expect(
                latitude >= -15 && latitude <= 15,
                "Ecliptic latitude \(latitude)° should be reasonable"
            )
        }
    }

    // MARK: - Epoch Reference Tests

    @Suite("Reference Epoch Accuracy")
    struct EpochTests {

        @Test("Position at 2000 epoch matches reference")
        func epoch2000() throws {
            let time = AstroTime(year: 2_000, month: 1, day: 1)
            let position = try Chiron.helioPosition(at: time)

            // Reference from JPL Horizons:
            // X = -3.532082802845036
            // Y = -8.673587566387649
            // Z = -2.935491685233997
            #expect(abs(position.x - (-3.532)) < 0.01, "X component matches reference")
            #expect(abs(position.y - (-8.674)) < 0.01, "Y component matches reference")
            #expect(abs(position.z - (-2.935)) < 0.01, "Z component matches reference")
        }

        @Test("Position at 2020 epoch matches reference")
        func epoch2020() throws {
            let time = AstroTime(year: 2_020, month: 1, day: 1)
            let position = try Chiron.helioPosition(at: time)

            // Reference from JPL Horizons:
            // X = 18.74979015626275
            // Y = 0.9060856547258316
            // Z = 1.445166327129911
            #expect(abs(position.x - 18.750) < 0.01, "X component matches reference")
            #expect(abs(position.y - 0.906) < 0.01, "Y component matches reference")
            #expect(abs(position.z - 1.445) < 0.01, "Z component matches reference")
        }
    }

    // MARK: - Multi-Year Tests

    @Suite("Multi-Year Calculations")
    struct MultiYearTests {

        @Test("Positions over 10 years are consistent")
        func tenYearRange() throws {
            var lastLongitude: Double?

            // Check positions at start of each year from 2020-2030
            for year in 2_020...2_030 {
                let time = AstroTime(year: year, month: 1, day: 1)
                let longitude = try Chiron.eclipticLongitude(at: time)

                #expect(longitude >= 0 && longitude < 360, "Longitude valid for year \(year)")

                if let prev = lastLongitude {
                    // Chiron moves roughly 1-3° per year (50 year orbital period)
                    // Annual change should be modest
                    var delta = longitude - prev
                    if delta < -180 { delta += 360 }
                    if delta > 180 { delta -= 360 }

                    #expect(
                        abs(delta) < 20,
                        "Annual change \(delta)° at year \(year) is reasonable"
                    )
                }

                lastLongitude = longitude
            }
        }
    }

    // MARK: - Horizon Coordinates

    @Suite("Horizon Coordinates")
    struct HorizonTests {

        @Test("Horizon coordinates for observer are valid")
        func horizonValid() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 35.5, longitude: -82.5)  // Asheville, NC
            let horizon = try Chiron.horizon(at: time, from: observer)

            #expect(horizon.altitude >= -90 && horizon.altitude <= 90, "Altitude is valid")
            #expect(horizon.azimuth >= 0 && horizon.azimuth < 360, "Azimuth is valid")
        }
    }

    // MARK: - State Vector Tests

    @Suite("State Vector")
    struct StateVectorTests {

        @Test("Geocentric state has valid velocity")
        func geoStateVelocity() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let state = try Chiron.geoState(at: time)

            // Velocity magnitude should be reasonable for a centaur
            let speed = state.velocity.magnitude
            #expect(speed > 0 && speed < 0.1, "Velocity \(speed) AU/day is reasonable")  // ~5 km/s max
        }
    }
}
