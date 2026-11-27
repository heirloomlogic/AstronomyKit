//
//  MoonPhase.swift
//  AstronomyKit
//
//  Moon phase calculations.
//

import Foundation

// MARK: - Moon Phase

/// A phase of the Moon.
public enum MoonPhase: Int, CaseIterable, Sendable, Codable {
    /// New Moon (0° phase angle).
    case new = 0

    /// First Quarter (90° phase angle).
    case firstQuarter = 1

    /// Full Moon (180° phase angle).
    case full = 2

    /// Third/Last Quarter (270° phase angle).
    case thirdQuarter = 3

    /// The display name of this phase.
    public var name: String {
        switch self {
        case .new: return "New Moon"
        case .firstQuarter: return "First Quarter"
        case .full: return "Full Moon"
        case .thirdQuarter: return "Third Quarter"
        }
    }

    /// The emoji representation of this phase.
    public var emoji: String {
        switch self {
        case .new: return "🌑"
        case .firstQuarter: return "🌓"
        case .full: return "🌕"
        case .thirdQuarter: return "🌗"
        }
    }

    /// The ecliptic longitude of this phase in degrees.
    public var longitude: Double {
        Double(rawValue) * 90.0
    }
}

extension MoonPhase: CustomStringConvertible {
    /// A textual representation showing the emoji and name of the phase.
    public var description: String { "\(emoji) \(name)" }
}

// MARK: - Moon Quarter

/// A lunar quarter event (the time when a specific moon phase occurs).
public struct MoonQuarter: Sendable, Equatable, Hashable {
    /// The phase of the Moon.
    public let phase: MoonPhase

    /// The time when this phase occurs.
    public let time: AstroTime
}

extension MoonQuarter: CustomStringConvertible {
    /// A textual representation showing the phase emoji, name, and time.
    public var description: String {
        "\(phase.emoji) \(phase.name) at \(time)"
    }
}

// MARK: - Moon Functions

/// Moon-specific calculations.
public enum Moon {
    /// Calculates the Moon's phase angle at the specified time.
    ///
    /// - Parameter time: The time at which to calculate the phase.
    /// - Returns: The phase angle in degrees (0-360).
    ///   - 0° = New Moon
    ///   - 90° = First Quarter
    ///   - 180° = Full Moon
    ///   - 270° = Third Quarter
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func phaseAngle(at time: AstroTime) throws -> Double {
        try EngineEvents.moonPhase(at: time)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        ((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Determines the approximate phase name for the given angle.
    ///
    /// - Parameter angle: The phase angle in degrees (0-360).
    /// - Returns: A human-readable phase name.
    public static func phaseName(for angle: Double) -> String {
        let normalized = normalizedAngle(angle)
        switch normalized {
        case 0..<22.5, 337.5..<360:
            return "New Moon"
        case 22.5..<67.5:
            return "Waxing Crescent"
        case 67.5..<112.5:
            return "First Quarter"
        case 112.5..<157.5:
            return "Waxing Gibbous"
        case 157.5..<202.5:
            return "Full Moon"
        case 202.5..<247.5:
            return "Waning Gibbous"
        case 247.5..<292.5:
            return "Third Quarter"
        case 292.5..<337.5:
            return "Waning Crescent"
        default:
            return "Unknown"
        }
    }

    /// The emoji for the given phase angle.
    ///
    /// - Parameter angle: The phase angle in degrees (0-360).
    /// - Returns: An emoji representing the moon phase.
    public static func emoji(for angle: Double) -> String {
        let normalized = normalizedAngle(angle)
        switch normalized {
        case 0..<22.5, 337.5..<360:
            return "🌑"
        case 22.5..<67.5:
            return "🌒"
        case 67.5..<112.5:
            return "🌓"
        case 112.5..<157.5:
            return "🌔"
        case 157.5..<202.5:
            return "🌕"
        case 202.5..<247.5:
            return "🌖"
        case 247.5..<292.5:
            return "🌗"
        case 292.5..<337.5:
            return "🌘"
        default:
            return "🌙"
        }
    }

    /// The illuminated fraction of the Moon (0.0 to 1.0).
    ///
    /// - Parameter angle: The phase angle in degrees.
    /// - Returns: The illumination fraction.
    public static func illumination(for angle: Double) -> Double {
        (1 - cos(angle * .pi / 180)) / 2
    }

    /// Searches for the next occurrence of a specific moon phase.
    ///
    /// - Parameters:
    ///   - phase: The phase to search for.
    ///   - startTime: The time to start searching from.
    ///   - limitDays: Maximum days to search. Defaults to 60.
    /// - Returns: The time when the phase occurs, or `nil` if it does not
    ///   occur within `limitDays`.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func searchPhase(
        _ phase: MoonPhase,
        after startTime: AstroTime,
        limitDays: Double = 60
    ) throws -> AstroTime? {
        do {
            return try EngineEvents.searchMoonPhase(
                targetLon: phase.longitude,
                after: startTime,
                limitDays: limitDays
            )
        } catch AstronomyError.noMoonQuarter {
            return nil
        }
    }

    /// Searches for the next moon quarter (new, first, full, or third).
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next moon quarter event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchQuarter(after startTime: AstroTime) throws -> MoonQuarter {
        try EngineEvents.searchMoonQuarter(after: startTime)
    }

    /// Finds the next moon quarter after a given quarter.
    ///
    /// - Parameter quarter: The previous quarter.
    /// - Returns: The next quarter event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextQuarter(after quarter: MoonQuarter) throws -> MoonQuarter {
        try EngineEvents.nextMoonQuarter(after: quarter)
    }

    /// Returns all moon quarters within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of moon quarter events.
    /// - Throws: `AstronomyError` if the search fails.
    public static func quarters(
        from startTime: AstroTime,
        to endTime: AstroTime
    ) throws -> [MoonQuarter] {
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var quarters: [MoonQuarter] = []
        var current: MoonQuarter
        do {
            current = try searchQuarter(after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.time < endTime {
            guard quarters.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            quarters.append(current)
            do {
                current = try nextQuarter(after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return quarters
    }

    /// Calculates the Moon's geocentric position.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The geocentric position vector.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func geocentricPosition(at time: AstroTime) throws -> Vector3D {
        try EnginePositions.geoMoon(at: time)
    }

    /// Calculates the Moon's ecliptic coordinates.
    ///
    /// The coordinates are geocentric and referred to the true ecliptic and
    /// equinox of date.
    ///
    /// - Parameter time: The time at which to calculate.
    /// - Returns: The ecliptic coordinates.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    public static func ecliptic(at time: AstroTime) throws -> Ecliptic {
        try EnginePositions.eclipticGeoMoon(at: time)
    }

    /// Calculates the Moon's geocentric state (position and velocity).
    ///
    /// The state vector contains both position and velocity, which is useful
    /// for calculating the Moon's speed and direction of motion.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric state vector with position in AU and velocity in AU/day.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let state = try Moon.geoState(at: .now)
    /// print("Moon position: \(state.position)")
    /// print("Moon velocity: \(state.velocity)")
    /// ```
    public static func geoState(at time: AstroTime) throws -> StateVector {
        try EnginePositions.geoMoonState(at: time)
    }
}
