//
//  EnginePlanets.swift
//  AstronomyKit
//
//  The planets of the VSOP87B tables.
//

import Foundation

extension Engine {
    /// A planet that the VSOP87B series and the polynomial tables cover, in
    /// table order.
    enum Planet: Int, CaseIterable, Sendable {
        case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune

        /// The planet `body` names, or `nil` for a body the tables do not
        /// cover, such as the Sun, the Moon or Pluto.
        init?(_ body: CelestialBody) {
            switch body {
            case .mercury: self = .mercury
            case .venus: self = .venus
            case .earth: self = .earth
            case .mars: self = .mars
            case .jupiter: self = .jupiter
            case .saturn: self = .saturn
            case .uranus: self = .uranus
            case .neptune: self = .neptune
            default: return nil
            }
        }
    }
}

// MARK: - VSOP87B

extension Engine {
    /// The VSOP87B planetary theory of Bretagnon and Francou (1988):
    /// heliocentric ecliptic longitude, latitude and radius of each planet,
    /// referred to the ecliptic and equinox of J2000, as Poisson series in
    /// Julian millennia of TT from J2000.
    enum VSOP87B {
        /// One planet's series.
        ///
        /// Coordinate `c` (0 longitude in radians, 1 latitude in radians, 2
        /// radius in AU) is `Σ_α t^α Σ_i A cos(B + C t)` with `t` in Julian
        /// millennia, summed over the powers `α` that `termCounts[c]` lists.
        struct Model: Sendable {
            /// The number of terms for each coordinate and power of `t`.
            let termCounts: [[Int]]
            /// `A`, `B`, `C` of every term, coordinate by coordinate and power
            /// by power, in the order of the C table they are generated from.
            let terms: [Double]
        }

        /// The series for `planet`.
        static func model(_ planet: Planet) -> Model {
            switch planet {
            case .mercury: mercury
            case .venus: venus
            case .earth: earth
            case .mars: mars
            case .jupiter: jupiter
            case .saturn: saturn
            case .uranus: uranus
            case .neptune: neptune
            }
        }
    }
}
