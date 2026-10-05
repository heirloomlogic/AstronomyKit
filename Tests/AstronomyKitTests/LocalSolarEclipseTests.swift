//
//  LocalSolarEclipseTests.swift
//  AstronomyKit
//
//  Tests for Local Solar Eclipse functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Local Solar Eclipse")
struct LocalSolarEclipseTests {
    @Test("Search local solar eclipse from NYC")
    func searchLocalSolarEclipse() throws {
        let startTime = AstroTime(year: 2_025, month: 1, day: 1)
        let observer = Observer(latitude: 40.7128, longitude: -74.0060)

        let eclipse = try Eclipse.searchLocalSolar(after: startTime, from: observer)

        #expect(eclipse.peak.time > startTime)
        #expect(eclipse.kind != .none)
        #expect(eclipse.obscuration >= 0 && eclipse.obscuration <= 1)
    }

    @Test("Eclipse event has altitude")
    func eclipseEventAltitude() throws {
        let startTime = AstroTime(year: 2_025, month: 1, day: 1)
        let observer = Observer(latitude: 40.7128, longitude: -74.0060)

        let eclipse = try Eclipse.searchLocalSolar(after: startTime, from: observer)

        // Peak altitude can be positive or negative depending on visibility
        #expect(eclipse.peak.altitude >= -90 && eclipse.peak.altitude <= 90)
    }

    @Test("Next local solar eclipse iterates")
    func nextLocalSolarEclipse() throws {
        let startTime = AstroTime(year: 2_025, month: 1, day: 1)
        let observer = Observer(latitude: 40.7128, longitude: -74.0060)

        let first = try Eclipse.searchLocalSolar(after: startTime, from: observer)
        let second = try Eclipse.nextLocalSolar(after: first, from: observer)

        #expect(second.peak.time > first.peak.time)
    }

    @Test("Known total eclipse contacts remain ordered", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func totalEclipsePhases(model: DeltaTModel) throws {
        let startTime = AstroTime(year: 2_024, month: 1, day: 1, deltaTModel: model)
        let observer = Observer(latitude: 32.7767, longitude: -96.7970)  // Dallas
        let eclipse = try Eclipse.searchLocalSolar(after: startTime, from: observer)
        #expect(eclipse.kind == .total)
        let begin = try #require(eclipse.totalBegin)
        let end = try #require(eclipse.totalEnd)
        #expect(eclipse.partialBegin.time < begin.time)
        #expect(begin.time < eclipse.peak.time)
        #expect(eclipse.peak.time < end.time)
        #expect(end.time < eclipse.partialEnd.time)
        #expect(eclipse.peak.time.deltaTModel == model)
    }
}
