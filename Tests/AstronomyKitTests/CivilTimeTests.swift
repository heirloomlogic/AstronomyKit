import CLibAstronomy
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

    @Test("C-returned times use the same civil inverse")
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

    @Test("TT inverse defines both signs of Delta T discontinuity")
    func deltaTJumpBoundaries() throws {
        AstronomyConfig.setDeltaTModel(.espenakMeeus)
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }

        func surroundingTimes(year: Double) -> (beforeUT: Double, beforeTT: Double, afterUT: Double, afterTT: Double) {
            let boundary = 14 + (year - 2_000) * 365.24217
            // Stay close to the jump while clearing cancellation in the
            // decimal-year conversion used by the piecewise model.
            let beforeUT = boundary - 1e-9
            let afterUT = boundary + 1e-9
            return (
                beforeUT,
                beforeUT + AstronomyConfig.deltaTEspenakMeeus(universalTime: beforeUT) / 86_400,
                afterUT,
                afterUT + AstronomyConfig.deltaTEspenakMeeus(universalTime: afterUT) / 86_400
            )
        }

        // The 1986 positive jump has no UT solution for TT values in its gap.
        // Such values clamp to the first representable UT after the jump.
        let positive = surroundingTimes(year: 1_986)
        #expect(positive.afterTT > positive.beforeTT)
        let gapTT = positive.beforeTT + (positive.afterTT - positive.beforeTT) / 2
        let clamped = AstroTime(tt: gapTT)
        #expect(clamped.terrestrialTime == gapTT)
        #expect(clamped.universalTime > positive.beforeUT)
        #expect(clamped.universalTime < positive.afterUT)
        let restored = try JSONDecoder().decode(
            AstroTime.self,
            from: JSONEncoder().encode(clamped)
        )
        #expect(restored.universalTime == clamped.universalTime)
        #expect(restored.terrestrialTime != clamped.terrestrialTime)

        // At 2005 the positive Delta T seed starts after the negative jump,
        // so fixed-point iteration reaches the later solution first.
        let negative = surroundingTimes(year: 2_005)
        #expect(negative.afterTT < negative.beforeTT)
        let overlapTT = negative.afterTT + (negative.beforeTT - negative.afterTT) / 2
        let later = AstroTime(tt: overlapTT)
        let modeledTT = later.universalTime
            + AstronomyConfig.deltaTEspenakMeeus(universalTime: later.universalTime) / 86_400
        #expect(later.terrestrialTime == overlapTT)
        #expect(later.universalTime > negative.beforeUT)
        #expect(abs(modeledTT - overlapTT) <= 1e-12)
    }

    @Test("Negative-Delta-T overlap follows the TT-seeded inverse")
    func negativeDeltaTOverlap() {
        AstronomyConfig.setDeltaTModel(.espenakMeeus)
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }

        let requestedTT = -36_510.21703178009
        let earlierUT = -36_510.21700051158
        let laterUT = -36_510.216999488424
        let overlap = AstroTime(tt: requestedTT)

        // Delta T is negative here, so the initial ut=tt estimate lies before
        // the 1900 jump and iteration reaches the earlier solution first.
        #expect(overlap.universalTime == earlierUT)
        #expect(overlap.terrestrialTime == requestedTT)
        for validUT in [earlierUT, laterUT] {
            let modeledTT = validUT
                + AstronomyConfig.deltaTEspenakMeeus(universalTime: validUT) / 86_400
            #expect(modeledTT == requestedTT)
        }
    }
}
