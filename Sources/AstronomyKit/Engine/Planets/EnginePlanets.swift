//
//  EnginePlanets.swift
//  AstronomyKit
//
//  The planets of the VSOP87B tables, and how the generated tables are stored.
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

    /// Decodes `count` doubles from `text`, the base64 of their little-endian
    /// IEEE 754 bit patterns. Characters outside the base64 alphabet, such as
    /// line breaks, are skipped.
    ///
    /// The generated tables are string literals because a Swift array literal
    /// of a million doubles takes the compiler hours. Each table calls this
    /// from a `static let` initializer, so it is decoded once, on first use.
    /// Traps when `text` does not hold exactly `count` doubles, which only a
    /// damaged generated file can cause.
    static func unpackDoubles(count: Int, _ text: StaticString) -> [Double] {
        let data = text.withUTF8Buffer { Data(base64Encoded: Data($0), options: .ignoreUnknownCharacters) }
        guard let data, data.count == count * 8 else {
            preconditionFailure("A generated table does not hold \(count) doubles")
        }
        return data.withUnsafeBytes { raw in
            (0..<count).map { index in
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)))
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
