//
//  DeltaTIersObservedTests.swift
//  AstronomyKit
//
//  Checks the default observed Delta T model against the raw IERS records it
//  was generated from, parsed here independently of the generator, and runs
//  rise and set through the civil path against JPL Horizons.
//

import Foundation
import Testing

@testable import AstronomyKit

/// Raw IERS rows parsed from the pinned files in `Scripts/deltat-data`.
private enum IERSRecords {
    struct Row {
        /// Modified Julian Date of the UTC sample.
        let mjd: Double
        /// UT1 − UTC in seconds.
        let ut1MinusUTC: Double
    }

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/deltat-data")

    static func lines(_ name: String) throws -> [Substring] {
        let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    /// IERS EOP 20 C04: whitespace-separated, MJD in field 5, UT1 − UTC in field 8.
    static func c04(_ name: String) throws -> [Row] {
        try lines(name).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 21, let mjd = Double(fields[4]), let dut = Double(fields[7]) else {
                throw ParseError.malformed(String(line))
            }
            return Row(mjd: mjd, ut1MinusUTC: dut)
        }
    }

    /// IERS Bulletin A finals2000A: fixed columns 8–15 (MJD), 58 (flag), 59–68 (UT1 − UTC).
    static func finals() throws -> [(row: Row, predicted: Bool)] {
        try lines("finals2000A.all").compactMap { line in
            let characters = Array(line.utf8)
            guard characters.count >= 68, characters[57] != UInt8(ascii: " ") else { return nil }
            func field(_ range: Range<Int>) -> Double? {
                Double(String(decoding: characters[range], as: UTF8.self).trimmingCharacters(in: .whitespaces))
            }
            guard let mjd = field(7..<15), let dut = field(58..<68) else {
                throw ParseError.malformed(String(line))
            }
            return (Row(mjd: mjd, ut1MinusUTC: dut), characters[57] == UInt8(ascii: "P"))
        }
    }

    enum ParseError: Error {
        case malformed(String)
    }
}

@Suite("Observed Delta T (IERS)", .serialized)
struct DeltaTIersObservedTests {
    /// Days from the Unix epoch to J2000 noon, as `AstroTime` uses.
    static let j2000UnixDays = 946_728_000.0 / 86_400

    /// UT1 − UTC in seconds that the civil path assigns to a UTC instant.
    static func civilUT1MinusUTC(mjd: Double) -> Double {
        let utcDays = mjd - 51_544.5
        let time = AstroTime(Date(timeIntervalSince1970: (utcDays + j2000UnixDays) * 86_400))
        return (time.universalTime - utcDays) * 86_400
    }

    /// The UT1 day coordinate of a Julian epoch year.
    static func ut(year: Double) -> Double { (year - 2_000) * 365.25 }

    // MARK: - Civil path against the raw IERS rows

    @Test("Civil UTC at every daily C04 and Bulletin A row reproduces IERS UT1 − UTC")
    func civilPathMatchesDailyRows() throws {
        let c04 = try IERSRecords.c04("eopc04.1962-now")
        let lastC04 = try #require(c04.last).mjd
        let bulletinA = try IERSRecords.finals().map(\.row).filter { $0.mjd > lastC04 }
        let rows = c04 + bulletinA
        #expect(rows.count > 24_000)
        #expect(rows.first?.mjd == 37_665)

        // At a row's own epoch interpolation contributes nothing; what is left
        // is the precision of a UT1 day coordinate near 1e4 days (~1e-7 s)
        // and the TT inverse's 1e-12-day tolerance.
        var worst = 0.0
        for row in rows {
            worst = max(worst, abs(Self.civilUT1MinusUTC(mjd: row.mjd) - row.ut1MinusUTC))
        }
        #expect(worst < 1e-6, "Largest departure \(worst) s")
    }

    @Test("Civil UTC at 12h matches the 12h C04 samples within the stated interpolation error")
    func civilPathMatchesMidday() throws {
        let midday = try IERSRecords.c04("eopc04.12h.1984-now")
        #expect(midday.count > 15_000)
        var worst = 0.0
        for row in midday {
            worst = max(worst, abs(Self.civilUT1MinusUTC(mjd: row.mjd) - row.ut1MinusUTC))
        }
        // The documented interpolation error: at most 0.16 ms against these samples.
        #expect(worst <= 0.000_16, "Largest departure \(worst) s")
    }

