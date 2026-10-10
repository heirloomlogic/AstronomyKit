//
//  EngineEarthRotationTests.swift
//  AstronomyKit
//
//  Earth rotation angle and sidereal time against SOFA.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.EarthRotation")
struct EngineEarthRotationTests {
    typealias Published = PublishedOrientation

    /// SOFA's tolerance for `eraEra00` and `eraGmst06`, in radians.
    static let tolerance = 1e-12

    static func time(ut: Double, tt: Double) -> Engine.Time {
        Engine.Time(ut: ut, tt: tt, deltaTModel: .espenakMeeus)
    }

    static func apparent(_ time: Engine.Time) -> Double {
        Engine.EarthRotation.apparentSiderealTime(time, cache: Published.uncached)
    }

    @Test("ERFA t_era00 reference")
    func erfaAngle() {
        let angle = Engine.EarthRotation.angle(ut: Published.days(mjd: Published.era00.mjd))
        #expect(abs(Published.wrapped(angle * Engine.radiansPerDegree - Published.era00.value)) <= Self.tolerance)
    }

    @Test("ERFA t_gmst06 reference")
    func erfaMeanSiderealTime() {
        let days = Published.days(mjd: Published.gmst06.mjd)
        let hours = Engine.EarthRotation.meanSiderealTime(Self.time(ut: days, tt: days))
        #expect(abs(Published.wrapped(hours * Engine.radiansPerHour - Published.gmst06.value)) <= Self.tolerance)
    }

    @Test("SOFA era00 and gmst06 from 1600 to 2500, with UT1 and TT apart", arguments: Published.references)
    func sofaEpochs(reference: Published.Reference) {
        let angle = Engine.EarthRotation.angle(ut: reference.ut) * Engine.radiansPerDegree
        #expect(abs(Published.wrapped(angle - reference.era00)) <= Self.tolerance)
        let hours = Engine.EarthRotation.meanSiderealTime(Self.time(ut: reference.ut, tt: reference.tt))
        #expect(abs(Published.wrapped(hours * Engine.radiansPerHour - reference.gmst06)) <= Self.tolerance)
    }

    @Test("Apparent sidereal time adds Δψ·cos εA and the complementary terms", arguments: Published.references)
    func equationOfEquinoxes(reference: Published.Reference) {
        let time = Self.time(ut: reference.ut, tt: reference.tt)
        let difference = (Self.apparent(time) - Engine.EarthRotation.meanSiderealTime(time)) * Engine.radiansPerHour
        let expected = reference.dpsi * cos(reference.obl06) + reference.eect00
        #expect(abs(Published.wrapped(difference - expected)) <= Self.tolerance)
    }

    /// The engine forms apparent sidereal time as `iauGmst06` plus `iauEe00`
    /// with IAU 2006/2000A nutation. SOFA's `iauGst06a` instead goes through
    /// the CIO locator and the full precession-nutation matrix; the two
    /// equations of the equinoxes differ by 8.4e-13 rad at this instant, and
    /// ERFA's own tolerance, 1e-12 rad, is the bound here.
    @Test("ERFA t_gst06a reference")
    func erfaApparentSiderealTime() {
        let days = Published.days(mjd: Published.gst06a.mjd)
        let hours = Self.apparent(Self.time(ut: days, tt: days))
        let difference = abs(Published.wrapped(hours * Engine.radiansPerHour - Published.gst06a.value))
        #expect(difference <= 1e-12)
    }

    /// `iauEe06a` is `iauGst06a` less `iauGmst06`, so the engine's equation of
    /// the equinoxes differs from it by the 8.4e-13 rad described above.
    @Test("ERFA t_ee06a reference for the equation of the equinoxes")
    func erfaEquationOfEquinoxes() {
        let days = Published.days(mjd: Published.ee06a.mjd)
        let time = Self.time(ut: days, tt: days)
        let difference = (Self.apparent(time) - Engine.EarthRotation.meanSiderealTime(time)) * Engine.radiansPerHour
        #expect(abs(Published.wrapped(difference - Published.ee06a.value)) <= 1e-12)
    }

    @Test("ERFA t_ee00 reference for Δψ·cos εA plus the complementary terms")
    func erfaEquationOfEquinoxesFormula() {
        let degrees = Engine.degreesPerRadian
        let nutation = Engine.Nutation.Angles(
            longitude: Published.ee00.dpsi * degrees,
            obliquity: 0,
            longitudeRate: 0,
            obliquityRate: 0
        )
        let tilt = Engine.EarthTilt(
            tt: Published.days(mjd: Published.ee00.mjd),
            nutation: nutation,
            meanObliquity: Published.ee00.epsa * degrees,
            meanObliquityRate: 0
        )
        #expect(abs(tilt.equationOfEquinoxes * Engine.radiansPerDegree - Published.ee00.value) <= 1e-18)
    }

    @Test(
        "Results stay in their ranges near the wrap and for negative days",
        arguments: [-1e6 - 0.3, -146_099.625, -0.5, -1e-12, 0, 0.5, 9_496.375, 1e6 + 0.3]
    )
    func ranges(ut: Double) {
        let angle = Engine.EarthRotation.angle(ut: ut)
        #expect(angle >= 0 && angle < 360)
        let time = Self.time(ut: ut, tt: ut + 0.000_8)
        for hours in [Engine.EarthRotation.meanSiderealTime(time), Self.apparent(time)] {
            #expect(hours >= 0 && hours < 24)
        }
    }

    @Test("The Earth rotation angle advances 360.985 612 288 088 degrees per UT1 day")
    func dailyAdvance() {
        let start = Engine.EarthRotation.angle(ut: 100.25)
        let end = Engine.EarthRotation.angle(ut: 101.25)
        let advance = (end - start + 360).truncatingRemainder(dividingBy: 360)
        #expect(abs(advance - 0.985_612_288_087_61) <= 1e-9)
    }

    @Test("Input that is not finite gives NaN", arguments: [Double.nan, .infinity, -.infinity])
    func nonfinite(value: Double) {
        #expect(Engine.EarthRotation.angle(ut: value).isNaN)
        let invalid = Self.time(ut: value, tt: value)
        #expect(Engine.EarthRotation.meanSiderealTime(invalid).isNaN)
        #expect(Self.apparent(invalid).isNaN)
    }
}
