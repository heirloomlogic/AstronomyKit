//
//  Transit.swift
//  AstronomyKit
//
//  Mercury and Venus transit calculations.
//

import Foundation

// MARK: - Transit

/// Information about a transit of Mercury or Venus across the Sun.
///
/// A transit occurs when Mercury or Venus passes between the Earth
/// and the Sun, appearing as a small dark spot moving across the
/// Sun's disc.
///
/// Transits are rare events. Mercury transits occur about 13 times
/// per century, while Venus transits occur in pairs separated by
/// 8 years, with over a century between pairs.
///
/// ## Example
///
/// ```swift
/// let transit = try Transit.search(body: .mercury, after: .now)
/// print("Transit starts: \(transit.start)")
/// print("Transit peak: \(transit.peak)")
/// print("Transit ends: \(transit.finish)")
/// ```
public struct Transit: Sendable, Equatable, Hashable {
    /// The transiting body (Mercury or Venus).
    public let body: CelestialBody

    /// The time when the transit begins (first contact).
    public let start: AstroTime

    /// The time of the transit's peak (mid-transit).
    public let peak: AstroTime

    /// The time when the transit ends (last contact).
    public let finish: AstroTime

    /// Angular separation between the centers of the Sun and planet
    /// at peak, in arcminutes.
    public let separation: Double

    /// The duration of the transit.
    public var duration: TimeInterval {
        finish.date.timeIntervalSince(start.date)
    }

    init(
        body: CelestialBody,
        start: AstroTime,
        peak: AstroTime,
        finish: AstroTime,
        separation: Double
    ) {
        self.body = body
        self.start = start
        self.peak = peak
        self.finish = finish
        self.separation = separation
    }
}

extension Transit: CustomStringConvertible {
    /// A textual representation showing the body, peak time, and angular separation.
    public var description: String {
        String(
            format: "%@ Transit on %@, separation: %.1f arcmin",
            body.name,
            peak.description,
            separation
        )
    }
}

// MARK: - Transit Search Functions

extension Transit {
    /// Searches for the next transit of Mercury or Venus.
    ///
    /// - Parameters:
    ///   - body: The body to search for (must be `.mercury` or `.venus`).
    ///   - startTime: The time to start searching from.
    /// - Returns: The next transit.
    /// - Throws: `AstronomyError` if the search fails or body is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Find the next Mercury transit
    /// let transit = try Transit.search(body: .mercury, after: .now)
    /// print("Mercury transit: \(transit.peak)")
    /// ```
    public static func search(body: CelestialBody, after startTime: AstroTime) throws -> Transit {
        try EngineTransits.search(body: body, after: startTime)
    }

    /// Finds the next transit after a given transit.
    ///
    /// - Parameters:
    ///   - body: The body to search for (must be `.mercury` or `.venus`).
    ///   - transit: The previous transit.
    /// - Returns: The next transit.
    /// - Throws: `AstronomyError` if the search fails.
    public static func next(body: CelestialBody, after transit: Transit) throws -> Transit {
        try EngineTransits.next(body: body, after: transit.peak)
    }

    /// Finds all transits within a date range.
    ///
    /// - Parameters:
    ///   - body: The body to search for (must be `.mercury` or `.venus`).
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of transits.
    /// - Throws: `AstronomyError` if the search fails.
    public static func transits(
        body: CelestialBody,
        from startTime: AstroTime,
        to endTime: AstroTime
    ) throws -> [Transit] {
        guard body == .mercury || body == .venus else { throw AstronomyError.invalidBody }
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var transits: [Transit] = []
        var current: Transit
        do {
            current = try search(body: body, after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.peak < endTime {
            guard transits.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            transits.append(current)
            do {
                current = try next(body: body, after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return transits
    }
}
