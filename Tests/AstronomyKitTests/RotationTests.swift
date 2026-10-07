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

        /// The J2000 galactic frame defined for the Hipparcos Catalogue (ESA
        /// 1997, SP-1200, Vol. 1, §1.5.3), following Murray (1989, A&A 218,
        /// 325): north galactic pole at α = 192.85948°, δ = +27.12825°, and the
        /// galactic plane's ascending node on the J2000 equator at galactic
        /// longitude 32.93192°, which puts the north celestial pole at
        /// longitude 122.93192°.
        static let galacticPoleRightAscension = 192.859_48
        static let galacticPoleDeclination = 27.128_25
        static let ascendingNodeLongitude = 32.931_92

        /// EQJ to GAL built from those three angles. Column j is galactic axis
        /// j in J2000 equatorial coordinates (x toward l = 0, b = 0; z toward
        /// the north galactic pole), which is both the engine's element layout
        /// and the layout of the published matrix A_G.
        static func hipparcosGalacticRotation() -> [[Double]] {
            let degree = Double.pi / 180
            let alpha = galacticPoleRightAscension * degree
            let delta = galacticPoleDeclination * degree
            let nodeLongitude = ascendingNodeLongitude * degree

            let pole = [cos(delta) * cos(alpha), cos(delta) * sin(alpha), sin(delta)]
            // The ascending node is on the equator at right ascension α + 90°.
            let node = [-sin(alpha), cos(alpha), 0]
            // pole × node: the galactic plane 90° further on from the node.
            let beyondNode = [
                pole[1] * node[2] - pole[2] * node[1],
                pole[2] * node[0] - pole[0] * node[2],
                pole[0] * node[1] - pole[1] * node[0],
            ]
            // The node is at galactic longitude l_Ω, so the l = 0 axis is l_Ω behind it.
            let x = (0..<3).map { cos(nodeLongitude) * node[$0] - sin(nodeLongitude) * beyondNode[$0] }
            let y = (0..<3).map { sin(nodeLongitude) * node[$0] + cos(nodeLongitude) * beyondNode[$0] }
            return (0..<3).map { [x[$0], y[$0], pole[$0]] }
        }

        /// A_G as printed in the Hipparcos Catalogue, Vol. 1, eq. 1.5.11, to
        /// ten decimals.
        static let publishedGalacticMatrix = [
            [-0.054_875_560_4, 0.494_109_427_9, -0.867_666_149_0],
            [-0.873_437_090_2, -0.444_829_630_0, -0.198_076_373_4],
            [-0.483_835_015_5, 0.746_982_244_5, 0.455_983_776_2],
        ]

        @Test("The Hipparcos galactic angles reproduce the published A_G")
        func hipparcosConstructionMatchesPublishedMatrix() {
            let constructed = Self.hipparcosGalacticRotation()

            // 1e-10: A_G is printed to ten decimals, and the construction
            // lands within 5e-11 of every element.
            for row in 0..<3 {
                for col in 0..<3 {
                    let difference = constructed[row][col] - Self.publishedGalacticMatrix[row][col]
                    #expect(abs(difference) < 1e-10, "[\(row), \(col)] off by \(difference)")
                }
            }
        }

        /// 1e-12: the construction evaluated in double precision.
        static let galacticTolerance = 1e-12

        /// The galactic rotations follow the Hipparcos axes, not the C engine's
        /// IAU 1958 matrix, which was 8.77″ off (#152).
        @Test("EQJ to GAL and GAL to EQJ are the Hipparcos J2000 galactic axes")
        func galacticMatchesHipparcos() throws {
            let expected = Self.hipparcosGalacticRotation()
            let toGalactic = try RotationMatrix.equatorialJ2000ToGalactic()
            let toEquatorial = try RotationMatrix.galacticToEquatorialJ2000()

            for row in 0..<3 {
                for col in 0..<3 {
                    let forward = toGalactic[row, col] - expected[row][col]
                    let inverse = toEquatorial[col, row] - expected[row][col]
                    #expect(abs(forward) < Self.galacticTolerance, "EQJ to GAL [\(row), \(col)] off by \(forward)")
                    #expect(abs(inverse) < Self.galacticTolerance, "GAL to EQJ [\(col), \(row)] off by \(inverse)")
                }
            }
        }

        /// Against the equatorial-to-galactic matrix of ERFA 2.0.1's
        /// `eraIcrs2g`, printed to 30 digits, at 1e-15: that catches a change
        /// in the 14th decimal place that keeps the matrix orthonormal, which
        /// the 1e-12 construction check above would miss.
        @Test("EQJ to GAL is ERFA's galactic matrix")
        func galacticMatchesErfa() throws {
            let toGalactic = try RotationMatrix.equatorialJ2000ToGalactic()

            // ERFA's row i is galactic axis i, which is column i here.
            for row in 0..<3 {
                for col in 0..<3 {
                    let expected = PublishedOrientation.galacticMatrix[col][row]
                    #expect(abs(toGalactic[row, col] - expected) <= 1e-15, "[\(row), \(col)]")
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
