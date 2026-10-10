//
//  Elongation.swift
//  AstronomyKit
//
//  Elongation and visibility calculations.
//

// MARK: - Visibility

/// Indicates whether a body is best seen in the morning or evening.
public enum Visibility: Sendable, Equatable, Hashable, Codable {
    /// The body is best visible in the morning, before sunrise.
    case morning

    /// The body is best visible in the evening, after sunset.
    case evening

    /// A human-readable description.
    public var name: String {
        switch self {
        case .morning: return "Morning"
        case .evening: return "Evening"
        }
    }
}

extension Visibility: CustomStringConvertible {
    /// A textual representation indicating morning or evening visibility.
    public var description: String { name }
}

// MARK: - Elongation

/// Information about a body's angular separation from the Sun.
///
/// Elongation is the angle between a planet and the Sun as seen from Earth.
/// This is important for observing planets, especially Mercury and Venus.
///
/// ## Example
///
/// ```swift
/// let elongation = try CelestialBody.venus.elongation(at: .now)
/// print("Venus is a \(elongation.visibility) star at \(elongation.angle)°")
/// ```
public struct Elongation: Sendable, Equatable {
    /// The date and time of the observation.
    public let time: AstroTime

    /// Whether the body is best seen in the morning or evening.
    public let visibility: Visibility

    /// The angular separation from the Sun in degrees.
    ///
    /// Values range from 0° (conjunction with the Sun) to 180° (opposition).
    public let angle: Double

    /// The difference between the ecliptic longitudes of the body and Sun.
    ///
    /// This is the angular separation measured along the ecliptic plane.
    public let eclipticSeparation: Double

    /// Creates an elongation result from the engine's, at `time`.
    init(_ elongation: Engine.Elongation, at time: AstroTime) {
        self.time = time
        self.visibility = elongation.visibility
        self.angle = elongation.elongation
        self.eclipticSeparation = elongation.eclipticSeparation
    }
}

extension Elongation: CustomStringConvertible {
    /// A textual representation showing visibility and angular separation from the Sun.
    public var description: String {
        String(format: "%@ star, %.1f° from Sun", visibility.name, angle)
    }
}

// MARK: - CelestialBody Extensions

extension CelestialBody {
    /// Calculates the elongation of this body at the specified time.
    ///
    /// Returns information about the angular separation from the Sun
    /// and whether the body is best seen in the morning or evening.
    ///
    /// - Parameter time: The time at which to calculate the elongation.
    /// - Returns: The elongation data for this body.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let elong = try CelestialBody.mercury.elongation(at: .now)
    /// if elong.visibility == .evening {
    ///     print("Mercury visible after sunset")
    /// }
    /// ```
    public func elongation(at time: AstroTime) throws -> Elongation {
        Elongation(try Engine.Positions.elongation(of: self, at: time.engine), at: time)
    }

    /// Searches for the next maximum elongation of this body.
    ///
    /// Maximum elongation is when a planet reaches its greatest angular
    /// separation from the Sun, making it easiest to observe. This is
    /// primarily useful for Mercury and Venus.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The elongation data at maximum separation.
    /// - Throws: `AstronomyError` if the search fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let maxElong = try CelestialBody.mercury.searchMaxElongation(after: .now)
    /// print("Mercury max elongation: \(maxElong.angle)° on \(maxElong.time)")
    /// ```
    public func searchMaxElongation(after startTime: AstroTime) throws -> Elongation {
        let result = try Engine.Events.searchMaximumElongation(of: self, after: startTime.engine)
        return Elongation(result, at: AstroTime(result.time))
    }
}
