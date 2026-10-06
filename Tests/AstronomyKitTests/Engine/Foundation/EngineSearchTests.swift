//
//  EngineSearchTests.swift
//  AstronomyKit
//
//  The native ascending-root search.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Search")
struct EngineSearchTests {
    struct CallbackFailure: Error, Equatable {
        let call: Int
    }

    static let base = 20_000.0

    /// A one-day window from `base` under `model`.
    static func window(_ model: DeltaTModel) -> (start: Engine.Time, end: Engine.Time) {
        let start = Engine.Time(ut: base, deltaTModel: model)
        return (start, start.adding(days: 1, fallback: model))
    }

    /// Searches from `start` to `end` with `function` of the days since
    /// `base`, recording every time the search passes it.
    static func search(
        from start: Engine.Time, to end: Engine.Time, tolerance: Double = 0.001, fallback: DeltaTModel = .espenakMeeus,
        _ function: (Double) -> Double
    ) throws -> (root: Engine.Time?, calls: [Engine.Time]) {
        var calls: [Engine.Time] = []
        let root = try Engine.Search.ascendingRoot(
            from: start, to: end, toleranceSeconds: tolerance, fallback: fallback
        ) { time in
            calls.append(time)
            return function(time.ut - base)
        }
        return (root, calls)
    }

    static func step(_ u: Double) -> Double { u < 0.375 ? -1 : 1 }

    /// A line, a curve with a second root outside its bracket, and a step,
    /// each with an ascending root that a 0.2 s tolerance accepts.
    static let functions: [@Sendable (Double) -> Double] = [
        { $0 - 0.375 }, { ($0 - 0.25) * ($0 - 0.75) }, step,
    ]

    // MARK: - Direction

    @Test(
        "An ascending root is found within the tolerance",
        arguments: DeltaTModel.allCases, [0.001, 1.0])
    func ascendingRoot(model: DeltaTModel, tolerance: Double) throws {
        let (start, end) = Self.window(model)
        for target in [0.001, 0.375, 0.5, 0.999] {
            let root = try #require(try Self.search(from: start, to: end, tolerance: tolerance) { $0 - target }.root)
            #expect(abs(root.ut - Self.base - target) * 86_400 < tolerance, "root at \(target)")
            #expect((start.ut...end.ut).contains(root.ut))
        }
    }

    @Test("A curved ascending root is found within the tolerance", arguments: DeltaTModel.allCases)
    func curvedRoot(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let root = try #require(try Self.search(from: start, to: end) { $0 * $0 - 0.140625 }.root)
        #expect(abs(root.ut - Self.base - 0.375) * 86_400 < 0.001)
    }

    /// Both ends of the window are positive; subdivision finds the
    /// ascending root at 0.75 and not the descending one at 0.25.
    @Test("An ascending root between two positive ends is found", arguments: DeltaTModel.allCases)
    func ascendingRootInside(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let root = try #require(try Self.search(from: start, to: end) { ($0 - 0.25) * ($0 - 0.75) }.root)
        #expect(abs(root.ut - Self.base - 0.75) * 86_400 < 0.001)
    }

    @Test(
        "A descending root returns nil",
        arguments: DeltaTModel.allCases, [0.001, 1.0, -0.001, Double.infinity])
    func descendingRoot(model: DeltaTModel, tolerance: Double) throws {
        let (start, end) = Self.window(model)
        for target in [0.001, 0.375, 0.5, 0.999] {
            #expect(try Self.search(from: start, to: end, tolerance: tolerance) { target - $0 }.root == nil)
        }
        let curved = try Self.search(from: start, to: end, tolerance: tolerance) { 0.140625 - $0 * $0 }
        #expect(curved.root == nil)
    }

    @Test(
        "A window given end first finds the ascending root and not the descending one",
        arguments: DeltaTModel.allCases)
    func reversedWindow(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let ascending = try #require(try Self.search(from: end, to: start) { $0 - 0.375 }.root)
        #expect(abs(ascending.ut - Self.base - 0.375) * 86_400 < 0.001)
        #expect(try Self.search(from: end, to: start) { 0.375 - $0 }.root == nil)
    }

