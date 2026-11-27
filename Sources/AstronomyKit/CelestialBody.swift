//
//  CelestialBody.swift
//  AstronomyKit
//
//  Enumeration of celestial bodies.
//

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
public enum CelestialBody: Sendable, Equatable, Hashable, CaseIterable {
    /// Mercury.
    case mercury

    /// Venus.
    case venus

    /// The Earth (for heliocentric calculations).
    case earth

    /// Mars.
    case mars

    /// Jupiter.
    case jupiter

    /// Saturn.
    case saturn

    /// Uranus.
    case uranus

    /// Neptune.
    case neptune

    /// Pluto.
    case pluto

    /// The Sun.
    case sun

    /// The Moon.
    case moon

    /// The Earth-Moon Barycenter.
    case earthMoonBarycenter

    /// The Solar System Barycenter.
    case solarSystemBarycenter

    /// Io, moon of Jupiter.
    case io

    /// Europa, moon of Jupiter.
    case europa

    /// Ganymede, moon of Jupiter.
    case ganymede

    /// Callisto, moon of Jupiter.
    case callisto

    /// The human-readable name of this body.
    public var name: String {
        switch self {
        case .mercury: return "Mercury"
        case .venus: return "Venus"
        case .earth: return "Earth"
        case .mars: return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        case .uranus: return "Uranus"
        case .neptune: return "Neptune"
        case .pluto: return "Pluto"
        case .sun: return "Sun"
        case .moon: return "Moon"
        case .earthMoonBarycenter: return "EMB"
        case .solarSystemBarycenter: return "SSB"
        case .io: return "Io"
        case .europa: return "Europa"
        case .ganymede: return "Ganymede"
        case .callisto: return "Callisto"
        }
    }

    /// Creates a body from its name.
    ///
    /// - Parameter name: The name of the body (case-insensitive),
    ///   e.g. "Mars", "moon", "EMB".
    public init?(name: String) {
        guard
            let match = Self.allCases.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })
        else { return nil }
        self = match
    }

    /// The orbital period around the Sun in days.
    ///
    /// Returns `nil` for bodies that don't orbit the Sun (Moon, etc.)
    /// or for the Sun itself.
    public var orbitalPeriod: Double? {
        let period = EngineMath.planetOrbitalPeriod(of: self)
        return period > 0 ? period : nil
    }

    /// The gravitational parameter (mass × G) in AU³/day².
    ///
    /// Returns `nil` for bodies without a defined mass.
    public var massProduct: Double? {
        let massProduct = EngineMath.massProduct(of: self)
        return massProduct > 0 ? massProduct : nil
    }
}

// MARK: - Body Categories

extension CelestialBody {
    /// The major planets other than Earth (Mercury, Venus, Mars, Jupiter, Saturn, Uranus, and Neptune).
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

    /// Whether this body is a major planet (excluding Earth).
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
    /// The human-readable name of this celestial body.
    public var description: String { name }
}

// MARK: - Codable

extension CelestialBody: Codable {
    /// Creates a celestial body by decoding its ``name`` string (case-insensitive).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawName = try container.decode(String.self)
        guard let body = CelestialBody(name: rawName) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown CelestialBody name: \(rawName)"
            )
        }
        self = body
    }

    /// Encodes this celestial body as its ``name`` string.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
