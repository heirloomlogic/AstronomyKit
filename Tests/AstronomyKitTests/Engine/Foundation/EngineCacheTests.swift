//
//  EngineCacheTests.swift
//  AstronomyKit
//
//  Keys, bounds, eviction, reset and concurrent use of the native engine's caches.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.ExactKey")
struct EngineExactKeyTests {
    @Test("Values that are not finite have no key", arguments: [Double.nan, -Double.nan, .infinity, -.infinity])
    func nonfiniteBypass(value: Double) {
        #expect(Engine.ExactKey(value) == nil)
    }

    @Test("Keys compare bit patterns: signed zeros differ and neighbors differ")
    func exactBits() {
        #expect(Engine.ExactKey(0.0) != Engine.ExactKey(-0.0))
        #expect(Engine.ExactKey(1.0) != Engine.ExactKey(1.0.nextUp))
        #expect(Engine.ExactKey(0.1 + 0.2) != Engine.ExactKey(0.3))
        #expect(Engine.ExactKey(36_525.0) == Engine.ExactKey(36_525.0))
        #expect(Engine.ExactKey(-2.5)?.bits == (-2.5).bitPattern)
    }
}

@Suite("Engine.BoundedCache")
struct EngineBoundedCacheTests {
    /// Counts how often a cache computes, so tests can tell a hit from a miss.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        func record() { lock.withLock { calls += 1 } }
        var count: Int { lock.withLock { calls } }
    }

    /// A value written on one thread and read on another.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Int?
        func set(_ value: Int) { lock.withLock { stored = value } }
        var value: Int? { lock.withLock { stored } }
    }

    struct Failure: Error, Equatable {}

    /// Fills `cache` with `capacity` keys from `firstKey` on, which it has not
    /// seen, and checks that it then holds exactly those, which it does only
    /// when its entries and its eviction slots agree.
    static func expectConsistent(_ cache: Engine.BoundedCache<Int, Int>, firstKey: Int) {
        let keys = firstKey..<firstKey + cache.capacity
        for key in keys {
            _ = cache.value(for: key) { key }
        }
        #expect(cache.count == cache.capacity)
        for key in keys {
            #expect(cache.value(for: key) { -1 } == key, "key \(key)")
        }
    }

    @Test("A miss computes and stores; a hit returns the stored value")
    func hitAndMiss() {
        let cache = Engine.BoundedCache<Int, Double>(capacity: 4, registry: Engine.CacheRegistry())
        let counter = Counter()
        let first = cache.value(for: 7) {
            counter.record()
            return 49.5
        }
        let second = cache.value(for: 7) {
            counter.record()
            return -1
        }
        #expect(first == 49.5)
        #expect(second == 49.5)
        #expect(counter.count == 1)
        #expect(cache.statistics == .init(hits: 1, misses: 1))
        #expect(cache.count == 1)
    }

    @Test("Signed zeros are separate entries")
    func signedZeroEntries() throws {
        let cache = Engine.BoundedCache<Engine.ExactKey, Double>(capacity: 4, registry: Engine.CacheRegistry())
        let positive = try #require(Engine.ExactKey(0.0))
        let negative = try #require(Engine.ExactKey(-0.0))
        #expect(cache.value(for: positive) { 1 } == 1)
        #expect(cache.value(for: negative) { 2 } == 2)
        #expect(cache.value(for: positive) { 3 } == 1)
        #expect(cache.count == 2)
    }

    @Test("Eviction replaces entries in insertion order, not by recent use")
    func roundRobinEviction() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 3, registry: Engine.CacheRegistry())
        for key in 0..<4 {
            _ = cache.value(for: key) { key * 10 }
        }
        // Key 0 was the oldest of four inserts into three slots.
        #expect(cache.count == 3)
        #expect(cache.statistics == .init(hits: 0, misses: 4))
        _ = cache.value(for: 1) { -1 }
        _ = cache.value(for: 2) { -1 }
        _ = cache.value(for: 3) { -1 }
        #expect(cache.statistics == .init(hits: 3, misses: 4))
        // Key 0 comes back and takes the slot of key 1, though key 1 was just read.
        #expect(cache.value(for: 0) { 0 } == 0)
        #expect(cache.value(for: 2) { -1 } == 20)
        #expect(cache.value(for: 1) { 11 } == 11)
        #expect(cache.statistics == .init(hits: 4, misses: 6))
        #expect(cache.count == 3)
    }

    @Test("A throwing computation propagates and stores nothing")
    func throwingCompute() {
        let cache = Engine.BoundedCache<Int, Double>(capacity: 2, registry: Engine.CacheRegistry())
        #expect(throws: Failure()) {
            try cache.value(for: 1) { throw Failure() }
        }
        #expect(cache.count == 0)
        #expect(cache.value(for: 1) { 5 } == 5)
        #expect(cache.statistics == .init(hits: 0, misses: 2))
    }

    @Test("Capacity zero computes every time and stores nothing")
    func zeroCapacity() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 0, registry: Engine.CacheRegistry())
        let counter = Counter()
        for _ in 0..<3 {
            _ = cache.value(for: 1) {
                counter.record()
                return 1
            }
        }
        #expect(counter.count == 3)
        #expect(cache.count == 0)
        #expect(cache.statistics == .init(hits: 0, misses: 3))
    }

    @Test("removeAll empties the entries and keeps the statistics")
    func removeAll() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 2, registry: Engine.CacheRegistry())
        _ = cache.value(for: 1) { 1 }
        _ = cache.value(for: 2) { 2 }
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.statistics == .init(hits: 0, misses: 2))
        // Eviction starts over from an empty cache.
        _ = cache.value(for: 3) { 3 }
        _ = cache.value(for: 4) { 4 }
        _ = cache.value(for: 5) { 5 }
        #expect(cache.value(for: 4) { -1 } == 4)
        #expect(cache.value(for: 5) { -1 } == 5)
        #expect(cache.value(for: 3) { 33 } == 33)
    }

    @Test("A computation can use the cache it fills")
    func reentrantCompute() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 4, registry: Engine.CacheRegistry())
        let outer = cache.value(for: 2) {
            cache.value(for: 1) { 10 } + 1
        }
        #expect(outer == 11)
        #expect(cache.count == 2)
    }

    @Test("Concurrent lookups return the computed value for each key")
    func concurrentUse() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 8, registry: Engine.CacheRegistry())
        let lookups = 4_000
        let mismatches = Counter()
        DispatchQueue.concurrentPerform(iterations: lookups) { index in
            let key = index % 12
            if cache.value(for: key, compute: { key * key }) != key * key {
                mismatches.record()
            }
        }
        #expect(mismatches.count == 0)
        #expect(cache.count <= 8)
        let statistics = cache.statistics
        #expect(statistics.hits + statistics.misses == lookups)
        #expect(statistics.misses >= 12)
    }

    /// 64 keys contend for 4 slots. Each computation also reads the count,
    /// so the bound is checked while other threads insert and evict.
    @Test("Eviction under contention keeps the bound and every value")
    func evictionUnderContention() {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 4, registry: Engine.CacheRegistry())
        let lookups = 8_000
        let mismatches = Counter()
        let overfull = Counter()
        DispatchQueue.concurrentPerform(iterations: lookups) { index in
            let key = (index * 37) % 64
            let found = cache.value(for: key) { () -> Int in
                if cache.count > 4 { overfull.record() }
                return key + 1_000
            }
            if found != key + 1_000 { mismatches.record() }
        }
        #expect(mismatches.count == 0)
        #expect(overfull.count == 0)
        #expect(cache.count <= 4)
        let statistics = cache.statistics
        #expect(statistics.hits + statistics.misses == lookups)
        Self.expectConsistent(cache, firstKey: 10_000)
    }

    @Test("A reset from inside a computation empties the cache; the computed value is stored after it")
    func resetInsideComputation() {
        let registry = Engine.CacheRegistry()
        let cache = Engine.BoundedCache<Int, Int>(capacity: 2, registry: registry)
        _ = cache.value(for: 1) { 10 }
        let found = cache.value(for: 2) { () -> Int in
            registry.removeAll()
            return 20
        }
        #expect(found == 20)
        #expect(cache.count == 1)
        #expect(cache.value(for: 2) { -1 } == 20)
        #expect(cache.value(for: 1) { 11 } == 11)
        Self.expectConsistent(cache, firstKey: 100)
    }

    /// The computation waits on another thread while this one resets the
    /// registry, so the reset lands between the miss and the store.
    @Test("A reset while another thread computes does not change its result")
    func resetDuringComputation() {
        let registry = Engine.CacheRegistry()
        let cache = Engine.BoundedCache<Int, Int>(capacity: 2, registry: registry)
        _ = cache.value(for: 1) { 10 }
        let computing = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let result = Box()
        DispatchQueue.global().async {
            let found = cache.value(for: 2) { () -> Int in
                computing.signal()
                resume.wait()
                return 20
            }
            result.set(found)
            finished.signal()
        }
        computing.wait()
        registry.removeAll()
        #expect(cache.count == 0)
        resume.signal()
        finished.wait()

        #expect(result.value == 20)
        // The entry from before the reset is gone; the one computed across it is stored.
        #expect(cache.count == 1)
        #expect(cache.value(for: 2) { -1 } == 20)
        #expect(cache.value(for: 1) { 11 } == 11)
        #expect(cache.statistics == .init(hits: 1, misses: 3))
    }

    /// Two caches in one registry, the outer computing through the inner,
    /// while one lookup in sixteen resets the registry.
    @Test("Resets during concurrent nested lookups keep every cache bounded and every value")
    func resetDuringConcurrentLookups() {
        let registry = Engine.CacheRegistry()
        let inner = Engine.BoundedCache<Int, Int>(capacity: 8, registry: registry)
        let outer = Engine.BoundedCache<Int, Int>(capacity: 4, registry: registry)
        let lookups = 8_000
        let mismatches = Counter()
        let overfull = Counter()
        DispatchQueue.concurrentPerform(iterations: lookups) { index in
            if index.isMultiple(of: 16) {
                registry.removeAll()
                return
            }
            let key = (index * 13) % 32
            let found = outer.value(for: key) { () -> Int in
                let square = inner.value(for: key) { key * key }
                if inner.count > 8 || outer.count > 4 { overfull.record() }
                return square + 1
            }
            if found != key * key + 1 { mismatches.record() }
        }
        #expect(mismatches.count == 0)
        #expect(overfull.count == 0)
        #expect(inner.count <= 8)
        #expect(outer.count <= 4)
        let statistics = outer.statistics
        #expect(statistics.hits + statistics.misses == lookups - lookups / 16)
        Self.expectConsistent(inner, firstKey: 1_000)
        Self.expectConsistent(outer, firstKey: 1_000)
    }
}

