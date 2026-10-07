//
//  EngineFrameRotationTests.swift
//  AstronomyKit
//
//  Rotations between the engine's frames against SOFA.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.FrameRotation")
struct EngineFrameRotationTests {
    typealias Published = PublishedOrientation
    typealias Matrix = [[Double]]
    typealias Rotations = Engine.FrameRotation

    static func time(_ reference: Published.Reference) -> Engine.Time {
        Engine.Time(ut: reference.ut, tt: reference.tt, deltaTModel: .espenakMeeus)
    }

    /// N·P from the SOFA angles: precession by IERS (2010) equation 5.39 and
    /// nutation R1(−εA − Δε)·R3(−Δψ)·R1(εA), as `eraNumat` builds it.
    static func equatorOfDate(_ reference: Published.Reference) -> Matrix {
        let precession = EnginePrecessionTests.equation539(
            psia: reference.psia,
            oma: reference.oma,
            chia: reference.chia
        )
        let nutation = Published.product(
            Published.r1(-(reference.obl06 + reference.deps)),
            Published.product(Published.r3(-reference.dpsi), Published.r1(reference.obl06))
        )
        return Published.product(nutation, precession)
    }

    @Test("J2000 equator to ecliptic is R1(ε0) with SOFA's ε0")
    func j2000Ecliptic() {
        let expected = Published.r1(Published.p06e.eps0)
        #expect(Published.maximumDifference(Published.matrix(Rotations.eqjToEcl), expected) <= 1e-16)
        let back = Published.matrix(Rotations.eclToEqj)
        #expect(Published.maximumDifference(back, Published.r1(-Published.p06e.eps0)) <= 1e-16)
    }

    @Test("J2000 to true equator of date is N·P on the SOFA angles", arguments: Published.references)
    func equatorOfDate(reference: Published.Reference) {
        let time = Self.time(reference)
        let expected = Self.equatorOfDate(reference)
        #expect(Published.maximumDifference(Published.matrix(Rotations.eqjToEqd(time)), expected) <= 2e-15)
        let back = Published.matrix(Rotations.eqdToEqj(time))
        #expect(Published.maximumDifference(back, Published.transposed(expected)) <= 2e-15)
    }

    @Test("True equator to true ecliptic of date is R1(εA + Δε)", arguments: Published.references)
    func eclipticOfDate(reference: Published.Reference) {
        let time = Self.time(reference)
        let tilt = Published.r1(reference.obl06 + reference.deps)
        #expect(Published.maximumDifference(Published.matrix(Rotations.eqdToEct(time)), tilt) <= 1e-15)
        let throughJ2000 = Published.product(tilt, Self.equatorOfDate(reference))
        #expect(Published.maximumDifference(Published.matrix(Rotations.eqjToEct(time)), throughJ2000) <= 2e-15)
        let fromDate = Published.transposed(Self.equatorOfDate(reference))
        let toMeanEcliptic = Published.product(Published.r1(Published.p06e.eps0), fromDate)
        #expect(Published.maximumDifference(Published.matrix(Rotations.eqdToEcl(time)), toMeanEcliptic) <= 2e-15)
    }

    /// Places a star at hour angle 1.1 rad and declination 1.2 rad for an
    /// observer at latitude 0.3 rad, using the engine's apparent sidereal
    /// time (checked against SOFA in `EngineEarthRotationTests`), and reads
    /// its azimuth (north through east) and elevation from the horizon
    /// vector.
    @Test("ERFA t_hd2ae reference through the horizon rotation", arguments: [-75.0, 0, 140.5])
    func erfaHorizon(longitude: Double) throws {
        let reference = Published.references[4]
        let time = Self.time(reference)
        let observer = Observer(latitude: Published.hd2ae.latitude * Engine.degreesPerRadian, longitude: longitude)
        let sidereal = Engine.EarthRotation.apparentSiderealTime(time) * Engine.radiansPerHour
        let rightAscension = sidereal + longitude * Engine.radiansPerDegree - Published.hd2ae.ha
        let star = Engine.Vector<Engine.EQD>(
            Engine.Spherical(
                latitude: Published.hd2ae.dec * Engine.degreesPerRadian,
                longitude: rightAscension * Engine.degreesPerRadian,
                distance: 1
            ),
            time: time
        )
        let horizon = Rotations.eqdToHor(time, observer: observer).apply(to: star)
        let azimuth = atan2(-horizon.y, horizon.x)
        let elevation = asin(horizon.z)
        #expect(abs(Published.wrapped(azimuth - Published.hd2ae.azimuth)) <= 1e-13)
        #expect(abs(elevation - Published.hd2ae.elevation) <= 1e-14)
    }

