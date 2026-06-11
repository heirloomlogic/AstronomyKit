//
//  Time.swift
//  AstronomyKit
//
//  Time representation for astronomical calculations.
//

import CLibAstronomy
import Foundation

/// Represents a moment in time for astronomical calculations.
///
/// `AstroTime` is the fundamental time type in AstronomyKit. It stores both
/// Universal Time (UT1/UTC) and Terrestrial Time (TT) for accurate calculations.
///
/// ## Creating Times
///
/// ```swift
/// // Current time
/// let now = AstroTime.now
///
/// // From a Foundation Date
/// let time = AstroTime(Date())
///
/// // From calendar components
/// let newYear = AstroTime(year: 2025, month: 1, day: 1)
/// ```
///
/// ## Time Arithmetic
///
/// ```swift
/// let tomorrow = now.addingDays(1)
/// let lastWeek = now.addingDays(-7)
/// ```
public struct AstroTime: Sendable {
    /// The underlying C time structure.
    var raw: astro_time_t

    /// Universal Time days since noon on January 1, 2000.
    ///
    /// This value is appropriate for calculations involving Earth's rotation,
    /// such as rise/set times and sidereal time.
    public var universalTime: Double { raw.ut }

    /// Terrestrial Time days since noon on January 1, 2000.
    ///
    /// This value is used for calculations not involving Earth's rotation,
    /// such as planetary orbits.
    public var terrestrialTime: Double { raw.tt }

    /// The current time.
    public static var now: AstroTime {
        AstroTime(raw: Astronomy_CurrentTime())
    }

    /// Creates a time from the underlying C structure.
    init(raw: astro_time_t) {
        self.raw = raw
    }

    /// Seconds from the Unix epoch (1970-01-01 00:00 UTC) to the J2000
    /// reference moment used by ``universalTime`` (2000-01-01 12:00 UTC).
    private static let j2000UnixOffset = 946_728_000.0

    /// Creates a time from a Foundation `Date`.
    ///
    /// - Parameter date: The date to convert.
    public init(_ date: Date) {
        self.init(ut: (date.timeIntervalSince1970 - Self.j2000UnixOffset) / 86_400)
    }

    /// Creates a time from calendar components.
    ///
    /// - Parameters:
    ///   - year: The year (e.g., 2025).
    ///   - month: The month (1-12).
    ///   - day: The day of month (1-31).
    ///   - hour: The hour (0-23). Defaults to 0.
    ///   - minute: The minute (0-59). Defaults to 0.
    ///   - second: The second (0.0-59.999...). Defaults to 0.
    public init(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Double = 0
    ) {
        self.raw = Astronomy_MakeTime(
            Int32(year),
            Int32(month),
            Int32(day),
            Int32(hour),
            Int32(minute),
            second
        )
    }

    /// Creates a time from Universal Time days since J2000.
    ///
    /// - Parameter ut: Days since noon on January 1, 2000 (UTC).
    public init(ut: Double) {
        self.raw = Astronomy_TimeFromDays(ut)
    }

    /// Creates a time from Terrestrial Time days since J2000.
    ///
    /// Terrestrial Time is used for calculations not involving Earth's rotation
    /// (planetary orbits, eclipses, etc.). This initializer is the inverse of
    /// ``init(ut:)`` — it starts from a TT value and derives the corresponding UT.
    ///
    /// - Parameter tt: Terrestrial Time days since noon on January 1, 2000.
    public init(tt: Double) {
        self.raw = Astronomy_TerrestrialTime(tt)
    }

    /// Converts this time to a Foundation `Date`.
    public var date: Date {
        Date(timeIntervalSince1970: raw.ut * 86_400 + Self.j2000UnixOffset)
    }

    /// Returns a new time by adding the specified number of days.
    ///
    /// - Parameter days: The number of days to add. Can be negative.
    /// - Returns: A new `AstroTime` offset by the given days.
    public func addingDays(_ days: Double) -> AstroTime {
        AstroTime(raw: Astronomy_AddDays(raw, days))
    }

    /// Returns a new time by adding the specified number of hours.
    ///
    /// - Parameter hours: The number of hours to add. Can be negative.
    /// - Returns: A new `AstroTime` offset by the given hours.
    public func addingHours(_ hours: Double) -> AstroTime {
        addingDays(hours / 24.0)
    }

    /// The sidereal time at the prime meridian (Greenwich).
    ///
    /// Sidereal time is the hour angle of the vernal equinox,
    /// measured in sidereal hours (0 to 24).
    public var siderealTime: Double {
        var copy = raw
        return Astronomy_SiderealTime(&copy)
    }

    /// The local sidereal time at a given geographic longitude.
    ///
    /// - Parameter longitude: The geographic longitude in degrees (-180 to +180).
    ///   Positive values are east of the prime meridian.
    /// - Returns: The local sidereal time in hours (0 to 24).
    public func siderealTime(longitude: Double) -> Double {
        // Local sidereal time = Greenwich sidereal time + longitude/15
        // (since 15° = 1 hour of sidereal time)
        var lst = siderealTime + longitude / 15.0
        // Normalize to 0-24 range
        while lst < 0 { lst += 24.0 }
        while lst >= 24 { lst -= 24.0 }
        return lst
    }
}

// MARK: - Protocol Conformances

extension AstroTime: Equatable {
    /// Returns whether two `AstroTime` values represent the same instant.
    public static func == (lhs: AstroTime, rhs: AstroTime) -> Bool {
        lhs.universalTime == rhs.universalTime
    }
}

extension AstroTime: Comparable {
    /// Returns whether the left-hand time occurs before the right-hand time.
    public static func < (lhs: AstroTime, rhs: AstroTime) -> Bool {
        lhs.universalTime < rhs.universalTime
    }
}

extension AstroTime: Hashable {
    /// Hashes the essential components of this time value.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(universalTime)
    }
}

extension AstroTime: CustomStringConvertible {
    // ISO8601DateFormatter is documented to be thread-safe, so a shared
    // instance avoids re-allocating a formatter on every description call.
    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// An ISO 8601 formatted string representation of this time.
    public var description: String {
        Self.iso8601Formatter.string(from: date)
    }
}

// MARK: - Codable

extension AstroTime: Codable {
    /// Creates a time by decoding a Universal Time value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let ut = try container.decode(Double.self)
        self.init(ut: ut)
    }

    /// Encodes this time as its Universal Time value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(universalTime)
    }
}
