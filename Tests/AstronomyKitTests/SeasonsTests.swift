//
//  SeasonsTests.swift
//  AstronomyKit
//
//  Comprehensive tests for the Seasons type.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Seasons Tests")
struct SeasonsTests {

    // MARK: - Basic Calculation Tests

    @Suite("Basic Calculations")
    struct BasicCalculations {

        @Test("Calculate seasons for a year")
        func calculateForYear() throws {
            let seasons = try Seasons.forYear(2025)

            // All four events should exist
            #expect(seasons.marchEquinox.ut != 0)
            #expect(seasons.juneSolstice.ut != 0)
            #expect(seasons.septemberEquinox.ut != 0)
            #expect(seasons.decemberSolstice.ut != 0)
        }

        @Test("Seasons occur in correct order")
        func correctOrder() throws {
            let seasons = try Seasons.forYear(2025)

            #expect(seasons.marchEquinox < seasons.juneSolstice)
            #expect(seasons.juneSolstice < seasons.septemberEquinox)
            #expect(seasons.septemberEquinox < seasons.decemberSolstice)
        }

        @Test("March equinox is in March")
        func marchEquinoxMonth() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.marchEquinox.date)

            #expect(month == 3)
        }

        @Test("June solstice is in June")
        func juneSolsticeMonth() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.juneSolstice.date)

            #expect(month == 6)
        }

        @Test("September equinox is in September")
        func septemberEquinoxMonth() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.septemberEquinox.date)

            #expect(month == 9)
        }

        @Test("December solstice is in December")
        func decemberSolsticeMonth() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.decemberSolstice.date)

            #expect(month == 12)
        }
    }

    // MARK: - Date Accuracy Tests

    @Suite("Date Accuracy")
    struct DateAccuracy {

        @Test("March equinox around expected day")
        func marchEquinoxDay() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.marchEquinox.date)

            // Typically March 19-21
            #expect(day >= 19 && day <= 21)
        }

        @Test("June solstice around expected day")
        func juneSolsticeDay() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.juneSolstice.date)

            // Typically June 20-22
            #expect(day >= 20 && day <= 22)
        }

        @Test("September equinox around expected day")
        func septemberEquinoxDay() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.septemberEquinox.date)

            // Typically Sept 22-24
            #expect(day >= 22 && day <= 24)
        }

        @Test("December solstice around expected day")
        func decemberSolsticeDay() throws {
            let seasons = try Seasons.forYear(2025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.decemberSolstice.date)

            // Typically Dec 20-22
            #expect(day >= 20 && day <= 22)
        }
    }

    // MARK: - All Events Property Tests

    @Suite("All Events")
    struct AllEventsTests {

        @Test("allEvents returns 4 events")
        func fourEvents() throws {
            let seasons = try Seasons.forYear(2025)
            let events = seasons.allEvents

            #expect(events.count == 4)
        }

        @Test("allEvents in chronological order")
        func chronologicalOrder() throws {
            let seasons = try Seasons.forYear(2025)
            let events = seasons.allEvents

            for i in 0..<(events.count - 1) {
                #expect(events[i].time < events[i + 1].time)
            }
        }

        @Test("allEvents has correct names")
        func correctNames() throws {
            let seasons = try Seasons.forYear(2025)
            let events = seasons.allEvents

            #expect(events[0].name == "March Equinox")
            #expect(events[1].name == "June Solstice")
            #expect(events[2].name == "September Equinox")
            #expect(events[3].name == "December Solstice")
        }
    }

    // MARK: - Multi-Year Tests

    @Suite("Multi-Year")
    struct MultiYearTests {

        @Test("Different years have different dates")
        func differentYears() throws {
            let seasons2024 = try Seasons.forYear(2024)
            let seasons2025 = try Seasons.forYear(2025)

            #expect(seasons2024.marchEquinox != seasons2025.marchEquinox)
            #expect(seasons2024.juneSolstice != seasons2025.juneSolstice)
        }

        @Test("Year-to-year intervals are approximately 365 days")
        func yearlyInterval() throws {
            let seasons2024 = try Seasons.forYear(2024)
            let seasons2025 = try Seasons.forYear(2025)

            let diff = seasons2025.marchEquinox.ut - seasons2024.marchEquinox.ut

            // Should be about 365-366 days
            #expect(diff > 364 && diff < 367)
        }

        @Test("Historical year", arguments: [1900, 1950, 2000])
        func historicalYears(year: Int) throws {
            let seasons = try Seasons.forYear(year)

            let calendar = Calendar(identifier: .gregorian)
            let marchYear = calendar.component(.year, from: seasons.marchEquinox.date)

            #expect(marchYear == year)
        }

        @Test("Future year")
        func futureYear() throws {
            let seasons = try Seasons.forYear(2100)

            let calendar = Calendar(identifier: .gregorian)
            let marchYear = calendar.component(.year, from: seasons.marchEquinox.date)

            #expect(marchYear == 2100)
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformances {

        @Test("Equatable - equal seasons")
        func equatable() throws {
            let s1 = try Seasons.forYear(2025)
            let s2 = try Seasons.forYear(2025)

            #expect(s1 == s2)
        }

        @Test("Equatable - different seasons")
        func equatableDifferent() throws {
            let s1 = try Seasons.forYear(2024)
            let s2 = try Seasons.forYear(2025)

            #expect(s1 != s2)
        }

        @Test("CustomStringConvertible contains all events")
        func description() throws {
            let seasons = try Seasons.forYear(2025)
            let desc = seasons.description

            #expect(desc.contains("March Equinox"))
            #expect(desc.contains("June Solstice"))
            #expect(desc.contains("September Equinox"))
            #expect(desc.contains("December Solstice"))
        }

        @Test("CustomStringConvertible contains emoji")
        func descriptionEmoji() throws {
            let seasons = try Seasons.forYear(2025)
            let desc = seasons.description

            #expect(desc.contains("🌸"))
            #expect(desc.contains("☀️"))
            #expect(desc.contains("🍂"))
            #expect(desc.contains("❄️"))
        }
    }

    // MARK: - Codable Tests

    @Suite("Codable")
    struct CodableTests {

        @Test("Encode and decode round-trip")
        func roundTrip() throws {
            let original = try Seasons.forYear(2025)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Seasons.self, from: data)

            #expect(original == decoded)
        }

        @Test("Encodes with expected keys")
        func encodesWithKeys() throws {
            let seasons = try Seasons.forYear(2025)

            let encoder = JSONEncoder()
            let data = try encoder.encode(seasons)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("marchEquinox"))
            #expect(json.contains("juneSolstice"))
            #expect(json.contains("septemberEquinox"))
            #expect(json.contains("decemberSolstice"))
        }
    }
}
