//
//  RotationAxisTests.swift
//  AstronomyKit
//
//  Tests for RotationAxis functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Rotation Axis Tests")
struct RotationAxisTests {

    @Test("Earth rotation axis returns valid data")
    func earthRotationAxis() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis = try CelestialBody.earth.rotationAxis(at: time)

        // Earth's north pole RA ~0h (near Polaris direction)
        #expect(axis.rightAscension >= 0 && axis.rightAscension <= 24)
        // Earth's north pole Dec ~90° (approximately)
        #expect(axis.declination > 60)
    }

    @Test("Mars rotation axis")
    func marsRotationAxis() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis = try CelestialBody.mars.rotationAxis(at: time)

        #expect(axis.rightAscension >= 0 && axis.rightAscension <= 24)
        #expect(axis.declination >= -90 && axis.declination <= 90)
        // Spin is the prime meridian angle - just verify it's defined
        #expect(axis.spin >= 0)
    }

    @Test("Jupiter rotation axis")
    func jupiterRotationAxis() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis = try CelestialBody.jupiter.rotationAxis(at: time)

        #expect(axis.rightAscension >= 0 && axis.rightAscension <= 24)
        #expect(axis.declination >= -90 && axis.declination <= 90)
    }

    @Test("Spin changes rapidly for fast rotators")
    func spinChanges() throws {
        let time1 = AstroTime(year: 2_025, month: 1, day: 1, hour: 0)
        let time2 = AstroTime(year: 2_025, month: 1, day: 1, hour: 6)

        let axis1 = try CelestialBody.jupiter.rotationAxis(at: time1)
        let axis2 = try CelestialBody.jupiter.rotationAxis(at: time2)

        // Jupiter rotates very fast (~10 hours), so spin should differ
        #expect(axis1.spin != axis2.spin)
    }

    @Test("North vector is a unit vector")
    func northIsUnitVector() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis = try CelestialBody.mars.rotationAxis(at: time)

        // Unit vector should have magnitude ~1
        #expect(axis.north.magnitude > 0.99 && axis.north.magnitude < 1.01)
    }

    @Test("RotationAxis is Equatable")
    func equatable() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis1 = try CelestialBody.mars.rotationAxis(at: time)
        let axis2 = try CelestialBody.mars.rotationAxis(at: time)

        #expect(axis1 == axis2)
    }

    @Test("CustomStringConvertible")
    func description() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let axis = try CelestialBody.mars.rotationAxis(at: time)

        #expect(axis.description.contains("Pole"))
        #expect(axis.description.contains("Spin"))
    }
}
