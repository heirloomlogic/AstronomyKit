//
//  Eclipse.swift
//  AstronomyKit
//
//  Lunar and solar eclipse calculations.
//

import CLibAstronomy

// MARK: - Eclipse Kind

/// The type of eclipse.
public enum EclipseKind: Sendable, Equatable, Hashable {
    /// No eclipse.
    case none

    /// A penumbral lunar eclipse or partial solar eclipse.
    case partial

    /// An annular solar eclipse.
    case annular

    /// A total eclipse.
    case total

    /// Creates an eclipse kind from the C enum.
    internal init(_ raw: astro_eclipse_kind_t) {
        switch raw {
        case ECLIPSE_NONE: self = .none
        case ECLIPSE_PARTIAL: self = .partial
        case ECLIPSE_ANNULAR: self = .annular
        case ECLIPSE_TOTAL: self = .total
        default: self = .none
        }
    }

    /// The display name.
    public var name: String {
        switch self {
        case .none: return "None"
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

    /// Creates a lunar eclipse from the C structure.
    internal init(_ raw: astro_lunar_eclipse_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.kind = EclipseKind(raw.kind)
        self.peak = AstroTime(raw: raw.peak)
        self.obscuration = raw.obscuration
        self.penumbralDuration = raw.sd_penum
        self.partialDuration = raw.sd_partial
        self.totalDuration = raw.sd_total
    }
}

extension LunarEclipse: CustomStringConvertible {
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

    /// Creates a global solar eclipse from the C structure.
    internal init(_ raw: astro_global_solar_eclipse_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.kind = EclipseKind(raw.kind)
        self.peak = AstroTime(raw: raw.peak)
        self.obscuration = raw.obscuration
        self.distance = raw.distance

        // Lat/lon only valid for total/annular
        if kind == .total || kind == .annular {
            self.latitude = raw.latitude
            self.longitude = raw.longitude
        } else {
            self.latitude = nil
            self.longitude = nil
        }
    }
}

extension GlobalSolarEclipse: CustomStringConvertible {
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

    /// Creates an eclipse event from the C structure.
    internal init(_ raw: astro_eclipse_event_t) {
        self.time = AstroTime(raw: raw.time)
        self.altitude = raw.altitude
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

    /// Creates a local solar eclipse from the C structure.
    internal init(_ raw: astro_local_solar_eclipse_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.kind = EclipseKind(raw.kind)
        self.obscuration = raw.obscuration
        self.partialBegin = EclipseEvent(raw.partial_begin)
        self.peak = EclipseEvent(raw.peak)
        self.partialEnd = EclipseEvent(raw.partial_end)

        // Total/annular phases only present for total/annular eclipses
        if kind == .total || kind == .annular {
            self.totalBegin = EclipseEvent(raw.total_begin)
            self.totalEnd = EclipseEvent(raw.total_end)
        } else {
            self.totalBegin = nil
            self.totalEnd = nil
        }
    }

    /// Whether any part of the eclipse is visible (Sun above horizon).
    public var isVisible: Bool {
        peak.isVisible || partialBegin.isVisible || partialEnd.isVisible
    }
}

extension LocalSolarEclipse: CustomStringConvertible {
    public var description: String {
        String(
            format: "%@ Solar Eclipse, %.0f%% obscuration at %@",
            kind.name, obscuration * 100, peak.time.description)
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
        let result = Astronomy_SearchLunarEclipse(startTime.raw)
        return try LunarEclipse(result)
    }

    /// Finds the next lunar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous lunar eclipse.
    /// - Returns: The next lunar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextLunar(after eclipse: LunarEclipse) throws -> LunarEclipse {
        let result = Astronomy_NextLunarEclipse(eclipse.peak.raw)
        return try LunarEclipse(result)
    }

    /// Finds all lunar eclipses within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of lunar eclipses.
    /// - Throws: `AstronomyError` if the search fails.
    public static func lunarEclipses(from startTime: AstroTime, to endTime: AstroTime) throws
        -> [LunarEclipse] {
        var eclipses: [LunarEclipse] = []
        var current = try searchLunar(after: startTime)

        while current.peak < endTime {
            eclipses.append(current)
            current = try nextLunar(after: current)
        }

        return eclipses
    }

    /// Searches for the next global solar eclipse.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next global solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchGlobalSolar(after startTime: AstroTime) throws -> GlobalSolarEclipse {
        let result = Astronomy_SearchGlobalSolarEclipse(startTime.raw)
        return try GlobalSolarEclipse(result)
    }

    /// Finds the next global solar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous solar eclipse.
    /// - Returns: The next global solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextGlobalSolar(after eclipse: GlobalSolarEclipse) throws
        -> GlobalSolarEclipse {
        let result = Astronomy_NextGlobalSolarEclipse(eclipse.peak.raw)
        return try GlobalSolarEclipse(result)
    }

    /// Finds all global solar eclipses within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of global solar eclipses.
    /// - Throws: `AstronomyError` if the search fails.
    public static func globalSolarEclipses(from startTime: AstroTime, to endTime: AstroTime) throws
        -> [GlobalSolarEclipse] {
        var eclipses: [GlobalSolarEclipse] = []
        var current = try searchGlobalSolar(after: startTime)

        while current.peak < endTime {
            eclipses.append(current)
            current = try nextGlobalSolar(after: current)
        }

        return eclipses
    }

    // MARK: - Local Solar Eclipse

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
        let result = Astronomy_SearchLocalSolarEclipse(startTime.raw, observer.raw)
        return try LocalSolarEclipse(result)
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
        let result = Astronomy_NextLocalSolarEclipse(eclipse.peak.time.raw, observer.raw)
        return try LocalSolarEclipse(result)
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
        var eclipses: [LocalSolarEclipse] = []
        var current = try searchLocalSolar(after: startTime, from: observer)

        while current.peak.time < endTime {
            eclipses.append(current)
            current = try nextLocalSolar(after: current, from: observer)
        }

        return eclipses
    }
}
