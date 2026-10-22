import Testing

@testable import AstronomyKit

/// Checks the observed Delta T model against IERS values and checks its joins
/// to Espenak-Meeus before the table and to the long-term parabola after it.
@Suite("Observed Delta T")
struct DeltaTObservedTests {
    /// The year of the table's last entry, where the extrapolation starts.
    static let tableEnd = 2027.0

    /// UT days since J2000 at Julian epoch `year`.
    static func ut(year: Double) -> Double { (year - 2000) * 365.25 }

    static func observed(_ ut: Double) -> Double { AstronomyConfig.deltaTObserved(universalTime: ut) }

    /// The long-term parabola, -20 + 32 u² seconds with u in centuries from 1820.
    static func parabola(year: Double) -> Double {
        let u = (year - 1820) / 100
        return -20 + 32 * u * u
    }

    /// IERS EOP 20 C04 (and, for 2026-07-01, Bulletin A) Delta T at 0h UTC,
    /// as (UT days since J2000, seconds). All fall between table entries.
    static let iers: [(Double, Double)] = [
        (-8950.5, 45.9834),  // 1975-07-01
        (-3471.5, 57.2226),  // 1990-07-01
        (2007.5, 64.7994),  // 2005-07-01
        (6208.5, 68.5918),  // 2016-12-31
        (9312.5, 69.1406),  // 2025-07-01
        (9677.5, 69.1695),  // 2026-07-01
    ]

    @Test("Within 0.1 s of IERS values", arguments: iers)
    func matchesIers(ut: Double, deltaT: Double) {
        #expect(abs(Self.observed(ut) - deltaT) < 0.1)
    }

    @Test("Is the default model")
    func isDefault() {
        let time = AstroTime(year: 2_025, month: 7, day: 1)
        let deltaT = (time.terrestrialTime - time.universalTime) * 86_400
        #expect(abs(deltaT - 69.1406) < 0.1)
    }

    /// Also guards the hard-coded 1962 join offset, which must change if the
    /// table's first entry ever does.
    @Test("Continuous at each join", arguments: [1952.0, 1962.0, tableEnd, 2150.0])
    func continuousAtJoin(year: Double) {
        let ut = Self.ut(year: year)
        let step = 1e-3  // days
        let before = Self.observed(ut - step)
        let at = Self.observed(ut)
        let after = Self.observed(ut + step)
        #expect(abs(at - before) < 1e-4)
        #expect(abs(after - at) < 1e-4)
    }

    @Test("Rate is continuous where the extrapolation starts and ends", arguments: [tableEnd, 2150.0])
    func rateContinuousAtExtrapolation(year: Double) {
        let ut = Self.ut(year: year)
        let step = 1.0  // days
        let rateBefore = Self.observed(ut) - Self.observed(ut - step)
        let rateAfter = Self.observed(ut + step) - Self.observed(ut)
        #expect(abs(rateAfter - rateBefore) < 1e-5)
    }

    @Test("Is Espenak-Meeus before 1952", arguments: [1951.9, 1900.0, 1000.0, -1000.0])
    func espenakMeeusBefore1952(year: Double) {
        let ut = Self.ut(year: year)
        #expect(Self.observed(ut) == AstronomyConfig.deltaTEspenakMeeus(universalTime: ut))
    }

    @Test("Is the long-term parabola from 2150", arguments: [2150.0, 2500.0, 5000.0])
    func parabolaFrom2150(year: Double) {
        let expected = Self.parabola(year: year)
        #expect(abs(Self.observed(Self.ut(year: year)) - expected) <= 1e-9 * expected)
    }

    @Test("Stays between the extrapolated line and the parabola until 2150")
    func boundedExtrapolation() {
        let last = Self.observed(Self.ut(year: Self.tableEnd))
        let rate = last - Self.observed(Self.ut(year: Self.tableEnd - 1))
        for year in stride(from: Self.tableEnd + 1, to: 2150.0, by: 1.0) {
            let line = last + (year - Self.tableEnd) * rate
            let parabola = Self.parabola(year: year)
            let deltaT = Self.observed(Self.ut(year: year))
            #expect(deltaT >= min(line, parabola) && deltaT <= max(line, parabola))
        }
    }

    @Test("Non-finite input")
    func nonFinite() {
        #expect(Self.observed(.nan).isNaN)
        #expect(Self.observed(.infinity) == .infinity)
        #expect(Self.observed(-.infinity) == .infinity)
    }
}
