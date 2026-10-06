//
//  EngineCache.swift
//  AstronomyKit
//
//  Bounded caches shared by synchronous engine calls, and their reset.
//

import Foundation

extension Engine {
    /// A cache key made from the exact bits of a finite `Double`.
    ///
    /// `0.0` and `-0.0` are different keys. A value that is not finite has no
    /// key: the caller evaluates it directly and stores nothing.
    struct ExactKey: Hashable, Sendable {
        let bits: UInt64

        init?(_ value: Double) {
            guard value.isFinite else { return nil }
            bits = value.bitPattern
        }
    }

    /// A cache that ``CacheRegistry/removeAll()`` can empty.
    protocol ResettableCache: AnyObject, Sendable {
        func removeAll()
    }

    /// A fixed-capacity cache of values that are pure functions of their keys.
    ///
    /// When full, a new entry replaces the oldest insertion, whether or not it
    /// was read recently. Lookups from any thread share the entries. The
    /// computation runs outside the lock, so it can use this or any other
    /// cache; two threads that miss the same key both compute it, and the
    /// first result stays. A computation that throws stores nothing.
    ///
    /// Entries must not depend on anything outside the key, such as the
    /// process Delta T default or a caller's time metadata. Then a hit returns
    /// exactly what recomputing would, and emptying the cache at any moment
    /// cannot change a result. ``removeAll()`` does not wait for computations
    /// in progress: one that missed before it stores its value after it.
    final class BoundedCache<Key: Hashable & Sendable, Value: Sendable>: ResettableCache, @unchecked Sendable {
        /// Lookup counts since the cache was created; ``removeAll()`` keeps them.
        struct Statistics: Equatable, Sendable {
            var hits = 0
            var misses = 0
        }

        private struct Storage {
            var entries: [Key: Value] = [:]
            /// Keys in insertion slots; `next` is the slot the next new key replaces once full.
            var slots: [Key] = []
            var next = 0
            var statistics = Statistics()
        }

        /// The most entries the cache holds. Zero stores nothing.
        let capacity: Int

        // NSLock rather than Synchronization.Mutex: ThreadSanitizer on Linux
        // models pthread locks but not Mutex (see .github/tsan-suppressions.txt).
        // `storage` is only touched while `lock` is held.
        private let lock = NSLock()
        private var storage = Storage()

        /// Creates an empty cache and registers it for reset.
        init(capacity: Int, registry: CacheRegistry) {
            precondition(capacity >= 0, "BoundedCache capacity must not be negative")
            self.capacity = capacity
            storage.entries.reserveCapacity(capacity)
            storage.slots.reserveCapacity(capacity)
            registry.register(self)
        }

        /// The cached value for `key`, or the result of `compute`, which is stored.
        func value(for key: Key, compute: () throws -> Value) rethrows -> Value {
            let cached: Value? = lock.withLock {
                if let value = storage.entries[key] {
                    storage.statistics.hits += 1
                    return value
                }
                storage.statistics.misses += 1
                return nil
            }
            if let cached { return cached }

            let value = try compute()
            guard capacity > 0 else { return value }
            lock.withLock {
                guard storage.entries[key] == nil else { return }
                storage.entries[key] = value
                if storage.slots.count < capacity {
                    storage.slots.append(key)
                } else {
                    storage.entries[storage.slots[storage.next]] = nil
                    storage.slots[storage.next] = key
                    storage.next = (storage.next + 1) % capacity
                }
            }
            return value
        }

        /// Removes every entry and releases its storage.
        func removeAll() {
            lock.withLock {
                storage.entries = [:]
                storage.slots = []
                storage.next = 0
            }
        }

        /// The number of stored entries.
        var count: Int { lock.withLock { storage.entries.count } }

        var statistics: Statistics { lock.withLock { storage.statistics } }
    }

    /// The caches that one reset empties.
    ///
    /// A cache registers when it is created. The registry holds it weakly:
    /// once nobody references a cache, ``removeAll()`` and ``count`` skip it,
    /// and the next registration drops its entry. Engine caches are
    /// `static let` properties of the module that owns them, created on first
    /// use. That is a convention, not something the registry checks: a cache
    /// made on every call would give correct results but never a hit. Tests
    /// create their own registry.
    final class CacheRegistry: @unchecked Sendable {
        /// The registry ``Engine/resetCaches()`` empties.
        static let shared = CacheRegistry()

        private struct Entry {
            weak var cache: (any ResettableCache)?
        }

        // See BoundedCache for the choice of NSLock. `entries` is only touched
        // while `lock` is held.
        private let lock = NSLock()
        private var entries: [Entry] = []

        /// Adds `cache` and drops the entries of caches that no longer exist,
        /// so the list never outgrows the most caches alive at once.
        func register(_ cache: any ResettableCache) {
            lock.withLock {
                entries.removeAll { $0.cache == nil }
                entries.append(Entry(cache: cache))
            }
        }

        /// Empties every registered cache that still exists.
        func removeAll() {
            // Take the list first so no cache lock is taken under this one.
            for cache in lock.withLock({ entries.compactMap(\.cache) }) {
                cache.removeAll()
            }
        }

        /// The number of registered caches that still exist.
        var count: Int { lock.withLock { entries.count { $0.cache != nil } } }

        /// The number of stored entries, including those of caches that no
        /// longer exist and have not been pruned yet.
        var entryCount: Int { lock.withLock { entries.count } }
    }

    /// Empties every engine cache. Results do not change; the next calls that
    /// need the removed entries compute them again.
    ///
    /// This does not touch the Delta T default, fixed star definitions, or
    /// gravity simulations, which are not caches.
    static func resetCaches() {
        CacheRegistry.shared.removeAll()
    }
}
