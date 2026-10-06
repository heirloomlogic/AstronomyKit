//
//  SearchTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("AstroSearch Tests")
struct SearchTests {
    @Test(
        "Descending and constant callbacks have no ascending event",
        arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func rejectsFalseRoots(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        for days in [1.0, 1e-10, 0.0] {
            for tolerance in [0.001, 1.0, -0.001, Double.infinity] {
                let end = start.addingDays(days)
                let descending = try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { time in
                    20000 + days / 2 - time.universalTime
                }
                #expect(descending == nil, "Descending window \(days), tolerance \(tolerance)")
                for value in [-1.0, 0.0, 1.0, -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude] {
                    let constant = try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { _ in value
                    }
                    #expect(constant == nil, "Constant \(value), window \(days), tolerance \(tolerance)")
                }
            }
        }
    }

    @Test("Reported false-positive reproductions return nil", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func reportedFalsePositives(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let descending = try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) {
            20000.375 - $0.universalTime
        }
        let absent = try AstroSearch.find(from: start, to: start.addingDays(1e-10), toleranceSeconds: 0.001) { _ in 1 }
        #expect(descending == nil)
        #expect(absent == nil)
    }

    @Test(
        "Ascending interpolation and short brackets still succeed", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func ascendingSuccessPaths(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        for days in [1.0, 1e-10] {
            let target = start.universalTime + days / 2
            let root = try #require(
                try AstroSearch.find(from: start, to: start.addingDays(days), toleranceSeconds: 0.001) {
                    $0.universalTime - target
                })
            #expect(abs(root.universalTime - target) * 86400 < 0.001)
            #expect(root.deltaTModel == model)
        }
        let quadratic = try #require(
            try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) { time in
                let u = time.universalTime - 20000
                return u * u - 0.140625
            })
        #expect(abs(quadratic.universalTime - 20000.375) * 86400 < 0.001)
    }

    @Test("Reversed ordinary windows retain ascending direction", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func reversedWindow(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let end = start.addingDays(1)
        let ascending = try #require(
            try AstroSearch.find(from: end, to: start, toleranceSeconds: 0.001) {
                $0.universalTime - 20000.375
            })
        #expect(abs(ascending.universalTime - 20000.375) * 86400 < 0.001)
        let descending = try AstroSearch.find(from: end, to: start, toleranceSeconds: 0.001) {
            20000.375 - $0.universalTime
        }
        #expect(descending == nil)
    }

    @Test("An internal ascending bracket remains discoverable", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func internalAscendingBracket(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        // The equal-sign outer endpoints must not cause an immediate rejection.
        // This finite example observes existing subdivision, not completeness for multiple roots.
        let result = try #require(
            try AstroSearch.find(from: start, to: start.addingDays(1), toleranceSeconds: 0.001) { time in
                let u = time.universalTime - 20000
                return (u - 0.25) * (u - 0.75)
            })
        #expect(abs(result.universalTime - 20000.75) * 86400 < 0.001)
    }

    @Test(
        "Observed ordinary endpoint searches retain their results", arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func ordinaryEndpoints(model: DeltaTModel) throws {
        let start = AstroTime(ut: 20000, deltaTModel: model)
        let end = start.addingDays(1)
        let lower = try AstroSearch.find(from: start, to: end, toleranceSeconds: 0.001) { $0.universalTime - 20000 }
        // Retain the reviewed legacy model-sensitive observation without imposing a new endpoint policy.
        if model == .espenakMeeus {
            #expect(lower == nil)
        } else {
            #expect(abs(try #require(lower).universalTime - 20000) * 86400 < 0.001)
        }
        let upper = try #require(
            try AstroSearch.find(from: start, to: end, toleranceSeconds: 0.001) { $0.universalTime - 20001 })
        #expect(abs(upper.universalTime - 20001) * 86400 < 0.001)
    }

    @Test("Sun.searchLongitude finds March equinox near Seasons result")
    func sunLongitudeMatchesSeasons() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let equinox = try #require(try Sun.searchLongitude(0, after: start))
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(equinox.universalTime - seasons.marchEquinox.universalTime) * 86400
        #expect(diffSeconds < 60, "Sun.searchLongitude and Seasons should agree within 60s, got \(diffSeconds)s")
    }

    @Test("Sun.searchLongitude finds June solstice at 90°")
    func sunLongitudeJuneSolstice() throws {
        let start = AstroTime(year: 2025, month: 3, day: 22)
        let solstice = try #require(try Sun.searchLongitude(90, after: start))
        let seasons = try Seasons.forYear(2025)

        let diffSeconds = abs(solstice.universalTime - seasons.juneSolstice.universalTime) * 86400
        #expect(diffSeconds < 60, "Expected June solstice match within 60s, got \(diffSeconds)s")
    }

    @Test("Sun.searchLongitude returns nil when the window is too short")
    func sunLongitudeShortWindow() throws {
        // The Sun cannot travel ~90° of ecliptic longitude in one day.
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let result = try Sun.searchLongitude(180, after: start, limitDays: 1)

        #expect(result == nil)
    }

    @Test("Moon.searchPhase returns nil when the window is too short")
    func moonPhaseShortWindow() throws {
        let start = AstroTime(year: 2025, month: 3, day: 1)
        let fullMoon = try #require(try Moon.searchPhase(.full, after: start))

        // Searching for the next full moon right after one just occurred
        // cannot succeed within 3 days.
        let result = try Moon.searchPhase(.full, after: fullMoon.addingDays(1), limitDays: 3)
        #expect(result == nil)
    }

    @Test("Generic search finds ascending root")
    func genericSearchFindsRoot() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)

        let result = try #require(
            try AstroSearch.find(from: start, to: end) { time in
                time.universalTime - start.universalTime - 15.0
            }
        )

        let expected = start.addingDays(15)
        let diffSeconds = abs(result.universalTime - expected.universalTime) * 86400
        #expect(diffSeconds < 1, "Expected root at day 15, got diff of \(diffSeconds)s")
    }

    @Test("Generic search matches Moon phase search")
    func genericSearchMatchesMoonPhase() throws {
        let start = AstroTime(year: 2025, month: 3, day: 1)
        let fullMoon = try #require(try Moon.searchPhase(.full, after: start))

        let end = start.addingDays(35)
        let result = try #require(
            try AstroSearch.find(from: start, to: end) { time in
                let phase = try Moon.phaseAngle(at: time)
                var diff = phase - 180.0
                while diff < -180 { diff += 360 }
                while diff > 180 { diff -= 360 }
                return diff
            }
        )

        let diffSeconds = abs(result.universalTime - fullMoon.universalTime) * 86400
        #expect(diffSeconds < 120, "Generic search and Moon.searchPhase should agree within 120s, got \(diffSeconds)s")
    }

    @Test("Generic search returns nil when no root crossing exists")
    func genericSearchNoRoot() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(1)

        // Monotonically increasing function with no root crossing in the window
        let result = try AstroSearch.find(from: start, to: end) { time in
            time.universalTime - start.universalTime + 100.0
        }

        #expect(result == nil)
    }

    @Test("Generic search rethrows closure errors")
    func genericSearchRethrows() {
        struct TestError: Error, Equatable {}

        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)

        #expect(throws: TestError.self) {
            try AstroSearch.find(from: start, to: end) { _ in
                throw TestError()
            }
        }
    }

    @Test("Generic search stops calling the closure after it throws")
    func genericSearchAbortsAfterThrow() {
        struct TestError: Error {}
        final class CallCounter: @unchecked Sendable {
            var count = 0
        }

        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = start.addingDays(30)
        let counter = CallCounter()

        #expect(throws: TestError.self) {
            try AstroSearch.find(from: start, to: end) { _ in
                counter.count += 1
                throw TestError()
            }
        }
        #expect(counter.count == 1, "C search must abort on the first thrown error")
    }

    @Test(
        "Sun.searchLongitude throws invalidParameter for a non-finite target",
        arguments: [Double.nan, .infinity, -.infinity]
    )
    func sunLongitudeNonFiniteTarget(target: Double) {
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try Sun.searchLongitude(target, after: AstroTime(year: 2025, month: 1, day: 1))
        }
    }

    @Test("Sun.searchLongitude wraps a target far outside 0-360 in constant time")
    func sunLongitudeWrappedTarget() throws {
        // 90 + 360 * 10^9 used to take 10^9 loop steps per function evaluation.
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let direct = try #require(try Sun.searchLongitude(90, after: start))
        let wrapped = try #require(try Sun.searchLongitude(90 + 360 * 1e9, after: start))
        #expect(abs(wrapped.universalTime - direct.universalTime) * 86_400 < 60)
    }
}

