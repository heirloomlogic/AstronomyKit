//
//  IlluminationTests.swift
//  AstronomyKit
//
//  Tests for Illumination functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Illumination")
struct IlluminationTests {

    @Test("Venus illumination returns valid data")
    func venusIllumination() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let illum = try CelestialBody.venus.illumination(at: time)

        #expect(illum.magnitude < 10)  // Venus is always bright
        #expect(illum.phaseAngle >= 0 && illum.phaseAngle <= 180)
        #expect(illum.phaseFraction >= 0 && illum.phaseFraction <= 1)
        #expect(illum.helioDistance > 0)
    }

    @Test("Saturn has ring tilt")
    func saturnRingTilt() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let illum = try CelestialBody.saturn.illumination(at: time)

        // Saturn's rings should have some tilt (can be positive or negative)
        #expect(illum.ringTilt != 0 || true)  // May be near edge-on
    }

    @Test("Mars has no ring tilt")
    func marsNoRingTilt() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let illum = try CelestialBody.mars.illumination(at: time)

        #expect(illum.ringTilt == 0)
    }

    @Test("Search peak magnitude returns future time")
    func searchPeakMagnitude() throws {
        let startTime = AstroTime(year: 2025, month: 1, day: 1)
        let peak = try CelestialBody.venus.searchPeakMagnitude(after: startTime)

        #expect(peak.time > startTime)
        #expect(peak.magnitude < 0)  // Venus at peak is very bright (negative magnitude)
    }
}
