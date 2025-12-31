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
    internal var raw: astro_time_t

    /// Universal Time days since noon on January 1, 2000.
    ///
    /// This value is appropriate for calculations involving Earth's rotation,
    /// such as rise/set times and sidereal time.
    public var ut: Double { raw.ut }

    /// Terrestrial Time days since noon on January 1, 2000.
    ///
    /// This value is used for calculations not involving Earth's rotation,
    /// such as planetary orbits.
    public var tt: Double { raw.tt }

    /// The current time.
    public static var now: AstroTime {
        AstroTime(raw: Astronomy_CurrentTime())
    }

    /// Creates a time from the underlying C structure.
    internal init(raw: astro_time_t) {
        self.raw = raw
    }

    /// Creates a time from a Foundation `Date`.
    ///
    /// - Parameter date: The date to convert.
    public init(_ date: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: date
        )

        self.raw = Astronomy_MakeTime(
            Int32(components.year ?? 2_000),
            Int32(components.month ?? 1),
            Int32(components.day ?? 1),
            Int32(components.hour ?? 0),
            Int32(components.minute ?? 0),
            Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000
        )
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

    /// Converts this time to a Foundation `Date`.
    public var date: Date {
        let utc = Astronomy_UtcFromTime(raw)
        var components = DateComponents()
        components.year = Int(utc.year)
        components.month = Int(utc.month)
        components.day = Int(utc.day)
        components.hour = Int(utc.hour)
        components.minute = Int(utc.minute)
        components.second = Int(utc.second)
        components.nanosecond = Int((utc.second - Double(Int(utc.second))) * 1_000_000_000)
        components.timeZone = TimeZone(identifier: "UTC")

        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components) ?? Date()
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
}

// MARK: - Protocol Conformances

extension AstroTime: Equatable {
    public static func == (lhs: AstroTime, rhs: AstroTime) -> Bool {
        lhs.ut == rhs.ut
    }
}

extension AstroTime: Comparable {
    public static func < (lhs: AstroTime, rhs: AstroTime) -> Bool {
        lhs.ut < rhs.ut
    }
}

extension AstroTime: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ut)
    }
}

extension AstroTime: CustomStringConvertible {
    public var description: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Codable

extension AstroTime: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let ut = try container.decode(Double.self)
        self.init(ut: ut)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ut)
    }
}
