//
//  Transit.swift
//  AstronomyKit
//
//  Mercury and Venus transit calculations.
//

import CLibAstronomy
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
public struct Transit: Sendable, Equatable {
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

    /// Creates a transit from the C structure.
    internal init(body: CelestialBody, _ raw: astro_transit_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.body = body
        self.start = AstroTime(raw: raw.start)
        self.peak = AstroTime(raw: raw.peak)
        self.finish = AstroTime(raw: raw.finish)
        self.separation = raw.separation
    }
}

extension Transit: CustomStringConvertible {
    public var description: String {
        String(
            format: "%@ Transit on %@, separation: %.1f arcmin",
            body.name, peak.description, separation)
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
        let result = Astronomy_SearchTransit(body.raw, startTime.raw)
        return try Transit(body: body, result)
    }

    /// Finds the next transit after a given transit.
    ///
    /// - Parameters:
    ///   - body: The body to search for (must be `.mercury` or `.venus`).
    ///   - transit: The previous transit.
    /// - Returns: The next transit.
    /// - Throws: `AstronomyError` if the search fails.
    public static func next(body: CelestialBody, after transit: Transit) throws -> Transit {
        let result = Astronomy_NextTransit(body.raw, transit.peak.raw)
        return try Transit(body: body, result)
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
        var transits: [Transit] = []
        var current = try search(body: body, after: startTime)

        while current.peak < endTime {
            transits.append(current)
            current = try next(body: body, after: current)
        }

        return transits
    }
}
