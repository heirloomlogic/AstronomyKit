//
//  EngineLightTravelTests.swift
//  AstronomyKit
//
//  The native light-travel iteration.
//

import Testing

@testable import AstronomyKit

@Suite("Engine.LightTravel")
struct EngineLightTravelTests {
    struct CallbackFailure: Error, Equatable {
        let call: Int
    }

    static let base = 20_000.0

    static func vector(_ x: Double, _ y: Double, _ z: Double, at time: Engine.Time) -> Engine.Vector<Engine.EQJ> {
        Engine.Vector(x: x, y: y, z: z, time: time)
    }

    /// Corrects with `position` of the days since `base`, recording every
    /// time the iteration passes it.
    static func correct(
        at time: Engine.Time, fallback: DeltaTModel = .espenakMeeus, _ position: (Double) throws -> [Double]
    ) throws -> (vector: Engine.Vector<Engine.EQJ>, calls: [Engine.Time]) {
        var calls: [Engine.Time] = []
        let vector = try Engine.LightTravel.correct(at: time, fallback: fallback) { time in
            calls.append(time)
            let xyz = try position(time.ut - base)
            return vector(xyz[0], xyz[1], xyz[2], at: time)
        }
        return (vector, calls)
    }

    // MARK: - Backdating

    /// A target receding at 10 AU per day, so every backdate moves.
    @Test("Each call after the first is the observation time backdated in UT", arguments: DeltaTModel.allCases)
    func backdatesInUT(model: DeltaTModel) throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: model)
        let result = try Self.correct(at: observation) { [1 + 10 * $0, 0.2, 0.3] }
        let calls = result.calls
        try #require(calls.count >= 3)
        #expect(calls[0].ut.bitPattern == observation.ut.bitPattern)
        #expect(calls[0].tt.bitPattern == observation.tt.bitPattern)
        for (previous, call) in zip(calls, calls.dropFirst()) {
            let u = previous.ut - Self.base
            let distance = Self.vector(1 + 10 * u, 0.2, 0.3, at: previous).length
            let ut = observation.ut + -distance / Engine.speedOfLightAUPerDay
            #expect(call.ut.bitPattern == ut.bitPattern)
            #expect(call.tt.bitPattern == Engine.Time(ut: ut, deltaTModel: model).tt.bitPattern)
            #expect(call.deltaTModel == model)
        }
    }

    /// Light leaving 0.01 day after a Delta T jump arrives just before it,
    /// so the observation's TT minus the light time misses the backdated
    /// TT by the size of the jump.
    @Test("A backdate across a Delta T jump takes TT from its own UT")
    func backdateAcrossJump() throws {
        let jump = try #require(
            EngineTimeConversionTests.jumps.filter { $0.model == .espenakMeeus }.max {
                abs($0.afterTT - $0.beforeTT) < abs($1.afterTT - $1.beforeTT)
            })
        let observation = Engine.Time(ut: jump.afterUT + 0.005, deltaTModel: .espenakMeeus)
        let distance = 0.01 * Engine.speedOfLightAUPerDay
        let result = try Self.correct(at: observation) { _ in [distance, 0, 0] }
        let backdated = result.vector.time
        #expect(backdated.ut < jump.afterUT)
        #expect(backdated.tt.bitPattern == Engine.Time(ut: backdated.ut, deltaTModel: .espenakMeeus).tt.bitPattern)
        let lightDays = distance / Engine.speedOfLightAUPerDay
        #expect(abs(backdated.tt - (observation.tt - lightDays)) > 1e-6)
    }

    @Test(
        "Every call has the observation time's model, whatever the fallback",
        arguments: DeltaTModel.allCases, DeltaTModel.allCases)
    func capturedModel(model: DeltaTModel, fallback: DeltaTModel) throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: model)
        let result = try Self.correct(at: observation, fallback: fallback) { [1 + 10 * $0, 0.2, 0.3] }
        #expect(result.calls.count >= 3)
        for time in result.calls + [result.vector.time] {
            #expect(time.deltaTModel == model)
            #expect(time.tt.bitPattern == Engine.Time(ut: time.ut, deltaTModel: model).tt.bitPattern)
        }
    }

    /// Espenak-Meeus TT overflows at UT 1e160, so the observation time is
    /// invalid. JPL Horizons holds Delta T, so its backdated time is valid;
    /// under Espenak-Meeus every backdated time is invalid too.
    @Test("Backdating an invalid time uses the fallback model")
    func invalidObservation() throws {
        let observation = Engine.Time(ut: 1e160, deltaTModel: .espenakMeeus)
        try #require(!observation.isValid)
        let jpl = try Self.correct(at: observation, fallback: .jplHorizons) { _ in [1, 0, 0] }
        #expect(jpl.vector.time.deltaTModel == .jplHorizons)
        #expect(jpl.calls.count == 2)
        #expect(throws: AstronomyError.noConvergence) {
            try Self.correct(at: observation, fallback: .espenakMeeus) { _ in [1, 0, 0] }
        }
    }

    // MARK: - Result

    @Test(
        "A fixed position returns after two calls, at the backdated time",
        arguments: DeltaTModel.allCases, [[1.0, 0, 0], [-1, 0, 0], [0.3, -40, 5]])
    func fixedPosition(model: DeltaTModel, xyz: [Double]) throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: model)
        let result = try Self.correct(at: observation) { _ in xyz }
        #expect(result.calls.count == 2)
        let vector = result.vector
        #expect([vector.x, vector.y, vector.z].map(\.bitPattern) == xyz.map(\.bitPattern))
        let lightDays = vector.length / Engine.speedOfLightAUPerDay
        #expect(vector.time.ut.bitPattern == (observation.ut + -lightDays).bitPattern)
    }

    @Test("A zero position returns after one call, at the observation time")
    func zeroPosition() throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: .espenakMeeus)
        let result = try Self.correct(at: observation) { _ in [0, 0, 0] }
        #expect(result.calls.count == 1)
        #expect(result.vector.time.ut.bitPattern == observation.ut.bitPattern)
    }

    @Test("The result has the time of the last call, not the time on the returned vector")
    func resultTime() throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: .jplHorizons)
        var calls: [Engine.Time] = []
        let vector = try Engine.LightTravel.correct(at: observation, fallback: .jplHorizons) { time in
            calls.append(time)
            return Self.vector(2, 0, 0, at: time.adding(days: 10, fallback: .jplHorizons))
        }
        let last = try #require(calls.last)
        #expect(vector.time.ut.bitPattern == last.ut.bitPattern)
        #expect(vector.time.tt.bitPattern == last.tt.bitPattern)
        #expect(vector.x == 2)
    }

    // MARK: - Failures

    /// The light-day is 173.144 632 674 240 33 AU by the IAU au and the SI
    /// speed of light.
    @Test("A distance of exactly one light-day is accepted and the next double is not")
    func lightDayLimit() throws {
        let observation = Engine.Time(ut: Self.base, deltaTModel: .espenakMeeus)
        let lightDay = Engine.speedOfLightAUPerDay
        let accepted = try Self.correct(at: observation) { _ in [lightDay, 0, 0] }
        #expect(accepted.vector.x == lightDay)
        for x in [lightDay.nextUp, 1e308, .infinity] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Self.correct(at: observation) { _ in [x, 0, 0] }
            }
        }
    }

    @Test("A NaN position or observation time fails after ten calls", arguments: DeltaTModel.allCases)
    func nanInput(model: DeltaTModel) {
        for (ut, x) in [(Self.base, Double.nan), (.nan, 1)] {
            var calls = 0
            #expect(throws: AstronomyError.noConvergence) {
                try Engine.LightTravel.correct(at: Engine.Time(ut: ut, deltaTModel: model), fallback: model) { time in
                    calls += 1
                    return Self.vector(x, 0, 0, at: time)
                }
            }
            #expect(calls == Engine.LightTravel.iterationLimit)
        }
    }

    /// x = 1 + 100 u gives a backdate map that contracts by only about 0.58
    /// per call, so the iterates are still moving after ten calls.
    @Test("A finite position that does not settle fails after ten calls", arguments: DeltaTModel.allCases)
    func finiteNonconvergence(model: DeltaTModel) {
        var calls: [Engine.Time] = []
        #expect(throws: AstronomyError.noConvergence) {
            try Engine.LightTravel.correct(at: Engine.Time(ut: Self.base, deltaTModel: model), fallback: model) {
                calls.append($0)
                return Self.vector(1 + 100 * ($0.ut - Self.base), 0, 0, at: $0)
            }
        }
        #expect(calls.count == Engine.LightTravel.iterationLimit)
        #expect(calls.allSatisfy { $0.ut.isFinite })
    }

    @Test(
        "An error from the position propagates unchanged and ends the iteration",
        arguments: DeltaTModel.allCases, [1, 2, 3, 4, 7])
    func throwingPosition(model: DeltaTModel, failingCall: Int) {
        let observation = Engine.Time(ut: Self.base, deltaTModel: model)
        var calls = 0
        #expect(throws: CallbackFailure(call: failingCall)) {
            try Engine.LightTravel.correct(at: observation, fallback: model) { time in
                calls += 1
                if calls == failingCall { throw CallbackFailure(call: failingCall) }
                // Slow contraction, so the seventh call is reached.
                return Self.vector(1 + 100 * (time.ut - Self.base), 0, 0, at: time)
            }
        }
        #expect(calls == failingCall)
    }

    @Test("An AstronomyError from the position is not replaced", arguments: [AstronomyError.badTime, .invalidBody])
    func throwingAstronomyError(error: AstronomyError) {
        let observation = Engine.Time(ut: Self.base, deltaTModel: .espenakMeeus)
        var calls = 0
        #expect(throws: error) {
            try Self.correct(at: observation) { u in
                calls += 1
                if calls == 2 { throw error }
                return [1 + 10 * u, 0, 0]
            }
        }
        #expect(calls == 2)
    }
}