@Suite("Engine.CacheRegistry")
struct EngineCacheRegistryTests {
    @Test("removeAll empties every cache registered with it and no other")
    func resetReachesRegisteredCaches() {
        let registry = Engine.CacheRegistry()
        let other = Engine.CacheRegistry()
        let first = Engine.BoundedCache<Int, Int>(capacity: 2, registry: registry)
        let second = Engine.BoundedCache<Engine.ExactKey, String>(capacity: 2, registry: registry)
        let elsewhere = Engine.BoundedCache<Int, Int>(capacity: 2, registry: other)
        _ = first.value(for: 1) { 1 }
        _ = second.value(for: Engine.ExactKey(1.5)!) { "x" }
        _ = elsewhere.value(for: 1) { 1 }
        #expect(registry.count == 2)

        registry.removeAll()

        #expect(first.count == 0)
        #expect(second.count == 0)
        #expect(elsewhere.count == 1)
    }

    @Test("Caches registered while another thread resets are all reachable")
    func concurrentRegistration() {
        let registry = Engine.CacheRegistry()
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            if index.isMultiple(of: 8) {
                registry.removeAll()
            } else {
                let cache = Engine.BoundedCache<Int, Int>(capacity: 1, registry: registry)
                _ = cache.value(for: index) { index }
            }
        }
        #expect(registry.count == 56)
    }

    /// A cache in the shared registry, made once like an engine cache.
    static let sharedCache = Engine.BoundedCache<Int, Int>(capacity: 1, registry: .shared)

    @Test("Engine.resetCaches empties the caches in the shared registry")
    func resetCachesReachesShared() {
        _ = Self.sharedCache.value(for: 1) { 1 }
        #expect(Self.sharedCache.count == 1)
        Engine.resetCaches()
        #expect(Self.sharedCache.count == 0)
    }
}