    /// The two reproductions in #142, which the C engine reported as roots
    /// before local patch 20.
    @Test("The descending and short constant windows from #142 return nil", arguments: DeltaTModel.allCases)
    func issue142(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        #expect(try Self.search(from: start, to: end) { 0.375 - $0 }.root == nil)
        let shortEnd = start.adding(days: 1e-10, fallback: model)
        #expect(try Self.search(from: start, to: shortEnd) { _ in 1 }.root == nil)
    }

    // MARK: - Absent roots

    @Test(
        "A function that keeps one sign returns nil",
        arguments: DeltaTModel.allCases, [-1.0, 0, 1, -.greatestFiniteMagnitude, .greatestFiniteMagnitude])
    func constant(model: DeltaTModel, value: Double) throws {
        let start = Engine.Time(ut: Self.base, deltaTModel: model)
        for days in [1.0, 1e-10, 0] {
            let end = start.adding(days: days, fallback: model)
            for tolerance in [0.001, 1.0, -0.001, Double.infinity] {
                let result = try Self.search(from: start, to: end, tolerance: tolerance) { _ in value }
                #expect(result.root == nil, "window \(days), tolerance \(tolerance)")
            }
        }
    }

    @Test("A root outside the window returns nil", arguments: DeltaTModel.allCases)
    func rootOutside(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        #expect(try Self.search(from: start, to: end) { $0 + 100 }.root == nil)
        #expect(try Self.search(from: start, to: end) { $0 - 1.5 }.root == nil)
    }

    @Test(
        "A function that is not finite returns nil",
        arguments: DeltaTModel.allCases, [Double.nan, .infinity, -.infinity])
    func nonfiniteValue(model: DeltaTModel, value: Double) throws {
        let (start, end) = Self.window(model)
        #expect(try Self.search(from: start, to: end) { _ in value }.root == nil)
    }

    @Test("A start that is not finite returns nil", arguments: DeltaTModel.allCases, [Double.nan, .infinity])
    func nonfiniteStart(model: DeltaTModel, ut: Double) throws {
        let start = Engine.Time(ut: ut, deltaTModel: model)
        let end = start.adding(days: 1, fallback: model)
        #expect(try Self.search(from: start, to: end) { $0 - 0.375 }.root == nil)
    }

    // MARK: - Endpoints

    /// With an infinite tolerance the search returns the first midpoint
    /// exactly when the ends form an ascending bracket, so these cases show
    /// how a zero at either end counts.
    @Test(
        "A zero end makes an ascending bracket only when the other end gives the direction",
        arguments: DeltaTModel.allCases)
    func zeroEnds(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let midpoint = start.adding(days: (end.tt - start.tt) / 2, fallback: model)
        // (value at the earlier end, value at the later end, ascending bracket)
        let cases: [(Double, Double, Bool)] = [
            (0, 1, true), (-1, 0, true), (-1, 1, true),
            (0, 0, false), (0, -1, false), (1, 0, false), (1, -1, false),
        ]
        for (earlier, later, bracket) in cases {
            var calls = 0
            let root = try Engine.Search.ascendingRoot(
                from: start, to: end, toleranceSeconds: .infinity, fallback: model
            ) { time in
                calls += 1
                switch time.ut {
                case start.ut: return earlier
                case end.ut: return later
                default: return 0.5
                }
            }
            if bracket {
                #expect(root?.ut == midpoint.ut, "\(earlier), \(later)")
                #expect(calls == 2)
            } else {
                #expect(root == nil, "\(earlier), \(later)")
            }
        }
    }

    @Test("A root at the later end is found from either direction", arguments: DeltaTModel.allCases)
    func rootAtLaterEnd(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        for (first, second) in [(start, end), (end, start)] {
            let root = try #require(try Self.search(from: first, to: second) { $0 - (end.ut - Self.base) }.root)
            #expect(abs(root.ut - end.ut) * 86_400 < 0.001)
            #expect(root.ut <= end.ut)
        }
    }

