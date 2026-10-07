//
//  EngineRotationAlgebraTests.swift
//  AstronomyKit
//
//  Inverting, combining and pivoting native engine rotations.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Rotation algebra")
struct EngineRotationAlgebraTests {
    typealias Published = PublishedOrientation
    typealias Matrix = [[Double]]

    static let a: Matrix = [[0.36, 0.48, -0.8], [-0.8, 0.6, 0], [0.48, 0.64, 0.6]]
    static let b: Matrix = [[0.6, 0, -0.8], [0, 1, 0], [0.8, 0, 0.6]]

    @Test("The inverse is the transpose and undoes the rotation")
    func inverse() {
        let r: Engine.Rotation<Engine.EQJ, Engine.ECL> = Published.rotation(Self.a)
        let m = Published.matrix(r.inverse)
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(m[i][j] == Self.a[j][i])
            }
        }
        let identity = Published.matrix(r.then(r.inverse))
        #expect(Published.maximumDifference(identity, Published.identity) <= 1e-15)
    }

    @Test("Combining applies the first rotation, then the second")
    func combine() {
        let first: Engine.Rotation<Engine.EQJ, Engine.ECL> = Published.rotation(Self.a)
        let second: Engine.Rotation<Engine.ECL, Engine.GAL> = Published.rotation(Self.b)
        let combined = first.then(second)
        let product = Published.product(Self.b, Self.a)
        #expect(Published.maximumDifference(Published.matrix(combined), product) <= 1e-15)

        let time = Engine.Time(ut: 0, tt: 0, deltaTModel: .espenakMeeus)
        let vector = Engine.Vector<Engine.EQJ>(x: 0.3, y: -1.2, z: 2.5, time: time)
        let direct = combined.apply(to: vector)
        let stepwise = second.apply(to: first.apply(to: vector))
        #expect(abs(direct.x - stepwise.x) <= 1e-15)
        #expect(abs(direct.y - stepwise.y) <= 1e-15)
        #expect(abs(direct.z - stepwise.z) <= 1e-15)
    }

    /// A pivot turns vectors; SOFA's `eraRx`, `eraRy` and `eraRz` turn the
    /// axes. So pivoting by −φ after a rotation is SOFA's rotation by φ of
    /// its matrix.
    @Test("ERFA t_rx, t_ry and t_rz references", arguments: 0..<3)
    func erfaAxisRotations(axis: Int) throws {
        let input: Engine.Rotation<Engine.EQJ, Engine.EQJ> = Published.rotation(Published.rotationInput)
        let degrees = -Published.axisRotations.angle * Engine.degreesPerRadian
        let pivoted = try input.pivoted(axis: axis, angle: degrees)
        let expected = Published.axisRotations.results[axis]
        #expect(Published.maximumDifference(Published.matrix(pivoted), expected) <= 1e-12)
    }

    @Test("A quarter turn about z carries x to y, counterclockwise from +z")
    func rightHanded() throws {
        let quarter = try Engine.Rotation<Engine.EQJ, Engine.EQJ>.identity.pivoted(axis: 2, angle: 90)
        let time = Engine.Time(ut: 0, tt: 0, deltaTModel: .espenakMeeus)
        let turned = quarter.apply(to: Engine.Vector(x: 1, y: 0, z: 0, time: time))
        #expect(abs(turned.x) <= 1e-16)
        #expect(abs(turned.y - 1) <= 1e-16)
        #expect(turned.z == 0)
    }

    @Test(
        "Pivoting rejects an axis outside 0...2 or an angle that is not finite",
        arguments: [(-1, 10.0), (3, 10.0), (0, .nan), (1, .infinity), (2, -.infinity)]
    )
    func pivotRejects(axis: Int, angle: Double) {
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Rotation<Engine.EQJ, Engine.EQJ>.identity.pivoted(axis: axis, angle: angle)
        }
    }
}
