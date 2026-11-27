//
//  ValueTypeConformanceTests.swift
//  AstronomyKit
//
//  Verifies uniform Sendable, Equatable, and Hashable conformances across
//  public value types and DeltaTModel propagation through search APIs.
//

import Testing

@testable import AstronomyKit

@Suite("Value Type Conformances & Delta T Propagation")
struct ValueTypeConformanceTests {
    private static func expectValueType<T: Sendable & Equatable & Hashable>(
        _ a: T,
        equalTo b: T
    ) {
        #expect(a == b)
        let set: Set<T> = [a, b]
        #expect(set.count == 1)
    }

    @Test("Public enums conform uniformly to Sendable, Equatable, and Hashable")
    func publicEnumsConform() {
        Self.expectValueType(DeltaTModel.observed, equalTo: .observed)
        Self.expectValueType(Refraction.normal, equalTo: .normal)
        Self.expectValueType(Aberration.corrected, equalTo: .corrected)
        Self.expectValueType(EquatorDate.j2000, equalTo: .j2000)
        Self.expectValueType(RiseSetDirection.rise, equalTo: .rise)
        Self.expectValueType(LagrangePointID.l2, equalTo: .l2)
        Self.expectValueType(CelestialBody.mars, equalTo: .mars)
        Self.expectValueType(RotationMatrix.Axis.z, equalTo: .z)
        Self.expectValueType(MoonPhase.full, equalTo: .full)
        Self.expectValueType(ApsisKind.pericenter, equalTo: .pericenter)
        Self.expectValueType(EclipseKind.total, equalTo: .total)
        Self.expectValueType(Visibility.evening, equalTo: .evening)
        Self.expectValueType(NodeKind.ascending, equalTo: .ascending)
        Self.expectValueType(AstronomyError.badTime, equalTo: .badTime)
    }

    @Test("Public value structs conform uniformly to Sendable, Equatable, and Hashable")
    func publicStructsConform() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let observer = Observer.greenwich

        Self.expectValueType(
            try Moon.searchApsis(after: time),
            equalTo: try Moon.searchApsis(after: time)
        )
        Self.expectValueType(
            try Atmosphere.at(elevation: 1_000),
            equalTo: try Atmosphere.at(elevation: 1_000)
        )
        Self.expectValueType(
            try Eclipse.searchLunar(after: time),
            equalTo: try Eclipse.searchLunar(after: time)
        )
        let totalEclipseStart = AstroTime(year: 2_024, month: 1, day: 1)
        Self.expectValueType(
            try Eclipse.searchGlobalSolar(after: totalEclipseStart),
            equalTo: try Eclipse.searchGlobalSolar(after: totalEclipseStart)
        )
        let localSolar1 = try Eclipse.searchLocalSolar(after: time, from: observer)
        let localSolar2 = try Eclipse.searchLocalSolar(after: time, from: observer)
        Self.expectValueType(localSolar1, equalTo: localSolar2)
        Self.expectValueType(localSolar1.peak, equalTo: localSolar2.peak)

        Self.expectValueType(
            try CelestialBody.venus.elongation(at: time),
            equalTo: try CelestialBody.venus.elongation(at: time)
        )
        Self.expectValueType(
            try CelestialBody.venus.illumination(at: time),
            equalTo: try CelestialBody.venus.illumination(at: time)
        )
        Self.expectValueType(
            try Jupiter.moons(at: time),
            equalTo: try Jupiter.moons(at: time)
        )
        Self.expectValueType(
            try Moon.geoState(at: time),
            equalTo: try Moon.geoState(at: time)
        )
        Self.expectValueType(
            Moon.libration(at: time),
            equalTo: Moon.libration(at: time)
        )
        Self.expectValueType(
            try Moon.searchNode(after: time),
            equalTo: try Moon.searchNode(after: time)
        )
        Self.expectValueType(
            try Moon.searchQuarter(after: time),
            equalTo: try Moon.searchQuarter(after: time)
        )
        Self.expectValueType(
            try CelestialBody.sun.culmination(after: time, from: observer),
            equalTo: try CelestialBody.sun.culmination(after: time, from: observer)
        )
        Self.expectValueType(
            try DailyEvents(body: .sun, date: time, from: observer),
            equalTo: try DailyEvents(body: .sun, date: time, from: observer)
        )
        Self.expectValueType(
            try RotationMatrix.pivot(axis: .z, angle: 45),
            equalTo: try RotationMatrix.pivot(axis: .z, angle: 45)
        )
        Self.expectValueType(
            try CelestialBody.mars.rotationAxis(at: time),
            equalTo: try CelestialBody.mars.rotationAxis(at: time)
        )
        Self.expectValueType(
            try Seasons.forYear(2_025),
            equalTo: try Seasons.forYear(2_025)
        )
        Self.expectValueType(
            try Transit.search(body: .mercury, after: time),
            equalTo: try Transit.search(body: .mercury, after: time)
        )
    }

    @Test("DeltaTModel propagates through search helpers including Neptune apsis and AstroSearch")
    func deltaTPropagatesThroughSearches() throws {
        let start = AstroTime(year: 2_027, month: 1, day: 1, deltaT: .jplHorizons)

        let root = try AstroSearch.find(from: start, to: start.addingDays(2)) { t in
            #expect(t.deltaTModel == .jplHorizons)
            return t.universalTime - (start.universalTime + 1.0)
        }
        #expect(root?.deltaTModel == .jplHorizons)

        let neptuneApsis = try CelestialBody.neptune.searchApsis(after: start)
        #expect(neptuneApsis.time.deltaTModel == .jplHorizons)

        let lunarApsis = try Moon.searchApsis(after: start)
        #expect(lunarApsis.time.deltaTModel == .jplHorizons)

        let node = try Moon.searchNode(after: start)
        #expect(node.time.deltaTModel == .jplHorizons)

        let quarter = try Moon.searchQuarter(after: start)
        #expect(quarter.time.deltaTModel == .jplHorizons)

        let transit = try Transit.search(body: .mercury, after: start)
        #expect(transit.peak.deltaTModel == .jplHorizons)
        #expect(transit.start.deltaTModel == .jplHorizons)
        #expect(transit.finish.deltaTModel == .jplHorizons)
    }
}