    // MARK: - Joins

    @Test("Bulletin A agrees with C04 over the year before the join")
    func bulletinAMeetsC04() throws {
        let c04 = try IERSRecords.c04("eopc04.1962-now")
        let lastC04 = try #require(c04.last).mjd
        let byMJD = Dictionary(uniqueKeysWithValues: c04.map { ($0.mjd, $0.ut1MinusUTC) })
        let overlap = try IERSRecords.finals().map(\.row).filter { $0.mjd > lastC04 - 365 && $0.mjd <= lastC04 }
        #expect(overlap.count == 365)
        for row in overlap {
            let c04Value = try #require(byMJD[row.mjd])
            #expect(abs(row.ut1MinusUTC - c04Value) < 0.000_1, "MJD \(row.mjd)")
        }
    }

    @Test("Every join is continuous", arguments: ["-720 spline start", "1962 IERS start", "last prediction"])
    func joinsAreContinuous(join: String) throws {
        let ut: Double
        switch join {
        case "-720 spline start":
            ut = Self.ut(year: -720)
        case "1962 IERS start":
            // The first C04 row: 1962-01-01 0h UTC plus its UT1 − UTC.
            ut = (37_665 - 51_544.5) + 0.032_633_8 / 86_400
        default:
            let last = try #require(try IERSRecords.finals().last(where: \.predicted)).row
            ut = (last.mjd - 51_544.5) + last.ut1MinusUTC / 86_400
        }
        let before = AstronomyConfig.deltaTIersObserved(universalTime: ut.nextDown)
        let after = AstronomyConfig.deltaTIersObserved(universalTime: ut.nextUp)
        let regimes = [ut - 1e-6, ut + 1e-6].map { AstronomyConfig.deltaTIersObservedRegime(universalTime: $0) }
        #expect(abs(after - before) < 1e-9, "\(join): \(before) → \(after)")
        #expect(regimes[0] != regimes[1], "\(join) separates two regimes")
    }

    @Test("Table S15 segments meet within its published 1 ms precision")
    func splineKnotsMeet() {
        // Knots of Table S15 v2020 from -720 through 1959.
        let knots: [Double] = [
            -100, 400, 1_000, 1_150, 1_300, 1_500, 1_600, 1_650, 1_720, 1_800, 1_810, 1_820, 1_830,
            1_840, 1_850, 1_855, 1_860, 1_865, 1_870, 1_875, 1_880, 1_885, 1_890, 1_895, 1_900,
            1_905, 1_910, 1_915, 1_920, 1_925, 1_930, 1_935, 1_940, 1_945, 1_950, 1_953, 1_956, 1_959,
        ]
        for knot in knots {
            let ut = Self.ut(year: knot)
            let step =
                AstronomyConfig.deltaTIersObserved(universalTime: ut)
                - AstronomyConfig.deltaTIersObserved(universalTime: ut.nextDown)
            #expect(abs(step) <= 0.001_000_1, "Knot \(knot): \(step) s")
        }
    }

    // MARK: - Historical and extrapolated values against HMNAO's tables

    /// Delta T tabulated by HM Nautical Almanac Office (https://astro.ukho.gov.uk/nao/lvm/,
    /// archived 2021-06-18), with the rounding step of each table.
    @Test(
        "Historical spline reproduces HMNAO's tabulated Delta T",
        arguments: [
            (-720.0, 20_370.0, 10.0), (-500, 16_940, 10), (0, 10_440, 10), (500, 5_590, 10),
            (1_000, 1_650, 10), (1_500, 290, 10), (1_600, 109, 1), (1_700, 14, 1), (1_750, 17, 1),
            (1_800, 18.4, 0.1), (1_850, 9.3, 0.1), (1_875, -1.13, 0.01), (1_900, -1.98, 0.01),
            (1_925, 23.79, 0.01), (1_950, 28.93, 0.01),
        ] as [(Double, Double, Double)]
    )
    func historicalMatchesHMNAO(year: Double, deltaT: Double, rounding: Double) {
        let ut = Self.ut(year: year)
        #expect(AstronomyConfig.deltaTIersObservedRegime(universalTime: ut) == .historical)
        let value = AstronomyConfig.deltaTIersObserved(universalTime: ut)
        #expect(abs(value - deltaT) <= rounding / 2 + 1e-9, "\(year): \(value) s")
    }

