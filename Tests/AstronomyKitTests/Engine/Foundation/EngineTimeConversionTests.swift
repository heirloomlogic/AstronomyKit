//
//  EngineTimeConversionTests.swift
//  AstronomyKit
//
//  UT to TT, the bounded TT inverse, and model propagation in derived times.
//

import Testing

@testable import AstronomyKit

@Suite("Engine.Time conversion")
struct EngineTimeConversionTests {
    /// The TT that `model` gives for `ut`, by the definition the engine
    /// documents: TT = UT + ΔT / 86400.
    static func modelTT(ut: Double, _ model: DeltaTModel) -> Double {
        ut + Engine.DeltaT.seconds(ut: ut, model: model) / 86_400
    }

    static func tolerance(_ tt: Double) -> Double {
        Engine.Time.inverseTolerance(tt: tt)
    }

    /// A Delta T discontinuity: the last UT before a piece boundary, the
    /// first UT after it, and the TT each gives.
    struct Jump: CustomTestStringConvertible {
        let boundary: Double
        let model: DeltaTModel
        let beforeUT: Double
        let afterUT: Double
        let beforeTT: Double
        let afterTT: Double
        var testDescription: String { "\(model) at \(boundary)" }
        /// TT values that no UT reaches, wider than the inverse tolerance.
        var isGap: Bool { afterTT - beforeTT > tolerance(afterTT) }
        /// TT values that two UTs reach, wider than the inverse tolerance.
        var isOverlap: Bool { beforeTT - afterTT > tolerance(afterTT) }
    }

    /// Every Espenak-Meeus boundary, under both models where the model reaches it.
    static let jumps: [Jump] = DeltaTModel.allCases.flatMap { model in
        EngineDeltaTTests.boundaries.compactMap { boundary in
            let (before, after) = EngineDeltaTTests.straddle(boundary)
            // JPL Horizons holds Delta T constant from early 2017.
            if model == .jplHorizons, after > 17 * Engine.DeltaT.daysPerTropicalYear { return nil }
            return Jump(
                boundary: boundary, model: model, beforeUT: before, afterUT: after,
                beforeTT: modelTT(ut: before, model), afterTT: modelTT(ut: after, model)
            )
        }
    }

    // MARK: - UT to TT

    @Test("TT is UT plus Delta T under the given model", arguments: DeltaTModel.allCases)
    func fromUT(model: DeltaTModel) {
        for ut in [-1e6, -36_525, -0.0, 0, 9_131.25, 36_525, 1e6] {
            let time = Engine.Time(ut: ut, deltaTModel: model)
            #expect(time.ut.bitPattern == ut.bitPattern)
            #expect(time.tt == Self.modelTT(ut: ut, model))
            #expect(time.deltaTModel == model)
        }
    }

    @Test("A UT whose TT overflows keeps the UT and has no model")
    func overflowingTT() {
        let time = Engine.Time(ut: 1e160, deltaTModel: .espenakMeeus)
        #expect(time.ut == 1e160)
        #expect(time.tt == .infinity)
        #expect(time.deltaTModel == nil)
        // JPL Horizons holds Delta T, so the same UT is valid under it.
        #expect(Engine.Time(ut: 1e160, deltaTModel: .jplHorizons).isValid)
        for ut in [Double.nan, .infinity, -.infinity] {
            #expect(!Engine.Time(ut: ut, deltaTModel: .jplHorizons).isValid)
        }
    }

    // MARK: - TT inverse

    @Test(
        "The inverse returns the requested TT and a UT the model maps to it",
        arguments: DeltaTModel.allCases,
        [-1e9, -1e6, -36_510.217, -1, 0, 0.25, 9_131.25, 36_525, 1e6, 1e9]
    )
    func inverse(model: DeltaTModel, tt: Double) {
        let time = Engine.Time(tt: tt, deltaTModel: model)
        #expect(time.tt == tt)
        #expect(time.deltaTModel == model)
        #expect(abs(Self.modelTT(ut: time.ut, model) - tt) <= Self.tolerance(tt))
    }

    @Test(
        "Large TT converges at the precision a double holds",
        arguments: [
            (DeltaTModel.espenakMeeus, 1e11), (.espenakMeeus, -1e11),
            (.jplHorizons, 1e11), (.jplHorizons, -1e11), (.jplHorizons, 3e15),
        ] as [(DeltaTModel, Double)]
    )
    func representationalPrecision(model: DeltaTModel, tt: Double) {
        // From |TT| near 1e5 days, one ulp of TT exceeds the 1e-12-day floor,
        // so iteration can only get within a few ulps.
        let time = Engine.Time(tt: tt, deltaTModel: model)
        #expect(time.isValid)
        #expect(time.tt == tt)
        #expect(abs(Self.modelTT(ut: time.ut, model) - tt) <= Self.tolerance(tt))
    }

