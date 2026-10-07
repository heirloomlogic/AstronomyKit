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

    @Test("Apparent sidereal time is mean sidereal time plus Δψ·cos εA", arguments: Published.references)
    func equationOfEquinoxes(reference: Published.Reference) {
        let time = Self.time(ut: reference.ut, tt: reference.tt)
        let difference = (Self.apparent(time) - Engine.EarthRotation.meanSiderealTime(time)) * Engine.radiansPerHour
        let expected = reference.dpsi * cos(reference.obl06)
        #expect(abs(Published.wrapped(difference - expected)) <= Self.tolerance)
    }

    /// The engine's apparent sidereal time leaves out the complementary
    /// terms of the equation of the equinoxes (below 3 mas, #170) and uses IAU
    /// 2000B, which McCarthy and Luzum (2003) give as within 1 mas of IAU
    /// 2000A from 1995 to 2050. Together that is under 4 mas, 1.94e-8 rad.
    /// The difference at this date is 0.73 mas.
    @Test("ERFA t_gst06a reference, within the model difference")
    func erfaApparentSiderealTime() {
        let days = Published.days(mjd: Published.gst06a.mjd)
        let hours = Self.apparent(Self.time(ut: days, tt: days))
        #expect(abs(Published.wrapped(hours * Engine.radiansPerHour - Published.gst06a.value)) <= 1.94e-8)
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
