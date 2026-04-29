//
//  LightTravelTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Light Travel Corrections")
struct LightTravelTests {
    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("CorrectLightTravel produces a valid position")
    func correctLightTravel() throws {
        let result = try AstroSearch.correctLightTravel(at: testTime) { time in
            try! CelestialBody.mars.helioPosition(at: time)
        }
        #expect(result.magnitude > 1.0, "Mars should be > 1 AU from Sun")
    }

    @Test("BackdatePosition produces valid position for Mars")
    func backdatePosition() throws {
        let result = try CelestialBody.mars.backdatedPosition(
            at: testTime,
            seenFrom: .earth
        )
        #expect(result.magnitude > 0)
    }

    @Test("BackdatePosition differs from instantaneous position")
    func backdateVsInstantaneous() throws {
        let instant = try CelestialBody.jupiter.helioPosition(at: testTime)
        let backdated = try CelestialBody.jupiter.backdatedPosition(
            at: testTime,
            seenFrom: .earth,
            aberration: .none
        )
        let diff = abs(instant.x - backdated.x) + abs(instant.y - backdated.y) + abs(instant.z - backdated.z)
        #expect(diff > 1e-6, "Backdated position should differ from instantaneous")
    }
}
