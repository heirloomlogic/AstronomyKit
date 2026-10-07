//
//  EnginePlutoCacheTests.swift
//  AstronomyKit
//
//  The Pluto segment cache: a miss is one segment integrated, a hit is
//  reuse, and a reset at any moment leaves results unchanged.
//

import Foundation
import Testing

@testable import AstronomyKit

extension PlutoSegmentSuites {
    @Suite("Engine.Pluto cache")
    struct EnginePlutoCacheTests {
        typealias Pluto = Engine.Pluto
        typealias Statistics = Pluto.Cache.Statistics

        /// A cache with its own registry, so its counts and entries do not
        /// depend on other suites.
        static func makeCache(capacity: Int = Pluto.segmentCount) -> (Pluto.Cache, Engine.CacheRegistry) {
            let registry = Engine.CacheRegistry()
            return (Pluto.Cache(capacity: capacity, registry: registry), registry)
        }

        static func bits(_ state: (position: SIMD3<Double>, velocity: SIMD3<Double>)) -> [UInt64] {
            [
                state.position.x, state.position.y, state.position.z, state.velocity.x, state.velocity.y,
                state.velocity.z,
            ]
            .map(\.bitPattern)
        }

        /// Instants in segments 24 (1920 to 2000) and 25 (2000 to 2080), which
        /// integrate quickly because the planets come from their polynomials.
        static let segment24 = -10_000.25
        static let segment25 = 12_345.5

        @Test("The shared cache has one entry per segment, and a cache registers with its registry")
        func shared() throws {
            #expect(Pluto.cache.capacity == 50)
            let (own, registry) = Self.makeCache()
            _ = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: own)
            #expect(registry.count == 1 && own.count == 1)
            registry.removeAll()
            #expect(own.count == 0)
        }