    /// Zero at both ends is no bracket, but the negative midpoint makes the
    /// later half one.
    @Test(
        "A function zero at both ends and negative between them converges to the later end",
        arguments: DeltaTModel.allCases)
    func zeroAtBothEnds(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let span = end.ut - Self.base
        let root = try #require(try Self.search(from: start, to: end) { $0 * ($0 - span) }.root)
        #expect(abs(root.ut - end.ut) * 86_400 < 0.001)
    }

    /// The function never changes sign, but it rises through zero at the
    /// later end. The root is a tangent, so the tolerance is 1 s: at 1 ms the
    /// error estimate misses by up to 0.4 ms, and under JPL Horizons the
    /// search runs out of passes.
    @Test(
        "A function negative up to the later end and zero there has a root at that end",
        arguments: DeltaTModel.allCases)
    func touchesZeroAtLaterEnd(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let span = end.ut - Self.base
        for (first, second) in [(start, end), (end, start)] {
            let result = try Self.search(from: first, to: second, tolerance: 1) { -($0 - span) * ($0 - span) }
            let root = try #require(result.root)
            #expect(abs(root.ut - end.ut) * 86_400 < 1)
        }
    }

    // MARK: - Calls

    @Test("The first two calls receive the start and the end unchanged", arguments: DeltaTModel.allCases)
    func firstCalls(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        for (first, second) in [(start, end), (end, start)] {
            let calls = try Self.search(from: first, to: second) { $0 - 0.375 }.calls
            try #require(calls.count >= 2)
            for (received, sent) in zip(calls.prefix(2), [first, second]) {
                #expect(received.ut.bitPattern == sent.ut.bitPattern)
                #expect(received.tt.bitPattern == sent.tt.bitPattern)
                #expect(received.deltaTModel == model)
            }
        }
    }

    @Test(
        "Every time passed to the function has the start's model, whatever the fallback",
        arguments: DeltaTModel.allCases, DeltaTModel.allCases)
    func capturedModel(model: DeltaTModel, fallback: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        for function in Self.functions {
            let result = try Self.search(from: start, to: end, tolerance: 0.2, fallback: fallback, function)
            let root = try #require(result.root)
            #expect(result.calls.count >= 3)
            for time in result.calls + [root] {
                #expect(time.deltaTModel == model)
                #expect(time.tt.bitPattern == Engine.Time(ut: time.ut, deltaTModel: model).tt.bitPattern)
            }
        }
    }

