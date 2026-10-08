//
//  EngineIllumination.swift
//  AstronomyKit
//
//  Visual magnitude, phase and Saturn's ring tilt, and the angles between
//  bodies and the Sun as seen from Earth.
//

import Foundation

extension Engine {
    /// How bright a body appears from Earth's center and how much of it is
    /// lit, the C engine's `astro_illum_t`.
    struct Illumination: Sendable {
        var time: Time
        /// Visual magnitude.
        var magnitude: Double
        /// The angle in degrees between the Sun and Earth seen from the
        /// body; 0 for the Sun.
        var phaseAngle: Double
        /// (1 + cos phase angle) / 2.
        var phaseFraction: Double
        /// The body's distance from the Sun in AU.
        var heliocentricDistance: Double
        /// The tilt in degrees of Saturn's rings seen from Earth; 0 for
        /// every other body.
        var ringTilt: Double
    }

    /// A body's angle from the Sun seen from Earth's center, and the side
    /// of the Sun it is on, the C engine's `astro_elongation_t`.
    struct Elongation: Sendable {
        var time: Time
        /// Morning when the body is west of the Sun, ecliptic longitude less
        /// the Sun's beyond 180°; evening otherwise.
        var visibility: Visibility
        /// The angle in degrees between the body and the Sun, 0 to 180.
        var elongation: Double
        /// The difference of the two ecliptic longitudes in degrees, 0 to
        /// 180.
        var eclipticSeparation: Double
    }
}

extension Engine.Positions {
    /// The visual magnitude, phase and, for Saturn, ring tilt of `body` seen
    /// from Earth's center, the C engine's `Astronomy_Illumination`.
    ///
    /// The vectors are geometric, with no light time: Earth and the body at
    /// `time`, the Moon from ``Engine/Moon/geocentricPosition(at:cache:)``.
    /// The magnitude models are the C engine's: the Sun's absolute magnitude
    /// −0.17 at one parsec; Mercury and Venus from Hilton (2005, AJ 129,
    /// 2902); Mars, Jupiter, Uranus, Neptune and Pluto as polynomials in the
    /// phase angle; the Moon's phase curve; and Saturn's with its rings from
    /// Paul Schlyter's formulas, ring plane inclined 28.06° to the ecliptic
    /// with its ascending node at 169.51° + 3.82e-5° per TT day.
    ///
    /// - Throws: `AstronomyError.earthNotAllowed` for Earth, before anything
    ///   else; `AstronomyError.badTime` as ``heliocentricPosition(of:at:)``;
    ///   `AstronomyError.invalidBody` for a body none of the models covers,
    ///   the barycenters included; `AstronomyError.badVector` when the body is
    ///   at Earth's or the Sun's center; `AstronomyError.badTime` for a result
    ///   that is not finite.
    static func illumination(of body: CelestialBody, at time: Engine.Time) throws -> Engine.Illumination {
        guard body != .earth else { throw AstronomyError.earthNotAllowed }
        let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
        let geocentric: Engine.Vector<Engine.EQJ>
        let heliocentric: Engine.Vector<Engine.EQJ>
        let phase: Double
        switch body {
        case .sun:
            geocentric = Engine.Vector(x: -earth.x, y: -earth.y, z: -earth.z, time: time)
            heliocentric = Engine.Vector(x: 0, y: 0, z: 0, time: time)
            phase = 0
        case .moon:
            geocentric = try Engine.Moon.geocentricPosition(at: time)
            heliocentric = Engine.Vector(
                x: earth.x + geocentric.x, y: earth.y + geocentric.y, z: earth.z + geocentric.z, time: time)
            phase = try geocentric.angle(to: heliocentric)
        default:
            heliocentric = try heliocentricPosition(of: body, at: time)
            geocentric = Engine.Vector(
                x: heliocentric.x - earth.x, y: heliocentric.y - earth.y, z: heliocentric.z - earth.z, time: time)
            phase = try geocentric.angle(to: heliocentric)
        }

        let (geocentricDistance, heliocentricDistance) = (geocentric.length, heliocentric.length)
        var ringTilt = 0.0
        let magnitude: Double
        switch body {
        case .sun:
            magnitude = -0.17 + 5 * log10(geocentricDistance * Engine.radiansPerArcsecond)
        case .moon:
            magnitude = moonMagnitude(phase: phase, heliocentric: heliocentricDistance, geocentric: geocentricDistance)
        case .saturn:
            ringTilt = saturnRingTilt(Engine.Ecliptic(geocentric), tt: time.tt)
            let sinTilt = sin(abs(ringTilt) * Engine.radiansPerDegree)
            magnitude =
                -9.0 + 0.044 * phase + sinTilt * (-2.6 + 1.2 * sinTilt)
                + 5 * log10(heliocentricDistance * geocentricDistance)
        default:
            magnitude =
                try visualMagnitude(body, phase: phase)
                + 5 * log10(heliocentricDistance * geocentricDistance)
        }

        let illumination = Engine.Illumination(
            time: time, magnitude: magnitude, phaseAngle: phase,
            phaseFraction: (1 + cos(phase * Engine.radiansPerDegree)) / 2,
            heliocentricDistance: heliocentricDistance, ringTilt: ringTilt)
        let values = [magnitude, phase, illumination.phaseFraction, heliocentricDistance, ringTilt]
        guard values.allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
        return illumination
    }

