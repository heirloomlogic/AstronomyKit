//
//  EngineMoonCacheTests.swift
//  AstronomyKit
//
//  Work counts of the lunar cache: a miss is one evaluation of the lunar
//  model, and a hit is reuse.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Moon cache")
struct EngineMoonCacheTests {
    typealias Cache = Engine.BoundedCache<Engine.ExactKey, SIMD3<Double>>
    typealias Statistics = Cache.Statistics

    static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

    /// A cache with its own registry, so its counts and entries do not
    /// depend on other suites.
    static func makeCache(capacity: Int = 32) -> (Cache, Engine.CacheRegistry) {
        let registry = Engine.CacheRegistry()
        return (Cache(capacity: capacity, registry: registry), registry)
    }

    /// Instants where the model is DE441, a blend, and DE440 alone.
    static let series = 200_000.25
    static let blend = Engine.MoonEphemeris.fullWeightEnd + 16
    static let de440 = 9_497.375

    /// The shared cache is made with `registry: .shared`, which
    /// `Engine.resetCaches()` empties. Resetting it here would race with
    /// other suites that read it.
    @Test("The shared cache holds 32 entries, and a cache registers with its registry")
    func shared() {
        #expect(Engine.Moon.cache.capacity == 32)
        let (own, registry) = Self.makeCache()
        _ = Engine.Moon.coordinates(centuries: 0.25, cache: own)
        #expect(registry.count == 1 && own.count == 1)
        registry.removeAll()
        #expect(own.count == 0)
    }

    @Test("A repeated ecliptic state reads the same one epoch from the cache in DE441")
    func outerEpoch() throws {
        let (cache, _) = Self.makeCache()
        let time = Self.time(tt: Self.series)
        let first = try Engine.Moon.eclipticState(at: time, cache: cache)
        #expect(cache.statistics == Statistics(hits: 0, misses: 1))
        #expect(cache.count == 1)
        let second = try Engine.Moon.eclipticState(at: time, cache: cache)
        #expect(cache.statistics == Statistics(hits: 1, misses: 1))
        #expect(second.longitudeRate == first.longitudeRate && second.distanceRate == first.distanceRate)
        // The other state and both positions reuse the center epoch.
        _ = try Engine.Moon.geocentricState(at: time, cache: cache)
        _ = try Engine.Moon.barycenterState(at: time, cache: cache)
        _ = try Engine.Moon.geocentricPosition(at: time, cache: cache)
        _ = try Engine.Moon.eclipticPosition(at: time, cache: cache)
        #expect(cache.statistics == Statistics(hits: 5, misses: 1))
    }

    @Test("Both tables and their blend read one cached position epoch per state")
    func oneEpoch() throws {
        for tt in [Self.de440, Self.blend] {
            let (cache, _) = Self.makeCache()
            let time = Self.time(tt: tt)
            _ = try Engine.Moon.eclipticState(at: time, cache: cache)
            _ = try Engine.Moon.geocentricState(at: time, cache: cache)
            #expect(cache.statistics == Statistics(hits: 1, misses: 1), "tt \(tt)")
        }
    }

    @Test("A cache with no capacity evaluates every time and gives the same results")
    func disabled() throws {
        let (cache, _) = Self.makeCache(capacity: 0)
        let time = Self.time(tt: Self.series)
        let first = try Engine.Moon.eclipticState(at: time, cache: cache)
        let second = try Engine.Moon.eclipticState(at: time, cache: cache)
        #expect(cache.statistics == Statistics(hits: 0, misses: 2))
        #expect(cache.count == 0)
        let shared = try Engine.Moon.eclipticState(at: time)
        #expect([first.longitude, first.longitudeRate] == [second.longitude, second.longitudeRate])
        #expect([first.longitude, first.longitudeRate] == [shared.longitude, shared.longitudeRate])
    }

    @Test("Signed zeros are different keys, and centuries that are not finite are not stored")
    func keys() {
        let (cache, _) = Self.makeCache()
        let positive = Engine.Moon.coordinates(centuries: 0.0, cache: cache)
        let negative = Engine.Moon.coordinates(centuries: -0.0, cache: cache)
        #expect(positive == negative)
        #expect(cache.statistics == Statistics(hits: 0, misses: 2) && cache.count == 2)
        for t in [Double.nan, .infinity, -.infinity] {
            let value = Engine.Moon.coordinates(centuries: t, cache: cache)
            #expect(value.x.isNaN)
        }
        #expect(cache.statistics == Statistics(hits: 0, misses: 2) && cache.count == 2)
    }

    @Test("The oldest of 32 entries is replaced first")
    func eviction() {
        let (cache, _) = Self.makeCache()
        for k in 0..<33 {
            _ = Engine.Moon.coordinates(centuries: Double(k) / 64, cache: cache)
        }
        #expect(cache.count == 32)
        _ = Engine.Moon.coordinates(centuries: 1.0 / 64, cache: cache)
        #expect(cache.statistics.hits == 1)
        _ = Engine.Moon.coordinates(centuries: 0, cache: cache)
        #expect(cache.statistics.misses == 34)
    }

    /// The cache holds only the model's values, so a hit carries nothing of
    /// the call that stored it.
    @Test("A hit returns the caller's own time")
    func callerTime() throws {
        let (cache, _) = Self.makeCache()
        let first = Engine.Time(ut: Self.series - 0.001, tt: Self.series, deltaTModel: .espenakMeeus)
        let second = Engine.Time(ut: Self.series - 0.002, tt: Self.series, deltaTModel: .jplHorizons)
        _ = try Engine.Moon.geocentricState(at: first, cache: cache)
        let state = try Engine.Moon.geocentricState(at: second, cache: cache)
        #expect(cache.statistics.hits == 1)
        #expect(state.time.ut == second.ut && state.time.deltaTModel == .jplHorizons)
    }

    @Test("Simultaneous callers get the serial results")
    func concurrent() throws {
        let (cache, _) = Self.makeCache(capacity: 8)
        let instants = (0..<64).map { Self.series + Double($0 % 16) * 0.25 }
        let serial = try instants.map { try Engine.Moon.eclipticState(at: Self.time(tt: $0)).longitudeRate }
        let mismatches = EngineBoundedCacheTests.Counter()
        DispatchQueue.concurrentPerform(iterations: instants.count) { index in
            let rate = try? Engine.Moon.eclipticState(at: Self.time(tt: instants[index]), cache: cache).longitudeRate
            if rate != serial[index] { mismatches.record() }
        }
        #expect(mismatches.count == 0)
    }
}
