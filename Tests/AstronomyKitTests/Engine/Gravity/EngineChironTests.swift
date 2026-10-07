//
//  EngineChironTests.swift
//  AstronomyKit
//
//  Chiron's anchors, supported span, anchor choice, reuse, and the states
//  against JPL Horizons.
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

    /// Horizons' Chiron from `sources/horizons/chiron-anchor-vector.json`.
    static let vectors = IndependentReferenceArchive.shared.vectors.filter { $0.body == "chiron-anchor" }

    static func reference(_ julianDateTDB: Double) throws -> IndependentReferenceArchive.Vector {
        try #require(vectors.first { $0.julianDateTDB == julianDateTDB })
    }

    /// Kilometres and arcseconds between the engine's state at a Horizons
    /// epoch and Horizons' position, and the velocity error over the speed.
    static func errors(
        _ reference: IndependentReferenceArchive.Vector
    ) throws -> (km: Double, arcseconds: Double, velocity: Double) {
        let state = try Chiron.heliocentricState(at: time(tt: Horizons.tt(reference)))
        let km = length(state.positionVector - Horizons.expected(reference)) * Engine.kilometersPerAU
        let arcseconds = try Horizons.arcminutes(state.positionVector, reference) * 60
        let velocity = EngineMoonStatesTests.eqj(reference.velocityAUPerDay)
        return (km, arcseconds, length(state.velocityVector - velocity) / length(velocity))
    }

    /// True in an optimized build. The 2150 check integrates 50 years
    /// against the planets' full series, which takes about 30 s optimized
    /// and many minutes in Debug.
    static let optimized: Bool = {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }()

    // MARK: - Anchors and span

    static let anchorDates = [2_451_544.5, 2_455_197.5, 2_458_849.5, 2_462_502.5, 2_466_154.5]

    /// The anchors are Horizons states as AstronomyKit recorded them years
    /// ago. Horizons' current solution moves them by 0.6 to 4.1 km and
    /// their velocities by at most 1.2e-11 AU per day.
    @Test("The anchors match Horizons' current states within 5 km, at 00:00 TDB")
    func anchors() throws {
        #expect(Chiron.anchors.count == 5)
        #expect(Self.vectors.count == 19)
        for (anchor, date) in zip(Chiron.anchors, Self.anchorDates) {
            let reference = try Self.reference(date)
            let km = Self.length(anchor.position - Horizons.expected(reference)) * Engine.kilometersPerAU
            let velocity = Self.length(anchor.velocity - EngineMoonStatesTests.eqj(reference.velocityAUPerDay))
            #expect(km <= 5, "\(reference.tdb): \(km) km")
            #expect(velocity <= 2e-11, "\(reference.tdb): \(velocity)")
            // 00:00 TDB is within 1.7 ms (2e-8 day) of 00:00 TT.
            #expect(abs(anchor.tt - (date - 2_451_545)) <= 2e-8)
        }
    }

    @Test("At an anchor's time the state is the anchor")
    func atAnchor() throws {
        for anchor in Chiron.anchors {
            let state = try Chiron.heliocentricState(at: Self.time(tt: anchor.tt))
            #expect(Self.length(state.positionVector - anchor.position) <= 1e-14)
            #expect(Self.length(state.velocityVector - anchor.velocity) <= 1e-17)
        }
    }

    @Test("The span is 1900-01-01 00:00 UT through 2150-01-01 00:00 UTC; outside it, badTime")
    func span() throws {
        #expect(Chiron.earliestUT == -36_524.5)
        // 2150-01-01 00:00 UTC is 69.184 s later in TT, the last announced offset.
        #expect(abs(Chiron.latestTT - (54_786.5 + 69.184 / 86_400)) < 1e-9)
        let outside = [
            Engine.Time(ut: Chiron.earliestUT.nextDown, deltaTModel: .espenakMeeus),
            Self.time(tt: Chiron.latestTT.nextUp), Engine.Time.invalid,
            Engine.Time(ut: Chiron.earliestUT, tt: .nan, deltaTModel: .espenakMeeus),
        ]
        for time in outside {
            #expect(throws: AstronomyError.badTime) { try Chiron.checkSupported(time) }
            #expect(throws: AstronomyError.badTime) { _ = try Chiron.heliocentricState(at: time) }
        }
        try Chiron.checkSupported(Engine.Time(ut: Chiron.earliestUT, deltaTModel: .jplHorizons))
        try Chiron.checkSupported(Self.time(tt: Chiron.latestTT))
    }

    @Test("The nearest anchor is chosen, the earlier one on an exact tie")
    func nearestAnchor() {
        let tts = Chiron.anchors.map(\.tt)
        var ties = 0
        for index in 0..<4 {
            let midpoint = (tts[index] + tts[index + 1]) / 2
            #expect(Chiron.nearestAnchor(tt: midpoint - 1e-6) == index)
            #expect(Chiron.nearestAnchor(tt: midpoint + 1e-6) == index + 1)
            // Rounding can leave the computed midpoint an ulp nearer one
            // side; look a few ulps around it for times exactly as far from
            // both anchors.
            var tt = midpoint
            for _ in 0..<4 { tt = tt.nextDown }
            for _ in 0..<9 {
                if abs(tts[index] - tt) == abs(tts[index + 1] - tt) {
                    #expect(Chiron.nearestAnchor(tt: tt) == index, "tie at \(tt)")
                    ties += 1
                }
                tt = tt.nextUp
            }
        }
        #expect(ties > 0)
        #expect(Chiron.nearestAnchor(tt: -40_000) == 0)
        #expect(Chiron.nearestAnchor(tt: 60_000) == 4)
    }

    // MARK: - Against JPL Horizons

    /// Within five years of an anchor, at the four midpoints with a day
    /// either side, the state is within 1,200 km and 0.09″ of Horizons and
    /// within 2.3e-6 of the speed. The bounds, 2,000 km, 0.5″ and 5e-6, are
    /// measured, not published.
    @Test("Where the nearest anchor changes, within 2,000 km and 0.5″ of Horizons")
    func transitions() throws {
        let transitions = Self.vectors.filter { (reference) -> Bool in
            let date: Double = reference.julianDateTDB
            let inside: Bool = date > 2_416_000.0 && date < 2_500_000.0
            return inside && !Self.anchorDates.contains(date)
        }
        #expect(transitions.count == 12)
        for reference in transitions {
            let (km, arcseconds, velocity) = try Self.errors(reference)
            #expect(km <= 2_000, "\(reference.tdb): \(km) km")
            #expect(arcseconds <= 0.5, "\(reference.tdb): \(arcseconds)″")
            #expect(velocity <= 5e-6, "\(reference.tdb): \(velocity)")
        }
    }

    /// 110 years on from the 2040 anchor, 3.1″ and 22,000 km from Horizons.
    @Test("At the end of the span, 2150-01-01, within 1′ of Horizons", .enabled(if: optimized))
    func spanEnd() throws {
        let (_, arcseconds, _) = try Self.errors(try Self.reference(2_506_331.5))
        #expect(arcseconds <= 60, "\(arcseconds)″")
    }

    /// The `chiron-vector` rows that `AuditValidationTests.chironPosition`
    /// reads, with its archived 0.01 AU. The engine is 254,000 km (0.0017
    /// AU) off in 1900 and 102,000 km in 2100. 1900-01-01 is also the start
    /// of the span: there, a century back from the 2000 anchor, the state
    /// is 32″ from Horizons, within the 1′ the public documentation gives
    /// for Chiron, which it states for ±5 years of an anchor.
    @Test("The AuditValidationTests chiron-vector rows within their 0.01 AU, and 1900 within 1′")
    func auditRows() throws {
        let rows = IndependentReferenceArchive.shared.vectors.filter { $0.body == "chiron" }
        #expect(rows.count == 3)
        for reference in rows {
            let tolerance = try #require(reference.sanityToleranceAU)
            let (km, arcseconds, _) = try Self.errors(reference)
            #expect(km / Engine.kilometersPerAU <= tolerance, "\(reference.tdb): \(km) km")
            if reference.julianDateTDB == 2_415_020.5 {
                #expect(arcseconds <= 60, "\(arcseconds)″")
            }
        }
    }

    // MARK: - Reuse

    @Test("A sequence reuses its simulation within the path budget and starts again beyond it")
    func reuse() throws {
        let sequence = Chiron.ReusableSimulation()
        let anchor = Chiron.anchors[1].tt
        func path(_ expected: Double) -> Bool { abs(sequence.pathDays - expected) < 1e-6 }
        _ = try sequence.heliocentricState(at: Self.time(tt: anchor + 100))
        #expect(sequence.anchorIndex == 1 && path(100))
        // 30 days back: 130 ≤ max(2 × 70, 365), so the simulation steps on.
        _ = try sequence.heliocentricState(at: Self.time(tt: anchor + 70))
        #expect(sequence.anchorIndex == 1 && path(130))
        // 400 days on: 530 ≤ max(2 × 470, 365), still reused.
        _ = try sequence.heliocentricState(at: Self.time(tt: anchor + 470))
        #expect(path(530))
        // Back to 10 days: 990 > max(2 × 10, 365), so a fresh start.
        _ = try sequence.heliocentricState(at: Self.time(tt: anchor + 10))
        #expect(sequence.anchorIndex == 1 && path(10))
        // Past the midpoint: the next anchor, fresh.
        let next = Chiron.anchors[2].tt
        _ = try sequence.heliocentricState(at: Self.time(tt: next - 1_000))
        #expect(sequence.anchorIndex == 2 && path(1_000))
    }

    /// Light-time correction asks for times a few hours apart. A reused
    /// sequence answers each within 1e-9 AU of a fresh start; the gap is the
    /// integrator's, from a different path to the same time.
    @Test("A light-time sequence agrees with fresh starts")
    func lightTimeSequence() throws {
        let time = Self.time(tt: Chiron.anchors[2].tt + 1_000)
        let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
        let sequence = Chiron.ReusableSimulation()
        var asked: [Engine.Time] = []
        let reused = try Engine.LightTravel.correct(at: time) { backdated in
            asked.append(backdated)
            let chiron = try sequence.heliocentricState(at: backdated)
            return Engine.Vector<Engine.EQJ>(
                x: chiron.x - earth.x, y: chiron.y - earth.y, z: chiron.z - earth.z, time: backdated)
        }
        #expect(asked.count >= 3)
        #expect(sequence.anchorIndex == 2)
        let last = try #require(asked.last)
        let fresh = try Chiron.heliocentricState(at: last)
        let reusedPosition = SIMD3<Double>(reused.x, reused.y, reused.z) + SIMD3<Double>(earth.x, earth.y, earth.z)
        let gap = reusedPosition - fresh.positionVector
        #expect(Self.length(gap) <= 1e-9)
    }

    @Test("The state carries the caller's time, scales and model")
    func callerTime() throws {
        let anchor = Chiron.anchors[0].tt
        let time = Engine.Time(ut: anchor + 3, deltaTModel: .jplHorizons)
        let state = try Chiron.heliocentricState(at: time)
        #expect(state.time.ut == time.ut && state.time.tt == time.tt && state.time.deltaTModel == .jplHorizons)
    }

    @Test("Sequences on separate threads get the serial results")
    func concurrent() throws {
        let anchor = Chiron.anchors[3].tt
        let instants = [anchor - 50, anchor + 25.25, anchor + 300]
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
