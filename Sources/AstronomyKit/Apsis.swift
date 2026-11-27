//
//  Apsis.swift
//  AstronomyKit
//
//  Apsis (perigee/apogee, perihelion/aphelion) calculations.
//

import Foundation

// MARK: - Apsis Kind

/// The type of apsis: closest or farthest approach.
public enum ApsisKind: Sendable, Equatable, Hashable, Codable {
    /// The body is at its closest approach (perigee for Moon, perihelion for planets).
    case pericenter

    /// The body is at its farthest distance (apogee for Moon, aphelion for planets).
    case apocenter

    /// A human-readable name for the Moon's apsis.
    public var lunarName: String {
        switch self {
        case .pericenter: return "Perigee"
        case .apocenter: return "Apogee"
        }
    }

    /// A human-readable name for a planet's apsis relative to the Sun.
    public var solarName: String {
        switch self {
        case .pericenter: return "Perihelion"
        case .apocenter: return "Aphelion"
        }
    }
}

extension ApsisKind: CustomStringConvertible {
    /// A textual representation of the apsis kind, using the solar terminology.
    public var description: String { solarName }
}

// MARK: - Apsis

/// An apsis event: the closest or farthest point in an orbit.
///
/// For the Moon orbiting Earth, use `lunarName` for terminology
/// (perigee/apogee). For planets orbiting the Sun, use `solarName`
/// (perihelion/aphelion).
///
/// ## Example
///
/// ```swift
/// let apsis = try Moon.searchApsis(after: .now)
/// print("\(apsis.kind.lunarName) at \(apsis.time)")
/// print("Distance: \(Int(apsis.distanceKM)) km")
/// ```
public struct Apsis: Sendable, Equatable {
    /// Whether this is a closest or farthest approach.
    public let kind: ApsisKind

    /// The date and time of the apsis.
    public let time: AstroTime

    /// The distance between the centers of the bodies in AU.
    public let distanceAU: Double

    /// The distance between the centers of the bodies in kilometers.
    public let distanceKM: Double
}

extension Apsis: CustomStringConvertible {
    /// A textual representation showing the apsis type, time, and distance in kilometers.
    public var description: String {
        String(format: "%@ at %@: %.0f km", kind.solarName, time.description, distanceKM)
    }
}

// MARK: - Moon Apsis Functions

extension Moon {
    /// Searches for the next lunar apsis (perigee or apogee).
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError.badTime` if the search would evaluate the Moon outside
    ///   the accepted time range (see ``AstroTime``), or another `AstronomyError` if the
    ///   search fails.
    public static func searchApsis(after startTime: AstroTime) throws -> Apsis {
        try EngineApsis.searchLunarApsis(after: startTime)
    }

    /// Finds the next lunar apsis after a given apsis.
    ///
    /// Use this to iterate through alternating perigees and apogees.
    ///
    /// - Parameter apsis: The previous apsis.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextApsis(after apsis: Apsis) throws -> Apsis {
        try EngineApsis.nextLunarApsis(after: apsis)
    }

    /// Returns all lunar apsides within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of apsis events.
    /// - Throws: `AstronomyError` if the search fails.
    public static func apsides(from startTime: AstroTime, to endTime: AstroTime) throws -> [Apsis] {
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var apsides: [Apsis] = []
        var current: Apsis
        do {
            current = try searchApsis(after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.time < endTime {
            guard apsides.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            apsides.append(current)
            do {
                current = try nextApsis(after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return apsides
    }
}

// MARK: - Planet Apsis Functions

extension CelestialBody {
    /// Searches for the next planetary apsis (perihelion or aphelion).
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError.badTime` if the search would evaluate the planet
    ///   outside the accepted time range (see ``AstroTime``), which includes a
    ///   non-finite `startTime`, or another `AstronomyError` if the calculation fails.
    ///   The search samples the orbit ahead of `startTime` (Neptune's up to about 123
    ///   years ahead and 14 years behind), so it can throw well inside the range's edges.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let apsis = try CelestialBody.mars.searchApsis(after: .now)
    /// print("Mars \(apsis.kind.solarName): \(apsis.time)")
    /// ```
    public func searchApsis(after startTime: AstroTime) throws -> Apsis {
        try EngineApsis.searchPlanetApsis(of: self, after: startTime)
    }

    /// Finds the next planetary apsis after a given apsis.
    ///
    /// - Parameter apsis: The previous apsis.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError` if the search fails.
    public func nextApsis(after apsis: Apsis) throws -> Apsis {
        try EngineApsis.nextPlanetApsis(of: self, after: apsis)
    }

    /// Returns all planetary apsides within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of apsis events.
    /// - Throws: `AstronomyError` if the search fails.
    public func apsides(from startTime: AstroTime, to endTime: AstroTime) throws -> [Apsis] {
        switch self {
        case .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
            break
        default:
            throw AstronomyError.invalidBody
        }
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var apsides: [Apsis] = []
        var current: Apsis
        do {
            current = try searchApsis(after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.time < endTime {
            guard apsides.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            apsides.append(current)
            do {
                current = try nextApsis(after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return apsides
    }
}
