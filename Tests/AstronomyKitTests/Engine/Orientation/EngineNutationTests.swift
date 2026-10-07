//
//  EngineNutationTests.swift
//  AstronomyKit
//
//  IAU 2000B nutation and Earth's tilt against SOFA, and their rates.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Nutation")
struct EngineNutationTests {
    typealias Published = PublishedOrientation

    /// SOFA's own tolerance for `eraNut00b` is 1e-13 rad. The series agrees
    /// with it to about 1e-16 rad from 1600 to 2500, so this is tighter.
    static let tolerance = 1e-15

    static func radians(_ angles: Engine.Nutation.Angles) -> (dpsi: Double, deps: Double) {
        (angles.longitude * Engine.radiansPerDegree, angles.obliquity * Engine.radiansPerDegree)
    }

    @Test("The table holds the 77 luni-solar terms, largest first")
    func table() {
        #expect(Engine.Nutation.terms.count == 77)
        let first = Engine.Nutation.terms[0]
        #expect([first.nl, first.nlp, first.nf, first.nd, first.nom] == [0, 0, 0, 0, 1])
        #expect([first.ps, first.pst, first.pc] == [-172_064_161, -174_666, 33_386])
        #expect([first.ec, first.ect, first.es] == [92_052_331, 9_086, 15_377])
        let amplitudes = Engine.Nutation.terms.map { abs($0.ps) }
        #expect(amplitudes[0] == amplitudes.max())
    }

    @Test("ERFA t_nut00b reference")
    func erfaReference() {
        let tt = Published.days(mjd: Published.nut00b.mjd)
        let (dpsi, deps) = Self.radians(Engine.Nutation.evaluate(centuries: tt / 36525))
        #expect(abs(dpsi - Published.nut00b.dpsi) <= Self.tolerance)
        #expect(abs(deps - Published.nut00b.deps) <= Self.tolerance)
    }

    @Test("SOFA nut00b from 1600 to 2500", arguments: Published.references)
    func sofaEpochs(reference: Published.Reference) {
        let (dpsi, deps) = Self.radians(Engine.Nutation.evaluate(centuries: reference.tt / 36525))
        #expect(abs(dpsi - reference.dpsi) <= Self.tolerance)
        #expect(abs(deps - reference.deps) <= Self.tolerance)
    }

    /// Rates reach about 5e-5 degrees per day. The five-point difference
    /// with a 1/32-day step is good to about 4e-14 degrees per day on the
    /// 13.7-day term. Far from J2000 the Delaunay arguments reach 1e10
    /// arcseconds before they are reduced, and their rounding moves each
    /// sample enough to add about 1e-13 degrees per day to the difference.
    @Test("Rates are the derivatives of the angles", arguments: Published.references)
    func rates(reference: Published.Reference) {
        let angles = Engine.Nutation.evaluate(centuries: reference.tt / 36525)
        let step = 1.0 / 32
        let longitude = Published.derivative(at: reference.tt, step: step) {
            Engine.Nutation.evaluate(centuries: $0 / 36525).longitude
        }
        let obliquity = Published.derivative(at: reference.tt, step: step) {
            Engine.Nutation.evaluate(centuries: $0 / 36525).obliquity
        }
        #expect(abs(angles.longitudeRate - longitude) <= 3e-13)
        #expect(abs(angles.obliquityRate - obliquity) <= 3e-13)
        #expect(abs(angles.longitudeRate) > 1e-7)
    }

    @Test("Input that is not finite gives NaN", arguments: [Double.nan, .infinity, -.infinity])
    func nonfinite(tt: Double) {
        let angles = Engine.Nutation.evaluate(centuries: tt / 36525)
        #expect(angles.longitude.isNaN)
        #expect(angles.obliquity.isNaN)
        #expect(angles.longitudeRate.isNaN)
        #expect(angles.obliquityRate.isNaN)
    }
}

@Suite("Engine.EarthTilt")
struct EngineEarthTiltTests {
    typealias Published = PublishedOrientation

    static func tilt(tt: Double) -> Engine.EarthTilt {
        Engine.EarthTilt(tt: tt, cache: Published.uncached)
    }

    @Test("Obliquities and the equation of the equinoxes combine the SOFA angles", arguments: Published.references)
    func angles(reference: Published.Reference) {
        let tilt = Self.tilt(tt: reference.tt)
        let radians = Engine.radiansPerDegree
        #expect(abs(tilt.meanObliquity * radians - reference.obl06) <= 1e-15)
        #expect(abs(tilt.trueObliquity * radians - (reference.obl06 + reference.deps)) <= 2e-15)
        let equation = reference.dpsi * cos(reference.obl06) + reference.eect00
        #expect(abs(tilt.equationOfEquinoxes * radians - equation) <= 1e-15)
        #expect(tilt.trueObliquityRate == tilt.meanObliquityRate + tilt.nutation.obliquityRate)
    }

    @Test("ERFA t_numat reference for the nutation matrix")
    func erfaNumat() {
        let degrees = Engine.degreesPerRadian
        let angles = Engine.Nutation.Angles(
            longitude: Published.numat.dpsi * degrees,
            obliquity: Published.numat.deps * degrees,
            longitudeRate: 0,
            obliquityRate: 0
        )
        let tilt = Engine.EarthTilt(
            tt: Published.days(mjd: 53_736.0),
            nutation: angles,
            meanObliquity: Published.numat.epsa * degrees,
            meanObliquityRate: 0
        )
        let matrix = Published.matrix(tilt.nutationRotation)
        #expect(Published.maximumDifference(matrix, Published.numat.matrix) <= 1e-12)
    }

    @Test("The nutation matrix is a rotation", arguments: Published.references)
    func orthonormal(reference: Published.Reference) {
        Published.expectProperRotation(Published.matrix(Self.tilt(tt: reference.tt).nutationRotation))
    }

    /// Elements move by up to about 8e-7 per day; the five-point difference
    /// with a 1/32-day step agrees to about 1e-15 per day.
    @Test("The nutation rate matrix is the derivative of the matrix", arguments: Published.references)
    func nutationRate(reference: Published.Reference) {
        let rate = Self.tilt(tt: reference.tt).nutationRate
        for i in 0..<3 {
            for j in 0..<3 {
                let difference = Published.derivative(at: reference.tt, step: 1.0 / 32) {
                    Self.tilt(tt: $0).nutationRotation[i, j]
                }
                #expect(abs(rate[i, j] - difference) <= 1e-13, "element \(i), \(j)")
            }
        }
    }
}
