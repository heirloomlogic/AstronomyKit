//
//  EngineRotationTests.swift
//  AstronomyKit
//
//  Index convention of the native engine's rotation type, and applying it.
//

import Testing

@testable import AstronomyKit

@Suite("Engine.Rotation")
struct EngineRotationTests {
    @Test("Rotation subscripts read the storage in C index order")
    func rotationIndexOrder() {
        let rotation = Engine.Rotation<Engine.EQJ, Engine.ECL>(
            rot: (
                (0.0, 0.1, 0.2),
                (1.0, 1.1, 1.2),
                (2.0, 2.1, 2.2)
            )
        )
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(rotation[i, j] == Double(i) + Double(j) / 10)
            }
        }
    }

    @Test("The identity has ones on the diagonal and zeros elsewhere")
    func identity() {
        let identity = Engine.Rotation<Engine.EQD, Engine.EQD>.identity
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(identity[i, j] == (i == j ? 1 : 0))
            }
        }
    }

    /// Distinct integer entries, so every product and sum is exact and a
    /// transposed index changes the result.
    static let rotation = Engine.Rotation<Engine.EQJ, Engine.ECL>(
        rot: (
            (1, 2, 3),
            (4, 5, 6),
            (7, 8, 10)
        )
    )

    static let time = Engine.Time(ut: 9_000.25, deltaTModel: .jplHorizons)

    @Test("Component j of a rotated vector is the sum over i of rot[i][j] times component i")
    func applyToVector() {
        let rotated = Self.rotation.apply(to: Engine.Vector<Engine.EQJ>(x: 1, y: 10, z: 100, time: Self.time))
        #expect(rotated.x == 741)  // 1 · 1 + 4 · 10 + 7 · 100
        #expect(rotated.y == 852)  // 2 · 1 + 5 · 10 + 8 · 100
        #expect(rotated.z == 1063)  // 3 · 1 + 6 · 10 + 10 · 100
        #expect(rotated.time.ut.bitPattern == Self.time.ut.bitPattern)
        #expect(rotated.time.tt.bitPattern == Self.time.tt.bitPattern)
        #expect(rotated.time.deltaTModel == .jplHorizons)
    }

    @Test("A rotated state turns its position and its velocity the same way")
    func applyToState() {
        let state = Engine.State<Engine.EQJ>(x: 1, y: 10, z: 100, vx: -1, vy: 0.5, vz: 2, time: Self.time)
        let rotated = Self.rotation.apply(to: state)
        let position = Self.rotation.apply(to: state.position)
        #expect([rotated.x, rotated.y, rotated.z] == [position.x, position.y, position.z])
        #expect(rotated.vx == 15)  // 1 · -1 + 4 · 0.5 + 7 · 2
        #expect(rotated.vy == 16.5)  // 2 · -1 + 5 · 0.5 + 8 · 2
        #expect(rotated.vz == 20)  // 3 · -1 + 6 · 0.5 + 10 · 2
        #expect(rotated.time.ut.bitPattern == Self.time.ut.bitPattern)
        #expect(rotated.time.tt.bitPattern == Self.time.tt.bitPattern)
    }

    /// A quarter turn about z: in the target frame the source x axis lies
    /// along -y and the source y axis along +x.
    @Test("A quarter turn about z sends x to -y and y to +x")
    func quarterTurn() {
        let turn = Engine.Rotation<Engine.EQJ, Engine.ECL>(rot: ((0, -1, 0), (1, 0, 0), (0, 0, 1)))
        let x = turn.apply(to: Engine.Vector<Engine.EQJ>(x: 1, y: 0, z: 0, time: Self.time))
        let y = turn.apply(to: Engine.Vector<Engine.EQJ>(x: 0, y: 1, z: 0, time: Self.time))
        #expect([x.x, x.y, x.z] == [0, -1, 0])
        #expect([y.x, y.y, y.z] == [1, 0, 0])
    }

    @Test("The identity leaves a vector's components unchanged")
    func identityApplied() {
        let vector = Engine.Vector<Engine.EQD>(x: 0.25, y: -3, z: 1e-9, time: Self.time)
        let same = Engine.Rotation<Engine.EQD, Engine.EQD>.identity.apply(to: vector)
        #expect([same.x, same.y, same.z].map(\.bitPattern) == [vector.x, vector.y, vector.z].map(\.bitPattern))
    }
}
