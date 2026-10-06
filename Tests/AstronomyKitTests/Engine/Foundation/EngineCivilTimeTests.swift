//
//  EngineCivilTimeTests.swift
//  AstronomyKit
//
//  Civil UTC through the engine, against the archived USNO and IERS records.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine civil time")
struct EngineCivilTimeTests {
    /// One line of USNO `tai-utc.dat`: from Julian Day `start`,
    /// TAI − UTC = `offset` + (MJD − `referenceMJD`) × `rate` seconds.
    struct Row: Sendable {
        let start: Double
        let offset: Double
        let referenceMJD: Double
        let rate: Double

        /// TT − UTC in seconds at civil Julian Day `julianDay`.
        func terrestrialMinusUTC(julianDay: Double) -> Double {
            32.184 + offset + (julianDay - 2_400_000.5 - referenceMJD) * rate
        }
    }

    static let timeData = EngineContractTests.root.appendingPathComponent("Scripts/time-data")

    /// The archived USNO table, read here independently of the generator.
    static func usnoRows() throws -> [Row] {
        let text = try String(contentsOf: timeData.appendingPathComponent("tai-utc.dat"), encoding: .utf8)
        let pattern = #/=JD\s+([\d.]+)\s+TAI-UTC=\s+([\d.]+)\s*S\s*\+\s*\(MJD\s*-\s*([\d.]+)\)\s*X\s*([\d.]+)\s*S/#
        return try text.split(separator: "\n").map { line in
            let match = try #require(line.firstMatch(of: pattern), "\(line)")
            return Row(
                start: try #require(Double(match.1)),
                offset: try #require(Double(match.2)),
                referenceMJD: try #require(Double(match.3)),
                rate: try #require(Double(match.4))
            )
        }
    }

    /// The civil time at `utcDays` through the engine.
    static func civil(utcDays: Double, _ model: DeltaTModel = .espenakMeeus) -> (time: Engine.Time, fromTable: Bool) {
        Engine.Time.civil(utcDays: utcDays, deltaTModel: model)
    }

    @Test("Every USNO TAI-UTC row gives TT - UTC at its start and halfway to the next", arguments: DeltaTModel.allCases)
    func usnoTable(model: DeltaTModel) throws {
        let rows = try Self.usnoRows()
        #expect(rows.count == 41)
        for (index, row) in rows.enumerated() {
            let next = index + 1 < rows.count ? rows[index + 1].start : row.start + 1_000
            for julianDay in [row.start, (row.start + next) / 2] {
                let (time, fromTable) = Self.civil(utcDays: julianDay - EngineCalendarTests.j2000, model)
                #expect(fromTable)
                #expect(time.deltaTModel == model)
                let seconds = (time.tt - (julianDay - EngineCalendarTests.j2000)) * 86_400
                // Differences of day counts near 1e4 lose about 2e-7 s.
                #expect(abs(seconds - row.terrestrialMinusUTC(julianDay: julianDay)) < 1e-6, "JD \(julianDay)")
                #expect(abs(time.utcDays - (julianDay - EngineCalendarTests.j2000)) * 86_400 < 1e-6, "JD \(julianDay)")
            }
        }
    }

    @Test("IERS Bulletin C 72: UTC - TAI = -37 s from 2017 January 1 until further notice")
    func bulletinC() throws {
        let text = try String(contentsOf: Self.timeData.appendingPathComponent("bulletin-c.txt"), encoding: .utf8)
        let match = try #require(
            text.firstMatch(of: /from 2017 January 1, 0h UTC, until further notice : UTC-TAI = (-?\d+) s/))
        let taiMinusUTC = -(try #require(Double(match.1)))
        #expect(taiMinusUTC == 37)
        for (year, month) in [(2017, 1), (2026, 10), (2100, 1)] {
            let utc = EngineCalendarTests.days(year, month, 1)
            let (time, fromTable) = Self.civil(utcDays: utc)
            #expect(fromTable)
            #expect(abs((time.tt - utc) * 86_400 - (32.184 + taiMinusUTC)) < 1e-6)
        }
    }

