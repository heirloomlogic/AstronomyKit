//
//  CelestialBody.swift
//  AstronomyKit
//
//  Enumeration of celestial bodies.
//

import CLibAstronomy

/// A celestial body in the solar system.
///
/// This enum represents the Sun, Moon, planets, and select moons
/// that can be used in astronomical calculations.
///
/// ## Planets and Major Bodies
///
/// ```swift
/// let mars = CelestialBody.mars
/// print(mars.name) // "Mars"
/// ```
///
/// ## Iterating Over Bodies
///
/// ```swift
/// for body in CelestialBody.allCases {
///     print(body.name)
/// }
/// ```
public enum CelestialBody: Int32, CaseIterable, Sendable {
    /// Mercury.
    case mercury = 0

    /// Venus.
    case venus = 1

    /// The Earth (for heliocentric calculations).
    case earth = 2

    /// Mars.
    case mars = 3

    /// Jupiter.
    case jupiter = 4

    /// Saturn.
    case saturn = 5

    /// Uranus.
    case uranus = 6

    /// Neptune.
    case neptune = 7

    /// Pluto.
    case pluto = 8

    /// The Sun.
    case sun = 9

    /// The Moon.
    case moon = 10

    /// The Earth-Moon Barycenter.
    case emb = 11

    /// The Solar System Barycenter.
    case ssb = 12

    /// Io, moon of Jupiter.
    case io = 21

    /// Europa, moon of Jupiter.
    case europa = 22

    /// Ganymede, moon of Jupiter.
    case ganymede = 23

    /// Callisto, moon of Jupiter.
    case callisto = 24

    // MARK: - Internal (Fixed Star Support)

    /// Internal star slot used by FixedStar.
    /// Use the `FixedStar` type instead of accessing this directly.
    case star1 = 101

    /// The underlying C body enum value.
    internal var raw: astro_body_t {
        astro_body_t(rawValue: rawValue)
    }

    /// Creates a body from the C enum value.
    internal init?(raw: astro_body_t) {
        self.init(rawValue: raw.rawValue)
    }

    /// The human-readable name of this body.
    public var name: String {
        String(cString: Astronomy_BodyName(raw))
    }

    /// Creates a body from its name.
    ///
    /// - Parameter name: The name of the body (case-insensitive).
    /// - Returns: The matching body, or `nil` if not found.
    public init?(name: String) {
        let body = Astronomy_BodyCode(name)
        guard body.rawValue >= 0 else { return nil }
        self.init(raw: body)
    }

    /// The orbital period around the Sun in days.
    ///
    /// Returns `nil` for bodies that don't orbit the Sun (Moon, etc.)
    /// or for the Sun itself.
    public var orbitalPeriod: Double? {
        let period = Astronomy_PlanetOrbitalPeriod(raw)
        return period > 0 ? period : nil
    }

    /// The gravitational parameter (mass × G) in AU³/day².
    ///
    /// Returns `nil` for bodies without a defined mass.
    public var massProduct: Double? {
        let mp = Astronomy_MassProduct(raw)
        return mp > 0 ? mp : nil
    }
}

// MARK: - Body Categories

extension CelestialBody {
    /// The major planets (Mercury through Neptune).
    public static let planets: [CelestialBody] = [
        .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune,
    ]

    /// The inner planets (Mercury, Venus, Mars).
    public static let innerPlanets: [CelestialBody] = [
        .mercury, .venus, .mars,
    ]

    /// The outer planets (Jupiter, Saturn, Uranus, Neptune).
    public static let outerPlanets: [CelestialBody] = [
        .jupiter, .saturn, .uranus, .neptune,
    ]

    /// The Galilean moons of Jupiter.
    public static let galileanMoons: [CelestialBody] = [
        .io, .europa, .ganymede, .callisto,
    ]

    /// Whether this body is a major planet.
    public var isPlanet: Bool {
        Self.planets.contains(self)
    }

    /// Whether this body is visible to the naked eye.
    public var isNakedEyeVisible: Bool {
        switch self {
        case .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension CelestialBody: CustomStringConvertible {
    public var description: String { name }
}

// MARK: - Codable

extension CelestialBody: Codable {}

// MARK: - Hashable

extension CelestialBody: Hashable {}
