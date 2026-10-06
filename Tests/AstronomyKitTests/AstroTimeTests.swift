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
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2_025)
            #expect(components.month == 6)
            #expect(components.day == 21)
        }

        @Test("Create from full components including time")
        func createFromFullComponents() {
            let time = AstroTime(year: 2_025, month: 12, day: 25, hour: 14, minute: 30, second: 45.5)

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2_025)
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
                originalDate.timeIntervalSince1970 - roundTrippedDate.timeIntervalSince1970
            )

            #expect(difference < 1.0, "Round-tripped date should be within 1 second")
        }

        @Test("Create from UT days")
        func createFromUTDays() {
            let time = AstroTime(ut: 0)

            // ut=0 is UT1 noon; its civil UTC date differs by the modeled DUT1.
            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2_000)
            #expect(components.month == 1)
            #expect(components.day == 1)
            #expect(time.universalTime == 0)
            #expect(abs(date.timeIntervalSince1970 - 946_728_000) < 1)
        }

        @Test("J2000 epoch verification")
        func j2000Epoch() {
            let time = AstroTime(year: 2_000, month: 1, day: 1, hour: 12)

            #expect(abs(time.universalTime) < 0.0001, "J2000 epoch should have ut ≈ 0")
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
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let later = time.addingDays(10)

            #expect(later.universalTime - time.universalTime == 10, "Difference should be exactly 10 days")
            #expect(later > time)
        }

        @Test("Add negative days")
        func addNegativeDays() {
            let time = AstroTime(year: 2_025, month: 1, day: 15)
            let earlier = time.addingDays(-5)

            #expect(time.universalTime - earlier.universalTime == 5, "Difference should be exactly 5 days")
            #expect(earlier < time)
        }

        @Test("Add fractional days")
        func addFractionalDays() {
            let time = AstroTime(year: 2_025, month: 1, day: 1, hour: 0)
            let later = time.addingDays(0.5)  // Add 12 hours

            let date = later.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let hour = calendar.component(.hour, from: date)

            #expect(hour == 12)
        }

        @Test("Add positive hours")
        func addPositiveHours() {
            let time = AstroTime(year: 2_025, month: 1, day: 1, hour: 0)
            let later = time.addingHours(6)

            let expectedDayDiff = 6.0 / 24.0
            #expect(abs(later.universalTime - time.universalTime - expectedDayDiff) < 0.0001)
        }

        @Test("Add negative hours")
        func addNegativeHours() {
            let time = AstroTime(year: 2_025, month: 1, day: 1, hour: 12)
            let earlier = time.addingHours(-3)

            let date = earlier.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let hour = calendar.component(.hour, from: date)

            #expect(hour == 8 || hour == 9)
            #expect(abs(earlier.date.timeIntervalSince(time.date) + 10_800) < 0.01)
        }

        @Test("Chain multiple operations")
        func chainOperations() {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let result = time.addingDays(1).addingHours(12).addingDays(-0.5)

            // 1 day + 12 hours - 12 hours = 1 day
            #expect(abs(result.universalTime - time.universalTime - 1.0) < 0.0001)
        }
    }

    // MARK: - Properties Tests

    @Suite("Properties")
    struct Properties {
        @Test("UT and TT properties exist")
        func utAndTT() {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            // TT should be slightly ahead of UT (by ~69 seconds in modern era)
            #expect(time.terrestrialTime > time.universalTime)

            // The difference should be reasonable (less than 2 minutes)
            let diffSeconds = (time.terrestrialTime - time.universalTime) * 24 * 3_600
            #expect(diffSeconds > 0 && diffSeconds < 120)
        }

        @Test("Sidereal time is in valid range")
        func siderealTimeRange() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let sidereal = time.siderealTime

            #expect(sidereal >= 0)
            #expect(sidereal < 24)
        }

        @Test("Local sidereal time wraps into [0, 24) for any finite longitude")
        func localSiderealTimeWrapsFiniteLongitudes() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let longitudes: [Double] = [
                0, -0.0, 180, -180, 360, -360, 721.5, -721.5, 1e6, -1e6,
                1e300, -1e300, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
                .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
            ]
            for longitude in longitudes {
                let lst = time.siderealTime(longitude: longitude)
                #expect(lst >= 0, "longitude \(longitude) gave \(lst)")
                #expect(lst < 24, "longitude \(longitude) gave \(lst)")
                #expect(lst.sign == .plus, "longitude \(longitude) gave negative zero")
            }
        }

        @Test("Local sidereal time matches Greenwich time plus longitude for ordinary longitudes")
        func localSiderealTimeOrdinary() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let greenwich = time.siderealTime
            for longitude in [-122.4, -75.0, 0, 30.5, 139.7] {
                let expected = (greenwich + longitude / 15.0).truncatingRemainder(dividingBy: 24)
                let wrapped = expected < 0 ? expected + 24 : expected
                #expect(abs(time.siderealTime(longitude: longitude) - wrapped) < 1e-12)
            }
            #expect(time.siderealTime(longitude: 0) == greenwich)
        }

        @Test("Local sidereal time is periodic in 360 degrees of longitude")
        func localSiderealTimePeriodic() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let base = time.siderealTime(longitude: 10)
            #expect(abs(time.siderealTime(longitude: 370) - base) < 1e-9)
            #expect(abs(time.siderealTime(longitude: -350) - base) < 1e-9)
        }

        @Test("Local sidereal time never returns 24 when the wrap rounds up")
        func localSiderealTimeNeverExactly24() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let greenwich = time.siderealTime
            // Step the longitude across the point where the local sidereal time
            // crosses 0. Just below it, the remainder is a tiny negative number and
            // adding 24 rounds to exactly 24.
            var roundsUpTo24 = 0
            var longitude = -greenwich * 15.0
            for _ in 0..<64 {
                let raw = greenwich + longitude / 15.0
                if raw < 0, raw + 24.0 == 24.0 { roundsUpTo24 += 1 }
                let lst = time.siderealTime(longitude: longitude)
                #expect(lst >= 0 && lst < 24, "longitude \(longitude) gave \(lst)")
                longitude = longitude.nextDown
            }
            #expect(roundsUpTo24 > 0, "the sweep never reached the rounding case")
        }

        @Test("Local sidereal time is NaN for non-finite longitudes and does not hang")
        func localSiderealTimeNonFinite() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            #expect(time.siderealTime(longitude: .infinity).isNaN)
            #expect(time.siderealTime(longitude: -.infinity).isNaN)
            #expect(time.siderealTime(longitude: .nan).isNaN)
        }

        @Test("Date property round-trips correctly")
        func dateRoundTrip() {
            let original = AstroTime(year: 2_025, month: 7, day: 4, hour: 18, minute: 30, second: 0)
            let date = original.date
            let recreated = AstroTime(date)

            // Should be within 1 second
            #expect(abs(original.universalTime - recreated.universalTime) < 1.0 / 86_400.0)
        }

        @Test("Date round-trip preserves fractional seconds")
        func dateRoundTripFractionalSeconds() {
            let original = AstroTime(
                year: 2_025, month: 7, day: 4, hour: 18, minute: 30, second: 12.345
            )
            let recreated = AstroTime(original.date)

            // Conversion is pure arithmetic, so it should hold to well under
            // a millisecond.
            #expect(
                abs(original.universalTime - recreated.universalTime) < 0.001 / 86_400.0
            )
        }

        @Test("Date round-trip works before 1970")
        func dateRoundTripPre1970() {
            let original = AstroTime(year: 1_950, month: 3, day: 15, hour: 6)
            let date = original.date
            let recreated = AstroTime(date)

            #expect(date.timeIntervalSince1970 < 0)
            #expect(abs(original.universalTime - recreated.universalTime) < 0.001 / 86_400.0)
        }

        @Test("Date conversion matches the J2000 epoch")
        func dateMatchesJ2000() {
            let date = Date(timeIntervalSince1970: 946_728_000)
            let j2000 = AstroTime(date)
            #expect(j2000.date == date)
            #expect(abs(j2000.terrestrialTime * 86_400 - 64.184) < 0.000001)
        }
    }

    // MARK: - Protocol Conformance Tests

    @Suite("Protocol Conformances")
    struct ProtocolConformances {
        @Test("Equatable - equal times")
        func equatableEqual() {
            let time1 = AstroTime(year: 2_025, month: 1, day: 1)
            let time2 = AstroTime(year: 2_025, month: 1, day: 1)

            #expect(time1 == time2)
        }

        @Test("Equatable - unequal times")
        func equatableUnequal() {
            let time1 = AstroTime(year: 2_025, month: 1, day: 1)
            let time2 = AstroTime(year: 2_025, month: 1, day: 2)

            #expect(time1 != time2)
        }

        @Test("Comparable - less than")
        func comparableLessThan() {
            let earlier = AstroTime(year: 2_020, month: 1, day: 1)
            let later = AstroTime(year: 2_025, month: 1, day: 1)

            #expect(earlier < later)
            #expect(later > earlier)
            #expect(earlier <= later)
            #expect(later >= earlier)
        }

        @Test("Hashable - equal times have equal hashes")
        func hashableEqual() {
            let time1 = AstroTime(year: 2_025, month: 6, day: 21)
            let time2 = AstroTime(year: 2_025, month: 6, day: 21)

            #expect(time1.hashValue == time2.hashValue)
        }

        @Test("Hashable - can be used in Set")
        func hashableInSet() {
            let time1 = AstroTime(year: 2_025, month: 1, day: 1)
            let time2 = AstroTime(year: 2_025, month: 1, day: 2)
            let time3 = AstroTime(year: 2_025, month: 1, day: 1)  // Duplicate

            let set: Set<AstroTime> = [time1, time2, time3]

            #expect(set.count == 2)
        }

        @Test("Equality, ordering and hashing use UT alone")
        func universalTimeOnly() {
            let pair = AstroTime(tt: 5, ut: 10, deltaTModel: .jplHorizons)
            let otherTT = AstroTime(tt: 7, ut: 10, deltaTModel: .espenakMeeus)
            let derived = AstroTime(ut: 10, deltaTModel: .jplHorizons)
            #expect(pair == otherTT)
            #expect(pair == derived)
            #expect(pair.hashValue == otherTT.hashValue)
            #expect(pair.hashValue == derived.hashValue)
            #expect(Set([pair, otherTT, derived]).count == 1)

            let nextUT = AstroTime(tt: 5, ut: 10.0.nextUp, deltaTModel: .jplHorizons)
            #expect(pair != nextUT)
            #expect(pair < nextUT)
            // A later TT does not make a time later.
            #expect(AstroTime(tt: 100, ut: 1) < AstroTime(tt: 0, ut: 2))
        }

        @Test("Signed zero UTs are equal and hash alike")
        func signedZero() {
            let positive = AstroTime(tt: 0.000_7, ut: 0.0)
            let negative = AstroTime(tt: 0.000_7, ut: -0.0)
            #expect(negative.universalTime.sign == .minus)
            #expect(positive == negative)
            #expect(positive.hashValue == negative.hashValue)
        }

        @Test("CustomStringConvertible - ISO8601 format")
        func description() {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12, minute: 0, second: 0)
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
            let original = AstroTime(year: 2_025, month: 6, day: 21, hour: 14, minute: 30)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AstroTime.self, from: data)

            #expect(original == decoded)
        }

        @Test("Decodes as single value (UT)")
        func decodesAsSingleValue() throws {
            // AstroTime encodes as a single Double (the UT value)
            let original = AstroTime(year: 2_025, month: 1, day: 1, hour: 12)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)
            let jsonString = String(data: data, encoding: .utf8)!

            // Should be a simple number, not an object
            #expect(!jsonString.contains("{"))
            #expect(!jsonString.contains("}"))
        }

        /// TT one day after UT is not what either Delta T model gives, so a
        /// decoded time cannot have it.
        @Test("The encoded form is exactly the UT; decoding derives TT again")
        func encodesUniversalTimeOnly() throws {
            for ut in [9_131.25, 0.1 + 0.2, -36_525.123_456_789_012, 1e15 + 0.5, 5e-324] {
                let original = AstroTime(tt: ut + 1, ut: ut, deltaTModel: .jplHorizons)
                let data = try JSONEncoder().encode(original)
                #expect(try JSONDecoder().decode(Double.self, from: data).bitPattern == ut.bitPattern)
                let decoded = try JSONDecoder().decode(AstroTime.self, from: data)
                #expect(decoded.universalTime.bitPattern == ut.bitPattern)
                #expect(decoded == original)
                #expect(decoded.terrestrialTime != original.terrestrialTime)
            }
        }

        @Test("Decode from raw UT value")
        func decodeFromRawUT() throws {
            // ut = 0 is J2000 epoch
            let json = "0.0"
            let data = json.data(using: .utf8)!

            let decoder = JSONDecoder()
            let time = try decoder.decode(AstroTime.self, from: data)

            #expect(abs(time.universalTime) < 0.0001)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {
        @Test("Leap year date")
        func leapYearDate() {
            let time = AstroTime(year: 2_024, month: 2, day: 29)  // Leap year

            let date = time.date
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

            #expect(components.year == 2_024)
            #expect(components.month == 2)
            #expect(components.day == 29)
        }

        @Test("Year boundaries")
        func yearBoundaries() {
            let endOfYear = AstroTime(
                year: 2_024,
                month: 12,
                day: 31,
                hour: 23,
                minute: 59,
                second: 59
            )
            let startOfYear = AstroTime(year: 2_025, month: 1, day: 1, hour: 0, minute: 0, second: 0)

            #expect(startOfYear > endOfYear)

            let diff = startOfYear.universalTime - endOfYear.universalTime
            #expect(diff > 0 && diff < 1.0 / 1_440.0)  // Less than 1 minute apart
        }

        @Test("Far future date")
        func farFutureDate() {
            let time = AstroTime(year: 3_000, month: 1, day: 1)

            let date = time.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let year = calendar.component(.year, from: date)

            // Allow some variance due to calendar/Foundation limitations
            #expect(year >= 2_999 && year <= 3_001)
        }

        @Test("Components beyond Int32 range don't crash")
        func extremeComponents() {
            let time = AstroTime(year: Int.max, month: Int.min, day: 1)

            // Clamped components produce a finite (if physically meaningless) time.
            #expect(time.universalTime.isFinite)
        }

        @Test("Historical date")
        func historicalDate() {
            let time = AstroTime(year: 1_900, month: 1, day: 1)

            let date = time.date
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let year = calendar.component(.year, from: date)

            // Allow some variance due to calendar/Foundation limitations
            #expect(year >= 1_899 && year <= 1_901)
        }

        @Test("Midnight boundary")
        func midnightBoundary() {
            let justBeforeMidnight = AstroTime(
                year: 2_025,
                month: 1,
                day: 1,
                hour: 23,
                minute: 59,
                second: 59
            )
            let midnight = AstroTime(year: 2_025, month: 1, day: 2, hour: 0, minute: 0, second: 0)

            #expect(midnight > justBeforeMidnight)
        }
    }
}