    /// A linear function needs four calls, so the seventh call uses a step
    /// function, which keeps bisecting.
    @Test(
        "An error from the function propagates unchanged and ends the search",
        arguments: DeltaTModel.allCases, [1, 2, 3, 4, 7])
    func throwingFunction(model: DeltaTModel, failingCall: Int) {
        let (start, end) = Self.window(model)
        var calls = 0
        #expect(throws: CallbackFailure(call: failingCall)) {
            try Engine.Search.ascendingRoot(from: start, to: end, toleranceSeconds: 0.001, fallback: model) { time in
                calls += 1
                if calls == failingCall { throw CallbackFailure(call: failingCall) }
                let u = time.ut - Self.base
                return failingCall < 7 ? u - 0.375 : Self.step(u)
            }
        }
        #expect(calls == failingCall)
    }

    @Test("An AstronomyError from the function is not replaced", arguments: [AstronomyError.badTime, .noConvergence])
    func throwingAstronomyError(error: AstronomyError) {
        let (start, end) = Self.window(.espenakMeeus)
        var calls = 0
        #expect(throws: error) {
            try Engine.Search.ascendingRoot(from: start, to: end, toleranceSeconds: 0.001, fallback: .espenakMeeus) {
                calls += 1
                if calls == 3 { throw error }
                return $0.ut - Self.base - 0.375
            }
        }
        #expect(calls == 3)
    }

    // MARK: - Tolerance and convergence

    @Test("A negative tolerance acts as its magnitude", arguments: DeltaTModel.allCases)
    func negativeTolerance(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        for function in Self.functions {
            let positive = try Self.search(from: start, to: end, tolerance: 0.2, function)
            let negative = try Self.search(from: start, to: end, tolerance: -0.2, function)
            #expect(negative.root?.ut.bitPattern == positive.root?.ut.bitPattern)
            #expect(negative.calls.map(\.ut.bitPattern) == positive.calls.map(\.ut.bitPattern))
        }
    }

    @Test("A step meets a 0.2 s tolerance at the step", arguments: DeltaTModel.allCases)
    func stepCoarseTolerance(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let root = try #require(try Self.search(from: start, to: end, tolerance: 0.2, Self.step).root)
        #expect(abs(root.ut - Self.base - 0.375) * 86_400 <= 0.2)
    }

    /// Twenty halvings of one day leave 0.08 s, and interpolation cannot
    /// narrow a step. Each pass calls the function at the midpoint and at
    /// the interpolated root, so the search makes 2 + 20 × 2 = 42 calls and
    /// throws before a 21st pass. A limit of 19 or 21 passes gives 40 or 44.
    @Test("A step cannot meet a 1 ms tolerance in 20 passes", arguments: DeltaTModel.allCases)
    func stepNonconvergence(model: DeltaTModel) {
        let (start, end) = Self.window(model)
        for (first, second) in [(start, end), (end, start)] {
            var calls = 0
            #expect(throws: AstronomyError.noConvergence) {
                try Engine.Search.ascendingRoot(from: first, to: second, toleranceSeconds: 0.001, fallback: model) {
                    time -> Double in
                    calls += 1
                    return Self.step(time.ut - Self.base)
                }
            }
            #expect(calls == 42)
        }
        #expect(Engine.Search.iterationLimit == 20)
    }

    @Test("A zero or NaN tolerance never converges", arguments: DeltaTModel.allCases, [0, Double.nan])
    func unusableTolerance(model: DeltaTModel, tolerance: Double) {
        let (start, end) = Self.window(model)
        #expect(throws: AstronomyError.noConvergence) {
            try Self.search(from: start, to: end, tolerance: tolerance) { $0 - 0.375 }
        }
    }

    @Test("A root with zero slope still converges near it", arguments: DeltaTModel.allCases)
    func flatCubic(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let cubic = try Self.search(from: start, to: end) { ($0 - 0.375) * ($0 - 0.375) * ($0 - 0.375) }
        let root = try #require(cubic.root)
        #expect(abs(root.ut - Self.base - 0.375) * 86_400 < 0.01)
    }

    // MARK: - Narrowed window

    /// Rises through zero at 0.375, steeply enough that the interpolated
    /// root's estimated error falls below a tenth of the half-window.
    static func rising(_ u: Double) -> Double { exp(5 * (u - 0.375)) - 1 }

    /// Whether `left` and `right` are a window centered on `center`, as the
    /// search builds around an interpolated root.
    static func isWindow(around center: Engine.Time, left: Engine.Time, right: Engine.Time) -> Bool {
        left.ut < center.ut && center.ut < right.ut
            && abs((center.ut - left.ut) - (right.ut - center.ut)) < 1e-12
    }

    /// The calls of a forward search for the root of ``rising(_:)``, by
    /// number from 1:
    ///
    /// - 1 and 2 are the bounds, 3 the midpoint 0.5, 4 the interpolated root.
    /// - 5 and 6 are a narrower window around 4. Both values are positive,
    ///   so the window is not taken and the search bisects: 7 is the
    ///   midpoint of 0 and 0.5, and 8 its interpolated root.
    /// - 9 and 10 are a window around 8 that brackets the root. It replaces
    ///   the search window, and 8's value stands in for its midpoint, so the
    ///   next pass makes no midpoint call: 11 is the interpolated root.
    /// - 12 and 13 narrow the window around 11 again, and 14, the next
    ///   interpolated root, is close enough to return.
    @Test("A narrower window around an interpolated root replaces the window", arguments: DeltaTModel.allCases)
    func narrowedWindow(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let result = try Self.search(from: start, to: end, Self.rising)
        let calls = result.calls
        try #require(calls.count == 14)
        func call(_ number: Int) -> Engine.Time { calls[number - 1] }

        for (center, left, right) in [(4, 5, 6), (8, 9, 10), (11, 12, 13)] {
            let window = Self.isWindow(around: call(center), left: call(left), right: call(right))
            #expect(window, "calls \(left), \(right)")
        }
        // The rejected window: the search bisects the half from 0 to 0.5.
        #expect(Self.rising(call(5).ut - Self.base) > 0)
        let bisected = start.adding(days: (call(3).tt - start.tt) / 2, fallback: model)
        #expect(call(7).ut.bitPattern == bisected.ut.bitPattern)
        // Each later call lies inside the window that replaced the search's.
        for number in 11...14 {
            #expect(call(9).ut < call(number).ut && call(number).ut < call(10).ut, "call \(number)")
        }
        #expect(call(12).ut < call(14).ut && call(14).ut < call(13).ut)

        let root = try #require(result.root)
        #expect(root.ut.bitPattern == call(14).ut.bitPattern)
        #expect(abs(root.ut - Self.base - 0.375) * 86_400 < 0.001)
    }

    /// The narrower window needs its estimated error below a tenth of the
    /// half-window, which is negative when the window runs backward.
    @Test("A window given end first is never narrowed", arguments: DeltaTModel.allCases)
    func reversedWindowNotNarrowed(model: DeltaTModel) throws {
        let (start, end) = Self.window(model)
        let result = try Self.search(from: end, to: start, Self.rising)
        let calls = result.calls
        for index in calls.indices.dropLast(2) {
            #expect(!Self.isWindow(around: calls[index], left: calls[index + 1], right: calls[index + 2]))
        }
        let root = try #require(result.root)
        #expect(abs(root.ut - Self.base - 0.375) * 86_400 < 0.001)
    }

    @Test(
        "An error from a call at a narrower window's end propagates unchanged",
        arguments: DeltaTModel.allCases, [5, 6, 9, 10, 12, 13])
    func throwingNarrowedWindow(model: DeltaTModel, failingCall: Int) {
        let (start, end) = Self.window(model)
        var calls = 0
        #expect(throws: CallbackFailure(call: failingCall)) {
            try Engine.Search.ascendingRoot(from: start, to: end, toleranceSeconds: 0.001, fallback: model) {
                time -> Double in
                calls += 1
                if calls == failingCall { throw CallbackFailure(call: failingCall) }
                return Self.rising(time.ut - Self.base)
            }
        }
        #expect(calls == failingCall)
    }

    // MARK: - Interpolation

    @Test("Interpolation finds the root of a line or a parabola inside the window")
    func quadraticRoot() throws {
        // A line through (-1, -1), (0, 0), (1, 1) mapped to tm = 10, dt = 2.
        let line = try #require(Engine.Search.quadraticRoot(tm: 10, dt: 2, fa: -1, fm: 0, fb: 1))
        #expect(line.ut == 10)
        #expect(line.slope == 0.5)
        // x² - 0.25 crosses zero at -0.5 and 0.5: two roots in range.
        #expect(Engine.Search.quadraticRoot(tm: 0, dt: 1, fa: 0.75, fm: -0.25, fb: 0.75) == nil)
        // x² + x - 0.75 = (x + 1.5)(x - 0.5): one root in range, at 0.5.
        let parabola = try #require(Engine.Search.quadraticRoot(tm: 0, dt: 1, fa: -0.75, fm: -0.75, fb: 1.25))
        #expect(parabola.ut == 0.5)
        #expect(parabola.slope == 2)
        // Flat, tangent, or out of range.
        #expect(Engine.Search.quadraticRoot(tm: 0, dt: 1, fa: 1, fm: 1, fb: 1) == nil)
        #expect(Engine.Search.quadraticRoot(tm: 0, dt: 1, fa: 1, fm: 0, fb: 1) == nil)
        #expect(Engine.Search.quadraticRoot(tm: 0, dt: 1, fa: 2, fm: 3, fb: 4) == nil)
    }
}
