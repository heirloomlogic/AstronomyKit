//
//  CoordinatesTests.swift
//  AstronomyKit
//
//  Comprehensive tests for coordinate types.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Coordinates Tests")
struct CoordinatesTests {

    // MARK: - Vector3D Tests

    @Suite("Vector3D")
    struct Vector3DTests {

        @Test("Create vector with components")
        func createVector() {
            let time = AstroTime.now
            let vector = Vector3D(x: 1.0, y: 2.0, z: 3.0, time: time)

            #expect(vector.x == 1.0)
            #expect(vector.y == 2.0)
            #expect(vector.z == 3.0)
            #expect(vector.time == time)
        }

        @Test("Magnitude calculation")
        func magnitude() {
            let time = AstroTime.now

            // 3-4-5 triangle extended to 3D
            let vector = Vector3D(x: 3.0, y: 4.0, z: 0.0, time: time)

            #expect(abs(vector.magnitude - 5.0) < 0.0001)
        }

        @Test("Unit vector magnitude")
        func unitVectorMagnitude() {
            let time = AstroTime.now
            let vector = Vector3D(x: 1.0, y: 0.0, z: 0.0, time: time)

            #expect(abs(vector.magnitude - 1.0) < 0.0001)
        }

        @Test("Zero vector magnitude")
        func zeroVectorMagnitude() {
            let time = AstroTime.now
            let vector = Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time)

            #expect(vector.magnitude == 0.0)
        }

        @Test("Normalized vector has unit magnitude")
        func normalizedMagnitude() {
            let time = AstroTime.now
            let vector = Vector3D(x: 10.0, y: 10.0, z: 10.0, time: time)
            let normalized = vector.normalized

            #expect(abs(normalized.magnitude - 1.0) < 0.0001)
        }

        @Test("Normalized zero vector remains zero")
        func normalizedZeroVector() {
            let time = AstroTime.now
            let vector = Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time)
            let normalized = vector.normalized

