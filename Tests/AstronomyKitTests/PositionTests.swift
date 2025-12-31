//
//  PositionTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Position calculations using swift-testing.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Position Tests")
struct PositionTests {

    // MARK: - Geocentric Position Tests

    @Suite("Geocentric Position")
    struct GeocentricPositionTests {

        @Test("Get geocentric position for Mars")
        func marsGeoPosition() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try CelestialBody.mars.geoPosition(at: time)

            #expect(position.magnitude > 0)
        }

        @Test("Moon is closer than planets")
        func moonCloser() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let moonPos = try CelestialBody.moon.geoPosition(at: time)
            let marsPos = try CelestialBody.mars.geoPosition(at: time)

            #expect(moonPos.magnitude < marsPos.magnitude)
        }

        @Test("Geocentric position has time")
        func positionHasTime() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try CelestialBody.jupiter.geoPosition(at: time)

            #expect(position.time == time)
        }

        @Test("Geocentric position with aberration options")
        func aberrationOptions() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let corrected = try CelestialBody.mars.geoPosition(at: time, aberration: .corrected)
            let uncorrected = try CelestialBody.mars.geoPosition(at: time, aberration: .none)

            // Positions should be slightly different
            #expect(
                corrected.magnitude != uncorrected.magnitude || corrected.x != uncorrected.x
                    || corrected.y != uncorrected.y || corrected.z != uncorrected.z)
        }

        @Test("All planets can get geocentric position", arguments: CelestialBody.planets)
        func allPlanetsGeoPosition(planet: CelestialBody) throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try planet.geoPosition(at: time)

            #expect(position.magnitude > 0)
        }
    }

    // MARK: - Heliocentric Position Tests

    @Suite("Heliocentric Position")
    struct HeliocentricPositionTests {

        @Test("Earth is about 1 AU from Sun")
        func earthDistance() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try CelestialBody.earth.helioPosition(at: time)

            #expect(position.magnitude > 0.98)
            #expect(position.magnitude < 1.02)
        }

        @Test(
            "All planets have heliocentric positions", arguments: CelestialBody.planets + [.earth])
        func allPlanetsHelioPosition(planet: CelestialBody) throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try planet.helioPosition(at: time)

            #expect(position.magnitude > 0)
        }

        @Test("Outer planets are farther than inner planets")
        func outerFartherThanInner() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let marsPos = try CelestialBody.mars.helioPosition(at: time)
            let jupiterPos = try CelestialBody.jupiter.helioPosition(at: time)

            #expect(jupiterPos.magnitude > marsPos.magnitude)
        }

        @Test("Mercury is closest to Sun")
        func mercuryClosest() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let mercuryPos = try CelestialBody.mercury.helioPosition(at: time)

            // Mercury orbit ~0.39 AU
            #expect(mercuryPos.magnitude > 0.3)
            #expect(mercuryPos.magnitude < 0.5)
        }
    }

    // MARK: - Distance From Sun Tests

    @Suite("Distance From Sun")
    struct DistanceFromSunTests {

        @Test("Earth distance is about 1 AU")
        func earthDistance() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let distance = try CelestialBody.earth.distanceFromSun(at: time)

            #expect(distance > 0.98)
            #expect(distance < 1.02)
        }

        @Test("Planet distances are in expected ranges")
        func planetDistanceRanges() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let mercury = try CelestialBody.mercury.distanceFromSun(at: time)
            #expect(mercury > 0.3 && mercury < 0.5)

            let mars = try CelestialBody.mars.distanceFromSun(at: time)
            #expect(mars > 1.3 && mars < 1.7)

            let jupiter = try CelestialBody.jupiter.distanceFromSun(at: time)
            #expect(jupiter > 4.9 && jupiter < 5.5)
        }
    }

    // MARK: - Equatorial Coordinates Tests

    @Suite("Equatorial Coordinates")
    struct EquatorialCoordinatesTests {

        @Test("Equatorial coordinates have valid RA")
        func validRA() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            #expect(eq.rightAscension >= 0)
            #expect(eq.rightAscension < 24)
        }

        @Test("Equatorial coordinates have valid Dec")
        func validDec() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            #expect(eq.declination >= -90)
            #expect(eq.declination <= 90)
        }

        @Test("Equatorial with J2000 vs of-date")
        func equatorDateOptions() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let j2000 = try CelestialBody.mars.equatorial(at: time, equatorDate: .j2000)
            let ofDate = try CelestialBody.mars.equatorial(at: time, equatorDate: .ofDate)

            // Should be slightly different due to precession
            let raDiff = abs(j2000.rightAscension - ofDate.rightAscension)
            // Precession is small but measurable
            #expect(raDiff < 1.0)  // Within 1 hour
        }

        @Test("Equatorial from observer location")
        func fromObserver() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let eq = try CelestialBody.moon.equatorial(at: time, from: observer)

            #expect(eq.rightAscension >= 0)
            #expect(eq.distance > 0)
        }
    }

    // MARK: - Horizon Coordinates Tests

    @Suite("Horizon Coordinates")
    struct HorizonCoordinatesTests {

        @Test("Sun above horizon at noon in summer")
        func sunAtNoon() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 17)  // 12 noon EST = 17 UTC
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)  // NYC

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(horizon.isAboveHorizon)
            #expect(horizon.altitude > 60)  // Sun should be high in summer
        }

        @Test("Sun below horizon at midnight")
        func sunAtMidnight() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 4)  // Midnight EST = 4 UTC
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)  // NYC

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(!horizon.isAboveHorizon)
            #expect(horizon.altitude < 0)
        }
    }

    // MARK: - Ecliptic Longitude Tests

    @Suite("Ecliptic Longitude")
    struct EclipticLongitudeTests {

        @Test("Ecliptic longitude in valid range")
        func validRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let longitude = try CelestialBody.mars.eclipticLongitude(at: time)

            #expect(longitude >= 0)
            #expect(longitude < 360)
        }

        @Test("All planets have ecliptic longitude", arguments: CelestialBody.planets)
        func allPlanetsLongitude(planet: CelestialBody) throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let longitude = try planet.eclipticLongitude(at: time)

            #expect(longitude >= 0)
            #expect(longitude < 360)
        }
    }

    // MARK: - Angle From Sun Tests

    @Suite("Angle From Sun")
    struct AngleFromSunTests {

        @Test("Angle from Sun in valid range")
        func validRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let angle = try CelestialBody.mars.angleFromSun(at: time)

            #expect(angle >= 0)
            #expect(angle <= 180)
        }

        @Test("Moon angle from Sun varies with phase")
        func moonAngleVaries() throws {
            // At new moon, angle should be near 0
            // At full moon, angle should be near 180
            let newMoon = try Moon.searchPhase(
                .new, after: AstroTime(year: 2_025, month: 1, day: 1))
            let fullMoon = try Moon.searchPhase(
                .full, after: AstroTime(year: 2_025, month: 1, day: 1))

            let newMoonAngle = try CelestialBody.moon.angleFromSun(at: newMoon)
            let fullMoonAngle = try CelestialBody.moon.angleFromSun(at: fullMoon)

            #expect(newMoonAngle < 10)
            #expect(fullMoonAngle > 170)
        }
    }

    // MARK: - Sun Position Tests

    @Suite("Sun Position")
    struct SunPositionTests {

        @Test("Get Sun position")
        func getSunPosition() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try Sun.position(at: time)

            #expect(position.longitude >= 0)
            #expect(position.longitude < 360)
        }

        @Test("Sun latitude is near zero")
        func sunLatitudeNearZero() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let position = try Sun.position(at: time)

            // Sun's ecliptic latitude should be essentially zero
            #expect(abs(position.latitude) < 0.0001)
        }

        @Test("Sun at summer solstice is near 90°")
        func summerSolstice() throws {
            let seasons = try Seasons.forYear(2_025)
            let position = try Sun.position(at: seasons.juneSolstice)

            // At June solstice, Sun is at ~90° longitude (Cancer)
            #expect(position.longitude > 88)
            #expect(position.longitude < 92)
        }

        @Test("Sun at winter solstice is near 270°")
        func winterSolstice() throws {
            let seasons = try Seasons.forYear(2_025)
            let position = try Sun.position(at: seasons.decemberSolstice)

            // At December solstice, Sun is at ~270° longitude (Capricorn)
            #expect(position.longitude > 268)
            #expect(position.longitude < 272)
        }

        @Test("Sun at March equinox is near 0°")
        func marchEquinox() throws {
            let seasons = try Seasons.forYear(2_025)
            let position = try Sun.position(at: seasons.marchEquinox)

            // At March equinox, Sun is at ~0° longitude (Aries)
            #expect(position.longitude < 2 || position.longitude > 358)
        }
    }

    // MARK: - Aberration Tests

    @Suite("Aberration")
    struct AberrationTests {

        @Test("Aberration enum cases")
        func aberrationCases() {
            _ = Aberration.none
            _ = Aberration.corrected
        }
    }

    // MARK: - EquatorDate Tests

    @Suite("EquatorDate")
    struct EquatorDateTests {

        @Test("EquatorDate enum cases")
        func equatorDateCases() {
            _ = EquatorDate.j2000
            _ = EquatorDate.ofDate
        }
    }
}