/// The public contract of the two callback-driven solvers, `AstroSearch.find` and `AstroSearch.correctLightTravel`:
/// which requests return a value, return nil or throw, how many times a throwing callback is visited, and which times
/// the callbacks receive. The cases and outcomes come from the #84 callback corpus protocol and supplement (retained in
/// the history of #143) as replayed against the source repaired in #145. Exact per-visit traces are deliberately not
/// pinned: visit counts other than the throwing visit are solver internals, not part of the contract.
///
/// Every window starts from a time built with an explicit model, so these tests never depend on the process default.
/// Every callback goes through ``Visits/record(_:)``, which throws after the corpus's 128-visit research cap, so a
/// solver that stopped terminating fails its test instead of stalling the run; `.timeLimit` cannot interrupt a loop
/// inside the C engine.
@Suite("Search callback contract", .timeLimit(.minutes(1)))
struct SearchCallbackContractTests {
    struct CallbackFailure: Error, Equatable {
        let visit: Int
    }

    struct CallbackCapExceeded: Error {}

    /// Records each time a callback receives. The solvers call back synchronously on the calling thread.
    final class Visits: @unchecked Sendable {
        static let cap = 128
        var times: [AstroTime] = []
        var count: Int { times.count }

        func record(_ time: AstroTime) throws {
            times.append(time)
            if count > Self.cap { throw CallbackCapExceeded() }
        }
    }