        @Test("A cold call integrates the segment, and warm calls in it reuse it with the same bits")
        func coldAndWarm() throws {
            let (cache, _) = Self.makeCache()
            let cold = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: cache)
            #expect(cache.statistics == Statistics(hits: 0, misses: 1))
            let warm = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: cache)
            _ = try Pluto.modelState(tt: Self.segment25 + 1_000, heliocentric: false, cache: cache)
            #expect(cache.statistics == Statistics(hits: 2, misses: 1))
            #expect(Self.bits(warm) == Self.bits(cold))
            _ = try Pluto.modelState(tt: Self.segment24, heliocentric: true, cache: cache)
            #expect(cache.statistics == Statistics(hits: 2, misses: 2) && cache.count == 2)
        }

        @Test("DE440, and the extrapolation beyond the table, do not touch the cache")
        func bypass() throws {
            let (cache, _) = Self.makeCache()
            _ = try Pluto.heliocentricState(at: PlanetTestSupport.time(tt: 9_497.375), cache: cache)
            _ = try Pluto.barycentricState(at: PlanetTestSupport.time(tt: 0), cache: cache)
            let last = Pluto.stateTable[Pluto.segmentCount].tt
            _ = try Pluto.heliocentricState(at: PlanetTestSupport.time(tt: last + 1), cache: cache)
            _ = try Pluto.heliocentricState(at: PlanetTestSupport.time(tt: -last - 1), cache: cache)
            #expect(cache.statistics == Statistics(hits: 0, misses: 0) && cache.count == 0)
        }

        @Test("A reset empties the cache, and the next call integrates the segment again to the same bits")
        func reset() throws {
            let (cache, registry) = Self.makeCache()
            let before = try Pluto.modelState(tt: Self.segment24, heliocentric: true, cache: cache)
            registry.removeAll()
            #expect(cache.count == 0)
            let after = try Pluto.modelState(tt: Self.segment24, heliocentric: true, cache: cache)
            #expect(cache.statistics == Statistics(hits: 0, misses: 2))
            #expect(Self.bits(after) == Self.bits(before))
        }

        @Test("A cache with no capacity integrates every time and gives the same results")
        func disabled() throws {
            let (cache, _) = Self.makeCache(capacity: 0)
            let first = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: cache)
            let second = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: cache)
            #expect(cache.statistics == Statistics(hits: 0, misses: 2) && cache.count == 0)
            let shared = try Pluto.modelState(tt: Self.segment25, heliocentric: true)
            #expect(Self.bits(first) == Self.bits(second) && Self.bits(first) == Self.bits(shared))
        }

        @Test("The oldest segment is replaced first when the cache is full")
        func eviction() throws {
            let (cache, _) = Self.makeCache(capacity: 1)
            _ = try Pluto.modelState(tt: Self.segment24, heliocentric: true, cache: cache)
            _ = try Pluto.modelState(tt: Self.segment25, heliocentric: true, cache: cache)
            _ = try Pluto.modelState(tt: Self.segment25 + 1, heliocentric: true, cache: cache)
            _ = try Pluto.modelState(tt: Self.segment24, heliocentric: true, cache: cache)
            #expect(cache.statistics == Statistics(hits: 1, misses: 3) && cache.count == 1)
        }

        /// The JPL Horizons vectors at 2000-01-01 00:00, 1999-12-23 00:00 and
        /// J2000 fall in segments 24 and 25, where the integrated model is
        /// within 1′ of Horizons. Callers on many threads, while another
        /// thread resets the cache, get the serial bits and stay within 1′.
        @Test("Simultaneous callers during resets get the serial results, within 1′ of Horizons")
        func concurrentResets() throws {
            let references = IndependentReferenceArchive.shared.vectors.filter {
                $0.body == "pluto" && [2_451_536.5, 2_451_544.5, 2_451_545.0].contains($0.julianDateTDB)
            }
            #expect(references.count == 3)
            let instants = references.map(EnginePlutoHorizonsTests.tt)
            for (reference, tt) in zip(references, instants) {
                let model = try Pluto.modelState(tt: tt, heliocentric: true)
                let error = try EnginePlutoHorizonsTests.arcminutes(model.position, reference)
                #expect(error <= toleranceArcminutes, "\(reference.tdb): \(error)′")
            }
            let serial = try instants.map { Self.bits(try Pluto.modelState(tt: $0, heliocentric: true)) }

            let (cache, registry) = Self.makeCache()
            let mismatches = EngineBoundedCacheTests.Counter()
            let resets = EngineBoundedCacheTests.Counter()
            let calls = 48
            DispatchQueue.concurrentPerform(iterations: calls + 1) { index in
                guard index < calls else {
                    for _ in 0..<16 {
                        registry.removeAll()
                        resets.record()
                        usleep(500)
                    }
                    return
                }
                let slot = index % instants.count
                let state = try? Pluto.modelState(tt: instants[slot], heliocentric: true, cache: cache)
                if state.map(Self.bits) != serial[slot] { mismatches.record() }
            }
            #expect(mismatches.count == 0)
            #expect(resets.count == 16)
        }

        @Test("Simultaneous public calls across DE440, the blend and the model get the serial results")
        func concurrentStates() throws {
            // 2026-01-22, a blend and segment 23. The cache starts with the
            // shared copy of segment 23, and nothing else resets it.
            let (cache, _) = Self.makeCache()
            _ = try cache.value(for: 23) { try Pluto.cache.value(for: 23) { try Pluto.segment(23) } }
            let instants = [9_517.0, -36_540.5, -36_600]
            @Sendable func bits(_ tt: Double) -> [UInt64]? {
                let state = try? Pluto.heliocentricState(at: PlanetTestSupport.time(tt: tt), cache: cache)
                return state.map { [$0.x, $0.y, $0.z, $0.vx, $0.vy, $0.vz].map(\.bitPattern) }
            }
            let serial = instants.map(bits)
            #expect(serial.allSatisfy { $0 != nil })
            let mismatches = EngineBoundedCacheTests.Counter()
            DispatchQueue.concurrentPerform(iterations: 24) { index in
                let slot = index % instants.count
                if bits(instants[slot]) != serial[slot] { mismatches.record() }
            }
            #expect(mismatches.count == 0)
            #expect(cache.statistics.misses == 1 && cache.count == 1)
        }
    }
}