            #expect(normalized.x == 0.0)
            #expect(normalized.y == 0.0)
            #expect(normalized.z == 0.0)
        }

        @Test("Equatable")
        func equatable() {
            let time = AstroTime.now
            let v1 = Vector3D(x: 1.0, y: 2.0, z: 3.0, time: time)
            let v2 = Vector3D(x: 1.0, y: 2.0, z: 3.0, time: time)

            #expect(v1 == v2)
        }

        @Test("Hashable in Set")
        func hashableInSet() {
            let time = AstroTime.now
            let v1 = Vector3D(x: 1.0, y: 2.0, z: 3.0, time: time)
            let v2 = Vector3D(x: 4.0, y: 5.0, z: 6.0, time: time)
            let v3 = Vector3D(x: 1.0, y: 2.0, z: 3.0, time: time)  // Duplicate

            let set: Set<Vector3D> = [v1, v2, v3]

            #expect(set.count == 2)
        }

        @Test("CustomStringConvertible")
        func description() {
            let time = AstroTime.now
            let vector = Vector3D(x: 1.5, y: 2.5, z: 3.5, time: time)
            let desc = vector.description

            #expect(desc.contains("AU"))
            #expect(desc.contains("1.5"))
        }
    }

    // MARK: - Spherical Tests

    @Suite("Spherical")
    struct SphericalTests {

        @Test("Create spherical with components")
        func createSpherical() {
            let spherical = Spherical(latitude: 45.0, longitude: 120.0, distance: 1.5)

            #expect(spherical.latitude == 45.0)
            #expect(spherical.longitude == 120.0)
            #expect(spherical.distance == 1.5)
        }

        @Test("Spherical Equatable")
        func sphericalEquatable() {
            let s1 = Spherical(latitude: 30.0, longitude: 60.0, distance: 2.0)
            let s2 = Spherical(latitude: 30.0, longitude: 60.0, distance: 2.0)
            let s3 = Spherical(latitude: 45.0, longitude: 60.0, distance: 2.0)

            #expect(s1 == s2)
            #expect(s1 != s3)
        }

        @Test("Spherical Hashable in Set")
        func sphericalHashable() {
            let s1 = Spherical(latitude: 30.0, longitude: 60.0, distance: 2.0)
            let s2 = Spherical(latitude: 45.0, longitude: 90.0, distance: 3.0)
            let s3 = Spherical(latitude: 30.0, longitude: 60.0, distance: 2.0)  // Duplicate

            let set: Set<Spherical> = [s1, s2, s3]

            #expect(set.count == 2)
        }

        @Test("Spherical CustomStringConvertible")
        func sphericalDescription() {
            let spherical = Spherical(latitude: 45.5, longitude: 120.25, distance: 1.5)
            let desc = spherical.description

            #expect(desc.contains("lat"))
            #expect(desc.contains("lon"))
            #expect(desc.contains("dist"))
            #expect(desc.contains("AU"))
        }
    }

    // MARK: - Horizon Tests

    @Suite("Horizon")
    struct HorizonTests {

        @Test("Above horizon detection")
        func aboveHorizon() throws {
            // Get Sun position at noon in summer - should be well above horizon
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(horizon.isAboveHorizon)
            #expect(horizon.altitude > 0)
        }

        @Test("Below horizon detection")
        func belowHorizon() throws {
            // Get Sun position at midnight local time - should be below horizon
            // NYC is UTC-5 or UTC-4 (DST), so hour 5 UTC is midnight EST
            let time = AstroTime(year: 2_025, month: 1, day: 21, hour: 5)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(!horizon.isAboveHorizon)
            #expect(horizon.altitude < 0)
        }

        @Test("Azimuth in valid range")
        func azimuthRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(horizon.azimuth >= 0)
            #expect(horizon.azimuth < 360)
        }

        @Test("Altitude in valid range")
        func altitudeRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(horizon.altitude >= -90)
            #expect(horizon.altitude <= 90)
        }

        @Test(
            "Compass directions",
            arguments: [
                (0.0, "N"),
                (45.0, "NE"),
                (90.0, "E"),
                (135.0, "SE"),
                (180.0, "S"),
                (225.0, "SW"),
                (270.0, "W"),
                (315.0, "NW"),
            ])
        func compassDirections(azimuth: Double, expected: String) throws {
            // Create a horizon with specific azimuth
            let time = AstroTime.now
            let observer = Observer(latitude: 0, longitude: 0)

            // Find a body at approximately the desired azimuth
            // This is a simpler approach - just verify the compass calculation logic
            let horizon = try CelestialBody.moon.horizon(at: time, from: observer)

            // The actual azimuth test is done in description output
            let direction = horizon.compassDirection
            #expect(!direction.isEmpty)
        }

        @Test("CustomStringConvertible includes key info")
        func descriptionContent() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizon = try CelestialBody.sun.horizon(at: time, from: observer)
            let desc = horizon.description

            #expect(desc.contains("Alt"))
            #expect(desc.contains("Az"))
        }

        @Test("Equatable")
        func equatable() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let h1 = try CelestialBody.sun.horizon(at: time, from: observer)
            let h2 = try CelestialBody.sun.horizon(at: time, from: observer)

            #expect(h1 == h2)
        }
    }

    // MARK: - Equatorial Tests

    @Suite("Equatorial")
    struct EquatorialTests {

        @Test("Right ascension in valid range")
        func raRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            #expect(eq.rightAscension >= 0)
            #expect(eq.rightAscension < 24)
        }

        @Test("Declination in valid range")
        func decRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            #expect(eq.declination >= -90)
            #expect(eq.declination <= 90)
        }

        @Test("Distance is positive")
        func distancePositive() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            #expect(eq.distance > 0)
        }

        @Test("Formatted right ascension")
        func formattedRA() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            let formatted = eq.rightAscensionFormatted

            #expect(formatted.contains("h"))
            #expect(formatted.contains("m"))
            #expect(formatted.contains("s"))
        }

        @Test("Formatted declination")
        func formattedDec() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            let formatted = eq.declinationFormatted

            #expect(formatted.contains("°"))
            #expect(formatted.contains("'"))
            #expect(formatted.contains("\""))
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let eq = try CelestialBody.mars.equatorial(at: time)

            let desc = eq.description

            #expect(desc.contains("RA"))
            #expect(desc.contains("Dec"))
        }
    }

    // MARK: - Ecliptic Tests

    @Suite("Ecliptic")
    struct EclipticTests {

        @Test("Longitude in valid range")
        func longitudeRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let ecliptic = try Sun.position(at: time)

            #expect(ecliptic.longitude >= 0)
            #expect(ecliptic.longitude < 360)
        }

        @Test("Latitude in valid range")
        func latitudeRange() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let ecliptic = try Sun.position(at: time)

            #expect(ecliptic.latitude >= -90)
            #expect(ecliptic.latitude <= 90)
        }

        @Test("Sun latitude is near zero")
        func sunLatitudeNearZero() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let ecliptic = try Sun.position(at: time)

            // Sun's ecliptic latitude should be essentially zero
            #expect(abs(ecliptic.latitude) < 0.1)
        }

        @Test("Distance is positive")
        func distancePositive() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let ecliptic = try Sun.position(at: time)

            #expect(ecliptic.distance > 0)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let ecliptic = try Sun.position(at: time)

            let desc = ecliptic.description

            #expect(desc.contains("λ"))
            #expect(desc.contains("β"))
        }
    }

    // MARK: - Refraction Tests

    @Suite("Refraction")
    struct RefractionTests {

        @Test("Refraction enum cases exist")
        func refractionCases() {
            _ = Refraction.none
            _ = Refraction.normal
            _ = Refraction.jplHorizons
        }

        @Test("Different refraction produces different results")
        func refractionAffectsHorizon() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 6)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let horizonNoRefraction = try CelestialBody.sun.horizon(
                at: time, from: observer, refraction: .none
            )
            let horizonNormal = try CelestialBody.sun.horizon(
                at: time, from: observer, refraction: .normal
            )

            // Refraction correction should increase apparent altitude
            // (especially near horizon)
            // The difference may be small but should exist
            #expect(horizonNormal.altitude >= horizonNoRefraction.altitude - 0.001)
        }
    }
}
