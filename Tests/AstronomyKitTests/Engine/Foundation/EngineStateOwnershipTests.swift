//
//  EngineStateOwnershipTests.swift
//  AstronomyKit
//
//  Integrated cache, model, star, Pluto and simulation ownership checks.
//

import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Engine state ownership")
struct EngineStateOwnershipTests {
    struct Query: Sendable {
        let jplBody: CelestialBody
        let jplObserver: Observer
        let jplYear: Int
        let jplMonth: Int
        let jplDay: Int
        let jplRightAscension: Double
        let jplDeclination: Double
        let jplToleranceArcminutes: Double
        let distanceBody: CelestialBody
        let distanceMode: String
        let distanceTT: Double
        let distanceAU: Double
        let distanceToleranceKM: Double
        let auditBody: CelestialBody
        let auditUT: Double
        let auditRightAscensionDegrees: Double
        let auditDeclinationDegrees: Double
        let auditToleranceArcminutes: Double
        let index: Int
    }

    struct Snapshot: Equatable, Sendable {
        let bits: [UInt64]
    }

    final class Checksum: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: UInt64 = 0

        func combine(_ value: UInt64) {
            lock.withLock { stored ^= value }
        }

        var value: UInt64 {
            lock.withLock { stored }
        }
    }

    enum Operation: Int, CaseIterable {
        case jpl
        case distance
        case audit
        case moon
        case pluto
        case nutation
        case star
        case simulation
    }

    static let orders: [[Operation]] = [
        Operation.allCases,
        [.simulation, .star, .nutation, .pluto, .moon, .audit, .distance, .jpl],
        [.distance, .moon, .jpl, .pluto, .audit, .simulation, .nutation, .star],
    ]

    static func body(named name: String) throws -> CelestialBody {
        try #require(CelestialBody(name: name))
    }

    static func queries() throws -> [Query] {
        let jplSuites = EngineEquatorialTests.suites
        let distances = EnginePositionsReferenceTests.distanceRecords
        let audits = IndependentReferenceArchive.shared.observations.filter { $0.series != "mercury-station" }
        #expect(jplSuites.count == 19)
        #expect(distances.count == 2_546)
        #expect(audits.count == 9)
        return try (0..<12).map { index in
            let jpl = jplSuites[(index * 7) % jplSuites.count]
            let jplReference = jpl.references[index % jpl.references.count]
            let distance = distances[index * distances.count / 12]
            let audit = audits[index % audits.count]
            return Query(
                jplBody: jpl.body, jplObserver: jpl.observer,
                jplYear: jplReference.year, jplMonth: jplReference.month, jplDay: jplReference.day,
                jplRightAscension: jplReference.rightAscension, jplDeclination: jplReference.declination,
                jplToleranceArcminutes: jpl.arcminutes,
                distanceBody: distance.body, distanceMode: distance.2.mode, distanceTT: distance.time.tt,
                distanceAU: distance.2.referenceRangeAU, distanceToleranceKM: distance.2.allowedErrorKm,
                auditBody: try body(named: audit.body),
                auditUT: IndependentReferenceDate.civil(audit.utc).universalTime,
                auditRightAscensionDegrees: audit.rightAscensionDegrees,
                auditDeclinationDegrees: audit.declinationDegrees,
                auditToleranceArcminutes: audit.angularToleranceArcminutes, index: index)
        }
    }

    static func jpl(_ query: Query) throws -> [UInt64] {
        let ut = Engine.Time.days(
            year: query.jplYear, month: query.jplMonth, day: query.jplDay, hour: 0, minute: 0, second: 0)
        let result = try Engine.Positions.equatorial(
            of: query.jplBody, at: Engine.Time(ut: ut, deltaTModel: .espenakMeeus),
            from: query.jplObserver, equatorDate: .j2000, aberration: .corrected)
        let error = angularSeparation(
            ra1: query.jplRightAscension, dec1: query.jplDeclination,
            ra2: result.rightAscension, dec2: result.declination)
        #expect(error <= query.jplToleranceArcminutes)
        return [result.rightAscension, result.declination, result.distance].map(\.bitPattern)
    }

    static func distance(_ query: Query) throws -> [UInt64] {
        let time = Engine.Time(tt: query.distanceTT, deltaTModel: .jplHorizons)
        let result =
            query.distanceMode == "heliocentric"
            ? try Engine.Positions.heliocentricDistance(of: query.distanceBody, at: time)
            : try Engine.Positions.geocentricPosition(of: query.distanceBody, at: time, aberration: .none).length
        #expect(abs(result - query.distanceAU) * Engine.kilometersPerAU <= query.distanceToleranceKM)
        return [result.bitPattern]
    }

    static func audit(_ query: Query) throws -> [UInt64] {
        let result = try Engine.Positions.equatorial(
            of: query.auditBody, at: Engine.Time(ut: query.auditUT, deltaTModel: .espenakMeeus),
            from: .geocentric, equatorDate: .j2000, aberration: .corrected)
        let error = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: result.rightAscension * 15, decDegrees1: result.declination,
            raDegrees2: query.auditRightAscensionDegrees, decDegrees2: query.auditDeclinationDegrees)
        #expect(error <= query.auditToleranceArcminutes)
        return [result.rightAscension, result.declination, result.distance].map(\.bitPattern)
    }

    static func moon(_ query: Query) throws -> [UInt64] {
        let state = try Engine.Moon.eclipticState(at: PlanetTestSupport.time(tt: 200_000.25 + Double(query.index) / 8))
        return [state.longitude, state.latitude, state.distance, state.longitudeRate].map(\.bitPattern)
    }

    static func pluto(_ query: Query) throws -> [UInt64] {
        let state = try Engine.Pluto.modelState(
            tt: -10_000.25 + Double(query.index) * 31, heliocentric: query.index.isMultiple(of: 2))
        return [
            state.position.x, state.position.y, state.position.z,
            state.velocity.x, state.velocity.y, state.velocity.z,
        ].map(\.bitPattern)
    }

    static func nutation(_ query: Query) -> [UInt64] {
        let tilt = Engine.EarthTilt(tt: -30_000.5 + Double(query.index) * 2_000.25)
        return [
            tilt.nutation.longitude, tilt.nutation.obliquity,
            tilt.nutation.longitudeRate, tilt.nutation.obliquityRate,
        ].map(\.bitPattern)
    }

    static func star(_ query: Query) throws -> [UInt64] {
        let star = Engine.Star(
            rightAscension: Double(query.index) + 0.25,
            declination: -60 + Double(query.index) * 10,
            distance: 4 + Double(query.index) * 13)
        let position = try star.ecliptic(
            at: Engine.Time(ut: 9_000 + Double(query.index), deltaTModel: .jplHorizons))
        return [position.longitude, position.latitude, position.vector.length].map(\.bitPattern)
    }

    static func simulation(_ query: Query) throws -> [UInt64] {
        let start = PlanetTestSupport.time(tt: 0.25)
        let body = Engine.State<Engine.EQJ>(
            x: -9.8, y: -27.9, z: -5.7, vx: 3.0e-3, vy: -1.1e-3, vz: -1.2e-3, time: start)
        let simulation = try Engine.GravitySimulation(origin: .sun, time: start, states: [body])
        let state = try #require(
            simulation.update(to: PlanetTestSupport.time(tt: 1 + Double(query.index) / 4)).first)
        return [state.x, state.y, state.z, state.vx, state.vy, state.vz].map(\.bitPattern)
    }

    static func run(_ query: Query, order: Int) throws -> Snapshot {
        var values = [[UInt64]?](repeating: nil, count: Operation.allCases.count)
        for operation in orders[order % orders.count] {
            values[operation.rawValue] = try {
                switch operation {
                case .jpl: try jpl(query)
                case .distance: try distance(query)
                case .audit: try audit(query)
                case .moon: try moon(query)
                case .pluto: try pluto(query)
                case .nutation: nutation(query)
                case .star: try star(query)
                case .simulation: try simulation(query)
                }
            }()
        }
        return Snapshot(bits: try values.flatMap { try #require($0) })
    }

    @Test("Published fixture samples agree in varied call orders, during contention and after resets")
    func integratedWorkloads() throws {
        let queries = try Self.queries()
        let serial = try queries.map { try Self.run($0, order: 0) }
        Engine.resetCaches()
        for index in queries.indices.reversed() {
            #expect(try Self.run(queries[index], order: index) == serial[index])
        }

        let mismatches = EngineBoundedCacheTests.Counter()
        let calls = 192
        DispatchQueue.concurrentPerform(iterations: calls) { iteration in
            if iteration.isMultiple(of: 17) {
                Engine.resetCaches()
            }
            let index = (iteration * 7) % queries.count
            do {
                if try Self.run(queries[index], order: iteration) != serial[index] { mismatches.record() }
            } catch {
                Issue.record(error)
                mismatches.record()
            }
        }
        #expect(mismatches.count == 0)
    }

    private enum ConcurrentFirstUse {
        static let registry = Engine.CacheRegistry()
        static let cache = Engine.VSOP87B.Cache(capacity: 8, registry: registry)
    }

    @Test("Concurrent first initialization publishes one cache whose callers agree")
    func concurrentFirstInitialization() {
        let mismatches = EngineBoundedCacheTests.Counter()
        let expected = Engine.VSOP87B.coordinates(Engine.VSOP87B.model(.mars), millennia: -2.0)
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let actual = Engine.VSOP87B.coordinates(.mars, millennia: -2.0, cache: ConcurrentFirstUse.cache)
            if actual != expected { mismatches.record() }
        }
        let store = ConcurrentFirstUse.cache.coordinates[Engine.Planet.mars.rawValue]
        _ = Engine.VSOP87B.coordinates(.mars, millennia: -2.0, cache: ConcurrentFirstUse.cache)
        #expect(mismatches.count == 0)
        #expect(ConcurrentFirstUse.registry.count == 16)
        #expect(store.count == 1)
        #expect(store.statistics.hits + store.statistics.misses == 65)
        #expect(store.statistics.hits > 0 && store.statistics.misses > 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CACHE_OWNERSHIP_MEASUREMENT_OUTPUT"] != nil))
    func measurement() throws {
        func peakBytes() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1_024
            #endif
        }
        let queries = try Self.queries()
        Engine.resetCaches()
        let peakBefore = peakBytes()
        let serialStart = Date()
        let checksum = Checksum()
        for iteration in 0..<48 {
            checksum.combine(try Self.run(queries[iteration % queries.count], order: iteration).bits[0])
        }
        let serialSeconds = Date().timeIntervalSince(serialStart)
        let peakAfterSerial = peakBytes()
        let contentionStart = Date()
        DispatchQueue.concurrentPerform(iterations: 192) { iteration in
            do {
                let bits = try Self.run(queries[(iteration * 7) % queries.count], order: iteration).bits
                checksum.combine(bits[iteration % bits.count])
            } catch {
                Issue.record(error)
            }
        }
        let result: [String: Any] = [
            "schemaVersion": 1, "serialWorkloads": 48, "contendedWorkloads": 192,
            "serialSeconds": serialSeconds,
            "contentionSeconds": Date().timeIntervalSince(contentionStart),
            "peakBytesBefore": peakBefore, "peakBytesAfterSerial": peakAfterSerial,
            "peakBytesAfterContention": peakBytes(), "checksum": checksum.value,
            "host": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        let path = try #require(ProcessInfo.processInfo.environment["CACHE_OWNERSHIP_MEASUREMENT_OUTPUT"])
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(
            to: URL(fileURLWithPath: path))
    }
}
