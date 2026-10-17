//
//  EngineChironTests.swift
//  AstronomyKit
//
//  Chiron's table, its supported span, and its states against JPL Horizons.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Chiron")
struct EngineChironTests {
    typealias Chiron = Engine.Chiron
    typealias Horizons = PlutoSegmentSuites.EnginePlutoHorizonsTests

    static func length(_ v: SIMD3<Double>) -> Double { EngineGravityTests.length(v) }

    static func time(tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .espenakMeeus) }

    /// A time with both scales as given, which need not agree with the model.
    static func pair(ut: Double, tt: Double) -> Engine.Time {
        Engine.Time.fromPair(ut: ut, tt: tt, deltaTModel: .espenakMeeus)
    }

    /// The start of the span, 1900-01-01 00:00 UT, as TT.
    static let earliestTT = Engine.Time(ut: Chiron.earliestUT, deltaTModel: .espenakMeeus).tt

    // MARK: - Table

    /// 2,403 records of 38 days from 1899-12-31 00:00 TDB, which leaves
    /// about a day before the span's start for light time (under three hours
    /// at Chiron's distance) and two days after its end.
    @Test("The table covers the span with a day to spare at each end")
    func coverage() {
        let table = Chiron.table
        #expect(table.start == -36_525.5)
        #expect(table.recordDays == 38)
        #expect(table.recordCount == 2_403)
        #expect(table.degreeCount == 16)
        #expect(table.coefficients.count == 2_403 * 3 * 16)
        let end = table.start + Double(table.recordCount) * table.recordDays
        #expect(table.start <= Self.earliestTT - 0.99)
        #expect(end >= Chiron.latestTT + 1.99)
    }

    /// `Scripts/chiron-data/report.json` records the largest jump between
    /// records as 0.136 km and 0.000217 km per day. Each record is read just
    /// before its end and carried to it at its velocity, then compared with
    /// the next record's start.
    @Test("Adjacent records meet within 0.2 km and 0.001 km per day")
    func seams() {
        let table = Chiron.table
        let step = 1e-6
        var position = 0.0
        var velocity = 0.0
        for record in 1..<table.recordCount {
            let seam = table.start + Double(record) * table.recordDays
            guard let before = table.evaluate(tdb: seam - step), let after = table.evaluate(tdb: seam) else {
                Issue.record("record \(record) is missing")
                return
            }
            position = max(position, Self.length(before.position + before.velocity * step - after.position))
            velocity = max(velocity, Self.length(before.velocity - after.velocity))
        }
        #expect(position <= 0.2, "\(position) km")
        #expect(velocity <= 0.001, "\(velocity) km/day")
    }

    // MARK: - Against JPL Horizons

    /// Horizons' Chiron from `sources/horizons/chiron-anchor-vector.json`
    /// and `chiron-vector.json`: 1900, the 2000–2040 decades with a day
    /// either side of their midpoints, 2100 and 2150. None is a table source
    /// epoch, and each was requested as a time list rather than the table's
    /// daily series. Horizons' small-body integration varies slightly with
    /// the query, so the measured gap, 2.3 km and 0.0011 km per day at most,
    /// exceeds the 0.13 km of the heldout epochs in
    /// `Scripts/chiron-data/report.json`.
    @Test("Within 5 km and 0.01 km per day of every recorded Horizons vector, 1900 to 2150")
    func horizonsVectors() throws {
        let vectors = IndependentReferenceArchive.shared.vectors.filter {
            $0.body == "chiron" || $0.body == "chiron-anchor"
        }
        #expect(vectors.count == 22)
        #expect(vectors.contains { $0.julianDateTDB == 2_415_020.5 })
        #expect(vectors.contains { $0.julianDateTDB == 2_506_331.5 })
        for reference in vectors {
            let state = try Chiron.heliocentricState(at: Self.time(tt: Horizons.tt(reference)))
            let km = Self.length(state.positionVector - Horizons.expected(reference)) * Engine.kilometersPerAU
            let velocity = EngineMoonStatesTests.eqj(reference.velocityAUPerDay)
            let kmPerDay = Self.length(state.velocityVector - velocity) * Engine.kilometersPerAU
            #expect(km <= 5, "\(reference.tdb): \(km) km")
            #expect(kmPerDay <= 0.01, "\(reference.tdb): \(kmPerDay) km/day")
        }
    }

    @Test("The velocity is the derivative of the position per TT day")
    func velocity() throws {
        let h = 1.0 / 64
        for tt in [-36_000.25, -1_000.5, 9_500.75, 54_000.125] {
            func position(_ offset: Double) throws -> SIMD3<Double> {
                try Chiron.heliocentricState(at: Self.time(tt: tt + offset)).positionVector
            }
            let difference =
                (try position(-2 * h) - 8 * position(-h) + 8 * position(h) - position(2 * h)) / (12 * h)
            let state = try Chiron.heliocentricState(at: Self.time(tt: tt))
            #expect(Self.length(state.velocityVector - difference) <= 1e-11, "\(tt)")
        }
    }

    // MARK: - Span

    @Test("The span is 1900-01-01 00:00 UT through 2150-01-01 00:00 UTC; outside it, badTime")
    func span() throws {
        #expect(Chiron.earliestUT == -36_524.5)
        // 2150-01-01 00:00 UTC is 69.184 s later in TT, the last announced offset.
        #expect(abs(Chiron.latestTT - (54_786.5 + 69.184 / 86_400)) < 1e-9)
        // The span is checked on TT, so the start is stepped back in TT; see
        // `startAfterDeltaTDrop` for UTs just before it.
        let outside = [
            Self.time(tt: Self.earliestTT.nextDown), Self.time(tt: Chiron.latestTT.nextUp), Engine.Time.invalid,
            Engine.Time(ut: Chiron.earliestUT, tt: .nan, deltaTModel: .espenakMeeus),
        ]
        for time in outside {
            #expect(throws: AstronomyError.badTime) { try Chiron.checkSupported(time) }
            #expect(throws: AstronomyError.badTime) { _ = try Chiron.heliocentricState(at: time) }
        }
        try Chiron.checkSupported(Engine.Time(ut: Chiron.earliestUT, deltaTModel: .jplHorizons))
        _ = try Chiron.heliocentricState(at: Self.time(tt: Self.earliestTT))
        _ = try Chiron.heliocentricState(at: Self.time(tt: Chiron.latestTT))
    }

    /// Espenak-Meeus Delta T is -2.7016 s just before 1900.0, from the
    /// 1860-1900 polynomial, and -2.79 s at it, from the 1900-1920 one. Both
    /// models use those pieces there. A UT up to 88.4 ms before 1900-01-01
    /// 00:00 therefore has a TT after the start's, and is accepted.
    @Test("UTs up to 88 ms before the start are accepted, after Delta T drops at 1900.0")
    func startAfterDeltaTDrop() throws {
        for model in DeltaTModel.allCases {
            let inside = Engine.Time(ut: Chiron.earliestUT - 0.088 / 86_400, deltaTModel: model)
            let outside = Engine.Time(ut: Chiron.earliestUT - 0.089 / 86_400, deltaTModel: model)
            try Chiron.checkSupported(inside)
            #expect(throws: AstronomyError.badTime) { try Chiron.checkSupported(outside) }
        }
    }

    /// A pair rebuilt from recorded scales need not agree with its model.
    /// The table is read at TT, so the span is checked on TT alone.
    @Test("A time is checked by its TT; its UT neither passes nor blocks it")
    func spanChecksTT() throws {
        // 2000-01-01 UT with a TT 2,700 years earlier, then each end.
        let outside = [
            Self.pair(ut: 0, tt: -1_000_000),
            Self.pair(ut: 0, tt: Self.earliestTT.nextDown),
            Self.pair(ut: 0, tt: Chiron.latestTT.nextUp),
        ]
        for time in outside {
            #expect(throws: AstronomyError.badTime) { try Chiron.checkSupported(time) }
            #expect(throws: AstronomyError.badTime) { _ = try Chiron.heliocentricState(at: time) }
        }
        try Chiron.checkSupported(Self.pair(ut: 0, tt: Self.earliestTT))
        try Chiron.checkSupported(Self.pair(ut: 1_000_000, tt: Chiron.latestTT))

        let state = try Chiron.heliocentricState(at: Self.pair(ut: -1_000_000, tt: 0))
        let consistent = try Chiron.heliocentricState(at: Self.time(tt: 0))
        #expect(state.positionVector == consistent.positionVector)
        #expect(state.velocityVector == consistent.velocityVector)
        #expect(state.time.ut == -1_000_000)
    }

    /// The light-time evaluation may precede the span, as it does in the
    /// first hours of 1900, but not the table, which starts a day earlier.
    @Test("An internal light-time state needs a supported observation and the table", arguments: DeltaTModel.allCases)
    func lightTimeObservationGuard(model: DeltaTModel) throws {
        let observation = Engine.Time(ut: Chiron.earliestUT + 1.0 / 24, deltaTModel: model)
        let backdated = observation.adding(days: -2.0 / 24)
        let state = try Chiron.heliocentricState(forLightTimeAt: backdated, observedAt: observation)
        #expect(state.time.tt == backdated.tt)

        let before = Engine.Time(
            tt: Engine.Time(ut: Chiron.earliestUT, deltaTModel: model).tt.nextDown, deltaTModel: model)
        #expect(throws: AstronomyError.badTime) {
            _ = try Chiron.heliocentricState(forLightTimeAt: backdated, observedAt: before)
        }
        for evaluation in [observation.adding(days: 1.0 / 24), observation.adding(days: -2)] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Chiron.heliocentricState(forLightTimeAt: evaluation, observedAt: observation)
            }
        }
    }

    @Test("The state carries the caller's time, scales and model")
    func callerTime() throws {
        let time = Engine.Time(ut: 3, deltaTModel: .jplHorizons)
        let state = try Chiron.heliocentricState(at: time)
        #expect(state.time.ut == time.ut && state.time.tt == time.tt && state.time.deltaTModel == .jplHorizons)
    }

    @Test("Calls on separate threads get the serial results")
    func concurrent() throws {
        let instants = [-20_000.5, 10_000.25, 40_000.0]
        let serial: [[UInt64]] = try instants.map { tt in
            let state = try Chiron.heliocentricState(at: Self.time(tt: tt))
            return [state.x, state.y, state.z, state.vx, state.vy, state.vz].map(\.bitPattern)
        }
        let mismatches = EngineBoundedCacheTests.Counter()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let slot = index % instants.count
            guard let state = try? Chiron.heliocentricState(at: Self.time(tt: instants[slot])) else {
                mismatches.record()
                return
            }
            let bits = [state.x, state.y, state.z, state.vx, state.vy, state.vz].map(\.bitPattern)
            if bits != serial[slot] { mismatches.record() }
        }
        #expect(mismatches.count == 0)
    }
}
