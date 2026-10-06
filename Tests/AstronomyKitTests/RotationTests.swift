//
//  RotationTests.swift
//  AstronomyKit
//
//  Tests for RotationMatrix functionality.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Rotation Matrix Tests")
struct RotationTests {
    // MARK: - Pivot Validation

    @Suite("Pivot Validation")
    struct PivotValidation {
        @Test("Out-of-range axes throw invalidParameter", arguments: [-1, 3, Int.max])
        func invalidAxisThrows(axis: Int) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try RotationMatrix.pivot(axis: axis, angle: 30)
            }
        }

        @Test("Valid axes are accepted", arguments: [0, 1, 2])
        func validAxisSucceeds(axis: Int) throws {
            _ = try RotationMatrix.pivot(axis: axis, angle: 30)
        }
    }

    // MARK: - Identity and Basic Operations

    @Suite("Basic Operations")
    struct BasicOperationsTests {
        @Test("Identity matrix")
        func identityMatrix() {
            let identity = RotationMatrix.identity

            // Every element of the identity matrix, read via the subscript, matches.
            for row in 0..<3 {
                for col in 0..<3 {
                    #expect(identity[row, col] == (row == col ? 1 : 0))
                }
            }
        }

        @Test("Subscript reads every element of a non-trivial matrix")
        func subscriptReadsAllElements() throws {
            // A 90° pivot about the z axis has a known, non-symmetric layout, so it
            // exercises each subscript branch distinctly.
            let rotation = try RotationMatrix.pivot(axis: 2, angle: 90)

            #expect(abs(rotation[0, 0] - 0) < 0.001)
            #expect(abs(rotation[0, 1] - 1) < 0.001)
            #expect(abs(rotation[1, 0] - -1) < 0.001)
            #expect(abs(rotation[1, 1] - 0) < 0.001)
            #expect(abs(rotation[2, 2] - 1) < 0.001)
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

    // MARK: - Absolute J2000 Frames

    /// Checks the fixed J2000 rotations against published constants instead
    /// of against each other: a matrix and its inverse that are wrong in the
    /// same way still round-trip.
    ///
    /// Element `[i, j]` is the weight of input component `i` in output
    /// component `j`, which is how `Astronomy_RotateVector` applies it.
    @Suite("Absolute J2000 Frames")
    struct AbsoluteJ2000FrameTests {
        /// Mean obliquity of the J2000 ecliptic: 84,381.406″, the P03 value
        /// adopted by IAU 2006 Resolution B1 (Capitaine, Wallace & Chapront
        /// 2003, A&A 412, 567).
        static let obliquity = 84_381.406 / 3_600 * .pi / 180
        static let cosObliquity = cos(obliquity)
        static let sinObliquity = sin(obliquity)

        /// The engine stores the obliquity's cosine and sine as literals within
        /// 5e-12 of the closed form. A 1″ obliquity error moves the sine by
        /// 4.4e-6 and the cosine by 1.9e-6.
        static let tolerance = 1e-10

        /// Expected element `[i, j]` of the rotation about the x axis that
        /// takes equatorial to ecliptic coordinates (`sign` +1) or back (−1).
        static func obliquityRotation(_ sign: Double) -> [[Double]] {
            let c = cosObliquity
            let s = sign * sinObliquity
            return [
                [1, 0, 0],
                [0, c, -s],
                [0, s, c],
            ]
        }

        static func expectElements(of matrix: RotationMatrix, equal expected: [[Double]]) {
            for row in 0..<3 {
                for col in 0..<3 {
                    #expect(
                        abs(matrix[row, col] - expected[row][col]) < tolerance,
                        "[\(row), \(col)] = \(matrix[row, col]), expected \(expected[row][col])"
                    )
                }
            }
        }

        @Test("EQJ to ECL is the IAU 2006 J2000 obliquity rotation")
        func equatorialToEcliptic() throws {
            let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()

            Self.expectElements(of: rotation, equal: Self.obliquityRotation(1))
        }

        @Test("ECL to EQJ is the reverse obliquity rotation")
        func eclipticToEquatorial() throws {
            let rotation = try RotationMatrix.eclipticToEquatorialJ2000()

            Self.expectElements(of: rotation, equal: Self.obliquityRotation(-1))
        }

        @Test("EQJ to ECL takes the celestial poles to their ecliptic positions")
        func polesMapToEclipticPositions() throws {
            let time = AstroTime(ut: 0)
            let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
            let c = Self.cosObliquity
            let s = Self.sinObliquity

            // The north celestial pole sits at ecliptic longitude 90°, latitude 90° − ε.
            let celestialPole = try Vector3D(x: 0, y: 0, z: 1, time: time).rotated(by: rotation)
            #expect(abs(celestialPole.x) < Self.tolerance)
            #expect(abs(celestialPole.y - s) < Self.tolerance)
            #expect(abs(celestialPole.z - c) < Self.tolerance)

            // The north ecliptic pole sits at RA 18h, declination 90° − ε.
            let eclipticPole = try Vector3D(x: 0, y: -s, z: c, time: time).rotated(by: rotation)
            #expect(abs(eclipticPole.x) < Self.tolerance)
            #expect(abs(eclipticPole.y) < Self.tolerance)
            #expect(abs(eclipticPole.z - 1) < Self.tolerance)
        }

        /// Each galactic element is a 16-digit literal, so a correctly typed
        /// matrix is orthonormal to about 1e-15. A wrong sign, swapped
        /// elements, or a wrong digit down to the 13th decimal place breaks
        /// that by more than this.
        static let orthonormalityTolerance = 1e-14

        /// These checks hold for any galactic pole convention the matrix
        /// encodes, so they test the stored literals rather than the convention.
        @Test("EQJ to GAL is a proper rotation")
        func galacticIsProperRotation() throws {
            let m = try RotationMatrix.equatorialJ2000ToGalactic()

            for i in 0..<3 {
                for j in 0..<3 {
                    let dot = m[i, 0] * m[j, 0] + m[i, 1] * m[j, 1] + m[i, 2] * m[j, 2]
                    #expect(abs(dot - (i == j ? 1 : 0)) < Self.orthonormalityTolerance, "rows \(i), \(j): \(dot)")
                }
            }

            let determinant =
                m[0, 0] * (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1])
                - m[0, 1] * (m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0])
                + m[0, 2] * (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0])
            #expect(abs(determinant - 1) < Self.orthonormalityTolerance, "determinant \(determinant)")
        }

        @Test("GAL to EQJ is exactly the transpose of EQJ to GAL")
        func galacticInverseIsTranspose() throws {
            let toGalactic = try RotationMatrix.equatorialJ2000ToGalactic()
            let toEquatorial = try RotationMatrix.galacticToEquatorialJ2000()

            for row in 0..<3 {
                for col in 0..<3 {
                    #expect(toEquatorial[row, col] == toGalactic[col, row], "[\(row), \(col)]")
                }
            }
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

        @Test("Distinct matrices are not equal")
        func inequality() throws {
            let ecliptic = try RotationMatrix.equatorialJ2000ToEcliptic()

            #expect(ecliptic != .identity)
        }

        @Test("CustomStringConvertible")
        func description() {
            let identity = RotationMatrix.identity
            let desc = identity.description

            #expect(desc.contains("1"))
        }
    }
}