    /// The angle in degrees between `body` and the Sun, both from
    /// ``geocentricPosition(of:at:aberration:)`` with aberration: the C
    /// engine's `Astronomy_AngleFromSun`.
    ///
    /// - Throws: `AstronomyError.earthNotAllowed` for Earth; then as
    ///   ``geocentricPosition(of:at:aberration:)``, the Sun first; and
    ///   `AstronomyError.badVector` for a body with no direction from Earth.
    static func angleFromSun(of body: CelestialBody, at time: Engine.Time) throws -> Double {
        guard body != .earth else { throw AstronomyError.earthNotAllowed }
        let sun = try geocentricPosition(of: .sun, at: time, aberration: .corrected)
        return try sun.angle(to: try geocentricPosition(of: body, at: time, aberration: .corrected))
    }

    /// The ecliptic longitude of `first` less that of `second`, both seen
    /// from Earth's center without aberration on the true ecliptic of date,
    /// in [0, 360): the C engine's `Astronomy_PairLongitude`.
    ///
    /// - Throws: `AstronomyError.earthNotAllowed` when either body is Earth;
    ///   then as ``geocentricPosition(of:at:aberration:)``, `first` first.
    static func pairLongitude(_ first: CelestialBody, _ second: CelestialBody, at time: Engine.Time) throws -> Double {
        guard first != .earth, second != .earth else { throw AstronomyError.earthNotAllowed }
        let a = Engine.Ecliptic(try geocentricPosition(of: first, at: time, aberration: .none)).longitude
        let b = Engine.Ecliptic(try geocentricPosition(of: second, at: time, aberration: .none)).longitude
        return Engine.normalizedLongitude(a - b)
    }

    /// `body`'s elongation from the Sun and the side it is on, the C engine's
    /// `Astronomy_Elongation`: ``pairLongitude(_:_:at:)`` with the Sun gives
    /// the side and the ecliptic separation, ``angleFromSun(of:at:)`` the
    /// elongation.
    ///
    /// - Throws: As ``pairLongitude(_:_:at:)``, then
    ///   ``angleFromSun(of:at:)``.
    static func elongation(of body: CelestialBody, at time: Engine.Time) throws -> Engine.Elongation {
        let longitude = try pairLongitude(body, .sun, at: time)
        let (visibility, separation) = longitude > 180 ? (Visibility.morning, 360 - longitude) : (.evening, longitude)
        return Engine.Elongation(
            time: time, visibility: visibility, elongation: try angleFromSun(of: body, at: time),
            eclipticSeparation: separation)
    }

    // MARK: - Magnitude models

    /// The Moon's magnitude at phase angle `phase` degrees, `heliocentric`
    /// AU from the Sun and `geocentric` AU from Earth, scaled to its mean
    /// distance of 385,000.6 km.
    private static func moonMagnitude(phase: Double, heliocentric: Double, geocentric: Double) -> Double {
        let radians = phase * Engine.radiansPerDegree
        let radians2 = radians * radians
        let magnitude = -12.717 + 1.49 * abs(radians) + 0.0431 * radians2 * radians2
        let meanDistance = 385_000.6 / Engine.kilometersPerAU
        return magnitude + 5 * log10(heliocentric * (geocentric / meanDistance))
    }

    /// The tilt in degrees of Saturn's rings seen along `ecliptic`'s
    /// direction at `tt`: the latitude of the line of sight above the ring
    /// plane.
    private static func saturnRingTilt(_ ecliptic: Engine.Ecliptic, tt: Double) -> Double {
        let inclination = 28.06 * Engine.radiansPerDegree
        let node = (169.51 + 3.82e-5 * tt) * Engine.radiansPerDegree
        let latitude = ecliptic.latitude * Engine.radiansPerDegree
        let longitude = ecliptic.longitude * Engine.radiansPerDegree
        let tilt = asin(sin(latitude) * cos(inclination) - cos(latitude) * sin(inclination) * sin(longitude - node))
        return tilt * Engine.degreesPerRadian
    }

    /// The magnitude at unit distances of a planet other than Earth and
    /// Saturn, or Pluto, at phase angle `phase` degrees: c0 + c1·x + c2·x² +
    /// c3·x³ with x = phase / 100.
    ///
    /// - Throws: `AstronomyError.invalidBody` for any other body.
    private static func visualMagnitude(_ body: CelestialBody, phase: Double) throws -> Double {
        let c: (Double, Double, Double, Double)
        switch body {
        case .mercury: c = (-0.60, 4.98, -4.88, 3.02)
        case .venus: c = phase < 163.6 ? (-4.47, 1.03, 0.57, 0.13) : (0.98, -1.02, 0, 0)
        case .mars: c = (-1.52, 1.60, 0, 0)
        case .jupiter: c = (-9.40, 0.50, 0, 0)
        case .uranus: c = (-7.19, 0.25, 0, 0)
        case .neptune: c = (-6.87, 0, 0, 0)
        case .pluto: c = (-1.00, 4.00, 0, 0)
        default: throw AstronomyError.invalidBody
        }
        let x = phase / 100
        return c.0 + x * (c.1 + x * (c.2 + x * c.3))
    }
}
