//
//  EnginePrecessionTests.swift
//  AstronomyKit
//
//  Long-term precession and mean obliquity against ERFA, and their rates.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Precession")
struct EnginePrecessionTests {
    typealias Published = PublishedOrientation

    static let radians = Engine.radiansPerDegree

    @Test(
        "ERFA unbiased long-term matrices and pole-derived obliquity", arguments: PublishedLongTermPrecession.references
    )
    func erfaEpochs(reference: PublishedLongTermPrecession.Reference) {
        let matrix = Published.matrix(Engine.Precession.rotation(tt: reference.tt))
        #expect(Published.maximumDifference(matrix, reference.matrix) <= 1e-15)
        #expect(
            abs(Engine.Precession.meanObliquity(tt: reference.tt) * Self.radians - reference.meanObliquity) <= 1e-15)
        #expect(Published.maximumDifference(matrix, reference.biasedMatrix) > 1e-8)
        Published.expectProperRotation(matrix)
    }

    @Test("A NaN element fails the matrix comparison wherever it sits")
    func nanFailsComparison() {
        let identity = Published.identity
        for i in 0..<3 {
            for j in 0..<3 {
                var damaged = identity
                damaged[i][j] = .nan
                #expect(!(Published.maximumDifference(damaged, identity) <= 1), "element \(i), \(j)")
            }
        }
    }

    /// ERFA's finite decimal coefficients leave a one-microarcsecond
    /// residual at J2000. Preserve the published unbiased model rather
    /// than adding an unrequested epoch renormalization or ICRS bias.
    @Test("J2000 retains ERFA's coefficient-rounding residual without frame bias")
    func identityAtJ2000() {
        let matrix = Published.matrix(Engine.Precession.rotation(tt: 0))
        #expect(Published.maximumDifference(matrix, PublishedLongTermPrecession.at(0).matrix) <= 1e-15)
        #expect(Published.maximumDifference(matrix, Published.identity) < 5e-12)
        #expect(abs(matrix[2][1] - 4.848244276876856e-12) <= 1e-15)
    }

    @Test("The matrix is a rotation", arguments: Published.references)
    func orthonormal(reference: Published.Reference) {
        Published.expectProperRotation(Published.matrix(Engine.Precession.rotation(tt: reference.tt)))
    }

    @Test(
        "Analytic matrix and obliquity rates match five-point differences",
        arguments: PublishedLongTermPrecession.references)
    func rates(reference: PublishedLongTermPrecession.Reference) {
        let tt = reference.tt
        let difference = { (f: (Double) -> Double) in Published.derivative(at: tt, step: 64, f) }
        let obliquityRate = Engine.Precession.meanObliquityRate(tt: tt)
        #expect(abs(obliquityRate - difference { Engine.Precession.meanObliquity(tt: $0) }) <= 1e-15)
        let rate = Engine.Precession.rate(tt: tt)
        for i in 0..<3 {
            for j in 0..<3 {
                let element = difference { Engine.Precession.rotation(tt: $0)[i, j] }
                #expect(abs(rate[i, j] - element) <= 1e-15, "element \(i), \(j)")
            }
        }
    }

    /// A body moving uniformly in J2000 axes, seen in axes precessing with
    /// it: the velocity of date must be the derivative of the position of
    /// date.
    @Test("A state through a moving rotation has the derivative of the rotated position")
    func movingState() {
        let model = DeltaTModel.espenakMeeus
        let tt = 18_262.5
        let start = (x: 0.3, y: -1.1, z: 0.45)
        let velocity = (x: 0.012, y: 0.004, z: -0.002)
        func state(_ at: Double) -> Engine.State<Engine.EQJ> {
            let dt = at - tt
            return Engine.State(
                x: start.x + velocity.x * dt, y: start.y + velocity.y * dt, z: start.z + velocity.z * dt,
                vx: velocity.x, vy: velocity.y, vz: velocity.z,
                time: Engine.Time(tt: at, deltaTModel: model)
            )
        }
        let rotated = Engine.Precession.rotation(tt: tt).apply(to: state(tt), rate: Engine.Precession.rate(tt: tt))
        func position(_ tt: Double, _ axis: KeyPath<Engine.State<Engine.EQM>, Double>) -> Double {
            Engine.Precession.rotation(tt: tt).apply(to: state(tt))[keyPath: axis]
        }
        let axes: [(KeyPath<Engine.State<Engine.EQM>, Double>, KeyPath<Engine.State<Engine.EQM>, Double>)] = [
            (\.vx, \.x), (\.vy, \.y), (\.vz, \.z),
        ]
        for (velocity, axis) in axes {
            let difference = Published.derivative(at: tt, step: 1) { position($0, axis) }
            #expect(abs(rotated[keyPath: velocity] - difference) <= 1e-15)
        }
        #expect(rotated.time.tt == tt)
        let plain = Engine.Precession.rotation(tt: tt).apply(to: state(tt))
        #expect((rotated.x, rotated.y, rotated.z) == (plain.x, plain.y, plain.z))
        #expect(abs(rotated.vx - plain.vx) > 1e-9)
    }
}
