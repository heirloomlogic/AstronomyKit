//
//  AstroTimeTests.swift
//  AstronomyKit
//
//  Comprehensive tests for the AstroTime type.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("AstroTime Tests")
struct AstroTimeTests {

    // MARK: - Construction Tests

    @Suite("Construction")
    struct Construction {

        @Test("Create from year/month/day components")
        func createFromComponents() {
            let time = AstroTime(year: 2025, month: 6, day: 21)

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2025)
            #expect(components.month == 6)
            #expect(components.day == 21)
        }

        @Test("Create from full components including time")
        func createFromFullComponents() {
            let time = AstroTime(year: 2025, month: 12, day: 25, hour: 14, minute: 30, second: 45.5)

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2025)
            #expect(components.month == 12)
            #expect(components.day == 25)
            #expect(components.hour == 14)
            #expect(components.minute == 30)
            #expect(components.second == 45)
        }

        @Test("Create from Foundation Date")
        func createFromDate() {
            let originalDate = Date(timeIntervalSince1970: 1_735_689_600)  // 2025-01-01T00:00:00Z
            let time = AstroTime(originalDate)

            let roundTrippedDate = time.date
            let difference = abs(
                originalDate.timeIntervalSince1970 - roundTrippedDate.timeIntervalSince1970)

            #expect(difference < 1.0, "Round-tripped date should be within 1 second")
        }

        @Test("Create from UT days")
        func createFromUTDays() {
            let time = AstroTime(ut: 0)

            // ut=0 corresponds to J2000 epoch: 2000-01-01 12:00:00 UTC
            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2000)
            #expect(components.month == 1)
            #expect(components.day == 1)
            #expect(components.hour == 12)
        }

        @Test("J2000 epoch verification")
        func j2000Epoch() {
            let time = AstroTime(year: 2000, month: 1, day: 1, hour: 12)

            #expect(abs(time.ut) < 0.0001, "J2000 epoch should have ut ≈ 0")
        }

        @Test("Static now property")
        func staticNow() {
            let before = Date()
            let time = AstroTime.now
            let after = Date()

            let timeDate = time.date

            // Allow 1 second tolerance for test execution timing
            #expect(timeDate.timeIntervalSince1970 >= before.timeIntervalSince1970 - 1)
            #expect(timeDate.timeIntervalSince1970 <= after.timeIntervalSince1970 + 1)
        }
    }

    // MARK: - Time Arithmetic Tests

    @Suite("Time Arithmetic")
    struct TimeArithmetic {

        @Test("Add positive days")
        func addPositiveDays() {
            let time = AstroTime(year: 2025, month: 1, day: 1)
            let later = time.addingDays(10)

            #expect(later.ut - time.ut == 10, "Difference should be exactly 10 days")
            #expect(later > time)
        }

        @Test("Add negative days")
        func addNegativeDays() {
            let time = AstroTime(year: 2025, month: 1, day: 15)
            let earlier = time.addingDays(-5)

            #expect(time.ut - earlier.ut == 5, "Difference should be exactly 5 days")
            #expect(earlier < time)
        }

        @Test("Add fractional days")
        func addFractionalDays() {
            let time = AstroTime(year: 2025, month: 1, day: 1, hour: 0)
            let later = time.addingDays(0.5)  // Add 12 hours

            let date = later.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let hour = calendar.component(.hour, from: date)

            #expect(hour == 12)
        }

        @Test("Add positive hours")
        func addPositiveHours() {
            let time = AstroTime(year: 2025, month: 1, day: 1, hour: 0)
            let later = time.addingHours(6)

            let expectedDayDiff = 6.0 / 24.0
            #expect(abs(later.ut - time.ut - expectedDayDiff) < 0.0001)
        }

        @Test("Add negative hours")
        func addNegativeHours() {
            let time = AstroTime(year: 2025, month: 1, day: 1, hour: 12)
            let earlier = time.addingHours(-3)

            let date = earlier.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let hour = calendar.component(.hour, from: date)

            #expect(hour == 9)
        }

        @Test("Chain multiple operations")
        func chainOperations() {
            let time = AstroTime(year: 2025, month: 1, day: 1)
            let result = time.addingDays(1).addingHours(12).addingDays(-0.5)

            // 1 day + 12 hours - 12 hours = 1 day
            #expect(abs(result.ut - time.ut - 1.0) < 0.0001)
        }
    }

    // MARK: - Properties Tests

    @Suite("Properties")
    struct Properties {

        @Test("UT and TT properties exist")
        func utAndTT() {
            let time = AstroTime(year: 2025, month: 6, day: 21)

            // TT should be slightly ahead of UT (by ~69 seconds in modern era)
            #expect(time.tt > time.ut)

            // The difference should be reasonable (less than 2 minutes)
            let diffSeconds = (time.tt - time.ut) * 24 * 3600
            #expect(diffSeconds > 0 && diffSeconds < 120)
        }

        @Test("Sidereal time is in valid range")
        func siderealTimeRange() {
            let time = AstroTime(year: 2025, month: 6, day: 21, hour: 12)
            let sidereal = time.siderealTime

            #expect(sidereal >= 0)
            #expect(sidereal < 24)
        }

        @Test("Date property round-trips correctly")
        func dateRoundTrip() {
            let original = AstroTime(year: 2025, month: 7, day: 4, hour: 18, minute: 30, second: 0)
            let date = original.date
            let recreated = AstroTime(date)

            // Should be within 1 second
            #expect(abs(original.ut - recreated.ut) < 1.0 / 86400.0)
        }
    }

    // MARK: - Protocol Conformance Tests

    @Suite("Protocol Conformances")
    struct ProtocolConformances {

        @Test("Equatable - equal times")
        func equatableEqual() {
            let time1 = AstroTime(year: 2025, month: 1, day: 1)
            let time2 = AstroTime(year: 2025, month: 1, day: 1)

            #expect(time1 == time2)
        }

        @Test("Equatable - unequal times")
        func equatableUnequal() {
            let time1 = AstroTime(year: 2025, month: 1, day: 1)
            let time2 = AstroTime(year: 2025, month: 1, day: 2)

            #expect(time1 != time2)
        }

        @Test("Comparable - less than")
        func comparableLessThan() {
            let earlier = AstroTime(year: 2020, month: 1, day: 1)
            let later = AstroTime(year: 2025, month: 1, day: 1)

            #expect(earlier < later)
            #expect(later > earlier)
            #expect(earlier <= later)
            #expect(later >= earlier)
        }

        @Test("Hashable - equal times have equal hashes")
        func hashableEqual() {
            let time1 = AstroTime(year: 2025, month: 6, day: 21)
            let time2 = AstroTime(year: 2025, month: 6, day: 21)

            #expect(time1.hashValue == time2.hashValue)
        }

        @Test("Hashable - can be used in Set")
        func hashableInSet() {
            let time1 = AstroTime(year: 2025, month: 1, day: 1)
            let time2 = AstroTime(year: 2025, month: 1, day: 2)
            let time3 = AstroTime(year: 2025, month: 1, day: 1)  // Duplicate

            let set: Set<AstroTime> = [time1, time2, time3]

            #expect(set.count == 2)
        }

        @Test("CustomStringConvertible - ISO8601 format")
        func description() {
            let time = AstroTime(year: 2025, month: 6, day: 21, hour: 12, minute: 0, second: 0)
            let description = time.description

            #expect(description.contains("2025"))
            #expect(description.contains("06"))
            #expect(description.contains("21"))
        }
    }

    // MARK: - Codable Tests

    @Suite("Codable")
    struct CodableTests {

        @Test("Encode and decode round-trip")
        func encodeDecodeRoundTrip() throws {
            let original = AstroTime(year: 2025, month: 6, day: 21, hour: 14, minute: 30)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AstroTime.self, from: data)

            #expect(original == decoded)
        }

        @Test("Decodes as single value (UT)")
        func decodesAsSingleValue() throws {
            // AstroTime encodes as a single Double (the UT value)
            let original = AstroTime(year: 2025, month: 1, day: 1, hour: 12)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)
            let jsonString = String(data: data, encoding: .utf8)!

            // Should be a simple number, not an object
            #expect(!jsonString.contains("{"))
            #expect(!jsonString.contains("}"))
        }

        @Test("Decode from raw UT value")
        func decodeFromRawUT() throws {
            // ut = 0 is J2000 epoch
            let json = "0.0"
            let data = json.data(using: .utf8)!

            let decoder = JSONDecoder()
            let time = try decoder.decode(AstroTime.self, from: data)

            #expect(abs(time.ut) < 0.0001)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test("Leap year date")
        func leapYearDate() {
            let time = AstroTime(year: 2024, month: 2, day: 29)  // Leap year

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2024)
            #expect(components.month == 2)
            #expect(components.day == 29)
        }

        @Test("Year boundaries")
        func yearBoundaries() {
            let endOfYear = AstroTime(
                year: 2024, month: 12, day: 31, hour: 23, minute: 59, second: 59)
            let startOfYear = AstroTime(year: 2025, month: 1, day: 1, hour: 0, minute: 0, second: 0)

            #expect(startOfYear > endOfYear)

            let diff = startOfYear.ut - endOfYear.ut
            #expect(diff > 0 && diff < 1.0 / 1440.0)  // Less than 1 minute apart
        }

        @Test("Far future date")
        func farFutureDate() {
            let time = AstroTime(year: 3000, month: 1, day: 1)

            let date = time.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let year = calendar.component(.year, from: date)

            // Allow some variance due to calendar/Foundation limitations
            #expect(year >= 2999 && year <= 3001)
        }

        @Test("Historical date")
        func historicalDate() {
            let time = AstroTime(year: 1900, month: 1, day: 1)

            let date = time.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let year = calendar.component(.year, from: date)

            // Allow some variance due to calendar/Foundation limitations
            #expect(year >= 1899 && year <= 1901)
        }

        @Test("Midnight boundary")
        func midnightBoundary() {
            let justBeforeMidnight = AstroTime(
                year: 2025, month: 1, day: 1, hour: 23, minute: 59, second: 59)
            let midnight = AstroTime(year: 2025, month: 1, day: 2, hour: 0, minute: 0, second: 0)

            #expect(midnight > justBeforeMidnight)
        }
    }
}