    @Test(
        "Extrapolation agrees with HMNAO's extrapolated Delta T within its error estimate",
        arguments: [
            (-2_000.0, 46_080.0, 1_080.0), (-1_000, 25_560, 720),  // 12.8 ± 0.3 h, 7.1 ± 0.2 h
            (2_050, 70, 6), (2_100, 80, 10), (2_200, 160, 20), (2_300, 330, 30), (2_500, 1_000, 100),
        ] as [(Double, Double, Double)]
    )
    func extrapolationMatchesHMNAO(year: Double, deltaT: Double, epsilon: Double) {
        let ut = Self.ut(year: year)
        let value = AstronomyConfig.deltaTIersObserved(universalTime: ut)
        #expect(abs(value - deltaT) <= epsilon, "\(year): \(value) s")
        #expect(AstronomyConfig.deltaTIersObservedUncertainty(universalTime: ut) == epsilon)
    }

    // MARK: - Regimes and uncertainty

    @Test(
        "Regime boundaries",
        arguments: [
            (-1_000.0, DeltaTRegime.extrapolatedPast), (1_000, .historical), (1_961.99, .historical),
            (1_962.01, .observed), (2_026.78, .observed), (2_026.80, .predicted), (2_027.7, .predicted),
            (2_028, .extrapolatedFuture), (3_000, .extrapolatedFuture),
        ] as [(Double, DeltaTRegime)]
    )
    func regimes(year: Double, regime: DeltaTRegime) {
        #expect(AstronomyConfig.deltaTIersObservedRegime(universalTime: Self.ut(year: year)) == regime)
    }

    @Test("Non-finite UT has no regime and no finite value")
    func nonFinite() {
        #expect(AstronomyConfig.deltaTIersObservedRegime(universalTime: .nan) == nil)
        #expect(AstronomyConfig.deltaTIersObserved(universalTime: .nan).isNaN)
        #expect(AstronomyConfig.deltaTIersObservedUncertainty(universalTime: .nan).isNaN)
        #expect(AstronomyConfig.deltaTIersObservedRegime(universalTime: .infinity) == .extrapolatedFuture)
        #expect(AstronomyConfig.deltaTIersObservedRegime(universalTime: -.infinity) == .extrapolatedPast)
        #expect(AstronomyConfig.deltaTIersObserved(universalTime: .infinity) == .infinity)
        #expect(AstronomyConfig.deltaTIersObserved(universalTime: -.infinity) == .infinity)
    }

    @Test("Uncertainty takes each regime's stated figure")
    func statedUncertainty() throws {
        // C04's formal error for 1962-01-01, at the row's own epoch.
        let first = (37_665 - 51_544.5) + 0.032_633_8 / 86_400
        #expect(abs(AstronomyConfig.deltaTIersObservedUncertainty(universalTime: first) - 0.002) < 1e-12)

        // Midday adds at most the 0.16 ms interpolation allowance.
        let midday = first + 0.5
        let middayUncertainty = AstronomyConfig.deltaTIersObservedUncertainty(universalTime: midday)
        #expect(middayUncertainty > 0.002 && middayUncertainty <= 0.002_16 + 1e-12)

        // Bulletin A's stated error for its last prediction.
        let last = try #require(try IERSRecords.finals().last(where: \.predicted)).row
        let lastUT = (last.mjd - 51_544.5) + last.ut1MinusUTC / 86_400
        #expect(abs(AstronomyConfig.deltaTIersObservedUncertainty(universalTime: lastUT) - 0.024_472_3) < 1e-9)

        // HMNAO's estimate, floored by the spline's 0.68 s departure from C04.
        #expect(AstronomyConfig.deltaTIersObservedUncertainty(universalTime: Self.ut(year: 1_000)) == 15)
        let modern = AstronomyConfig.deltaTIersObservedUncertainty(universalTime: Self.ut(year: 1_900))
        #expect(modern > 0.67 && modern < 0.68)

        // Beyond HMNAO's last estimate the uncertainty keeps growing.
        let far = [2_500.0, 3_000, 5_000].map {
            AstronomyConfig.deltaTIersObservedUncertainty(universalTime: Self.ut(year: $0))
        }
        #expect(far[0] == 100 && far[0] < far[1] && far[1] < far[2])
    }

