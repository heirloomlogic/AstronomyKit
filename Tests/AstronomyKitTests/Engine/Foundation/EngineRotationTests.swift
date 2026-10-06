//
//  EngineRotationTests.swift
//  AstronomyKit
//
//  Index convention of the native engine's rotation type.
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

    @Test("Identity exists only between a frame and itself")
    func identity() {
        let identity = Engine.Rotation<Engine.EQD, Engine.EQD>.identity
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(identity[i, j] == (i == j ? 1 : 0))
            }
        }
    }
}
