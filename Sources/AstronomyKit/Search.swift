//
//  Search.swift
//  AstronomyKit
//
//  Generic root-finding search for custom astronomical events.
//

import CLibAstronomy

private func searchTrampoline(context: UnsafeMutableRawPointer?, time: astro_time_t) -> astro_func_result_t {
    let box = context!.assumingMemoryBound(to: ((AstroTime) -> Double).self).pointee
    let value = box(AstroTime(raw: time))
    return astro_func_result_t(status: ASTRO_SUCCESS, value: value)
}

/// Generic root-finding search for custom astronomical events.
///
/// Finds the *ascending root* of a function within a time range: the moment
/// when the function transitions from negative to non-negative.
///
/// ## Example
///
/// ```swift
/// // Find when the Moon's ecliptic longitude crosses 90°
/// let start = AstroTime(year: 2025, month: 1, day: 1)
/// let end = start.addingDays(30)
/// let result = try AstroSearch.find(from: start, to: end) { time in
///     let lon = try! Moon.eclipticPosition(at: time).lon
///     var diff = lon - 90.0
///     while diff < -180 { diff += 360 }
///     while diff > 180 { diff -= 360 }
///     return diff
/// }
/// ```
public enum AstroSearch {
    /// Finds the ascending root of a function within a time range.
    ///
    /// The function should return negative values before the event and
    /// non-negative values after it. The search finds the transition point.
    ///
    /// - Parameters:
    ///   - t1: The start of the search window.
    ///   - t2: The end of the search window.
    ///   - toleranceSeconds: Desired precision in seconds. Defaults to 1.
    ///   - function: A closure that returns a value for a given time.
    /// - Returns: The time when the function crosses from negative to non-negative.
    /// - Throws: `AstronomyError` if the search fails to converge.
    public static func find(
        from t1: AstroTime,
        to t2: AstroTime,
        toleranceSeconds: Double = 1.0,
        _ function: @escaping @Sendable (AstroTime) -> Double
    ) throws -> AstroTime {
        var closure = function
        let result = withUnsafeMutablePointer(to: &closure) { ptr in
            Astronomy_Search(searchTrampoline, ptr, t1.raw, t2.raw, toleranceSeconds)
        }
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return AstroTime(raw: result.time)
    }
}
