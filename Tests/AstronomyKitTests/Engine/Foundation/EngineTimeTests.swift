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

    @Test("The invalid time has NaN scales and no model")
    func invalidTime() {
        #expect(Engine.Time.invalid.ut.isNaN)
        #expect(Engine.Time.invalid.tt.isNaN)
        #expect(Engine.Time.invalid.deltaTModel == nil)
        #expect(!Engine.Time.invalid.isValid)
    }
}
