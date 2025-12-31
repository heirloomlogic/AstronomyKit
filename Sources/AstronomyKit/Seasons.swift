//
//  Seasons.swift
//  AstronomyKit
//
//  Seasonal equinox and solstice calculations.
//

import CLibAstronomy

/// The four seasonal events (equinoxes and solstices) for a calendar year.
public struct Seasons: Sendable, Equatable {
    /// The March equinox (spring in the Northern Hemisphere).
    public let marchEquinox: AstroTime

    /// The June solstice (summer in the Northern Hemisphere).
    public let juneSolstice: AstroTime

    /// The September equinox (autumn in the Northern Hemisphere).
    public let septemberEquinox: AstroTime

    /// The December solstice (winter in the Northern Hemisphere).
    public let decemberSolstice: AstroTime

    /// Creates a seasons instance from the C structure.
    internal init(_ raw: astro_seasons_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.marchEquinox = AstroTime(raw: raw.mar_equinox)
        self.juneSolstice = AstroTime(raw: raw.jun_solstice)
        self.septemberEquinox = AstroTime(raw: raw.sep_equinox)
        self.decemberSolstice = AstroTime(raw: raw.dec_solstice)
    }

    /// Calculates the seasonal events for a given year.
    ///
    /// - Parameter year: The calendar year (e.g., 2025).
    /// - Returns: The four seasonal events for that year.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func forYear(_ year: Int) throws -> Seasons {
        let result = Astronomy_Seasons(Int32(year))
        return try Seasons(result)
    }

    /// Returns all four events as an array, in chronological order.
    public var allEvents: [(name: String, time: AstroTime)] {
        [
            ("March Equinox", marchEquinox),
            ("June Solstice", juneSolstice),
            ("September Equinox", septemberEquinox),
            ("December Solstice", decemberSolstice),
        ]
    }
}

extension Seasons: CustomStringConvertible {
    public var description: String {
        """
        🌸 March Equinox:     \(marchEquinox)
        ☀️ June Solstice:     \(juneSolstice)
        🍂 September Equinox: \(septemberEquinox)
        ❄️ December Solstice: \(decemberSolstice)
        """
    }
}

// MARK: - Codable

extension Seasons: Codable {
    enum CodingKeys: String, CodingKey {
        case marchEquinox, juneSolstice, septemberEquinox, decemberSolstice
    }
}
