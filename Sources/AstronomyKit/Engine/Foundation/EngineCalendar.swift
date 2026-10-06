//
//  EngineCalendar.swift
//  AstronomyKit
//
//  Proleptic Gregorian calendar dates as day counts.
//

extension Engine.Time {
    /// Days from 2000-01-01 12:00 to a proleptic Gregorian calendar date and
    /// time of day, on whatever scale the date is in.
    ///
    /// Years are astronomical: year 0 is 1 BCE. Each integer component is
    /// first clamped to the `Int32` range. Components outside their usual
    /// range carry over as calendar arithmetic: month 0 is December of the
    /// previous year, month 15 is March of the next, February 31 is March 2
    /// or 3, and hour 24 is the next midnight.
    ///
    /// The whole-day count uses floor division, so it holds for every
    /// clamped year. `NATIVE_ENGINE.md` records where it differs from
    /// `Astronomy_MakeTime`.
    static func days(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double) -> Double {
        // Shift the year so it starts in March; February's leap day is then
        // the last day of the shifted year.
        let monthIndex = Int64(Int32(clamping: month)) - 3  // March is 0
        let yearCarry = floorDivide(monthIndex, 12)
        let marchYear = Int64(Int32(clamping: year)) + yearCarry
        let marchMonth = monthIndex - 12 * yearCarry  // 0...11
        let era = floorDivide(marchYear, 400)
        let yearOfEra = marchYear - 400 * era  // 0...399
        let dayOfYear = (153 * marchMonth + 2) / 5 + Int64(Int32(clamping: day)) - 1
        let dayOfEra = 365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        // 0000-03-01 is 730,425 days before 2000-01-01.
        let wholeDays = 146_097 * era + dayOfEra - 730_425
        return (Double(wholeDays) - 0.5) + (Double(Int32(clamping: hour)) / 24.0)
            + (Double(Int32(clamping: minute)) / 1440.0) + (second / 86_400.0)
    }

    /// `a / b` rounded toward negative infinity, for positive `b`.
    private static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        return a % b < 0 ? quotient - 1 : quotient
    }
}
