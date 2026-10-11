//
//  Search.swift
//  AstronomyKit
//
//  Generic root-finding search for custom astronomical events.
//

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
/// let crossing = try AstroSearch.find(from: start, to: end) { time in
///     let lon = try Moon.ecliptic(at: time).longitude
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
    /// The function is called synchronously on the calling thread, one call
    /// at a time, and is not called again after it throws.
    ///
    /// - Parameters:
    ///   - startTime: The start of the search window.
    ///   - endTime: The end of the search window.
    ///   - toleranceSeconds: Desired precision in seconds. Defaults to 1.
    ///   - function: A closure that returns a value for a given time.
    /// - Returns: The time when the function crosses from negative to
    ///   non-negative, or `nil` if no such crossing occurs in the window.
    /// - Throws: Rethrows any error from `function`, or `AstronomyError` if
    ///   the search fails to converge.
    public static func find(
        from startTime: AstroTime,
        to endTime: AstroTime,
        toleranceSeconds: Double = 1.0,
        _ function: @escaping @Sendable (AstroTime) throws -> Double
    ) throws -> AstroTime? {
        try Engine.Search.ascendingRoot(
            from: startTime.engine, to: endTime.engine, toleranceSeconds: toleranceSeconds
        ) { time in
            try function(AstroTime(time))
        }
        .map(AstroTime.init)
    }

    /// Corrects a position for the finite speed of light.
    ///
    /// Given a function that returns an object's position at any time,
    /// this iteratively solves for the position the object had when light
    /// left it, such that it arrives at the observer at the specified time.
    /// The returned vector carries the time of the final call, the time the
    /// light left the object.
    ///
    /// - Parameters:
    ///   - time: The observation time (when light arrives).
    ///   - positionFunction: A closure that returns the object's position at a given time.
    /// - Returns: The light-corrected position vector.
    /// - Throws: Rethrows any error from `positionFunction`, or
    ///   `AstronomyError` if the iteration fails to converge.
    public static func correctLightTravel(
        at time: AstroTime,
        _ positionFunction: @escaping @Sendable (AstroTime) throws -> Vector3D
    ) throws -> Vector3D {
        Vector3D(
            try Engine.LightTravel.correct(at: time.engine) { backdated in
                let vector = try positionFunction(AstroTime(backdated))
                return Engine.Vector<Engine.EQJ>(x: vector.x, y: vector.y, z: vector.z, time: backdated)
            })
    }
}
