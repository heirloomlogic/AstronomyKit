//
//  EngineNutationCacheTests.swift
//  AstronomyKit
//
//  Work counts of the shared nutation cache.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Nutation cache")
struct EngineNutationCacheTests {
    typealias Cache = Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles>

    /// A cache like the shared one, with its own registry, so its counts
    /// are not disturbed by other suites.
    static func makeCache() -> (Cache, Engine.CacheRegistry) {
        let registry = Engine.CacheRegistry()
        return (Cache(capacity: Engine.Nutation.cache.capacity, registry: registry), registry)
    }

    static func time(tt: Double) -> Engine.Time {
        Engine.Time(ut: tt - 0.000_8, tt: tt, deltaTModel: .espenakMeeus)
    }

    @Test("The shared cache holds 32 entries")
    func sharedCapacity() {
        #expect(Engine.Nutation.cache.capacity == 32)
    }

    @Test("A cached result is the series result")
    func cachedEqualsSeries() {
        let (cache, _) = Self.makeCache()
        for tt in [-73_049.625, -0.5, 0.25, 9_496.375, 182_625.375] {
            let expected = Engine.Nutation.evaluate(centuries: tt / 36525)
            #expect(Engine.Nutation.angles(tt: tt, cache: cache) == expected)
            #expect(Engine.Nutation.angles(tt: tt, cache: cache) == expected)
        }
        #expect(cache.statistics == .init(hits: 5, misses: 5))
    }

    @Test("Angle, rate, tilt and sidereal-time callers at one instant share one evaluation")
    func sharedAcrossClients() {
        let (cache, _) = Self.makeCache()
        let tt = 9_496.375
        let angles = Engine.Nutation.angles(tt: tt, cache: cache)
        let tilt = Engine.EarthTilt(tt: tt, cache: cache)
        _ = tilt.nutationRotation
        _ = tilt.nutationRate
        _ = Engine.EarthRotation.apparentSiderealTime(Self.time(tt: tt), cache: cache)
        #expect(tilt.nutation == angles)
        #expect(cache.statistics == .init(hits: 2, misses: 1))
        #expect(cache.count == 1)
    }

    @Test("Mean sidereal time reads no nutation")
    func meanSiderealTime() {
        let (cache, _) = Self.makeCache()
        _ = Engine.EarthRotation.meanSiderealTime(Self.time(tt: 1_000.5))
        _ = Engine.EarthRotation.apparentSiderealTime(Self.time(tt: 1_000.5), cache: cache)
        #expect(cache.statistics == .init(hits: 0, misses: 1))
    }

    @Test("Signed zeros are different keys with equal results")
    func signedZeros() {
        let (cache, _) = Self.makeCache()
        let positive = Engine.Nutation.angles(tt: 0.0, cache: cache)
        let negative = Engine.Nutation.angles(tt: -0.0, cache: cache)
        #expect(positive == negative)
        #expect(cache.statistics == .init(hits: 0, misses: 2))
        #expect(cache.count == 2)
    }

    @Test("Instants that are not finite bypass the cache", arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteBypass(tt: Double) {
        let (cache, _) = Self.makeCache()
        let angles = Engine.Nutation.angles(tt: tt, cache: cache)
        #expect(angles.longitude.isNaN)
        #expect(cache.statistics == .init(hits: 0, misses: 0))
        #expect(cache.count == 0)
    }

    @Test("The 33rd instant replaces the oldest")
    func eviction() {
        let (cache, _) = Self.makeCache()
        let instants = (0...32).map { 100.0 + Double($0) / 4 }
        for tt in instants {
            _ = Engine.Nutation.angles(tt: tt, cache: cache)
        }
        #expect(cache.count == 32)
        _ = Engine.Nutation.angles(tt: instants[1], cache: cache)
        #expect(cache.statistics == .init(hits: 1, misses: 33))
        _ = Engine.Nutation.angles(tt: instants[0], cache: cache)
        #expect(cache.statistics == .init(hits: 1, misses: 34))
    }

    @Test("A reset empties the cache and the next call recomputes the same result")
    func reset() {
        let (cache, registry) = Self.makeCache()
        let first = Engine.Nutation.angles(tt: 2_000.125, cache: cache)
        registry.removeAll()
        #expect(cache.count == 0)
        #expect(Engine.Nutation.angles(tt: 2_000.125, cache: cache) == first)
        #expect(cache.statistics == .init(hits: 0, misses: 2))
    }

    @Test("Simultaneous callers get the serial results")
    func concurrentCallers() {
        let (cache, _) = Self.makeCache()
        let instants = (0..<48).map { -36_524.625 + Double($0) * 1_523.25 }
        let expected = instants.map { Engine.Nutation.evaluate(centuries: $0 / 36525) }
        let lookups = 4_096
        let mismatches = EngineBoundedCacheTests.Counter()
        DispatchQueue.concurrentPerform(iterations: lookups) { index in
            let i = (index * 7) % instants.count
            if Engine.Nutation.angles(tt: instants[i], cache: cache) != expected[i] {
                mismatches.record()
            }
        }
        #expect(mismatches.count == 0)
        #expect(cache.statistics.hits + cache.statistics.misses == lookups)
    }
}