    static let baseUT = 20_000.0
    static let errorVisits = [1, 2, 3, 4, 7]

    /// Days since the window's base UT, as the corpus fixtures measure them.
    static func elapsed(_ time: AstroTime, from base: Double = baseUT) -> Double {
        time.universalTime - base
    }

    static func window(_ model: DeltaTModel, base: Double = baseUT) -> (start: AstroTime, end: AstroTime) {
        let start = AstroTime(ut: base, deltaTModel: model)
        return (start, start.addingDays(1))
    }

    /// Searches the window with a capped callback that returns `function` of the elapsed days.
    static func find(
        _ model: DeltaTModel, base: Double = baseUT, tolerance: Double = 0.001, visits: Visits = Visits(),
        _ function: @escaping @Sendable (Double) -> Double
    ) throws -> AstroTime? {
        let (start, end) = window(model, base: base)
        return try AstroSearch.find(from: start, to: end, toleranceSeconds: tolerance) { time in
            try visits.record(time)
            return function(elapsed(time, from: base))
        }
    }

    /// Corrects a position for light time with a capped callback that returns `position` of the elapsed days.
    static func correct(
        _ model: DeltaTModel, base: Double = baseUT, visits: Visits = Visits(),
        _ position: @escaping @Sendable (Double) -> [Double]
    ) throws -> Vector3D {
        try AstroSearch.correctLightTravel(at: AstroTime(ut: base, deltaTModel: model)) { time in
            try visits.record(time)
            let xyz = position(elapsed(time, from: base))
            return Vector3D(x: xyz[0], y: xyz[1], z: xyz[2], time: time)
        }
    }

    static func step(_ u: Double) -> Double { u < 0.375 ? -1 : 1 }

    // MARK: - Root search

    @Test("An ascending root near 1e300 days returns nil", arguments: DeltaTModel.allCases)
    func extremeTime(model: DeltaTModel) throws {
        #expect(try Self.find(model, base: 1e300) { $0 - 0.375 } == nil)
    }