    @Test("The zenith of a pole observer is the celestial pole", arguments: [90.0, -90])
    func poles(latitude: Double) {
        let time = Self.time(Published.references[4])
        let m = Published.matrix(Rotations.eqdToHor(time, observer: Observer(latitude: latitude, longitude: 12.5)))
        // Row 2 is the zenith in equator-of-date coordinates.
        #expect(Published.maximumDifference([m[2]], [[0, 0, latitude > 0 ? 1 : -1]]) <= 1e-16)
    }

    @Test("Horizon rotations compose and invert consistently", arguments: Published.references)
    func horizonConsistency(reference: Published.Reference) {
        let time = Self.time(reference)
        let observer = Observer(latitude: 35.6, longitude: -82.55, height: 650)
        let eqdToHor = Published.matrix(Rotations.eqdToHor(time, observer: observer))
        Published.expectProperRotation(eqdToHor)
        let checks: [(Matrix, Matrix)] = [
            (Published.matrix(Rotations.horToEqd(time, observer: observer)), Published.transposed(eqdToHor)),
            (
                Published.matrix(Rotations.eqjToHor(time, observer: observer)),
                Published.product(eqdToHor, Self.equatorOfDate(reference))
            ),
            (
                Published.matrix(Rotations.eclToHor(time, observer: observer)),
                Published.product(
                    eqdToHor,
                    Published.product(Self.equatorOfDate(reference), Published.r1(-Published.p06e.eps0))
                )
            ),
        ]
        for (actual, expected) in checks {
            #expect(Published.maximumDifference(actual, expected) <= 2e-15)
        }
        let inverses: [(Matrix, Matrix)] = [
            (
                Published.matrix(Rotations.horToEqj(time, observer: observer)),
                Published.matrix(Rotations.eqjToHor(time, observer: observer))
            ),
            (
                Published.matrix(Rotations.horToEcl(time, observer: observer)),
                Published.matrix(Rotations.eclToHor(time, observer: observer))
            ),
            (Published.matrix(Rotations.ectToEqj(time)), Published.matrix(Rotations.eqjToEct(time))),
            (Published.matrix(Rotations.ectToEqd(time)), Published.matrix(Rotations.eqdToEct(time))),
            (Published.matrix(Rotations.eclToEqd(time)), Published.matrix(Rotations.eqdToEcl(time))),
        ]
        for (inverse, forward) in inverses {
            #expect(Published.maximumDifference(inverse, Published.transposed(forward)) <= 2e-15)
        }
    }

    @Test("J2000 to galactic is ERFA's eraIcrs2g matrix and the printed Hipparcos A_G")
    func galactic() {
        let matrix = Published.matrix(Rotations.eqjToGal)
        #expect(Published.maximumDifference(matrix, Published.galacticMatrix) <= 1e-15)
        // A_G in the Hipparcos Catalogue, Vol. 1, eq. 1.5.11, printed to ten
        // decimals, is the transpose of this matrix.
        let printed = RotationTests.AbsoluteJ2000FrameTests.publishedGalacticMatrix
        #expect(Published.maximumDifference(matrix, Published.transposed(printed)) <= 1e-10)
        #expect(Published.maximumDifference(Published.matrix(Rotations.galToEqj), Published.transposed(matrix)) == 0)
        Published.expectProperRotation(matrix)
    }

    @Test("ERFA t_icrs2g reference through the galactic rotation")
    func erfaGalacticCoordinates() throws {
        let time = Engine.Time(ut: 0, tt: 0, deltaTModel: .espenakMeeus)
        let equatorial = Engine.Vector<Engine.EQJ>(
            Engine.Spherical(
                latitude: Published.icrs2g.dec * Engine.degreesPerRadian,
                longitude: Published.icrs2g.ra * Engine.degreesPerRadian,
                distance: 1
            ),
            time: time
        )
        let galactic = try Engine.Spherical(Rotations.eqjToGal.apply(to: equatorial))
        #expect(abs(galactic.longitude * Engine.radiansPerDegree - Published.icrs2g.longitude) <= 1e-14)
        #expect(abs(galactic.latitude * Engine.radiansPerDegree - Published.icrs2g.latitude) <= 1e-14)
    }
}