    // MARK: - Engine wiring

    @Test("The observed model is the process default")
    func isDefault() {
        for year in [-1_000.0, 1_900, 1_990, 2_026.79, 2_027.5, 2_126] {
            let ut = Self.ut(year: year)
            let expected = ut + AstronomyConfig.deltaTIersObserved(universalTime: ut) / 86_400
            #expect(AstroTime(ut: ut).terrestrialTime == expected, "\(year)")
        }
    }

    @Test("The TT inverse converges in every regime")
    func inverseConverges() {
        var ut = Self.ut(year: -3_000)
        while ut < Self.ut(year: 3_000) {
            let time = AstroTime(ut: ut)
            let inverse = AstroTime(tt: time.terrestrialTime)
            #expect(abs(inverse.universalTime - ut) * 86_400 < 1e-5, "UT \(ut)")
            ut += 3_653.3
        }
    }

    // MARK: - Rise and set through the civil path

    /// JPL Horizons, retrieved 2026-10-17 (DE441, EOP file eop.261016.p270112): the Sun's
    /// airless apparent elevation and angular diameter from 35.5951° N, 82.5515° W, 0 m, at
    /// 1 s steps. Query: COMMAND='10', CENTER='coord@399', COORD_TYPE='GEODETIC',
    /// SITE_COORD='-82.5515,35.5951,0', QUANTITIES='4,13', APPARENT='AIRLESS',
    /// TIME_TYPE='UT' (UTC), START_TIME 2025-06-21 10:10 and 2025-06-22 00:44, 720 steps over
    /// 12 minutes. The instants below are where the centre's elevation crosses −(34′ +
    /// semidiameter), the rise and set definition the engine uses, interpolated linearly
    /// between the 1 s samples (the Sun's elevation rate there is 0.002935° s⁻¹). The USNO
    /// Astronomical Applications rise and set times for the same place and day, 10:15 and
    /// 00:49 UTC, agree to their published minute.
    static let horizonsSunrise = "2025-06-21T10:15:03.390Z"
    static let horizonsSunset = "2025-06-22T00:49:09.668Z"

    @Test("Civil sunrise and sunset match JPL Horizons within 0.25 s")
    func riseSetMatchHorizons() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let observer = Observer(latitude: 35.5951, longitude: -82.5515, height: 0)
        let start = AstroTime(try #require(formatter.date(from: "2025-06-21T04:00:00.000Z")))
        let sunriseReference = try #require(formatter.date(from: Self.horizonsSunrise))
        let sunsetReference = try #require(formatter.date(from: Self.horizonsSunset))

        func residuals() throws -> (rise: Double, set: Double) {
            let rise = try #require(try CelestialBody.sun.riseTime(after: start, from: observer))
            let set = try #require(try CelestialBody.sun.setTime(after: rise, from: observer))
            return (
                rise.date.timeIntervalSince(sunriseReference),
                set.date.timeIntervalSince(sunsetReference)
            )
        }

        let observed = try residuals()
        #expect(abs(observed.rise) < 0.25, "Sunrise off by \(observed.rise) s")
        #expect(abs(observed.set) < 0.25, "Sunset off by \(observed.set) s")

        // The check resolves Delta T: Espenak-Meeus is 5.6 s off observed UT1 here.
        AstronomyConfig.setDeltaTModel(.espenakMeeus)
        defer { AstronomyConfig.setDeltaTModel(.iersObserved) }
        let modeled = try residuals()
        #expect(modeled.rise > 5 && modeled.set > 5)
    }
}
