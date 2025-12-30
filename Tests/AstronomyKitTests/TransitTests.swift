//
//  TransitTests.swift
//  AstronomyKit
//
//  Tests for Transit functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Transit")
struct TransitTests {

    @Test("Search Mercury transit")
    func searchMercuryTransit() throws {
        let startTime = AstroTime(year: 2020, month: 1, day: 1)
        let transit = try Transit.search(body: .mercury, after: startTime)

        #expect(transit.body == .mercury)
        #expect(transit.peak > startTime)
        #expect(transit.start < transit.peak)
        #expect(transit.peak < transit.finish)
        #expect(transit.separation > 0)
    }

    @Test("Search Venus transit")
    func searchVenusTransit() throws {
        // Venus transits are very rare - search from a known transit year
        let startTime = AstroTime(year: 2012, month: 1, day: 1)
        let transit = try Transit.search(body: .venus, after: startTime)

        #expect(transit.body == .venus)
        #expect(transit.peak > startTime)
    }

    @Test("Transit duration is positive")
    func transitDuration() throws {
        let startTime = AstroTime(year: 2020, month: 1, day: 1)
        let transit = try Transit.search(body: .mercury, after: startTime)

        #expect(transit.duration > 0)
    }

    @Test("Next transit iterates")
    func nextTransit() throws {
        let startTime = AstroTime(year: 2020, month: 1, day: 1)
        let first = try Transit.search(body: .mercury, after: startTime)
        let second = try Transit.next(body: .mercury, after: first)

        #expect(second.peak > first.peak)
    }
}
