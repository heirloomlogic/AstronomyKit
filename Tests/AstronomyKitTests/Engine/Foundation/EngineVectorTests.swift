//
//  EngineVectorTests.swift
//  AstronomyKit
//
//  Vector length, the angle between vectors, and a state's position.
//

import Testing

@testable import AstronomyKit

@Suite("Engine.Vector")
struct EngineVectorTests {
    static let time = Engine.Time(ut: 100, deltaTModel: .espenakMeeus)

    static func vector(_ x: Double, _ y: Double, _ z: Double) -> Engine.Vector<Engine.EQJ> {
        Engine.Vector(x: x, y: y, z: z, time: time)
    }

    @Test("Length is the square root of the sum of squares")
    func length() {
        #expect(Self.vector(3, 4, 12).length == 13)
        #expect(Self.vector(-3, -4, -12).length == 13)
        #expect(Self.vector(0, 0, 0).length == 0)
        #expect(Self.vector(1e-200, 0, 0).length == 0)  // the square underflows
        #expect(Self.vector(1e200, 0, 0).length == .infinity)  // the square overflows
        #expect(Self.vector(.nan, 0, 0).length.isNaN)
    }

    @Test(
        "The angle between two vectors matches plane geometry",
        arguments: [
            ([1.0, 0, 0], [0.0, 1, 0], 90.0),
            ([1.0, 0, 0], [1.0, 1, 0], 45.0),
            ([1.0, 0, 0], [1.0, 3.0.squareRoot(), 0], 60.0),
            ([0.0, 0, 2], [0.0, 3.0.squareRoot(), 1], 60.0),
            ([1.0, 1, 1], [-1.0, -1, 1], 109.471_220_634_490_69),  // acos(-1/3)
        ] as [([Double], [Double], Double)])
    func angle(a: [Double], b: [Double], degrees: Double) throws {
        let angle = try Self.vector(a[0], a[1], a[2]).angle(to: Self.vector(b[0], b[1], b[2]))
        #expect(abs(angle - degrees) < 1e-12)
        let reverse = try Self.vector(b[0], b[1], b[2]).angle(to: Self.vector(a[0], a[1], a[2]))
        #expect(reverse == angle)
    }

    /// A cosine that rounds to ±1 or beyond gives exactly 0 or 180 rather than
    /// `acos` of a value outside its domain.
    @Test("Parallel and opposite vectors give exactly 0 and 180 degrees")
    func parallel() throws {
        #expect(try Self.vector(1, 0, 0).angle(to: Self.vector(5, 0, 0)) == 0)
        #expect(try Self.vector(1, 0, 0).angle(to: Self.vector(-2, 0, 0)) == 180)
        #expect(try Self.vector(0.1, 0.2, 0.3).angle(to: Self.vector(0.1, 0.2, 0.3)) == 0)
    }

    @Test("A length product of 1e-8 is accepted and anything smaller is a bad vector")
    func smallLengths() throws {
        let unit = Self.vector(1, 0, 0)
        #expect(try unit.angle(to: Self.vector(0, 1e-8, 0)) == 90)
        #expect(throws: AstronomyError.badVector) {
            try unit.angle(to: Self.vector(0, 1e-8.nextDown, 0))
        }
        #expect(throws: AstronomyError.badVector) {
            try unit.angle(to: Self.vector(0, 0, 0))
        }
        #expect(throws: AstronomyError.badVector) {
            try Self.vector(1e-4, 0, 0).angle(to: Self.vector(0, 0.99e-4, 0))
        }
    }

    @Test(
        "A component that is not finite, or lengths whose product overflows, is a bad vector",
        arguments: [
            [Double.nan, 0, 0], [0, .infinity, 0], [0, 0, -.infinity], [1e200, 0, 0], [1e154, 1e154, 1e154],
        ])
    func nonfinite(xyz: [Double]) {
        #expect(throws: AstronomyError.badVector) {
            try Self.vector(1e3, 1e3, 1e3).angle(to: Self.vector(xyz[0], xyz[1], xyz[2]))
        }
    }

    @Test("Large finite lengths with a finite product still give an angle")
    func largeLengths() throws {
        #expect(try Self.vector(1e100, 0, 0).angle(to: Self.vector(0, 1e100, 0)) == 90)
    }

    @Test("A state's position is its first three components at its time")
    func statePosition() {
        let state = Engine.State<Engine.ECL>(x: 1, y: -2, z: 3, vx: 4, vy: 5, vz: 6, time: Self.time)
        let position = state.position
        #expect([position.x, position.y, position.z] == [1, -2, 3])
        #expect(position.time.ut.bitPattern == Self.time.ut.bitPattern)
        #expect(position.time.tt.bitPattern == Self.time.tt.bitPattern)
    }
}