    @Test("Published ERFA UTC to TAI reference plus the TT offset")
    func erfaReference() {
        // ERFA t_utctai: 2453750.5 + 0.892100694 UTC -> 2453750.5 + 0.8924826384444444444 TAI.
        let utc = 2_205.5 + 0.892100694
        let expectedTT = 2_205.5 + 0.8924826384444444444 + 32.184 / 86_400
        let (time, _) = Self.civil(utcDays: utc)
        #expect(abs(time.tt - expectedTT) < 1e-12)
        #expect(abs(time.utcDays - utc) < 1e-11)
    }

    @Test("The positive leap second at the end of 2016 maps to the following midnight")
    func positiveLeapSecond() {
        let midnight = EngineCalendarTests.days(2017, 1, 1)
        let after = Self.civil(utcDays: midnight).time
        let before = Self.civil(utcDays: midnight - 1 / 86_400.0).time
        // 23:59:59 to 00:00:00 spans the inserted second: 2 s of TT.
        #expect(abs((after.tt - before.tt) * 86_400 - 2) < 1e-6)
        let inLeap = Engine.Time(tt: after.tt - 0.5 / 86_400, deltaTModel: .espenakMeeus)
        #expect(inLeap.utcDays == midnight)
    }

    @Test("The negative step of 1961 August 1 repeats civil times; the later occurrence wins")
    func negativeHistoricalStep() throws {
        let rows = try Self.usnoRows()
        // TAI - UTC dropped by 0.05 s at 1961 Aug 1.
        let step = rows[1].start - EngineCalendarTests.j2000
        let drop =
            rows[0].terrestrialMinusUTC(julianDay: rows[1].start)
            - rows[1].terrestrialMinusUTC(julianDay: rows[1].start)
        #expect(abs(drop - 0.05) < 1e-9)
        let later = Self.civil(utcDays: step + 0.025 / 86_400).time
        let earlier = Self.civil(utcDays: step - 0.025 / 86_400).time
        #expect(abs(later.tt - earlier.tt) * 86_400 < 1e-6)
        #expect(abs(earlier.utcDays - later.utcDays) * 86_400 < 1e-6)
        #expect(abs(earlier.utcDays - (step + 0.025 / 86_400)) * 86_400 < 1e-6)
    }

    @Test("Before 1961 the civil count is taken as UT1", arguments: DeltaTModel.allCases)
    func preTable(model: DeltaTModel) {
        for utc in [
            EngineCalendarTests.days(1900, 1, 1), (-14_244.5).nextDown, -1e6,
        ] {
            let (time, fromTable) = Engine.Time.civil(utcDays: utc, deltaTModel: model)
            #expect(!fromTable)
            #expect(time.ut == utc)
            #expect(time.tt == Engine.Time(ut: utc, deltaTModel: model).tt)
            #expect(time.utcDays == utc)
        }
    }

    @Test("A civil count that is not finite gives an invalid time", arguments: [Double.nan, .infinity, -.infinity])
    func nonfinite(utc: Double) {
        let (time, fromTable) = Self.civil(utcDays: utc)
        #expect(!fromTable)
        #expect(!time.isValid)
        #expect(time.utcDays.isNaN)
    }

    @Test("Civil TT stays invertible across the 1986 Delta T jump")
    func civilAcrossDeltaTGaps() throws {
        // A civil date whose table TT falls in the middle of the 1986 gap. The
        // inverse returns the first UT after the jump. The 1961 gap's TT comes
        // from a UTC just before the table's first row, 1961-01-01, so only
        // 1986 has a civil date in a gap.
        let (before, after) = EngineDeltaTTests.straddle(1986)
        let gap = (
            Engine.Time(ut: before, deltaTModel: .espenakMeeus).tt,
            Engine.Time(ut: after, deltaTModel: .espenakMeeus).tt
        )
        let middle = (gap.0 + gap.1) / 2
        var utc = middle
        for _ in 0..<4 {
            utc -= try #require(CivilTime.terrestrialTime(utcDays: utc)) - middle
        }
        let tt = try #require(CivilTime.terrestrialTime(utcDays: utc))
        try #require(gap.0 < tt && tt < gap.1)
        let time = Self.civil(utcDays: utc).time
        #expect(time.isValid)
        #expect(time.tt == tt)
        #expect(time.ut == after)
        #expect(abs(time.utcDays - utc) * 86_400 < 2e-6)
    }
}
