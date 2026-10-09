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
    // MARK: - Input Validation Tests

    @Suite("Input Validation")
    struct InputValidation {
        @Test("Year above Int32 range throws invalidParameter")
        func yearAboveInt32Throws() {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Seasons.forYear(Int(Int32.max) + 1)
            }
        }

        @Test("Int.min year throws invalidParameter")
        func intMinYearThrows() {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Seasons.forYear(Int.min)
            }
        }
    }

    // MARK: - Basic Calculation Tests

    @Suite("Basic Calculations")
    struct BasicCalculations {
        @Test("Calculate seasons for a year")
        func calculateForYear() throws {
            let seasons = try Seasons.forYear(2_025)

            // All four events should exist
            #expect(seasons.marchEquinox.universalTime != 0)
            #expect(seasons.juneSolstice.universalTime != 0)
            #expect(seasons.septemberEquinox.universalTime != 0)
            #expect(seasons.decemberSolstice.universalTime != 0)
        }

        @Test("Seasons occur in correct order")
        func correctOrder() throws {
            let seasons = try Seasons.forYear(2_025)

            #expect(seasons.marchEquinox < seasons.juneSolstice)
            #expect(seasons.juneSolstice < seasons.septemberEquinox)
            #expect(seasons.septemberEquinox < seasons.decemberSolstice)
        }

        @Test("March equinox is in March")
        func marchEquinoxMonth() throws {
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.marchEquinox.date)

            #expect(month == 3)
        }

        @Test("June solstice is in June")
        func juneSolsticeMonth() throws {
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.juneSolstice.date)

            #expect(month == 6)
        }

        @Test("September equinox is in September")
        func septemberEquinoxMonth() throws {
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let month = calendar.component(.month, from: seasons.septemberEquinox.date)

            #expect(month == 9)
        }

        @Test("December solstice is in December")
        func decemberSolsticeMonth() throws {
            let seasons = try Seasons.forYear(2_025)

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
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.marchEquinox.date)

            // Typically March 19-21
            #expect(day >= 19 && day <= 21)
        }

        @Test("June solstice around expected day")
        func juneSolsticeDay() throws {
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.juneSolstice.date)

            // Typically June 20-22
            #expect(day >= 20 && day <= 22)
        }

        @Test("September equinox around expected day")
        func septemberEquinoxDay() throws {
            let seasons = try Seasons.forYear(2_025)

            let calendar = Calendar(identifier: .gregorian)
            let day = calendar.component(.day, from: seasons.septemberEquinox.date)

            // Typically Sept 22-24
            #expect(day >= 22 && day <= 24)
        }

        @Test("December solstice around expected day")
        func decemberSolsticeDay() throws {
            let seasons = try Seasons.forYear(2_025)

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
            let seasons = try Seasons.forYear(2_025)
            let events = seasons.allEvents

            #expect(events.count == 4)
        }

        @Test("allEvents in chronological order")
        func chronologicalOrder() throws {
            let seasons = try Seasons.forYear(2_025)
            let events = seasons.allEvents

            for i in 0..<(events.count - 1) {
                #expect(events[i].time < events[i + 1].time)
            }
        }

        @Test("allEvents has correct names")
        func correctNames() throws {
            let seasons = try Seasons.forYear(2_025)
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
            let seasons2024 = try Seasons.forYear(2_024)
            let seasons2025 = try Seasons.forYear(2_025)

            #expect(seasons2024.marchEquinox != seasons2025.marchEquinox)
            #expect(seasons2024.juneSolstice != seasons2025.juneSolstice)
        }

        @Test("Year-to-year intervals are approximately 365 days")
        func yearlyInterval() throws {
            let seasons2024 = try Seasons.forYear(2_024)
            let seasons2025 = try Seasons.forYear(2_025)

            let diff = seasons2025.marchEquinox.universalTime - seasons2024.marchEquinox.universalTime

            // Should be about 365-366 days
            #expect(diff > 364 && diff < 367)
        }

        @Test("Historical year", arguments: [1_900, 1_950, 2_000])
        func historicalYears(year: Int) throws {
            let seasons = try Seasons.forYear(year)

            let calendar = Calendar(identifier: .gregorian)
            let marchYear = calendar.component(.year, from: seasons.marchEquinox.date)

            #expect(marchYear == year)
        }

        @Test("Future year")
        func futureYear() throws {
            let seasons = try Seasons.forYear(2_100)

            let calendar = Calendar(identifier: .gregorian)
            let marchYear = calendar.component(.year, from: seasons.marchEquinox.date)

            #expect(marchYear == 2_100)
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformances {
        @Test("Equatable - equal seasons")
        func equatable() throws {
            let s1 = try Seasons.forYear(2_025)
            let s2 = try Seasons.forYear(2_025)

            #expect(s1 == s2)
        }

        @Test("Equatable - different seasons")
        func equatableDifferent() throws {
            let s1 = try Seasons.forYear(2_024)
            let s2 = try Seasons.forYear(2_025)

            #expect(s1 != s2)
        }

        @Test("CustomStringConvertible contains all events")
        func description() throws {
            let seasons = try Seasons.forYear(2_025)
            let desc = seasons.description

            #expect(desc.contains("March Equinox"))
            #expect(desc.contains("June Solstice"))
            #expect(desc.contains("September Equinox"))
            #expect(desc.contains("December Solstice"))
        }

        @Test("CustomStringConvertible contains emoji")
        func descriptionEmoji() throws {
            let seasons = try Seasons.forYear(2_025)
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
            let original = try Seasons.forYear(2_025)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Seasons.self, from: data)

            #expect(original == decoded)
        }

        @Test("Encodes with expected keys")
        func encodesWithKeys() throws {
            let seasons = try Seasons.forYear(2_025)

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

/// Every equinox and solstice from 1900 through 2130 under both Delta T models, checked against independent truth in
/// `Fixtures/SeasonalRoots/seasonal-roots.txt`: crossings of the Sun's apparent ecliptic longitude computed from JPL
/// Horizons vectors and ERFA frame rotations, with no engine code involved. Every event must lie within 60 seconds.
///
/// `Seasons.forYear` evaluates under the process default model. Installing JPL Horizons as the default would shift
/// times built by suites running in parallel (see `DeltaTThreadSafetyTests`), so the JPL Horizons arm runs the same
/// four Sun longitude searches from start times that capture the model; a separate test pins that those searches are
/// exactly what `Seasons.forYear` computes.
@Suite("Seasonal epochs 1900-2130", .timeLimit(.minutes(5)))
struct SeasonalEpochTests {
    struct Event {
        let year: Int
        let kind: String
        let referenceJulianDateTT: Double
    }

    static let kinds = ["marchEquinox", "juneSolstice", "septemberEquinox", "decemberSolstice"]
    static let years = 1_900...2_130
    static let j2000 = 2_451_545.0

    static func loadEvents() throws -> [Event] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SeasonalRoots/seasonal-roots.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { line in
            let fields = line.split(separator: " ")
            try #require(fields.count == 3, "\(line)")
            return Event(
                year: try #require(Int(fields[0])), kind: String(fields[1]),
                referenceJulianDateTT: try #require(Double(String(fields[2])), "\(line)"))
        }
    }

    /// Days from 1970-01-01 to a proleptic Gregorian date.
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        return era * 146_097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear - 719_468
    }

    /// Days since J2000 at 00:00 on a calendar date, on whichever scale the caller reads the date in.
    static func midnight(year: Int, month: Int, day: Int) -> Double {
        Double(days(year: year, month: month, day: day) - days(year: 2_000, month: 1, day: 1)) - 0.5
    }

    /// The searches `Seasons.forYear` performs: the Sun's longitude crossing 0, 90, 180 and 270 degrees within 20 days
    /// after 00:00 UT on the 10th of March, June, September and December.
    static func searchedSeasons(year: Int, model: DeltaTModel) throws -> [AstroTime] {
        try zip([0.0, 90, 180, 270], [3, 6, 9, 12]).map { longitude, month in
            let start = AstroTime(ut: midnight(year: year, month: month, day: 10), deltaTModel: model)
            return try #require(try Sun.searchLongitude(longitude, after: start, limitDays: 20))
        }
    }

    static func seasons(year: Int, model: DeltaTModel) throws -> [AstroTime] {
        switch model {
        case .espenakMeeus: try Seasons.forYear(year).allEvents.map(\.time)
        case .jplHorizons: try searchedSeasons(year: year, model: .jplHorizons)
        }
    }

    @Test("The fixture lists the four events of every year from 1900 through 2130 in order")
    func fixtureCoverage() throws {
        let events = try Self.loadEvents()
        #expect(events.map(\.year) == Self.years.flatMap { Array(repeating: $0, count: 4) })
        #expect(events.map(\.kind) == Array(Array(repeating: Self.kinds, count: Self.years.count).joined()))
    }

    @Test("Seasons.forYear is the four Sun longitude searches")
    func forYearIsTheSearches() throws {
        var differing: [Int] = []
        for year in Self.years {
            let expected = try Self.searchedSeasons(year: year, model: .espenakMeeus)
            let actual = try Seasons.forYear(year).allEvents.map(\.time)
            if actual.map(\.universalTime.bitPattern) != expected.map(\.universalTime.bitPattern)
                || actual.map(\.terrestrialTime.bitPattern) != expected.map(\.terrestrialTime.bitPattern)
            {
                differing.append(year)
            }
        }
        #expect(differing.isEmpty, "\(differing.count) years, first \(differing.prefix(3))")
    }

    @Test("Each year has four ascending events in their months and TT calendar year", arguments: DeltaTModel.allCases)
    func ordering(model: DeltaTModel) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var failures: [String] = []
        for year in Self.years {
            let times = try Self.seasons(year: year, model: model)
            let tt = times.map(\.terrestrialTime)
            let first = Self.midnight(year: year, month: 1, day: 1)
            let next = Self.midnight(year: year + 1, month: 1, day: 1)
            let months = times.map { calendar.component(.month, from: $0.date) }
            if times.count != 4 || tt != tt.sorted() || Set(tt).count != 4
                || !tt.allSatisfy({ first <= $0 && $0 < next })
                || months != [3, 6, 9, 12]
            {
                failures.append("\(year): \(tt), months \(months)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) years, first \(failures.prefix(3))")
    }

    @Test("Events lie within 60 s of the independent Horizons and ERFA reference", arguments: DeltaTModel.allCases)
    func independentReference(model: DeltaTModel) throws {
        let events = try Self.loadEvents()
        var worst = 0.0
        var failures: [String] = []
        for (year, expected) in zip(Self.years, stride(from: 0, to: events.count, by: 4).map { events[$0..<$0 + 4] }) {
            for (time, event) in zip(try Self.seasons(year: year, model: model), expected) {
                let error = abs(time.terrestrialTime - (event.referenceJulianDateTT - Self.j2000)) * 86_400
                worst = max(worst, error)
                if !(error < 60) { failures.append("\(year) \(event.kind): \(error) s") }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) events, first \(failures.prefix(3)); worst \(worst) s")
    }
}
