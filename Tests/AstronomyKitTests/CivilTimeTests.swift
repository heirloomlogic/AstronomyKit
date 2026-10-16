import Foundation
import Testing

@testable import AstronomyKit

@Suite("Civil UTC, TT and modeled UT1")
struct CivilTimeTests {
    @Test("Known atomic offsets, including pre-1972 rate segments")
    func knownOffsets() {
        let values: [(Double, Double)] = [
            (-14_244.5, 33.606818),  // 1961-01-01: 32.184 + 1.422818
            (-14_243.5, 33.608114),  // one civil day later: +0.001296 s
            (-10_227.5, 42.184),  // 1972-01-01: 32.184 + 10
            (0, 64.184),  // 2000-01-01 noon: 32.184 + 32
            (6_209.5, 69.184),  // 2017-01-01: 32.184 + 37
            (36_524.5, 69.184),  // 2100-01-01: hold last announced offset
        ]
        for (utc, offset) in values {
            let date = Date(timeIntervalSince1970: utc * 86_400 + 946_728_000)
            let time = AstroTime(date)
            #expect(abs((time.terrestrialTime - utc) * 86_400 - offset) < 0.000002)
            #expect(abs(time.date.timeIntervalSince(date)) < 0.000002)
        }
    }

    @Test("Published ERFA UTC to TAI reference plus TT offset")
    func erfaReference() {
        // ERFA t_utctai: 2453750.5 + 0.892100694 UTC ->
        // 2453750.5 + 0.8924826384444444444 TAI.
        let utc = 2_205.5 + 0.892100694
        let expectedTT = 2_205.5 + 0.8924826384444444444 + 32.184 / 86_400
        let actual = CivilTime.terrestrialTime(utcDays: utc)!
        #expect(abs(actual - expectedTT) < 1e-12)
    }

    @Test("All announced transitions select the effective offset")
    func boundaries() {
        for segment in CivilTime.segments {
            let date = Date(timeIntervalSince1970: segment.start * 86_400 + 946_728_000)
            let time = AstroTime(date)
            #expect(abs(time.terrestrialTime - segment.terrestrialStart) < 1e-11)
            #expect(abs(time.date.timeIntervalSince(date)) < 0.000002)
            // The day after each change avoids gaps and overlaps; fractions survive.
            let later = date.addingTimeInterval(86_400.123456)
            #expect(abs(AstroTime(later).date.timeIntervalSince(later)) < 0.000002)
        }
    }

