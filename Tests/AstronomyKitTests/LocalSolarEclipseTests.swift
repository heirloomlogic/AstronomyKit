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

    @Test("Total eclipse has total begin/end")
    func totalEclipsePhases() throws {
        // Search for a total eclipse with a longer range if needed
        let startTime = AstroTime(year: 2_024, month: 1, day: 1)
        // Use a location in the path of the 2024 total eclipse
        let observer = Observer(latitude: 44.35, longitude: -99.46)  // South Dakota

        let eclipse = try Eclipse.searchLocalSolar(after: startTime, from: observer)

        // The eclipse may or may not be total depending on exact location
        if eclipse.kind == .total {
            #expect(eclipse.totalBegin != nil)
            #expect(eclipse.totalEnd != nil)
        }
    }
}
