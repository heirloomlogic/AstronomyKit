//
//  Seasons.swift
//  AstronomyKit
//
//  Seasonal equinox and solstice calculations.
//

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

    /// Calculates the seasonal events for a given year.
    ///
    /// - Parameter year: The calendar year (e.g., 2025).
    /// - Returns: The four seasonal events for that year.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func forYear(_ year: Int) throws -> Seasons {
        guard Int32(exactly: year) != nil else {
            throw AstronomyError.invalidParameter
        }
        return try EngineEvents.seasons(year: year)
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
    /// A textual representation listing all four equinox and solstice times.
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
