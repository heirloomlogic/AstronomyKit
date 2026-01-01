//
//  MoonPhase.swift
//  AstronomyKit
//
//  Moon phase calculations.
//

import CLibAstronomy
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
    public var description: String { "\(emoji) \(name)" }
}

// MARK: - Moon Quarter

/// A lunar quarter event (the time when a specific moon phase occurs).
public struct MoonQuarter: Sendable, Equatable {
    /// The phase of the Moon.
    public let phase: MoonPhase

    /// The time when this phase occurs.
    public let time: AstroTime

    /// Creates a moon quarter from the C structure.
    internal init(_ raw: astro_moon_quarter_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        guard let phase = MoonPhase(rawValue: Int(raw.quarter)) else {
            throw AstronomyError.internalError
        }
        self.phase = phase
        self.time = AstroTime(raw: raw.time)
    }
}

extension MoonQuarter: CustomStringConvertible {
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
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func phaseAngle(at time: AstroTime) throws -> Double {
        let result = Astronomy_MoonPhase(time.raw)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return result.angle
    }

    /// Determines the approximate phase name for the given angle.
    ///
    /// - Parameter angle: The phase angle in degrees (0-360).
    /// - Returns: A human-readable phase name.
    public static func phaseName(for angle: Double) -> String {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
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
        let normalized = angle.truncatingRemainder(dividingBy: 360)
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
    /// - Returns: The time when the phase occurs.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchPhase(
        _ phase: MoonPhase,
        after startTime: AstroTime,
        limitDays: Double = 60
    ) throws -> AstroTime {
        let result = Astronomy_SearchMoonPhase(phase.longitude, startTime.raw, limitDays)
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        return AstroTime(raw: result.time)
    }

    /// Searches for the next moon quarter (new, first, full, or third).
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next moon quarter event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchQuarter(after startTime: AstroTime) throws -> MoonQuarter {
        let result = Astronomy_SearchMoonQuarter(startTime.raw)
        return try MoonQuarter(result)
    }

    /// Finds the next moon quarter after a given quarter.
    ///
    /// - Parameter quarter: The previous quarter.
    /// - Returns: The next quarter event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextQuarter(after quarter: MoonQuarter) throws -> MoonQuarter {
        let raw = astro_moon_quarter_t(
            status: ASTRO_SUCCESS,
            quarter: Int32(quarter.phase.rawValue),
            time: quarter.time.raw
        )
        let result = Astronomy_NextMoonQuarter(raw)
        return try MoonQuarter(result)
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
        var quarters: [MoonQuarter] = []
        var current = try searchQuarter(after: startTime)

        while current.time < endTime {
            quarters.append(current)
            current = try nextQuarter(after: current)
        }

        return quarters
    }

    /// Calculates the Moon's geocentric position.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The geocentric position vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geoPosition(at time: AstroTime) throws -> Vector3D {
        let result = Astronomy_GeoMoon(time.raw)
        return try Vector3D(result)
    }

    /// Calculates the Moon's ecliptic coordinates.
    ///
    /// - Parameter time: The time at which to calculate.
    /// - Returns: The ecliptic coordinates.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticPosition(at time: AstroTime) throws -> Spherical {
        let result = Astronomy_EclipticGeoMoon(time.raw)
        return try Spherical(result)
    }

    /// Calculates the Moon's geocentric state (position and velocity).
    ///
    /// The state vector contains both position and velocity, which is useful
    /// for calculating the Moon's speed and direction of motion.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric state vector with position in AU and velocity in AU/day.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let state = try Moon.geoState(at: .now)
    /// print("Moon position: \(state.position)")
    /// print("Moon velocity: \(state.velocity)")
    /// ```
    public static func geoState(at time: AstroTime) throws -> StateVector {
        let result = Astronomy_GeoMoonState(time.raw)
        return try StateVector(result)
    }
}