    @Test("Positive leap seconds clamp to the next representable civil date")
    func leapGap() {
        let midnight = AstroTime(year: 2_017, month: 1, day: 1)
        let before = AstroTime(year: 2_016, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        #expect(abs((midnight.terrestrialTime - before.terrestrialTime) * 86_400 - 2) < 0.000002)
        let leap = AstroTime(tt: midnight.terrestrialTime - 0.5 / 86_400)
        #expect(abs(leap.date.timeIntervalSince(midnight.date)) < 0.000002)
        #expect(AstroTime(year: 2_016, month: 12, day: 31, hour: 23, minute: 59, second: 60).date == midnight.date)
    }

    @Test("Negative historical UTC steps choose the later civil occurrence")
    func historicalOverlap() {
        let later = AstroTime(year: 1_961, month: 8, day: 1, second: 0.025)
        let earlier = AstroTime(year: 1_961, month: 7, day: 31, hour: 23, minute: 59, second: 59.975)
        #expect(abs((later.terrestrialTime - earlier.terrestrialTime) * 86_400) < 0.000002)
        #expect(abs(earlier.date.timeIntervalSince(later.date)) < 0.000002)
    }

    @Test("Pre-table civil dates retain the historical UT1 convention")
    func historicalProxy() {
        let civil = AstroTime(year: 1_900, month: 1, day: 1)
        let native = AstroTime(ut: -36_524.5)
        #expect(civil == native)
        #expect(civil.date == native.date)
    }

    @Test("UT1 day arithmetic and numeric archives retain their semantics")
    func arithmeticAndArchives() throws {
        let time = AstroTime(year: 2_016, month: 12, day: 31)
        let tomorrow = time.addingDays(1)
        #expect(tomorrow.universalTime - time.universalTime == 1)
        let restored = try JSONDecoder().decode(AstroTime.self, from: JSONEncoder().encode(time))
        #expect(restored == time)
        #expect(restored.hashValue == time.hashValue)
        #expect(abs(restored.date.timeIntervalSince(time.date)) < 0.000002)
    }

    @Test("Search results use the same civil inverse")
    func returnedTimes() throws {
        let start = AstroTime(year: 2_041, month: 1, day: 1)
        let event = try #require(try Sun.searchLongitude(315, after: start, limitDays: 60))
        let roundTrip = AstroTime(event.date)
        #expect(abs(roundTrip.terrestrialTime - event.terrestrialTime) * 86_400 < 0.000002)
        #expect(abs(try Sun.position(at: roundTrip).longitude - 315) < 0.0001)
    }

    @Test("TT inverse terminates on invalid and extreme inputs")
    func boundedInverse() {
        for value in [Double.nan, .infinity, -.infinity] {
            let time = AstroTime(tt: value)
            #expect(time.universalTime.isNaN)
            #expect(time.terrestrialTime.isNaN)
        }

        // A finite extreme may either converge (for example, with JPL's
        // clamped Delta T) or be rejected by the selected model.
        let finiteExtreme = AstroTime(tt: .greatestFiniteMagnitude)
        #expect(finiteExtreme.universalTime.isFinite == finiteExtreme.terrestrialTime.isFinite)
        if finiteExtreme.universalTime.isFinite {
            #expect(finiteExtreme.terrestrialTime == .greatestFiniteMagnitude)
        } else {
            #expect(finiteExtreme.universalTime.isNaN)
            #expect(finiteExtreme.terrestrialTime.isNaN)
        }

        let extreme = AstroTime(year: Int.max, month: Int.min, day: 1)
        #expect(extreme.universalTime.isFinite)
    }

    @Test("Civil TT remains invertible across positive Delta T model jumps")
    func deltaTJumpGaps() throws {
        for unixSeconds in [506_140_670.85679626, -282_782_416.0919621] {
            let date = Date(timeIntervalSince1970: unixSeconds)
            let utcDays = (unixSeconds - 946_728_000) / 86_400
            let requestedTT = try #require(CivilTime.terrestrialTime(utcDays: utcDays))
            let inverse = AstroTime(tt: requestedTT)

            #expect(inverse.universalTime.isFinite)
            #expect(inverse.terrestrialTime == requestedTT)
            #expect(AstroTime(date).terrestrialTime == requestedTT)
            #expect(abs(inverse.date.timeIntervalSince(date)) < 0.000002)
        }
    }

    /// The Espenak-Meeus pieces meet at 1 January 0:00 UT of their years; the
    /// engine's jump table (`EngineTimeConversionTests.jumps`) straddles each one.
    private static func jump(at year: Double) throws -> EngineTimeConversionTests.Jump {
        try #require(EngineTimeConversionTests.jumps.first { $0.model == .espenakMeeus && $0.boundary == year })
    }

    @Test("TT inverse defines both signs of Delta T discontinuity")
    func deltaTJumpBoundaries() throws {
        // The 1986 positive jump has no UT solution for TT values in its gap.
        // Such values clamp to the first representable UT after the jump.
        let positive = try Self.jump(at: 1_986)
        #expect(positive.isGap)
        let gapTT = positive.beforeTT + (positive.afterTT - positive.beforeTT) / 2
        let clamped = AstroTime(tt: gapTT, deltaTModel: .espenakMeeus)
        #expect(clamped.terrestrialTime == gapTT)
        #expect(clamped.universalTime == positive.afterUT)
        let restored = try JSONDecoder().decode(
            AstroTime.self,
            from: JSONEncoder().encode(clamped)
        )
        #expect(restored.universalTime == clamped.universalTime)
        #expect(restored.terrestrialTime != clamped.terrestrialTime)

        // At 2005 the positive Delta T seed starts after the negative jump,
        // so fixed-point iteration reaches the later solution first.
        let negative = try Self.jump(at: 2_005)
        #expect(negative.isOverlap)
        let overlapTT = negative.afterTT + (negative.beforeTT - negative.afterTT) / 2
        let later = AstroTime(tt: overlapTT, deltaTModel: .espenakMeeus)
        let modeledTT =
            later.universalTime
            + AstronomyConfig.deltaTEspenakMeeus(universalTime: later.universalTime) / 86_400
        #expect(later.terrestrialTime == overlapTT)
        #expect(later.universalTime >= negative.afterUT)
        #expect(abs(modeledTT - overlapTT) <= Engine.Time.inverseTolerance(tt: overlapTT))
    }

    @Test("Negative-Delta-T overlap follows the TT-seeded inverse")
    func negativeDeltaTOverlap() throws {
        // 1900 is the only overlap where Delta T is negative: the initial
        // ut = tt estimate lies before the jump, so iteration reaches the
        // earlier solution first.
        let jump = try Self.jump(at: 1_900)
        #expect(jump.isOverlap)
        #expect(AstronomyConfig.deltaTEspenakMeeus(universalTime: jump.afterUT) < 0)
        let requestedTT = jump.afterTT + (jump.beforeTT - jump.afterTT) / 2
        let overlap = AstroTime(tt: requestedTT, deltaTModel: .espenakMeeus)
        #expect(overlap.terrestrialTime == requestedTT)
        #expect(overlap.universalTime <= jump.beforeUT)
        let modeledTT =
            overlap.universalTime
            + AstronomyConfig.deltaTEspenakMeeus(universalTime: overlap.universalTime) / 86_400
        #expect(abs(modeledTT - requestedTT) <= Engine.Time.inverseTolerance(tt: requestedTT))
    }
}
