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

    /// Adds `value` to `sum` and keeps the rounding error in `compensation`
    /// (Neumaier's improvement of Kahan summation). The caller adds
    /// `compensation` to `sum` once every term is in.
    @inline(__always)
    static func add(_ value: Double, to sum: inout Double, compensation: inout Double) {
        let next = sum + value
        compensation += abs(sum) >= abs(value) ? (sum - next) + value : (value - next) + sum
        sum = next
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
            var total = 0.0
            var totalCompensation = 0.0
            var power = 1.0
            for count in model.termCounts[coordinate] {
                var sum = 0.0
                var compensation = 0.0
                for _ in 0..<count {
                    let a = model.terms[3 * term]
                    let b = model.terms[3 * term + 1]
                    let c = model.terms[3 * term + 2]
                    add(a * cos(b + t * c), to: &sum, compensation: &compensation)
                    term += 1
                }
                sum += compensation
                var increment = power * sum
                if coordinate == 0 { increment = increment.truncatingRemainder(dividingBy: 2 * .pi) }
                add(increment, to: &total, compensation: &totalCompensation)
                power *= t
            }
            result[coordinate] = total + totalCompensation
        }
        return result
    }

    /// The derivatives of ``coordinates(_:millennia:)`` with respect to `t`:
    /// radians and AU per Julian millennium. Summed the same way.
    static func derivatives(_ model: Model, millennia t: Double) -> SIMD3<Double> {
        var result = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var total = 0.0
            var power = 1.0  // t^α
            var lowerPower = 0.0  // t^(α−1)
            for (alpha, count) in model.termCounts[coordinate].enumerated() {
                var sinSum = 0.0
                var sinCompensation = 0.0
                var cosSum = 0.0
                var cosCompensation = 0.0
                for _ in 0..<count {
                    let a = model.terms[3 * term]
                    let angle = model.terms[3 * term + 1] + t * model.terms[3 * term + 2]
                    add(a * model.terms[3 * term + 2] * sin(angle), to: &sinSum, compensation: &sinCompensation)
                    if alpha > 0 { add(a * cos(angle), to: &cosSum, compensation: &cosCompensation) }
                    term += 1
                }
                sinSum += sinCompensation
                cosSum += cosCompensation
                total += Double(alpha) * lowerPower * cosSum - power * sinSum
                lowerPower = power
                power *= t
            }
            result[coordinate] = total
        }
        return result
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
        guard let key = Engine.ExactKey(t) else { return coordinates(model(planet), millennia: t) }
        return cache.coordinates[planet.rawValue].value(for: key) { coordinates(model(planet), millennia: t) }
    }

    /// ``derivatives(_:millennia:)`` for `planet`, through `cache`.
    static func derivatives(_ planet: Engine.Planet, millennia t: Double, cache: Cache = cache) -> SIMD3<Double> {
        guard let key = Engine.ExactKey(t) else { return derivatives(model(planet), millennia: t) }
        return cache.derivatives[planet.rawValue].value(for: key) { derivatives(model(planet), millennia: t) }
    }
}