    @Test("Huge TT converges under JPL Horizons and is invalid under Espenak-Meeus")
    func largestFiniteTT() {
        let jpl = Engine.Time(tt: .greatestFiniteMagnitude, deltaTModel: .jplHorizons)
        #expect(jpl.tt == .greatestFiniteMagnitude)
        #expect(jpl.ut == .greatestFiniteMagnitude)
        #expect(jpl.deltaTModel == .jplHorizons)

        // Espenak-Meeus Delta T overflows there. At 3e15 days it stays finite
        // but grows faster than UT, so the iteration does not settle.
        for tt in [Double.greatestFiniteMagnitude, 3e15] {
            let em = Engine.Time(tt: tt, deltaTModel: .espenakMeeus)
            #expect(em.ut.isNaN)
            #expect(em.tt.isNaN)
            #expect(em.deltaTModel == nil)
        }
    }

    @Test(
        "A TT that is not finite gives the invalid time",
        arguments: DeltaTModel.allCases,
        [Double.nan, .infinity, -.infinity]
    )
    func nonfiniteTT(model: DeltaTModel, tt: Double) {
        let time = Engine.Time(tt: tt, deltaTModel: model)
        #expect(time.ut.isNaN)
        #expect(time.tt.isNaN)
        #expect(time.deltaTModel == nil)
    }

    @Test("Every TT in a positive jump's gap takes the first UT after the jump", arguments: jumps.filter(\.isGap))
    func gap(jump: Jump) {
        for fraction in [0.001, 0.5, 0.999] {
            let tt = jump.beforeTT + (jump.afterTT - jump.beforeTT) * fraction
            let time = Engine.Time(tt: tt, deltaTModel: jump.model)
            #expect(time.tt == tt)
            #expect(time.ut == jump.afterUT)
            #expect(time.deltaTModel == jump.model)
        }
    }

    @Test(
        "A TT in a negative jump's overlap takes the solution on the side iteration starts from",
        arguments: jumps.filter(\.isOverlap)
    )
    func overlap(jump: Jump) {
        let tt = jump.afterTT + (jump.beforeTT - jump.afterTT) / 2
        let time = Engine.Time(tt: tt, deltaTModel: jump.model)
        #expect(time.tt == tt)
        #expect(abs(Self.modelTT(ut: time.ut, jump.model) - tt) <= Self.tolerance(tt))
        // Iteration starts at UT = TT, which lies after both solutions when
        // Delta T is positive and before both when it is negative.
        if Engine.DeltaT.seconds(ut: jump.afterUT, model: jump.model) > 0 {
            #expect(time.ut >= jump.afterUT)
        } else {
            #expect(time.ut <= jump.beforeUT)
        }
    }

    @Test("Espenak-Meeus overlaps at eight boundaries and leaves gaps at five")
    func jumpSigns() throws {
        let espenakMeeus = Self.jumps.filter { $0.model == .espenakMeeus }
        #expect(espenakMeeus.filter(\.isOverlap).map(\.boundary) == [-500, 500, 1600, 1700, 1800, 1900, 2005, 2050])
        #expect(espenakMeeus.filter(\.isGap).map(\.boundary) == [1860, 1920, 1941, 1961, 1986])
        // At 2150 the pieces meet within a nanosecond, inside the tolerance,
        // so the inverse converges there without bisecting.
        let last = try #require(espenakMeeus.last)
        #expect(last.boundary == 2150)
        #expect(!last.isGap && !last.isOverlap)
        let time = Engine.Time(tt: last.afterTT, deltaTModel: .espenakMeeus)
        #expect(abs(Self.modelTT(ut: time.ut, .espenakMeeus) - last.afterTT) <= Self.tolerance(last.afterTT))
        // 1900 is the only overlap where Delta T is negative.
        #expect(Engine.DeltaT.espenakMeeus(ut: EngineDeltaTTests.straddle(1900).after) < 0)
    }

    // MARK: - Derived times

    @Test("Adding days keeps the time's model", arguments: DeltaTModel.allCases)
    func addingKeepsModel(model: DeltaTModel) {
        let time = Engine.Time(ut: 18_000, deltaTModel: model)
        let later = time.adding(days: 1_000.5)
        #expect(later.ut == 19_000.5)
        #expect(later.tt == Self.modelTT(ut: 19_000.5, model))
        #expect(later.deltaTModel == model)
        // A model from a reconstructed pair carries through too.
        let pair = Engine.Time.fromPair(ut: 10, tt: 5, deltaTModel: model)
        #expect(pair.adding(days: 1).deltaTModel == model)
    }

    @Test("A time derived from an invalid time is invalid")
    func addingFromInvalid() {
        // Espenak-Meeus TT overflows at this UT. Subtracting it gives a finite
        // UT, which is kept, but there is no model to derive its TT with.
        let huge = Engine.Time(ut: 1e160, deltaTModel: .espenakMeeus)
        #expect(!huge.isValid)
        for derived in [huge.adding(days: -1e160), huge.derived(ut: 0)] {
            #expect(derived.ut == 0)
            #expect(derived.tt.isNaN)
            #expect(derived.deltaTModel == nil)
        }
        #expect(huge.adding(days: 1).ut == 1e160)

        let nan = Engine.Time.invalid.adding(days: 1)
        #expect(nan.ut.isNaN)
        #expect(nan.deltaTModel == nil)
    }

    @Test("Adding days at a huge UT stalls at the same UT and keeps the model")
    func addingStall() {
        let time = Engine.Time(ut: 1e20, deltaTModel: .jplHorizons)
        let later = time.adding(days: 1)
        #expect(later.ut == time.ut)
        #expect(later.deltaTModel == .jplHorizons)
    }
}
