//
//  Apsis.swift
//  AstronomyKit
//
//  Apsis (perigee/apogee, perihelion/aphelion) calculations.
//

import CLibAstronomy

// MARK: - Apsis Kind

/// The type of apsis: closest or farthest approach.
public enum ApsisKind: Sendable, Equatable, Hashable, Codable {
    /// The body is at its closest approach (perigee for Moon, perihelion for planets).
    case pericenter

    /// The body is at its farthest distance (apogee for Moon, aphelion for planets).
    case apocenter

    internal init(_ raw: astro_apsis_kind_t) {
        switch raw {
        case APSIS_PERICENTER:
            self = .pericenter
        default:
            self = .apocenter
        }
    }

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

    /// Creates an apsis from the C structure.
    internal init(_ raw: astro_apsis_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.kind = ApsisKind(raw.kind)
        self.time = AstroTime(raw: raw.time)
        self.distanceAU = raw.dist_au
        self.distanceKM = raw.dist_km
    }
}

extension Apsis: CustomStringConvertible {
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
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchApsis(after startTime: AstroTime) throws -> Apsis {
        let result = Astronomy_SearchLunarApsis(startTime.raw)
        return try Apsis(result)
    }

    /// Finds the next lunar apsis after a given apsis.
    ///
    /// Use this to iterate through alternating perigees and apogees.
    ///
    /// - Parameter apsis: The previous apsis.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextApsis(after apsis: Apsis) throws -> Apsis {
        let raw = astro_apsis_t(
            status: ASTRO_SUCCESS,
            time: apsis.time.raw,
            kind: apsis.kind == .pericenter ? APSIS_PERICENTER : APSIS_APOCENTER,
            dist_au: apsis.distanceAU,
            dist_km: apsis.distanceKM
        )
        let result = Astronomy_NextLunarApsis(raw)
        return try Apsis(result)
    }

    /// Returns all lunar apsides within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of apsis events.
    /// - Throws: `AstronomyError` if the search fails.
    public static func apsides(from startTime: AstroTime, to endTime: AstroTime) throws -> [Apsis] {
        var apsides: [Apsis] = []
        var current = try searchApsis(after: startTime)

        while current.time < endTime {
            apsides.append(current)
            current = try nextApsis(after: current)
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
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let apsis = try CelestialBody.mars.searchApsis(after: .now)
    /// print("Mars \(apsis.kind.solarName): \(apsis.time)")
    /// ```
    public func searchApsis(after startTime: AstroTime) throws -> Apsis {
        let result = Astronomy_SearchPlanetApsis(raw, startTime.raw)
        return try Apsis(result)
    }

    /// Finds the next planetary apsis after a given apsis.
    ///
    /// - Parameter apsis: The previous apsis.
    /// - Returns: The next apsis event.
    /// - Throws: `AstronomyError` if the search fails.
    public func nextApsis(after apsis: Apsis) throws -> Apsis {
        let raw = astro_apsis_t(
            status: ASTRO_SUCCESS,
            time: apsis.time.raw,
            kind: apsis.kind == .pericenter ? APSIS_PERICENTER : APSIS_APOCENTER,
            dist_au: apsis.distanceAU,
            dist_km: apsis.distanceKM
        )
        let result = Astronomy_NextPlanetApsis(self.raw, raw)
        return try Apsis(result)
    }

    /// Returns all planetary apsides within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of apsis events.
    /// - Throws: `AstronomyError` if the search fails.
    public func apsides(from startTime: AstroTime, to endTime: AstroTime) throws -> [Apsis] {
        var apsides: [Apsis] = []
        var current = try searchApsis(after: startTime)

        while current.time < endTime {
            apsides.append(current)
            current = try nextApsis(after: current)
        }

        return apsides
    }
}
