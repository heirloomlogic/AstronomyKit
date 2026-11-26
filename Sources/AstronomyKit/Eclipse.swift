//
//  Eclipse.swift
//  AstronomyKit
//
//  Lunar and solar eclipse calculations.
//

import Foundation

// MARK: - Eclipse Kind

/// The type of eclipse.
public enum EclipseKind: Sendable, Equatable, Hashable {
    /// No eclipse.
    case none

    /// A penumbral lunar eclipse (Moon passes through Earth's penumbral shadow only).
    case penumbral

    /// A partial eclipse.
    case partial

    /// An annular solar eclipse.
    case annular

    /// A total eclipse.
    case total

    /// The display name.
    public var name: String {
        switch self {
        case .none: return "None"
        case .penumbral: return "Penumbral"
        case .partial: return "Partial"
        case .annular: return "Annular"
        case .total: return "Total"
        }
    }
}

// MARK: - Lunar Eclipse

/// Information about a lunar eclipse.
public struct LunarEclipse: Sendable, Equatable {
    /// The type of lunar eclipse.
    public let kind: EclipseKind

    /// The time at the peak of the eclipse.
    public let peak: AstroTime

    /// The obscuration of the Moon at peak (0.0 to ~1.5 for total).
    public let obscuration: Double

    /// Semi-duration of the penumbral phase in minutes.
    public let penumbralDuration: Double

    /// Semi-duration of the partial phase in minutes (0 if none).
    public let partialDuration: Double

    /// Semi-duration of the total phase in minutes (0 if none).
    public let totalDuration: Double
}

extension LunarEclipse: CustomStringConvertible {
    /// A textual representation showing the eclipse type and peak time.
    public var description: String {
        "\(kind.name) Lunar Eclipse at \(peak)"
    }
}

// MARK: - Global Solar Eclipse

/// Information about a solar eclipse as seen globally.
public struct GlobalSolarEclipse: Sendable, Equatable {
    /// The type of solar eclipse.
    public let kind: EclipseKind

    /// The time at the peak of the eclipse.
    public let peak: AstroTime

    /// The peak obscuration (total/annular only).
    public let obscuration: Double

    /// Distance from shadow axis to Earth's center in km.
    public let distance: Double

    /// Latitude at peak shadow center (total/annular only).
    public let latitude: Double?

    /// Longitude at peak shadow center (total/annular only).
    public let longitude: Double?
}

extension GlobalSolarEclipse: CustomStringConvertible {
    /// A textual representation showing the eclipse type, peak time, and center coordinates.
    public var description: String {
        if let lat = latitude, let lon = longitude {
            return "\(kind.name) Solar Eclipse at \(peak), center: (\(lat)°, \(lon)°)"
        }
        return "\(kind.name) Solar Eclipse at \(peak)"
    }
}

// MARK: - Eclipse Event

/// A specific moment during an eclipse with the Sun's altitude.
public struct EclipseEvent: Sendable, Equatable {
    /// The date and time of the event.
    public let time: AstroTime

    /// The altitude of the Sun above/below the horizon in degrees.
    ///
    /// Negative values indicate the Sun is below the horizon,
    /// meaning this phase of the eclipse is not visible.
    public let altitude: Double

    /// Whether the Sun is above the horizon at this event.
    public var isVisible: Bool { altitude > 0 }

    init(time: AstroTime, altitude: Double) {
        self.time = time
        self.altitude = altitude
    }
}

// MARK: - Local Solar Eclipse

/// Information about a solar eclipse as seen from a specific location.
///
/// This provides detailed timing for all phases of the eclipse
/// as visible from the observer's location.
///
/// ## Example
///
/// ```swift
/// let observer = Observer(latitude: 40.7128, longitude: -74.0060)
/// let eclipse = try Eclipse.searchLocalSolar(after: .now, from: observer)
/// print("Eclipse type: \(eclipse.kind)")
/// print("Obscuration: \(Int(eclipse.obscuration * 100))%")
/// ```
public struct LocalSolarEclipse: Sendable, Equatable {
    /// The type of solar eclipse.
    public let kind: EclipseKind

    /// The fraction of the Sun's disc obscured at peak (0 to 1).
    public let obscuration: Double

    /// When the partial phase begins.
    public let partialBegin: EclipseEvent

    /// When totality or annularity begins (nil for partial eclipses).
    public let totalBegin: EclipseEvent?

    /// The peak of the eclipse.
    public let peak: EclipseEvent

    /// When totality or annularity ends (nil for partial eclipses).
    public let totalEnd: EclipseEvent?

    /// When the partial phase ends.
    public let partialEnd: EclipseEvent

    init(
        kind: EclipseKind,
        obscuration: Double,
        partialBegin: EclipseEvent,
        totalBegin: EclipseEvent?,
        peak: EclipseEvent,
        totalEnd: EclipseEvent?,
        partialEnd: EclipseEvent
    ) {
        self.kind = kind
        self.obscuration = obscuration
        self.partialBegin = partialBegin
        self.totalBegin = totalBegin
        self.peak = peak
        self.totalEnd = totalEnd
        self.partialEnd = partialEnd
    }

    /// Whether any part of the eclipse is visible (Sun above horizon).
    public var isVisible: Bool {
        peak.isVisible || partialBegin.isVisible || partialEnd.isVisible
    }
}

