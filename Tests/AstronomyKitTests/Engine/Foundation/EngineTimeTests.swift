//
//  EngineTimeTests.swift
//  AstronomyKit
//
//  Validity and model capture of the native engine's time value.
//

import Testing

@testable import AstronomyKit

@Suite("Engine.Time")
struct EngineTimeTests {
    @Test("Finite scales are stored exactly and keep their model", arguments: DeltaTModel.allCases)
    func finiteScales(model: DeltaTModel) {
        let ut = 9_131.25
        let tt = ut + 64.184 / 86_400
        let time = Engine.Time(ut: ut, tt: tt, deltaTModel: model)
        #expect(time.ut.bitPattern == ut.bitPattern)
        #expect(time.tt.bitPattern == tt.bitPattern)
        #expect(time.deltaTModel == model)
        #expect(time.isValid)
    }

    @Test(
        "A scale that is not finite drops the model and keeps both values",
        arguments: [
            (1e160, Double.infinity),
            (-1e160, -Double.infinity),
            (Double.nan, 0),
            (0, Double.nan),
            (Double.infinity, Double.infinity),
        ] as [(Double, Double)]
    )
    func nonfiniteScales(ut: Double, tt: Double) {
        let time = Engine.Time(ut: ut, tt: tt, deltaTModel: .espenakMeeus)
        #expect(time.ut.bitPattern == ut.bitPattern)
        #expect(time.tt.bitPattern == tt.bitPattern)
        #expect(time.deltaTModel == nil)
        #expect(!time.isValid)
    }

    @Test("Negative zero survives on both scales")
    func signedZero() {
        let time = Engine.Time(ut: -0.0, tt: -0.0, deltaTModel: .jplHorizons)
        #expect(time.ut.sign == .minus)
        #expect(time.tt.sign == .minus)
        #expect(time.isValid)
    }

    @Test("Pair reconstruction stores the scales unchecked against the model")
    func pairStoresScales() {
        // TT below UT is not what either model gives; the pair is kept anyway.
        let time = Engine.Time.fromPair(ut: 10, tt: 5, deltaTModel: .jplHorizons)
        #expect(time.ut == 10)
        #expect(time.tt == 5)
        #expect(time.deltaTModel == .jplHorizons)
    }

    @Test(
        "Pair reconstruction with a scale that is not finite is the invalid time",
        arguments: [
            (0, Double.infinity),
            (Double.infinity, 0),
            (Double.nan, 0),
            (0, -Double.nan),
        ] as [(Double, Double)]
    )
    func pairRejectsNonfinite(ut: Double, tt: Double) {
        let time = Engine.Time.fromPair(ut: ut, tt: tt, deltaTModel: .espenakMeeus)
        #expect(time.ut.isNaN)
        #expect(time.tt.isNaN)
        #expect(time.deltaTModel == nil)
    }

    /// A TT inside every gap a positive Delta T jump leaves under `model`.
    static func gapTimes(_ model: DeltaTModel) -> [Engine.Time] {
        EngineTimeConversionTests.jumps.filter { $0.model == model && $0.isGap }.map { jump in
            Engine.Time(tt: jump.beforeTT + (jump.afterTT - jump.beforeTT) / 2, deltaTModel: model)
        }
    }

    /// Valid times from each way the engine makes one.
    static func madeTimes(_ model: DeltaTModel) -> [Engine.Time] {
        [
            Engine.Time(ut: 9_131.25, deltaTModel: model),
            Engine.Time(ut: -0.0, deltaTModel: model),
            Engine.Time(tt: 9_131.25, deltaTModel: model),
            Engine.Time(tt: -1e6, deltaTModel: model),
            Engine.Time.civil(utcDays: 6_208.5, deltaTModel: model).time,
            Engine.Time(ut: 1e15, deltaTModel: model).adding(days: 0.25),
        ] + gapTimes(model)
    }

    @Test("Pair reconstruction gives back every kind of engine time bit for bit", arguments: DeltaTModel.allCases)
    func pairRoundTrip(model: DeltaTModel) throws {
        for time in Self.madeTimes(model) {
            let recorded = try #require(time.deltaTModel)
            let rebuilt = Engine.Time.fromPair(ut: time.ut, tt: time.tt, deltaTModel: recorded)
            #expect(rebuilt.ut.bitPattern == time.ut.bitPattern, "\(time.ut)")
            #expect(rebuilt.tt.bitPattern == time.tt.bitPattern, "\(time.ut)")
            #expect(rebuilt.deltaTModel == model)
            // Times derived from the rebuilt value match those from the original.
            let derived = time.adding(days: 0.5)
            let rebuiltDerived = rebuilt.adding(days: 0.5)
            #expect(rebuiltDerived.ut.bitPattern == derived.ut.bitPattern)
            #expect(rebuiltDerived.tt.bitPattern == derived.tt.bitPattern)
        }
    }

    /// UT alone, which is what `AstroTime`'s `Codable` form records, cannot
    /// rebuild a time whose TT lies in a Delta T gap: no UT gives that TT.
    @Test("Only the pair rebuilds a time in a Delta T gap", arguments: DeltaTModel.allCases)
    func gapNeedsPair(model: DeltaTModel) throws {
        let times = Self.gapTimes(model)
        try #require(!times.isEmpty)
        for time in times {
            let fromUT = Engine.Time(ut: time.ut, deltaTModel: model)
            #expect(fromUT.ut.bitPattern == time.ut.bitPattern)
            #expect(abs(fromUT.tt - time.tt) > Engine.Time.inverseTolerance(tt: time.tt), "\(time.tt)")
            let fromPair = Engine.Time.fromPair(ut: time.ut, tt: time.tt, deltaTModel: model)
            #expect(fromPair.tt.bitPattern == time.tt.bitPattern)
        }
    }

    /// The pair of an invalid time has a scale that is not finite, and
    /// reconstruction gives the invalid time, as `AstroTime(tt:ut:)` does.
    @Test("Pair reconstruction does not keep the finite UT of an invalid time")
    func pairOfInvalidTime() {
        let overflowed = Engine.Time(ut: 1e160, deltaTModel: .espenakMeeus)
        #expect(overflowed.ut == 1e160)
        let rebuilt = Engine.Time.fromPair(ut: overflowed.ut, tt: overflowed.tt, deltaTModel: .espenakMeeus)
        #expect(rebuilt.ut.isNaN)
        #expect(rebuilt.tt.isNaN)
        #expect(rebuilt.deltaTModel == nil)
    }

    @Test("The invalid time has NaN scales and no model")
    func invalidTime() {
        #expect(Engine.Time.invalid.ut.isNaN)
        #expect(Engine.Time.invalid.tt.isNaN)
        #expect(Engine.Time.invalid.deltaTModel == nil)
        #expect(!Engine.Time.invalid.isValid)
    }
}