    /// A linear function needs only four visits, so the seventh visit uses a step function, which keeps bisecting.
    @Test("A root callback that throws stops the search at that visit", arguments: DeltaTModel.allCases, errorVisits)
    func rootCallbackError(model: DeltaTModel, visit: Int) {
        let (start, end) = Self.window(model)
        let visits = Visits()
        #expect(throws: CallbackFailure(visit: visit)) {
            try AstroSearch.find(from: start, to: end, toleranceSeconds: 0.001) { time in
                try visits.record(time)
                if visits.count == visit { throw CallbackFailure(visit: visit) }
                let u = Self.elapsed(time)
                return visit < 7 ? u - 0.375 : Self.step(u)
            }
        }
        #expect(visits.count == visit)
    }

    @Test(
        "A nonfinite callback value returns nil",
        arguments: DeltaTModel.allCases, [Double.nan, .infinity, -.infinity])
    func nonfiniteCallback(model: DeltaTModel, value: Double) throws {
        #expect(try Self.find(model) { _ in value } == nil)
    }

    @Test("A zero or NaN tolerance fails to converge", arguments: DeltaTModel.allCases, [0, Double.nan])
    func unusableTolerance(model: DeltaTModel, tolerance: Double) {
        #expect(throws: AstronomyError.noConvergence) {
            try Self.find(model, tolerance: tolerance) { $0 - 0.375 }
        }
    }

    @Test(
        "A negative or infinite tolerance still returns a root", arguments: DeltaTModel.allCases, [-0.001, .infinity])
    func permissiveTolerance(model: DeltaTModel, tolerance: Double) throws {
        let (start, end) = Self.window(model)
        let root = try #require(try Self.find(model, tolerance: tolerance) { $0 - 0.375 })
        #expect(root.deltaTModel == model)
        #expect((start.universalTime...end.universalTime).contains(root.universalTime))
    }

    @Test("A NaN or infinite start returns nil", arguments: DeltaTModel.allCases, [Double.nan, .infinity])
    func nonfiniteStart(model: DeltaTModel, base: Double) throws {
        #expect(try Self.find(model, base: base) { $0 - 0.375 } == nil)
    }

    @Test("A step function cannot meet a 1 ms tolerance", arguments: DeltaTModel.allCases)
    func stepFailsToConverge(model: DeltaTModel) {
        #expect(throws: AstronomyError.noConvergence) {
            try Self.find(model, Self.step)
        }
    }

    @Test("A step function meets a 0.2 s tolerance at the step", arguments: DeltaTModel.allCases)
    func stepWithCoarseTolerance(model: DeltaTModel) throws {
        let root = try #require(try Self.find(model, tolerance: 0.2, Self.step))
        #expect(abs(Self.elapsed(root) - 0.375) * 86_400 <= 0.2)
    }

    /// The cubic is flat at its root, which slows the solver's interpolation; the corpus measured a result 3.5 ms
    /// from the root under Espenak-Meeus and an exact one under JPL Horizons.
    @Test("A cubic with a flat root still converges near it", arguments: DeltaTModel.allCases)
    func flatCubic(model: DeltaTModel) throws {
        let root = try #require(try Self.find(model) { ($0 - 0.375) * ($0 - 0.375) * ($0 - 0.375) })
        #expect(abs(Self.elapsed(root) - 0.375) * 86_400 < 0.01)
    }

    @Test("The first two callbacks receive the window's start and end", arguments: DeltaTModel.allCases)
    func firstCallbacksAreEndpoints(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let visits = Visits()
        _ = try Self.find(model, visits: visits) { $0 - 0.375 }
        try #require(visits.count >= 2)
        for (received, sent) in zip(visits.times.prefix(2), [start, end]) {
            #expect(received.universalTime.bitPattern == sent.universalTime.bitPattern)
            #expect(received.terrestrialTime.bitPattern == sent.terrestrialTime.bitPattern)
            #expect(received.deltaTModel == model)
        }
    }

    /// The corpus flipped the process default between the two models on every visit. Installing JPL Horizons as the
    /// default would shift times built by suites running in parallel (see `DeltaTThreadSafetyTests`), so this captures
    /// JPL Horizons and only ever installs the Espenak-Meeus default. A callback time rebuilt from the default would
    /// then carry the wrong model and a different TT.
    @Test("Callback times keep the captured model when a callback changes the default")
    func callbackTimesKeepCapturedModel() throws {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let rootVisits = Visits()
        let root = try #require(
            try Self.find(.jplHorizons, visits: rootVisits) { u in
                AstronomyConfig.setDeltaTModel(.espenakMeeus)
                return u - 0.375
            })
        let lightVisits = Visits()
        let corrected = try Self.correct(.jplHorizons, visits: lightVisits) { u in
            AstronomyConfig.setDeltaTModel(.espenakMeeus)
            return [1 + 10 * u, 0.2, 0.3]
        }
        #expect(rootVisits.count >= 3)
        #expect(lightVisits.count >= 3)
        for time in rootVisits.times + [root] + lightVisits.times + [corrected.time] {
            #expect(time.deltaTModel == .jplHorizons)
            let captured = AstroTime(ut: time.universalTime, deltaTModel: .jplHorizons)
            #expect(time.terrestrialTime.bitPattern == captured.terrestrialTime.bitPattern)
        }
    }

    // MARK: - Light-time correction

    @Test(
        "A light-time callback that throws stops the iteration at that visit",
        arguments: DeltaTModel.allCases, errorVisits)
    func lightCallbackError(model: DeltaTModel, visit: Int) {
        let start = AstroTime(ut: Self.baseUT, deltaTModel: model)
        let visits = Visits()
        #expect(throws: CallbackFailure(visit: visit)) {
            try AstroSearch.correctLightTravel(at: start) { time in
                try visits.record(time)
                if visits.count == visit { throw CallbackFailure(visit: visit) }
                return Vector3D(x: 1 + 10 * Self.elapsed(time), y: 0.2, z: 0.3, time: time)
            }
        }
        #expect(visits.count == visit)
    }

    /// 173.14463268466929 AU is the double nearest one light-day; the next double above it is rejected.
    @Test(
        "Fixed positions within one light-day return the position",
        arguments: DeltaTModel.allCases,
        [[1.0, 0, 0], [-1, 0, 0], [0, 0, 0], [173.144_632_684_669_26, 0, 0], [173.144_632_684_669_29, 0, 0]])
    func fixedPosition(model: DeltaTModel, xyz: [Double]) throws {
        let start = AstroTime(ut: Self.baseUT, deltaTModel: model)
        let corrected = try Self.correct(model) { _ in xyz }
        #expect([corrected.x, corrected.y, corrected.z].map(\.bitPattern) == xyz.map(\.bitPattern))
        #expect(corrected.time.deltaTModel == model)
        #expect(corrected.time <= start)
    }

    @Test(
        "Positions beyond one light-day are invalid parameters",
        arguments: DeltaTModel.allCases, [Double.infinity, 1e308, 173.144_632_684_669_32])
    func distantPosition(model: DeltaTModel, x: Double) {
        #expect(throws: AstronomyError.invalidParameter) {
            try Self.correct(model) { _ in [x, 0, 0] }
        }
    }

    @Test("A NaN position fails to converge", arguments: DeltaTModel.allCases)
    func nanPosition(model: DeltaTModel) {
        #expect(throws: AstronomyError.noConvergence) {
            try Self.correct(model) { _ in [.nan, 0, 0] }
        }
    }

    @Test("A NaN observation time fails to converge", arguments: DeltaTModel.allCases)
    func nanTime(model: DeltaTModel) {
        #expect(throws: AstronomyError.noConvergence) {
            try Self.correct(model, base: .nan) { _ in [1, 0, 0] }
        }
    }

    /// The fixed-point map x = 1 + 100 dt contracts by only about 0.58 per iteration, so its finite iterates are still
    /// moving when the iteration limit is reached.
    @Test("A finite position that never settles fails to converge", arguments: DeltaTModel.allCases)
    func finiteNonconvergence(model: DeltaTModel) {
        let visits = Visits()
        #expect(throws: AstronomyError.noConvergence) {
            try Self.correct(model, visits: visits) { [1 + 100 * $0, 0, 0] }
        }
        #expect(visits.times.allSatisfy { $0.universalTime.isFinite })
    }

    /// The returned vector carries the time of the final callback, not a time stamped on the callback's vector.
    @Test("A time stamped on the returned position does not change the result", arguments: DeltaTModel.allCases)
    func suppliedVectorTime(model: DeltaTModel) throws {
        let start = AstroTime(ut: Self.baseUT, deltaTModel: model)
        let plain = try Self.correct(model) { _ in [1, 0, 0] }
        let visits = Visits()
        let stamped = try AstroSearch.correctLightTravel(at: start) { time in
            try visits.record(time)
            return Vector3D(x: 1, y: 0, z: 0, time: time.addingDays(10))
        }
        let last = try #require(visits.times.last)
        #expect([stamped.x, stamped.y, stamped.z].map(\.bitPattern) == [plain.x, plain.y, plain.z].map(\.bitPattern))
        #expect(stamped.time.universalTime.bitPattern == plain.time.universalTime.bitPattern)
        #expect(stamped.time.universalTime.bitPattern == last.universalTime.bitPattern)
        #expect(stamped.time.terrestrialTime.bitPattern == last.terrestrialTime.bitPattern)
        #expect(stamped.time.deltaTModel == model)
    }
}
