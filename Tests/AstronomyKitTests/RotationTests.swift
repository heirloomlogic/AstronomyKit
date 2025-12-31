//
//  RotationTests.swift
//  AstronomyKit
//
//  Tests for RotationMatrix functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Rotation Matrix Tests")
struct RotationTests {

    // MARK: - Identity and Basic Operations

    @Suite("Basic Operations")
    struct BasicOperationsTests {

        @Test("Identity matrix")
        func identityMatrix() {
            let identity = RotationMatrix.identity

            // Diagonal elements should be 1
            #expect(identity[0, 0] == 1)
            #expect(identity[1, 1] == 1)
            #expect(identity[2, 2] == 1)

            // Off-diagonal elements should be 0
            #expect(identity[0, 1] == 0)
            #expect(identity[0, 2] == 0)
        }

        @Test("Inverse of rotation")
        func inverseRotation() throws {
            let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
            let inverse = try rotation.inverse

            // Combining with inverse should give identity
            let combined = try rotation.combined(with: inverse)

            #expect(abs(combined[0, 0] - 1) < 0.001)
            #expect(abs(combined[1, 1] - 1) < 0.001)
            #expect(abs(combined[2, 2] - 1) < 0.001)
        }

        @Test("Combine rotations")
        func combineRotations() throws {
            let r1 = try RotationMatrix.equatorialJ2000ToEcliptic()
            let r2 = try RotationMatrix.eclipticToEquatorialJ2000()

            // These are inverses, so combined should be identity
            let combined = try r1.combined(with: r2)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("Pivot around axis")
        func pivotAroundAxis() throws {
            // 360 degree rotation should return to identity
            let rotation = try RotationMatrix.pivot(axis: 2, angle: 360)

            #expect(abs(rotation[0, 0] - 1) < 0.001)
            #expect(abs(rotation[1, 1] - 1) < 0.001)
        }
    }

    // MARK: - Coordinate System Conversions

    @Suite("Coordinate Conversions")
    struct CoordinateConversionsTests {

        @Test("EQJ to ECL and back")
        func eqjToEclAndBack() throws {
            let toEcl = try RotationMatrix.equatorialJ2000ToEcliptic()
            let toEqj = try RotationMatrix.eclipticToEquatorialJ2000()

            let combined = try toEcl.combined(with: toEqj)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("EQJ to Galactic and back")
        func eqjToGalAndBack() throws {
            let toGal = try RotationMatrix.equatorialJ2000ToGalactic()
            let toEqj = try RotationMatrix.galacticToEquatorialJ2000()

            let combined = try toGal.combined(with: toEqj)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("EQJ to EQD and back")
        func eqjToEqdAndBack() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let toEqd = try RotationMatrix.equatorialJ2000ToEquatorialOfDate(at: time)
            let toEqj = try RotationMatrix.equatorialOfDateToEquatorialJ2000(at: time)

            let combined = try toEqd.combined(with: toEqj)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("EQJ to Horizon and back")
        func eqjToHorAndBack() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let toHor = try RotationMatrix.equatorialJ2000ToHorizon(at: time, from: observer)
            let toEqj = try RotationMatrix.horizonToEquatorialJ2000(at: time, from: observer)

            let combined = try toHor.combined(with: toEqj)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("ECL to Horizon and back")
        func eclToHorAndBack() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let toHor = try RotationMatrix.eclipticToHorizon(at: time, from: observer)
            let toEcl = try RotationMatrix.horizonToEcliptic(at: time, from: observer)

            let combined = try toHor.combined(with: toEcl)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("EQD to Horizon and back")
        func eqdToHorAndBack() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            let toHor = try RotationMatrix.equatorialOfDateToHorizon(at: time, from: observer)
            let toEqd = try RotationMatrix.horizonToEquatorialOfDate(at: time, from: observer)

            let combined = try toHor.combined(with: toEqd)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }

        @Test("EQD to ECL and back")
        func eqdToEclAndBack() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let toEcl = try RotationMatrix.equatorialOfDateToEcliptic(at: time)
            let toEqd = try RotationMatrix.eclipticToEquatorialOfDate(at: time)

            let combined = try toEcl.combined(with: toEqd)

            #expect(abs(combined[0, 0] - 1) < 0.001)
        }
    }

    // MARK: - Vector Rotation

    @Suite("Vector Rotation")
    struct VectorRotationTests {

        @Test("Rotate vector with identity")
        func rotateWithIdentity() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let vec = Vector3D(x: 1, y: 2, z: 3, time: time)

            let rotated = try vec.rotated(by: .identity)

            #expect(abs(rotated.x - 1) < 0.001)
            #expect(abs(rotated.y - 2) < 0.001)
            #expect(abs(rotated.z - 3) < 0.001)
        }

        @Test("Rotate preserves magnitude")
        func rotatePreservesMagnitude() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let vec = Vector3D(x: 1, y: 2, z: 3, time: time)

            let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
            let rotated = try vec.rotated(by: rotation)

            #expect(abs(rotated.magnitude - vec.magnitude) < 0.001)
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformancesTests {

        @Test("Equatable")
        func equatable() throws {
            let r1 = try RotationMatrix.equatorialJ2000ToEcliptic()
            let r2 = try RotationMatrix.equatorialJ2000ToEcliptic()

            #expect(r1 == r2)
        }

        @Test("CustomStringConvertible")
        func description() {
            let identity = RotationMatrix.identity
            let desc = identity.description

            #expect(desc.contains("1"))
        }
    }
}
