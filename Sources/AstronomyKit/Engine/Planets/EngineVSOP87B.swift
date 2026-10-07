//
//  EngineVSOP87B.swift
//  AstronomyKit
//
//  The full VSOP87B series with compensated summation, and their cache.
//

import Foundation

extension Engine.VSOP87B {
    /// Julian days in a Julian millennium, the series' unit of time.
    static let daysPerMillennium = 365_250.0

    /// A running sum that keeps its rounding error (Neumaier's improvement of
    /// Kahan summation) and adds it back in ``value``.
    struct CompensatedSum {
        private var sum = 0.0
        private var compensation = 0.0

        mutating func add(_ term: Double) {
            let next = sum + term
            compensation += abs(sum) >= abs(term) ? (sum - next) + term : (term - next) + sum
            sum = next
        }

        var value: Double { sum + compensation }
    }

    /// Longitude and latitude in radians and radius in AU at `t` Julian
    /// millennia of TT from J2000.
    ///
    /// Every term is summed in table order with compensation, inside each
    /// power of `t` and across the powers. Plain addition would round every
    /// small term at the precision of the largest one, and the loss grows with
    /// `t`. Each longitude power's contribution is reduced modulo 2π before
    /// it is added. A `t` that is not finite gives NaN.
    static func coordinates(_ model: Model, millennia t: Double) -> SIMD3<Double> {
        var result = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var total = CompensatedSum()
            var power = 1.0
            for count in model.termCounts[coordinate] {
                var series = CompensatedSum()
                for _ in 0..<count {
                    let (a, b, c) = (model.terms[3 * term], model.terms[3 * term + 1], model.terms[3 * term + 2])
                    series.add(a * cos(b + t * c))
                    term += 1
                }
                var increment = power * series.value
                if coordinate == 0 { increment = increment.truncatingRemainder(dividingBy: 2 * .pi) }
                total.add(increment)
                power *= t
            }
            result[coordinate] = total.value
        }
        return result
    }

    /// The derivatives of ``coordinates(_:millennia:)`` with respect to `t`:
    /// radians and AU per Julian millennium. Each power's sums are
    /// compensated; the powers' contributions are added plainly.
    static func derivatives(_ model: Model, millennia t: Double) -> SIMD3<Double> {
        var result = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var total = 0.0
            var power = 1.0  // t^α
            var lowerPower = 0.0  // t^(α−1)
            for (alpha, count) in model.termCounts[coordinate].enumerated() {
                var sines = CompensatedSum()
                var cosines = CompensatedSum()
                for _ in 0..<count {
                    let (a, b, c) = (model.terms[3 * term], model.terms[3 * term + 1], model.terms[3 * term + 2])
                    let angle = b + t * c
                    sines.add(a * c * sin(angle))
                    if alpha > 0 { cosines.add(a * cos(angle)) }
                    term += 1
                }
                total += Double(alpha) * lowerPower * cosines.value - power * sines.value
                lowerPower = power
                power *= t
            }
            result[coordinate] = total
        }
        return result
    }

    /// Rectangular coordinates from longitude, latitude and radius.
    static func rectangular(_ sphere: SIMD3<Double>) -> SIMD3<Double> {
        let radialProjection = sphere[2] * cos(sphere[1])
        return SIMD3(radialProjection * cos(sphere[0]), radialProjection * sin(sphere[0]), sphere[2] * sin(sphere[1]))
    }

    /// The rectangular velocity in AU per day from longitude, latitude and
    /// radius and their ``derivatives(_:millennia:)``, by the chain rule.
    static func velocity(_ sphere: SIMD3<Double>, rates: SIMD3<Double>) -> SIMD3<Double> {
        let (cosLongitude, sinLongitude) = (cos(sphere[0]), sin(sphere[0]))
        let (cosLatitude, sinLatitude) = (cos(sphere[1]), sin(sphere[1]))
        let r = sphere[2]
        let perMillennium = SIMD3(
            rates[2] * cosLatitude * cosLongitude - r * sinLatitude * cosLongitude * rates[1]
                - r * cosLatitude * sinLongitude * rates[0],
            rates[2] * cosLatitude * sinLongitude - r * sinLatitude * sinLongitude * rates[1]
                + r * cosLatitude * cosLongitude * rates[0],
            rates[2] * sinLatitude + r * cosLatitude * rates[1]
        )
        // The C engine scales by the reciprocal too.
        return perMillennium * (1 / daysPerMillennium)
    }
}

// MARK: - Cache

extension Engine.VSOP87B {
    /// Series results for each planet, keyed by the exact bits of `t`, the
    /// scaled TT the series read. Coordinates and derivatives are kept apart,
    /// 32 entries each per planet; a position fills only the coordinates.
    ///
    /// The values are pure functions of the planet and `t`, so a hit returns
    /// what the series would. A `t` that is not finite has no key and is
    /// computed without touching the cache.
    final class Cache: Sendable {
        typealias Store = Engine.BoundedCache<Engine.ExactKey, SIMD3<Double>>

        /// One store per planet, in ``Engine/Planet`` order.
        let coordinates: [Store]
        let derivatives: [Store]

        init(capacity: Int = 32, registry: Engine.CacheRegistry) {
            coordinates = Engine.Planet.allCases.map { _ in Store(capacity: capacity, registry: registry) }
            derivatives = Engine.Planet.allCases.map { _ in Store(capacity: capacity, registry: registry) }
        }
    }

    /// The cache every engine caller shares, registered for
    /// ``Engine/resetCaches()``.
    static let cache = Cache(registry: .shared)

    /// ``coordinates(_:millennia:)`` for `planet`, through `cache`.
    static func coordinates(_ planet: Engine.Planet, millennia t: Double, cache: Cache = cache) -> SIMD3<Double> {
        cached(cache.coordinates[planet.rawValue], t) { coordinates(model(planet), millennia: t) }
    }

    /// ``derivatives(_:millennia:)`` for `planet`, through `cache`.
    static func derivatives(_ planet: Engine.Planet, millennia t: Double, cache: Cache = cache) -> SIMD3<Double> {
        cached(cache.derivatives[planet.rawValue], t) { derivatives(model(planet), millennia: t) }
    }

    /// `compute()` through `store`, or directly when `t` has no key.
    private static func cached(
        _ store: Cache.Store, _ t: Double, compute: () -> SIMD3<Double>
    ) -> SIMD3<Double> {
        guard let key = Engine.ExactKey(t) else { return compute() }
        return store.value(for: key, compute: compute)
    }
}
