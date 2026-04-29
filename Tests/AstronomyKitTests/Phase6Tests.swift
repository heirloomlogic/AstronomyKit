//
//  Phase6Tests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("LagrangePoint Fast")
struct LagrangePointFastTests {

    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("Fast calculation matches standard calculation")
    func fastMatchesStandard() throws {
        let standard = try LagrangePoint.calculate(
            point: .l2, at: testTime, majorBody: .sun, minorBody: .earth
        )

        let sunState = try CelestialBody.sun.barycentricState(at: testTime)
        let earthState = try CelestialBody.earth.barycentricState(at: testTime)
        let sunMass = try #require(CelestialBody.sun.massProduct)
        let earthMass = try #require(CelestialBody.earth.massProduct)

        let fast = try LagrangePoint.calculateFast(
            point: .l2,
            majorState: sunState,
            majorMass: sunMass,
            minorState: earthState,
            minorMass: earthMass
        )

        #expect(abs(fast.position.x - standard.position.x) < 1e-6)
        #expect(abs(fast.position.y - standard.position.y) < 1e-6)
        #expect(abs(fast.position.z - standard.position.z) < 1e-6)
    }

    @Test("Fast calculation works for all Lagrange points", arguments: LagrangePointID.allCases)
    func fastWorksForAllPoints(point: LagrangePointID) throws {
        let sunState = try CelestialBody.sun.barycentricState(at: testTime)
        let earthState = try CelestialBody.earth.barycentricState(at: testTime)
        let sunMass = try #require(CelestialBody.sun.massProduct)
        let earthMass = try #require(CelestialBody.earth.massProduct)

        let result = try LagrangePoint.calculateFast(
            point: point,
            majorState: sunState,
            majorMass: sunMass,
            minorState: earthState,
            minorMass: earthMass
        )
        #expect(result.position.magnitude > 0)
    }
}

@Suite("VectorObserver")
struct VectorObserverTests {

    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("Vector-to-observer roundtrip preserves location")
    func roundtrip() throws {
        let original = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)
        let vec = try original.vector(at: testTime, equator: .ofDate)
        let restored = Observer.from(vector: vec, equatorDate: .ofDate)

        #expect(abs(restored.latitude - original.latitude) < 0.01)
        #expect(abs(restored.longitude - original.longitude) < 0.01)
        #expect(abs(restored.height - original.height) < 100)
    }

    @Test("Vector-to-observer works with J2000 frame")
    func j2000Frame() throws {
        let original = Observer(latitude: 51.4769, longitude: -0.0005, height: 48)
        let vec = try original.vector(at: testTime, equator: .j2000)
        let restored = Observer.from(vector: vec, equatorDate: .j2000)

        #expect(abs(restored.latitude - original.latitude) < 0.01)
        #expect(abs(restored.longitude - original.longitude) < 0.5)
    }
}

@Suite("HourAngle")
struct HourAngleTests {

    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)
    let observer = Observer(latitude: 40.7128, longitude: -74.0060)

    @Test("Hour angle returns value in 0-24 range")
    func hourAngleRange() throws {
        let ha = try CelestialBody.sun.hourAngle(at: testTime, from: observer)
        #expect(ha >= 0 && ha < 24)
    }

    @Test("Hour angle near 0 at culmination")
    func hourAngleAtCulmination() throws {
        let culm = try CelestialBody.sun.culmination(after: testTime, from: observer)
        let ha = try CelestialBody.sun.hourAngle(at: culm.time, from: observer)
        #expect(ha < 0.01 || ha > 23.99, "Hour angle at culmination should be ~0, got \(ha)")
    }

    @Test("Hour angle works for planets", arguments: CelestialBody.planets)
    func hourAngleForPlanets(planet: CelestialBody) throws {
        let ha = try planet.hourAngle(at: testTime, from: observer)
        #expect(ha >= 0 && ha < 24)
    }
}

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
        // Jupiter is far enough that light travel time produces a measurable difference
        let diff = abs(instant.x - backdated.x) + abs(instant.y - backdated.y) + abs(instant.z - backdated.z)
        #expect(diff > 1e-6, "Backdated position should differ from instantaneous")
    }
}
