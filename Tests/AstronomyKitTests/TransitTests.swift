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
        let startTime = AstroTime(year: 2_020, month: 1, day: 1)
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
        let startTime = AstroTime(year: 2_012, month: 1, day: 1)
        let transit = try Transit.search(body: .venus, after: startTime)

        #expect(transit.body == .venus)
        #expect(transit.peak > startTime)
    }

    @Test("Transit duration is positive")
    func transitDuration() throws {
        let startTime = AstroTime(year: 2_020, month: 1, day: 1)
        let transit = try Transit.search(body: .mercury, after: startTime)

        #expect(transit.duration > 0)
    }

    @Test("Next transit iterates")
    func nextTransit() throws {
        let startTime = AstroTime(year: 2_020, month: 1, day: 1)
        let first = try Transit.search(body: .mercury, after: startTime)
        let second = try Transit.next(body: .mercury, after: first)

        #expect(second.peak > first.peak)
    }

    @Test("Find transits in range")
    func transitsInRange() throws {
        // Search for Mercury transits in a range known to contain at least one
        let startTime = AstroTime(year: 2_000, month: 1, day: 1)
        let endTime = AstroTime(year: 2_030, month: 1, day: 1)

        let transits = try Transit.transits(body: .mercury, from: startTime, to: endTime)

        // There should be multiple Mercury transits in 30 years
        #expect(transits.count >= 1)

        // All transits should be within range
        for transit in transits {
            #expect(transit.peak >= startTime)
            #expect(transit.peak < endTime)
        }
    }

    @Test("Transit description includes body name")
    func transitDescription() throws {
        let startTime = AstroTime(year: 2_020, month: 1, day: 1)
        let transit = try Transit.search(body: .mercury, after: startTime)

        let desc = transit.description

        #expect(desc.contains("Mercury"))
        #expect(desc.contains("Transit"))
    }

    @Test("Transit Equatable")
    func transitEquatable() throws {
        let startTime = AstroTime(year: 2_020, month: 1, day: 1)
        let transit1 = try Transit.search(body: .mercury, after: startTime)
        let transit2 = try Transit.search(body: .mercury, after: startTime)

        #expect(transit1 == transit2)
    }
}