extension LocalSolarEclipse: CustomStringConvertible {
    /// A textual representation showing the eclipse type, obscuration, and peak time.
    public var description: String {
        String(
            format: "%@ Solar Eclipse, %.0f%% obscuration at %@",
            kind.name,
            obscuration * 100,
            peak.time.description
        )
    }
}

// MARK: - Eclipse Search Functions

/// Eclipse search and calculation functions.
public enum Eclipse {
    /// Searches for the next lunar eclipse.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next lunar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchLunar(after startTime: AstroTime) throws -> LunarEclipse {
        try EngineEclipses.searchLunar(after: startTime)
    }

    /// Finds the next lunar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous lunar eclipse.
    /// - Returns: The next lunar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextLunar(after eclipse: LunarEclipse) throws -> LunarEclipse {
        try EngineEclipses.nextLunar(after: eclipse.peak)
    }

    /// Finds all lunar eclipses within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of lunar eclipses.
    /// - Throws: `AstronomyError` if the search fails.
    public static func lunarEclipses(
        from startTime: AstroTime,
        to endTime: AstroTime
    ) throws -> [LunarEclipse] {
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var eclipses: [LunarEclipse] = []
        var current: LunarEclipse
        do {
            current = try searchLunar(after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.peak < endTime {
            guard eclipses.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            eclipses.append(current)
            do {
                current = try nextLunar(after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return eclipses
    }

    /// Searches for the next global solar eclipse.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next global solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchGlobalSolar(after startTime: AstroTime) throws -> GlobalSolarEclipse {
        try EngineEclipses.searchGlobalSolar(after: startTime)
    }

    /// Finds the next global solar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous solar eclipse.
    /// - Returns: The next global solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextGlobalSolar(
        after eclipse: GlobalSolarEclipse
    ) throws -> GlobalSolarEclipse {
        try EngineEclipses.nextGlobalSolar(after: eclipse.peak)
    }

    /// Finds all global solar eclipses within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of global solar eclipses.
    /// - Throws: `AstronomyError` if the search fails.
    public static func globalSolarEclipses(
        from startTime: AstroTime,
        to endTime: AstroTime
    ) throws -> [GlobalSolarEclipse] {
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var eclipses: [GlobalSolarEclipse] = []
        var current: GlobalSolarEclipse
        do {
            current = try searchGlobalSolar(after: startTime)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.peak < endTime {
            guard eclipses.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            eclipses.append(current)
            do {
                current = try nextGlobalSolar(after: current)
            } catch AstronomyError.badTime {
                break
            }
        }

        return eclipses
    }

    // MARK: - Local Solar Eclipse

    private static func validatedSolarObserver(_ observer: Observer) throws -> Observer {
        let valid = try observer.validated()
        guard (-6_378_136.6...100_000.0).contains(valid.height) else {
            throw AstronomyError.invalidParameter
        }
        return valid
    }

    /// Searches for the next solar eclipse visible from a specific location.
    ///
    /// - Parameters:
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    /// - Returns: The next local solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let nyc = Observer(latitude: 40.7128, longitude: -74.0060)
    /// let eclipse = try Eclipse.searchLocalSolar(after: .now, from: nyc)
    /// print("Next eclipse: \(eclipse.kind) on \(eclipse.peak.time)")
    /// ```
    public static func searchLocalSolar(
        after startTime: AstroTime,
        from observer: Observer
    ) throws -> LocalSolarEclipse {
        try EngineEclipses.searchLocalSolar(
            after: startTime,
            observer: try validatedSolarObserver(observer)
        )
    }

    /// Finds the next local solar eclipse after a given eclipse.
    ///
    /// - Parameters:
    ///   - eclipse: The previous local solar eclipse.
    ///   - observer: The geographic observer location.
    /// - Returns: The next local solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextLocalSolar(
        after eclipse: LocalSolarEclipse,
        from observer: Observer
    ) throws -> LocalSolarEclipse {
        try EngineEclipses.nextLocalSolar(
            after: eclipse.peak.time,
            observer: try validatedSolarObserver(observer)
        )
    }

    /// Finds all local solar eclipses within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    ///   - observer: The geographic observer location.
    /// - Returns: An array of local solar eclipses.
    /// - Throws: `AstronomyError` if the search fails.
    public static func localSolarEclipses(
        from startTime: AstroTime,
        to endTime: AstroTime,
        observer: Observer
    ) throws -> [LocalSolarEclipse] {
        _ = try validatedSolarObserver(observer)
        try startTime.checkAcceptedTime()
        try endTime.checkAcceptedTime()
        guard startTime < endTime else { return [] }

        var eclipses: [LocalSolarEclipse] = []
        var current: LocalSolarEclipse
        do {
            current = try searchLocalSolar(after: startTime, from: observer)
        } catch AstronomyError.badTime where startTime.terrestrialTime > 0 {
            return []
        }

        while current.peak.time < endTime {
            guard eclipses.count < AstroTime.maxRangeResults else { throw AstronomyError.invalidParameter }
            eclipses.append(current)
            do {
                current = try nextLocalSolar(after: current, from: observer)
            } catch AstronomyError.badTime {
                break
            }
        }

        return eclipses
    }
}
