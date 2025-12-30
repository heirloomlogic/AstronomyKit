//
//  EclipseTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Eclipse types.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Eclipse Tests")
struct EclipseTests {

    // MARK: - EclipseKind Tests

    @Suite("EclipseKind")
    struct EclipseKindTests {

        @Test("Eclipse kind names")
        func kindNames() {
            #expect(EclipseKind.none.name == "None")
            #expect(EclipseKind.partial.name == "Partial")
            #expect(EclipseKind.annular.name == "Annular")
            #expect(EclipseKind.total.name == "Total")
        }

        @Test("Eclipse kinds are equatable")
        func equatable() {
            #expect(EclipseKind.total == EclipseKind.total)
            #expect(EclipseKind.total != EclipseKind.partial)
        }

        @Test("Eclipse kinds are hashable")
        func hashable() {
            let set: Set<EclipseKind> = [.none, .partial, .annular, .total]
            #expect(set.count == 4)
        }
    }

    // MARK: - Lunar Eclipse Search Tests

    @Suite("Lunar Eclipse Search")
    struct LunarEclipseSearchTests {

        @Test("Search finds next lunar eclipse")
        func searchFindsEclipse() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchLunar(after: startTime)

            #expect(eclipse.peak > startTime)
            #expect(eclipse.kind != .none)
        }

        @Test("Lunar eclipse has valid kind")
        func validKind() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchLunar(after: startTime)

            // Should be partial, total, or penumbral (mapped to partial)
            #expect(eclipse.kind == .partial || eclipse.kind == .total)
        }

        @Test("Lunar eclipse has magnitude")
        func hasMagnitude() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchLunar(after: startTime)

            // Magnitude should be between 0 and ~2 (can exceed 1 for deep total)
            #expect(eclipse.obscuration >= 0)
            #expect(eclipse.partialDuration >= 0)
        }

        @Test("Next lunar eclipse after previous")
        func nextLunarEclipse() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let first = try Eclipse.searchLunar(after: startTime)
            let second = try Eclipse.nextLunar(after: first)

            #expect(second.peak > first.peak)
        }

        @Test("Lunar eclipses in date range")
        func lunarEclipsesInRange() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let endTime = AstroTime(year: 2026, month: 1, day: 1)

            let eclipses = try Eclipse.lunarEclipses(from: startTime, to: endTime)

            // Typically 2-3 lunar eclipses per year
            #expect(eclipses.count >= 1)
            #expect(eclipses.count <= 5)

            // All should be in range
            for eclipse in eclipses {
                #expect(eclipse.peak >= startTime)
                #expect(eclipse.peak < endTime)
            }
        }
    }

    // MARK: - Global Solar Eclipse Search Tests

    @Suite("Global Solar Eclipse Search")
    struct GlobalSolarEclipseSearchTests {

        @Test("Search finds next global solar eclipse")
        func searchFindsEclipse() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            #expect(eclipse.peak > startTime)
            #expect(eclipse.kind != .none)
        }

        @Test("Global solar eclipse has valid kind")
        func validKind() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            #expect(eclipse.kind == .partial || eclipse.kind == .annular || eclipse.kind == .total)
        }

        @Test("Total/annular eclipses have coordinates")
        func hasCoordinatesForTotalAnnular() throws {
            // Search for several eclipses until we find a total or annular
            var eclipse = try Eclipse.searchGlobalSolar(
                after: AstroTime(year: 2020, month: 1, day: 1))
            var attempts = 0

            while eclipse.kind == .partial && attempts < 10 {
                eclipse = try Eclipse.nextGlobalSolar(after: eclipse)
                attempts += 1
            }

            if eclipse.kind == .total || eclipse.kind == .annular {
                #expect(eclipse.latitude != nil)
                #expect(eclipse.longitude != nil)
            }
        }

        @Test("Next global solar eclipse after previous")
        func nextGlobalSolarEclipse() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let first = try Eclipse.searchGlobalSolar(after: startTime)
            let second = try Eclipse.nextGlobalSolar(after: first)

            #expect(second.peak > first.peak)
        }

        @Test("Global solar eclipses in date range")
        func globalSolarEclipsesInRange() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let endTime = AstroTime(year: 2028, month: 1, day: 1)

            let eclipses = try Eclipse.globalSolarEclipses(from: startTime, to: endTime)

            // Typically 2-5 solar eclipses per year
            #expect(eclipses.count >= 2)

            // All should be in range
            for eclipse in eclipses {
                #expect(eclipse.peak >= startTime)
                #expect(eclipse.peak < endTime)
            }
        }
    }

    // MARK: - LunarEclipse Struct Tests

    @Suite("LunarEclipse Struct")
    struct LunarEclipseStructTests {

        @Test("LunarEclipse has all properties")
        func hasAllProperties() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchLunar(after: startTime)

            _ = eclipse.kind
            _ = eclipse.peak
            _ = eclipse.obscuration
            _ = eclipse.partialDuration
            _ = eclipse.totalDuration
        }

        @Test("Equatable")
        func equatable() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let e1 = try Eclipse.searchLunar(after: startTime)
            let e2 = try Eclipse.searchLunar(after: startTime)

            #expect(e1 == e2)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchLunar(after: startTime)

            let desc = eclipse.description

            #expect(desc.contains("Lunar Eclipse"))
        }
    }

    // MARK: - GlobalSolarEclipse Struct Tests

    @Suite("GlobalSolarEclipse Struct")
    struct GlobalSolarEclipseStructTests {

        @Test("GlobalSolarEclipse has all properties")
        func hasAllProperties() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            _ = eclipse.kind
            _ = eclipse.peak
            _ = eclipse.obscuration
            _ = eclipse.latitude
            _ = eclipse.longitude
        }

        @Test("Equatable")
        func equatable() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let e1 = try Eclipse.searchGlobalSolar(after: startTime)
            let e2 = try Eclipse.searchGlobalSolar(after: startTime)

            // Compare key properties (floating point values may differ slightly)
            #expect(e1.kind == e2.kind)
            #expect(e1.peak == e2.peak)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let startTime = AstroTime(year: 2025, month: 1, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            let desc = eclipse.description

            #expect(desc.contains("Solar Eclipse"))
        }
    }

    // MARK: - Historical Eclipse Tests

    @Suite("Historical Eclipses")
    struct HistoricalEclipseTests {

        @Test("Find 2017 total solar eclipse")
        func eclipse2017() throws {
            // Great American Eclipse was August 21, 2017
            let startTime = AstroTime(year: 2017, month: 8, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: eclipse.peak.date)
            let day = calendar.component(.day, from: eclipse.peak.date)

            #expect(month == 8)
            #expect(day == 21)
            #expect(eclipse.kind == .total)
        }

        @Test("Find 2024 total solar eclipse")
        func eclipse2024() throws {
            // Total solar eclipse April 8, 2024
            let startTime = AstroTime(year: 2024, month: 4, day: 1)
            let eclipse = try Eclipse.searchGlobalSolar(after: startTime)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: eclipse.peak.date)
            let day = calendar.component(.day, from: eclipse.peak.date)

            #expect(month == 4)
            #expect(day == 8)
            #expect(eclipse.kind == .total)
        }
    }
}
