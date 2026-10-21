//
//  FixedStarTests.swift
//  AstronomyKit
//
//  Tests for FixedStar functionality.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Fixed Star Tests")
struct FixedStarTests {
    // MARK: - Test Subject

    /// Algol (Beta Persei) - used as test subject for all fixed star tests.
    ///
    /// J2000 coordinates from SIMBAD/Hipparcos.
    static let algol = FixedStar(
        name: "Algol",
        rightAscension: 3.136148,  // 03h 08m 10.13s
        declination: 40.9556,  // +40° 57′ 20.3″
        distance: 92.95  // light-years
    )

    // MARK: - Input Validation Tests

    @Suite("Input Validation")
    struct InputValidation {
        @Test("Star with NaN right ascension throws invalidParameter")
        func nanRightAscensionThrows() {
            let star = FixedStar(
                name: "Bad",
                rightAscension: .nan,
                declination: 0,
                distance: 100
            )
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try star.equatorial(at: time)
            }
        }
    }

    // MARK: - Initialization Tests

    @Suite("Initialization")
    struct InitializationTests {
        @Test("Create fixed star with valid coordinates")
        func createStar() {
            let star = FixedStarTests.algol
            #expect(star.name == "Algol")
            #expect(star.rightAscension == 3.136148)
            #expect(star.declination == 40.9556)
            #expect(star.distance == 92.95)
        }

        @Test("Fixed star is Hashable")
        func hashable() {
            let algol1 = FixedStar(name: "Algol", rightAscension: 3.136148, declination: 40.9556, distance: 92.95)
            let algol2 = FixedStar(name: "Algol", rightAscension: 3.136148, declination: 40.9556, distance: 92.95)

            #expect(algol1 == algol2)
            #expect(algol1.hashValue == algol2.hashValue)
        }

        @Test("Fixed star description is name")
        func description() {
            let star = FixedStarTests.algol
            #expect(star.description == "Algol")
        }
    }

    // MARK: - Equatorial Coordinate Tests

    @Suite("Equatorial Coordinates")
    struct EquatorialTests {
        @Test("RA matches catalog value")
        func raMatchesCatalog() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let eq = try FixedStarTests.algol.equatorial(at: time)

            // Catalog RA: 3.136148 hours (03h 08m 10.13s)
            // Allow 0.1 hour tolerance for J2000 coordinates
            #expect(
                abs(eq.rightAscension - 3.136) < 0.1,
                "RA \(eq.rightAscension)h should be close to catalog value 3.136h"
            )
        }

        @Test("Dec matches catalog value")
        func decMatchesCatalog() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let eq = try FixedStarTests.algol.equatorial(at: time)

            // Catalog Dec: +40.9556° (+40° 57′ 20.3″)
            // Allow 0.5° tolerance
            #expect(
                abs(eq.declination - 40.956) < 0.5,
                "Dec \(eq.declination)° should be close to catalog value +40.956°"
            )
        }

        @Test("Distance is positive")
        func distancePositive() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let eq = try FixedStarTests.algol.equatorial(at: time)

            #expect(eq.distance > 0, "Distance should be positive")
        }
    }

    // MARK: - Ecliptic Coordinate Tests

    @Suite("Ecliptic Coordinates")
    struct EclipticTests {
        @Test("Ecliptic longitude is in valid range")
        func eclipticLongitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let longitude = try FixedStarTests.algol.eclipticLongitude(at: time)

            #expect(
                longitude >= 0 && longitude < 360,
                "Ecliptic longitude should be in [0, 360)°"
            )
        }

        @Test("Ecliptic longitude is approximately 26° Taurus")
        func eclipticLongitudeExpectedValue() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let longitude = try FixedStarTests.algol.eclipticLongitude(at: time)

            // Algol is traditionally at ~26° Taurus = ~56° ecliptic longitude
            // Allow 2° tolerance for calculation method differences
            #expect(
                abs(longitude - 56.0) < 2.0,
                "Ecliptic longitude \(longitude)° should be near 56° (26° Taurus)"
            )
        }

        @Test("Ecliptic latitude is in valid range")
        func eclipticLatitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let latitude = try FixedStarTests.algol.eclipticLatitude(at: time)

            #expect(
                latitude >= -90 && latitude <= 90,
                "Ecliptic latitude should be in [-90, +90]°"
            )
        }

        @Test("Full ecliptic coordinates are consistent")
        func eclipticConsistent() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)

            let longitude = try FixedStarTests.algol.eclipticLongitude(at: time)
            let latitude = try FixedStarTests.algol.eclipticLatitude(at: time)
            let ecliptic = try FixedStarTests.algol.ecliptic(at: time)

            #expect(
                abs(ecliptic.longitude - longitude) < 0.001,
                "Ecliptic longitude should match"
            )
            #expect(
                abs(ecliptic.latitude - latitude) < 0.001,
                "Ecliptic latitude should match"
            )
        }
    }

    // MARK: - Ecliptic of Date Tests

    /// Checks `ecliptic(at:)` against the true ecliptic and equinox of date at
    /// epochs a century either side of J2000, where the J2000 ecliptic is off
    /// by about 1.4° of precession.
    ///
    /// References come from pyerfa 2.0.1.5 (SOFA): the catalog direction less
    /// Earth's heliocentric position from `epv00`, annual aberration from
    /// `ab` with Earth's barycentric velocity, the IAU 2006/2000A
    /// bias-precession-nutation matrix `pnm06a`, and a rotation by the true
    /// obliquity (`obl06` plus the `nut06a` obliquity nutation). The engine
    /// uses IAU 1976 precession and IAU 2000B nutation; measured residuals
    /// against these references are at most 0.023″. The references take the
    /// calendar instants as TT; the engine's Delta T (up to 203 s at 2100)
    /// moves a star by far less than that.
    @Suite("Ecliptic of Date")
    struct EclipticOfDateTests {
        struct Reference: Sendable, CustomTestStringConvertible {
            let star: FixedStar
            let time: AstroTime
            let longitude: Double
            let latitude: Double

            var testDescription: String { "\(star.name) \(time)" }
        }

        /// Hipparcos J2000 positions (proper motion ignored, as the engine does).
        static let regulus = FixedStar(
            name: "Regulus",
            rightAscension: 10.13953083,
            declination: 11.96720833,
            distance: 79.3
        )
        static let spica = FixedStar(
            name: "Spica",
            rightAscension: 13.41988306,
            declination: -11.16131944,
            distance: 250.0
        )

        static let t1900 = AstroTime(year: 1_900, month: 1, day: 1, hour: 12)
        static let t2026 = AstroTime(year: 2_026, month: 7, day: 24, hour: 0)
        static let t2100 = AstroTime(year: 2_100, month: 1, day: 1, hour: 12)

        static let references: [Reference] = [
            Reference(star: regulus, time: t1900, longitude: 148.4412662, latitude: 0.4592337),
            Reference(star: regulus, time: t2026, longitude: 150.1977578, latitude: 0.4663342),
            Reference(star: regulus, time: t2100, longitude: 151.2310570, latitude: 0.4702852),
            Reference(star: spica, time: t1900, longitude: 202.4489112, latitude: -2.0480062),
            Reference(star: spica, time: t2026, longitude: 204.2140540, latitude: -2.0563696),
            Reference(star: spica, time: t2100, longitude: 205.2376442, latitude: -2.0606519),
        ]

        /// 0.36″: about 15 times the measured residual, and about 1/14,000
        /// of the J2000-frame error at these epochs.
        static let tolerance = 1e-4

        @Test("Matches an independent true-ecliptic-of-date reference", arguments: references)
        func matchesReference(_ reference: Reference) throws {
            let time = reference.time
            let ecliptic = try reference.star.ecliptic(at: time)

            #expect(
                abs(ecliptic.longitude - reference.longitude) < Self.tolerance,
                "longitude \(ecliptic.longitude)° vs reference \(reference.longitude)°"
            )
            #expect(
                abs(ecliptic.latitude - reference.latitude) < Self.tolerance,
                "latitude \(ecliptic.latitude)° vs reference \(reference.latitude)°"
            )
            #expect(try reference.star.eclipticLongitude(at: time) == ecliptic.longitude)
            #expect(try reference.star.eclipticLatitude(at: time) == ecliptic.latitude)
        }
    }

    // MARK: - Horizon Coordinate Tests

    @Suite("Horizon Coordinates")
    struct HorizonTests {
        @Test("Horizon coordinates are valid")
        func horizonValid() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 35.5, longitude: -82.5)  // Asheville, NC
            let horizon = try FixedStarTests.algol.horizon(at: time, from: observer)

            #expect(
                horizon.altitude >= -90 && horizon.altitude <= 90,
                "Altitude should be in [-90, +90]°"
            )
            #expect(
                horizon.azimuth >= 0 && horizon.azimuth < 360,
                "Azimuth should be in [0, 360)°"
            )
        }

        @Test("High latitude observer sees Algol")
        func highLatitudeObserver() throws {
            // Algol at Dec +41° is circumpolar for observers above ~49°N
            let time = AstroTime(year: 2_025, month: 1, day: 1, hour: 0)
            let observer = Observer(latitude: 55.0, longitude: 0.0)  // Northern UK
            let horizon = try FixedStarTests.algol.horizon(at: time, from: observer)

            // At this latitude, Algol should never set very far below horizon
            #expect(
                horizon.altitude > -50,
                "Algol should be visible or nearly circumpolar at 55°N"
            )
        }
    }

    // MARK: - Stability Tests

    @Suite("Position Stability")
    struct StabilityTests {
        @Test("Position is stable across multiple calls")
        func stablePosition() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)

            let lng1 = try FixedStarTests.algol.eclipticLongitude(at: time)
            let lng2 = try FixedStarTests.algol.eclipticLongitude(at: time)

            #expect(
                abs(lng1 - lng2) < 0.0001,
                "Position should be identical for same time"
            )
        }

        @Test("Position varies minimally over one year")
        func yearlyStability() throws {
            // Fixed stars should have minimal position change over a year
            // (only aberration and light-time effects)
            let time1 = AstroTime(year: 2_025, month: 1, day: 1)
            let time2 = AstroTime(year: 2_025, month: 7, day: 1)

            let lng1 = try FixedStarTests.algol.eclipticLongitude(at: time1)
            let lng2 = try FixedStarTests.algol.eclipticLongitude(at: time2)

            // Should vary by less than 1° due to aberration effects
            let delta = abs(lng1 - lng2)
            #expect(
                delta < 1.0,
                "Ecliptic longitude change \(delta)° over 6 months should be < 1°"
            )
        }
    }

    // MARK: - Multiple Stars Tests

    @Suite("Multiple Stars")
    struct MultipleStarsTests {
        @Test("Multiple stars work correctly")
        func multipleStars() throws {
            let algol = FixedStar(name: "Algol", rightAscension: 3.136148, declination: 40.9556, distance: 92.95)
            let sirius = FixedStar(name: "Sirius", rightAscension: 6.7525, declination: -16.7161, distance: 8.6)

            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let algolLon = try algol.eclipticLongitude(at: time)
            let siriusLon = try sirius.eclipticLongitude(at: time)

            // They should have different longitudes
            #expect(
                abs(algolLon - siriusLon) > 10,
                "Different stars should have different longitudes"
            )
        }

        @Test("Stars can be interleaved")
        func interleavedStars() throws {
            let algol = FixedStar(name: "Algol", rightAscension: 3.136148, declination: 40.9556, distance: 92.95)
            let sirius = FixedStar(name: "Sirius", rightAscension: 6.7525, declination: -16.7161, distance: 8.6)

            let time = AstroTime(year: 2_025, month: 1, day: 1)

            // Interleave calls to ensure slot switching works
            let algolLon1 = try algol.eclipticLongitude(at: time)
            let siriusLon1 = try sirius.eclipticLongitude(at: time)
            let algolLon2 = try algol.eclipticLongitude(at: time)
            let siriusLon2 = try sirius.eclipticLongitude(at: time)

            #expect(abs(algolLon1 - algolLon2) < 0.0001, "Algol should be consistent")
            #expect(abs(siriusLon1 - siriusLon2) < 0.0001, "Sirius should be consistent")
        }

        @Test("Many stars can be defined")
        func manyStars() throws {
            // Create more than 8 stars to prove there's no slot limit
            let stars = (0..<20).map { i in
                FixedStar(
                    name: "Star\(i)",
                    rightAscension: Double(i) + 1.0,
                    declination: Double(i) * 4.0 - 40.0,
                    distance: 100.0
                )
            }

            let time = AstroTime(year: 2_025, month: 1, day: 1)

            // All stars should calculate without error
            for star in stars {
                let longitude = try star.eclipticLongitude(at: time)
                #expect(longitude >= 0 && longitude < 360)
            }
        }
    }

    // MARK: - Constellation Tests

    @Suite("Constellation")
    struct ConstellationTests {
        @Test("Algol is in Perseus")
        func algolConstellation() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let constellation = try FixedStarTests.algol.constellation(at: time)

            #expect(constellation.symbol == "Per", "Algol should be in Perseus")
        }
    }
}
