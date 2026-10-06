//
//  EngineSearchTests.swift
//  AstronomyKit
//
//  The native ascending-root search.
//

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
    /// narrow a step.
    @Test("A step cannot meet a 1 ms tolerance in 20 passes", arguments: DeltaTModel.allCases)
    func stepNonconvergence(model: DeltaTModel) {
        let (start, end) = Self.window(model)
        #expect(throws: AstronomyError.noConvergence) {
            try Self.search(from: start, to: end, Self.step)
        }
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
