//
//  EngineCalendarTests.swift
//  AstronomyKit
//
//  Proleptic Gregorian day counts against published Julian Day values.
//

import Testing

@testable import AstronomyKit

@Suite("Engine calendar")
struct EngineCalendarTests {
    /// Days since 2000-01-01 12:00 of a date and time of day.
    static func days(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, second: Double = 0
    ) -> Double {
        Engine.Time.days(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    /// Julian Day of J2000, 2000-01-01 12:00.
    static let j2000 = 2_451_545.0

    @Test(
        "Gregorian dates match Meeus, Astronomical Algorithms (2nd ed.), chapter 7",
        arguments: [
            (2000, 1, 1, 12.0, 2_451_545.0),
            (1999, 1, 1, 0, 2_451_179.5),
            (1987, 1, 27, 0, 2_446_822.5),
            (1987, 6, 19, 12, 2_446_966.0),
            (1988, 1, 27, 0, 2_447_187.5),
            (1988, 6, 19, 12, 2_447_332.0),
            (1900, 1, 1, 0, 2_415_020.5),
            (1600, 1, 1, 0, 2_305_447.5),
            (1600, 12, 31, 0, 2_305_812.5),
        ] as [(Int, Int, Int, Double, Double)]
    )
    func meeus(year: Int, month: Int, day: Int, hours: Double, julianDay: Double) {
        let days = Self.days(year, month, day, second: hours * 3_600)
        #expect(days + Self.j2000 == julianDay)
    }

    @Test("Meeus example 7.a: 1957 October 4.81 is JD 2436116.31")
    func sputnik() {
        let days = Self.days(1957, 10, 4, second: 0.81 * 86_400)
        #expect(abs(days + Self.j2000 - 2_436_116.31) < 1e-9)
    }

    @Test("ERFA eraCal2jd reference: 2003-06-01 is MJD 52791")
    func erfa() {
        // t_erfa_c.c, t_cal2jd: djm0 = 2400000.5, djm = 52791.0.
        #expect(Self.days(2003, 6, 1) + Self.j2000 - 2_400_000.5 == 52_791)
    }

    @Test("Julian Day 0 is noon on -4713 November 24 in the proleptic Gregorian calendar")
    func julianDayZero() {
        let days = Self.days(-4713, 11, 24, hour: 12)
        #expect(days + Self.j2000 == 0)
    }

    @Test(
        "Every 400 Gregorian years has 146,097 days",
        arguments: [-2_147_483_648, -1_000_001, -999_999, -4713, -1, 0, 1582, 2000, 999_999, 2_147_483_247]
    )
    func gregorianCycle(year: Int) {
        for (month, day) in [(1, 1), (2, 29), (3, 1), (12, 31)] {
            #expect(Self.days(year + 400, month, day) - Self.days(year, month, day) == 146_097)
        }
    }

    @Test("Leap years follow the Gregorian rule")
    func leapYears() {
        for (year, leap) in [(1900, false), (2000, true), (2024, true), (2100, false), (0, true), (-100, false)] {
            let february = Self.days(year, 3, 1) - Self.days(year, 2, 1)
            #expect(february == (leap ? 29 : 28), "\(year)")
        }
    }

    @Test(
        "Out-of-range components carry over as calendar arithmetic",
        arguments: [
            ((2001, 13, 1), (2002, 1, 1)),
            ((2001, 14, 1), (2002, 2, 1)),
            ((2001, 15, 1), (2002, 3, 1)),
            ((2001, 27, 1), (2003, 3, 1)),
            ((2001, 0, 1), (2000, 12, 1)),
            ((2001, -10, 1), (2000, 2, 1)),
            ((2001, -12, 1), (1999, 12, 1)),
            ((2025, 2, 31), (2025, 3, 3)),
            ((2024, 2, 31), (2024, 3, 2)),
            ((2025, 3, 0), (2025, 2, 28)),
            ((2025, 1, -30), (2024, 12, 1)),
            ((2025, 1, 366), (2026, 1, 1)),
        ] as [((Int, Int, Int), (Int, Int, Int))]
    )
    func normalization(given: (Int, Int, Int), expected: (Int, Int, Int)) {
        #expect(Self.days(given.0, given.1, given.2) == Self.days(expected.0, expected.1, expected.2))
    }

    @Test("Hours, minutes and seconds past a day roll into the next")
    func timeOfDayCarry() {
        let next = Self.days(2025, 1, 2)
        #expect(Self.days(2025, 1, 1, hour: 24) == next)
        #expect(Self.days(2025, 1, 1, minute: 1_440) == next)
        #expect(Self.days(2025, 1, 1, second: 86_400) == next)
        #expect(
            Self.days(2025, 1, 2, hour: -24) == Self.days(2025, 1, 1))
    }

    @Test("Integer components clamp to the Int32 range")
    func int32Clamping() {
        let maxYear = Self.days(Int.max, 1, 1)
        #expect(maxYear == Self.days(Int(Int32.max), 1, 1))
        let minYear = Self.days(Int.min, 1, 1)
        #expect(minYear == Self.days(Int(Int32.min), 1, 1))
        #expect(Self.days(2000, Int.max, 1) == Self.days(2000, Int(Int32.max), 1))
        #expect(Self.days(2000, 1, Int.min) == Self.days(2000, 1, Int(Int32.min)))
        #expect(
            Engine.Time.days(year: 2000, month: 1, day: 1, hour: Int.max, minute: Int.min, second: 0)
                == Engine.Time.days(
                    year: 2000, month: 1, day: 1, hour: Int(Int32.max), minute: Int(Int32.min), second: 0)
        )
        // The extreme corner stays finite.
        let corner = Engine.Time.days(
            year: Int.max, month: Int.min, day: Int.max, hour: Int.min, minute: Int.max, second: 0)
        #expect(corner.isFinite)
    }

    @Test("A nonfinite second passes through")
    func nonfiniteSecond() {
        #expect(Self.days(2000, 1, 1, second: .nan).isNaN)
        #expect(Self.days(2000, 1, 1, second: .infinity) == .infinity)
    }
}
