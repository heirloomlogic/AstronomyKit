//
//  EnginePrecessionTests.swift
//  AstronomyKit
//
//  IAU 2006 precession and mean obliquity against SOFA, and their rates.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Precession")
struct EnginePrecessionTests {
    typealias Published = PublishedOrientation

    static let radians = Engine.radiansPerDegree

    /// R1(φ) and R3(φ) as SOFA's `iauRx` and `iauRz` apply them.
    static func r1(_ phi: Double) -> [[Double]] {
        [[1, 0, 0], [0, cos(phi), sin(phi)], [0, -sin(phi), cos(phi)]]
    }

    static func r3(_ phi: Double) -> [[Double]] {
        [[cos(phi), sin(phi), 0], [-sin(phi), cos(phi), 0], [0, 0, 1]]
    }

    static func product(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0.0) { $0 + a[i][$1] * b[$1][j] } } }
    }

    /// IERS Conventions (2010) equation 5.39, P = R3(χA)·R1(−ωA)·R3(−ψA)·R1(ε0),
    /// built from the given angles independently of the engine's expansion.
    static func equation539(psia: Double, oma: Double, chia: Double) -> [[Double]] {
        let eps0 = 84_381.406 * Engine.radiansPerArcsecond
        return product(r3(chia), product(r1(-oma), product(r3(-psia), r1(eps0))))
    }

    @Test("ERFA t_obl06 reference")
    func erfaObliquity() {
        let tt = Published.days(mjd: Published.obl06.mjd)
        #expect(abs(Engine.Precession.meanObliquity(tt: tt) * Self.radians - Published.obl06.value) <= 1e-15)
    }

    @Test("ERFA t_p06e reference for ε0, ψA, ωA and χA")
    func erfaAngles() {
        let angles = Engine.Precession.angles(tt: Published.days(mjd: Published.p06e.mjd))
        #expect(abs(Engine.Precession.obliquityAtJ2000 * Engine.radiansPerArcsecond - Published.p06e.eps0) <= 1e-15)
        #expect(abs(angles.psi * Self.radians - Published.p06e.psia) <= 1e-15)
        #expect(abs(angles.omega * Self.radians - Published.p06e.oma) <= 1e-15)
        #expect(abs(angles.chi * Self.radians - Published.p06e.chia) <= 1e-15)
    }

    @Test("SOFA obl06 and p06e from 1600 to 2500", arguments: Published.references)
    func sofaEpochs(reference: Published.Reference) {
        let angles = Engine.Precession.angles(tt: reference.tt)
        #expect(abs(Engine.Precession.meanObliquity(tt: reference.tt) * Self.radians - reference.obl06) <= 1e-15)
        #expect(abs(angles.psi * Self.radians - reference.psia) <= 1e-15)
        #expect(abs(angles.omega * Self.radians - reference.oma) <= 1e-15)
        #expect(abs(angles.chi * Self.radians - reference.chia) <= 1e-15)
    }

    @Test("The matrix is IERS equation 5.39 on the SOFA angles", arguments: Published.references)
    func equation539(reference: Published.Reference) {
        let expected = Self.equation539(psia: reference.psia, oma: reference.oma, chia: reference.chia)
        let matrix = Published.matrix(Engine.Precession.rotation(tt: reference.tt))
        #expect(Published.maximumDifference(matrix, expected) <= 1e-15)
    }

    /// `eraBp06` builds its precession from the Fukushima-Williams angles
    /// and removes the frame bias, a different route to the same IAU 2006
    /// model. The two agree to 3e-14 here; SOFA's 1e-14 off-diagonal
    /// tolerance is for its own route.
    @Test("ERFA t_bp06 precession matrix")
    func erfaMatrix() {
        let matrix = Published.matrix(Engine.Precession.rotation(tt: Published.days(mjd: Published.bp06.mjd)))
        #expect(Published.maximumDifference(matrix, Published.bp06.rp) <= 1e-13)
    }

    @Test("The matrix is the identity at J2000")
    func identityAtJ2000() {
        let matrix = Published.matrix(Engine.Precession.rotation(tt: 0))
        #expect(Published.maximumDifference(matrix, [[1, 0, 0], [0, 1, 0], [0, 0, 1]]) <= 1e-15)
    }

    @Test("The matrix is a rotation", arguments: Published.references)
    func orthonormal(reference: Published.Reference) {
        Published.expectProperRotation(Published.matrix(Engine.Precession.rotation(tt: reference.tt)))
    }

    /// The angles are polynomials, so a 64-day five-point step leaves only
    /// rounding: about 1e-17 per day against rates of up to 4e-5 degrees
    /// and 7e-9 per day.
    @Test("Rates are the derivatives of the angles and the matrix", arguments: Published.references)
    func rates(reference: Published.Reference) {
        let tt = reference.tt
        let angles = Engine.Precession.angles(tt: tt)
        let difference = { (f: (Double) -> Double) in Published.derivative(at: tt, step: 64, f) }
        #expect(abs(angles.psiRate - difference { Engine.Precession.angles(tt: $0).psi }) <= 1e-15)
        #expect(abs(angles.omegaRate - difference { Engine.Precession.angles(tt: $0).omega }) <= 1e-15)
        #expect(abs(angles.chiRate - difference { Engine.Precession.angles(tt: $0).chi }) <= 1e-15)
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
