//
//  EngineVSOP87BCacheTests.swift
//  AstronomyKit
//
//  Work counts of the VSOP87B series cache: a cache miss is one series
//  evaluation, and a hit is reuse.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.VSOP87B cache")
struct EngineVSOP87BCacheTests {
    typealias Statistics = Engine.VSOP87B.Cache.Store.Statistics

    static func time(tt: Double) -> Engine.Time {
        Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
    }

    /// A cache with its own registry, so its counts are not disturbed by
    /// other suites.
    static func makeCache(capacity: Int = 32) -> (Engine.VSOP87B.Cache, Engine.CacheRegistry) {
        let registry = Engine.CacheRegistry()
        return (Engine.VSOP87B.Cache(capacity: capacity, registry: registry), registry)
    }

    /// A TT outside the polynomial span, where the series apply.
    static let fallback = -50_000.5

    @Test("The shared cache holds 32 coordinate and 32 derivative entries per planet")
    func sharedCapacity() {
        let cache = Engine.VSOP87B.cache
        #expect(cache.coordinates.count == 8 && cache.derivatives.count == 8)
        #expect((cache.coordinates + cache.derivatives).allSatisfy { $0.capacity == 32 })
        let (own, registry) = Self.makeCache()
        withExtendedLifetime(own) { #expect(registry.count == 16) }
    }

    @Test("Inside the polynomial span the series are not evaluated")
    func polynomialBypass() throws {
        let (cache, _) = Self.makeCache()
        for planet in Engine.Planet.allCases {
            for tt in [0.0, 9_496.375, -30_000.25, 36_000.5] {
                let time = Self.time(tt: tt)
                _ = try planet.heliocentricPosition(at: time, cache: cache)
                _ = try planet.heliocentricState(at: time, cache: cache)
                _ = try planet.heliocentricDistance(at: time, cache: cache)
            }
            #expect(cache.coordinates[planet.rawValue].statistics == Statistics())
            #expect(cache.derivatives[planet.rawValue].statistics == Statistics())
        }
    }

    @Test("Position, state and distance at one fallback instant share one evaluation of each series")
    func sharedAcrossCallers() throws {
        let (cache, _) = Self.makeCache()
        let time = Self.time(tt: Self.fallback)
        let position = try Engine.Planet.mars.heliocentricPosition(at: time, cache: cache)
        let state = try Engine.Planet.mars.heliocentricState(at: time, cache: cache)
        let distance = try Engine.Planet.mars.heliocentricDistance(at: time, cache: cache)
        _ = try Engine.Planet.mars.heliocentricState(at: time, cache: cache)
        #expect(state.x == position.x && distance > 0)
        let index = Engine.Planet.mars.rawValue
        #expect(cache.coordinates[index].statistics == Statistics(hits: 3, misses: 1))
        #expect(cache.derivatives[index].statistics == Statistics(hits: 1, misses: 1))
    }

    @Test("An excluded polynomial segment uses the cached series")
    func excludedSegment() throws {
        let (cache, _) = Self.makeCache()
        let tt = Engine.PlanetPolynomial.mercury.start(ofSegment: 14) + 3
        #expect(Engine.PlanetPolynomial.position(.mercury, tt: tt) == nil)
        _ = try Engine.Planet.mercury.heliocentricPosition(at: Self.time(tt: tt), cache: cache)
        _ = try Engine.Planet.mercury.heliocentricPosition(at: Self.time(tt: tt), cache: cache)
        #expect(cache.coordinates[0].statistics == Statistics(hits: 1, misses: 1))
    }

    @Test("A cached result is the series result")
    func cachedEqualsSeries() throws {
        let (cache, _) = Self.makeCache()
        for planet in Engine.Planet.allCases {
            for t in [-3.5, -0.125, 0.25, 4.0] {
                let model = Engine.VSOP87B.model(planet)
                for _ in 0..<2 {
                    #expect(
                        Engine.VSOP87B.coordinates(planet, millennia: t, cache: cache)
                            == Engine.VSOP87B.coordinates(model, millennia: t))
                    #expect(
                        Engine.VSOP87B.derivatives(planet, millennia: t, cache: cache)
                            == Engine.VSOP87B.derivatives(model, millennia: t))
                }
            }
            #expect(cache.coordinates[planet.rawValue].statistics == Statistics(hits: 4, misses: 4))
        }
    }

    /// The negative control: with no capacity, nothing is reused, and the
    /// counts that show reuse above would fail.
    @Test("A cache with no capacity evaluates the series every time")
    func disabledCache() throws {
        let (cache, _) = Self.makeCache(capacity: 0)
        let time = Self.time(tt: Self.fallback)
        let first = try Engine.Planet.venus.heliocentricState(at: time, cache: cache)
        let second = try Engine.Planet.venus.heliocentricState(at: time, cache: cache)
        #expect(first.x == second.x && first.vz == second.vz)
        #expect(cache.coordinates[1].statistics == Statistics(hits: 0, misses: 2))
        #expect(cache.derivatives[1].statistics == Statistics(hits: 0, misses: 2))
        #expect(cache.coordinates[1].count == 0)
    }

    @Test("Each planet has its own entries")
    func planetsApart() throws {
        let (cache, _) = Self.makeCache()
        for planet in Engine.Planet.allCases {
            _ = try planet.heliocentricPosition(at: Self.time(tt: Self.fallback), cache: cache)
        }
        #expect(cache.coordinates.allSatisfy { $0.statistics == Statistics(hits: 0, misses: 1) && $0.count == 1 })
    }

    @Test("Signed zeros are different keys with equal results")
    func signedZeros() {
        let (cache, _) = Self.makeCache()
        let positive = Engine.VSOP87B.coordinates(.earth, millennia: 0.0, cache: cache)
        let negative = Engine.VSOP87B.coordinates(.earth, millennia: -0.0, cache: cache)
        #expect(positive == negative)
        #expect(cache.coordinates[2].statistics == Statistics(hits: 0, misses: 2))
        #expect(cache.coordinates[2].count == 2)
    }

    @Test("A t that is not finite bypasses the cache", arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteBypass(t: Double) {
        let (cache, _) = Self.makeCache()
        #expect(Engine.VSOP87B.coordinates(.jupiter, millennia: t, cache: cache)[0].isNaN)
        #expect(Engine.VSOP87B.derivatives(.jupiter, millennia: t, cache: cache)[0].isNaN)
        #expect(cache.coordinates[4].statistics == Statistics())
        #expect(cache.derivatives[4].statistics == Statistics())
    }

    @Test("The 33rd instant replaces the oldest")
    func eviction() throws {
        let (cache, _) = Self.makeCache()
        let instants = (0...32).map { Self.fallback - Double($0) / 4 }
        for tt in instants {
            _ = try Engine.Planet.saturn.heliocentricDistance(at: Self.time(tt: tt), cache: cache)
        }
        let store = cache.coordinates[5]
        #expect(store.count == 32)
        _ = try Engine.Planet.saturn.heliocentricDistance(at: Self.time(tt: instants[32]), cache: cache)
        _ = try Engine.Planet.saturn.heliocentricDistance(at: Self.time(tt: instants[0]), cache: cache)
        #expect(store.statistics == Statistics(hits: 1, misses: 34))
    }

    @Test("A reset empties every planet's entries, and the next call evaluates again")
    func reset() throws {
        let (cache, registry) = Self.makeCache()
        let time = Self.time(tt: Self.fallback)
        _ = try Engine.Planet.uranus.heliocentricState(at: time, cache: cache)
        registry.removeAll()
        #expect((cache.coordinates + cache.derivatives).allSatisfy { $0.count == 0 })
        _ = try Engine.Planet.uranus.heliocentricState(at: time, cache: cache)
        #expect(cache.coordinates[6].statistics == Statistics(hits: 0, misses: 2))
    }

    @Test("Simultaneous callers get the series result")
    func simultaneous() throws {
        let (cache, _) = Self.makeCache()
        let instants = (0..<8).map { Self.fallback + Double($0) }
        let expected = try instants.map {
            try Engine.Planet.neptune.heliocentricState(at: Self.time(tt: $0), cache: Self.makeCache().0)
        }
        let mismatches = Mismatches()
        DispatchQueue.concurrentPerform(iterations: 2_048) { index in
            let i = index % instants.count
            let state = try? Engine.Planet.neptune.heliocentricState(at: Self.time(tt: instants[i]), cache: cache)
            if state?.x != expected[i].x || state?.vy != expected[i].vy { mismatches.increment() }
        }
        #expect(mismatches.value == 0)
        #expect(cache.coordinates[7].count == instants.count)
    }

    final class Mismatches: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}
