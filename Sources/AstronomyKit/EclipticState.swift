//
//  EclipticState.swift
//  AstronomyKit
//
//  Geocentric ecliptic position and its rate of change.
//

// MARK: - Ecliptic State

/// Geocentric ecliptic position and velocity in the true ecliptic and equinox of date.
///
/// The position fields are bit-identical to the position function each state
/// function mirrors (see ``CelestialBody/geocentricEclipticState(at:aberration:)``,
/// ``Sun/eclipticState(at:)``, and ``Moon/eclipticState(at:)``). The rate fields
/// are the derivative of that same function with respect to Terrestrial Time,
/// taken as a five-point difference over ±1/8 day. Because they differentiate the
/// position function itself, they include light-time, aberration, and the motion of
/// the true ecliptic and equinox of date, and a zero of ``longitudeRate`` is a
/// stationary point of ``longitude``. Their rounding noise is about 2e-11 degrees per
/// day for the Sun and planets and 2e-10 for the Moon; the difference's own error is
/// below 1e-8.
public struct EclipticState: Sendable, Equatable, Hashable {
    /// Ecliptic longitude in degrees (0 to 360).
    public let longitude: Double

    /// Ecliptic latitude in degrees (-90 to +90).
    public let latitude: Double

    /// Distance in AU.
    public let distance: Double

    /// Rate of change of longitude in degrees per TT day.
    public let longitudeRate: Double

    /// Rate of change of latitude in degrees per TT day.
    public let latitudeRate: Double

    /// Rate of change of distance in AU per TT day.
    public let distanceRate: Double

    /// The observation time.
    public let time: AstroTime

    /// Creates an ecliptic state.
    public init(
        longitude: Double,
        latitude: Double,
        distance: Double,
        longitudeRate: Double,
        latitudeRate: Double,
        distanceRate: Double,
        time: AstroTime
    ) {
        self.longitude = longitude
        self.latitude = latitude
        self.distance = distance
        self.longitudeRate = longitudeRate
        self.latitudeRate = latitudeRate
        self.distanceRate = distanceRate
        self.time = time
    }

    /// The position part of the state.
    public var ecliptic: Ecliptic {
        Ecliptic(latitude: latitude, longitude: longitude, distance: distance)
    }

    /// Spacing of the five-point difference, in days. A power of two, so the offsets
    /// are exact.
    static let rateStep = 1.0 / 16

    /// Creates a state from `position` at `time` and a five-point difference of it at
    /// ±``rateStep`` and ±2 ``rateStep``.
    init(at time: AstroTime, position: (AstroTime) throws -> Ecliptic) throws {
        let center = try position(time)
        // The samples are offset in TT, the scale the rates are taken against. Offsets
        // in UT would pick up a Delta T model's step wherever one falls inside the
        // stencil, as Espenak-Meeus's do at the joins of its polynomials. Where the
        // step is forward, TT skips some values and `AstroTime(tt:)` misses them by up
        // to the step, so each sample's TT is set to the offset value exactly.
        let samples = try [-2.0, -1, 1, 2].map { offset in
            let tt = time.terrestrialTime + offset * Self.rateStep
            var sample = AstroTime(tt: tt)
            sample.raw.tt = tt
            return try position(sample)
        }

        // Differences from the center keep the values small; longitude wraps across 0/360.
        func rate(_ change: (Ecliptic) -> Double) -> Double {
            let d = samples.map(change)
            return (d[0] - 8 * d[1] + 8 * d[2] - d[3]) / (12 * Self.rateStep)
        }
        let longitudeRate = rate { sample in
            let change = sample.longitude - center.longitude
            return change > 180 ? change - 360 : change < -180 ? change + 360 : change
        }

        self.init(
            longitude: center.longitude,
            latitude: center.latitude,
            distance: center.distance,
            longitudeRate: longitudeRate,
            latitudeRate: rate { $0.latitude - center.latitude },
            distanceRate: rate { $0.distance - center.distance },
            time: time
        )
    }
}

// MARK: - State Functions

extension CelestialBody {
    /// Calculates the apparent geocentric ecliptic position and velocity of this body.
    ///
    /// The position fields are bit-identical to
    /// `geocentricPosition(at: time, aberration: aberration).toEcliptic()`. The rates
    /// are the derivative of that position per Terrestrial Time day; see
    /// ``EclipticState``.
    ///
    /// Supported bodies are the Sun, the Moon, Mercury through Neptune except
    /// Earth, and Pluto. Other bodies throw ``AstronomyError/invalidBody``.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - aberration: Whether to correct for aberration. Defaults to `.corrected`.
    ///     Ignored for the Moon, as in `geocentricPosition(at:aberration:)`.
    /// - Returns: The ecliptic position and velocity.
    /// - Throws: `AstronomyError.badTime` if `time`, or a time within 1/8 day of
    ///   it, is outside the accepted range (see ``AstroTime``), or another
    ///   `AstronomyError` if the calculation fails.
    public func geocentricEclipticState(
        at time: AstroTime,
        aberration: Aberration = .corrected
    ) throws -> EclipticState {
        switch self {
        case .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
            return try EclipticState(at: time) { sample in
                try geocentricPosition(at: sample, aberration: aberration).toEcliptic()
            }
        default:
            throw AstronomyError.invalidBody
        }
    }
}

extension Sun {
    /// Calculates the Sun's ecliptic position and velocity.
    ///
    /// The position fields are bit-identical to ``position(at:)``. The rates are the
    /// derivative of that position per Terrestrial Time day; see ``EclipticState``.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The ecliptic position and velocity of the Sun.
    /// - Throws: `AstronomyError.badTime` if `time`, or a time within 1/8 day of
    ///   it, is outside the accepted range (see ``AstroTime``), or another
    ///   `AstronomyError` if the calculation fails.
    public static func eclipticState(at time: AstroTime) throws -> EclipticState {
        try EclipticState(at: time, position: position(at:))
    }
}

extension Moon {
    /// Calculates the Moon's ecliptic position and velocity.
    ///
    /// The position fields are bit-identical to ``ecliptic(at:)``. The rates are the
    /// derivative of that position per Terrestrial Time day; see ``EclipticState``.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The ecliptic position and velocity of the Moon.
    /// - Throws: `AstronomyError.badTime` if `time`, or a time within 1/8 day of
    ///   it, is outside the accepted range (see ``AstroTime``), or another
    ///   `AstronomyError` if the calculation fails.
    public static func eclipticState(at time: AstroTime) throws -> EclipticState {
        try EclipticState(at: time, position: ecliptic(at:))
    }
}
