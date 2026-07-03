//
//  Search.swift
//  AstronomyKit
//
//  Generic root-finding search for custom astronomical events.
//

import CLibAstronomy

/// Carries a user-supplied search closure across the C boundary and captures
/// the first error it throws so the wrapper can rethrow it.
///
/// `@unchecked Sendable` is safe here because the C search functions invoke
/// the callback synchronously and serially on the calling thread: `thrownError`
/// is never accessed concurrently.
private final class ThrowingSearchBox: @unchecked Sendable {
    let function: (AstroTime) throws -> Double
    var thrownError: (any Error)?

    init(_ function: @escaping (AstroTime) throws -> Double) {
        self.function = function
    }
}

/// Same as ``ThrowingSearchBox``, for position closures.
private final class ThrowingPositionBox: @unchecked Sendable {
    let function: (AstroTime) throws -> Vector3D
    var thrownError: (any Error)?

    init(_ function: @escaping (AstroTime) throws -> Vector3D) {
        self.function = function
    }
}

private func searchTrampoline(context: UnsafeMutableRawPointer?, time: astro_time_t) -> astro_func_result_t {
    guard let context else {
        return astro_func_result_t(status: ASTRO_INTERNAL_ERROR, value: 0)
    }
    let box = Unmanaged<ThrowingSearchBox>.fromOpaque(context).takeUnretainedValue()
    do {
        return astro_func_result_t(status: ASTRO_SUCCESS, value: try box.function(AstroTime(raw: time)))
    } catch {
        // Returning a failure status makes the C search abort immediately;
        // the wrapper rethrows the captured error.
        box.thrownError = error
        return astro_func_result_t(status: ASTRO_INTERNAL_ERROR, value: 0)
    }
}

private func positionTrampoline(context: UnsafeMutableRawPointer?, time: astro_time_t) -> astro_vector_t {
    guard let context else {
        return astro_vector_t(status: ASTRO_INTERNAL_ERROR, x: 0, y: 0, z: 0, t: time)
    }
    let box = Unmanaged<ThrowingPositionBox>.fromOpaque(context).takeUnretainedValue()
    do {
        let vec = try box.function(AstroTime(raw: time))
        return astro_vector_t(status: ASTRO_SUCCESS, x: vec.x, y: vec.y, z: vec.z, t: time)
    } catch {
        // Returning a failure status makes the C iteration abort immediately;
        // the wrapper rethrows the captured error.
        box.thrownError = error
        return astro_vector_t(status: ASTRO_INTERNAL_ERROR, x: 0, y: 0, z: 0, t: time)
    }
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
/// let crossing = try AstroSearch.find(from: start, to: end) { time in
///     let lon = try Moon.eclipticPosition(at: time).lon
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
        let box = ThrowingSearchBox(function)
        let result = withExtendedLifetime(box) {
            Astronomy_Search(
                searchTrampoline,
                Unmanaged.passUnretained(box).toOpaque(),
                startTime.raw,
                endTime.raw,
                toleranceSeconds
            )
        }
        if let error = box.thrownError {
            throw error
        }
        if result.status == ASTRO_SEARCH_FAILURE {
            return nil
        }
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return AstroTime(raw: result.time)
    }

    /// Corrects a position for the finite speed of light.
    ///
    /// Given a function that returns an object's position at any time,
    /// this iteratively solves for the position the object had when light
    /// left it, such that it arrives at the observer at the specified time.
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
        let box = ThrowingPositionBox(positionFunction)
        let result = withExtendedLifetime(box) {
            Astronomy_CorrectLightTravel(
                Unmanaged.passUnretained(box).toOpaque(),
                positionTrampoline,
                time.raw
            )
        }
        if let error = box.thrownError {
            throw error
        }
        return try Vector3D(result)
    }
}
