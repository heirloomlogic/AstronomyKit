//
//  Eclipse.swift
//  AstronomyKit
//
//  Lunar and solar eclipse calculations.
//

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

    init(_ kind: Engine.Events.LunarEclipseKind) {
        switch kind {
        case .penumbral: self = .penumbral
        case .partial: self = .partial
        case .total: self = .total
        }
    }

    init(_ kind: Engine.Events.GlobalSolarKind) {
        switch kind {
        case .partial: self = .partial
        case .annular: self = .annular
        case .total: self = .total
        }
    }

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

    /// Creates a lunar eclipse from the engine's.
    init(_ eclipse: Engine.Events.LunarEclipse) {
        self.kind = EclipseKind(eclipse.kind)
        self.peak = AstroTime(eclipse.peak)
        self.obscuration = eclipse.obscuration
        self.penumbralDuration = eclipse.penumbralDurationMinutes
        self.partialDuration = eclipse.partialDurationMinutes
        self.totalDuration = eclipse.totalDurationMinutes
    }
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

    /// The fraction of the Sun's disc covered at the peak location
    /// (total/annular only; NaN for a partial eclipse).
    public let obscuration: Double

    /// Distance from shadow axis to Earth's center in km.
    public let distance: Double

    /// Latitude at peak shadow center (total/annular only).
    public let latitude: Double?

    /// Longitude at peak shadow center (total/annular only).
    public let longitude: Double?

    /// Creates a global solar eclipse from the engine's.
    init(_ eclipse: Engine.Events.GlobalSolarEclipse) {
        self.kind = EclipseKind(eclipse.kind)
        self.peak = AstroTime(eclipse.peak)
        self.obscuration = eclipse.obscuration
        self.distance = eclipse.distanceKilometers
        self.latitude = eclipse.latitude
        self.longitude = eclipse.longitude
    }
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

    /// Creates an eclipse event from the engine's contact.
    init(_ contact: Engine.Events.LocalSolarContact) {
        self.time = AstroTime(contact.time)
        self.altitude = contact.altitude
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

    /// Creates a local solar eclipse from the engine's.
    init(_ eclipse: Engine.Events.LocalSolarEclipse) {
        self.kind = EclipseKind(eclipse.kind)
        self.obscuration = eclipse.obscuration
        self.partialBegin = EclipseEvent(eclipse.partialBegin)
        self.totalBegin = eclipse.totalBegin.map(EclipseEvent.init)
        self.peak = EclipseEvent(eclipse.peak)
        self.totalEnd = eclipse.totalEnd.map(EclipseEvent.init)
        self.partialEnd = EclipseEvent(eclipse.partialEnd)
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
        LunarEclipse(try Engine.Events.searchLunarEclipse(after: startTime.engine))
    }

    /// Finds the next lunar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous lunar eclipse.
    /// - Returns: The next lunar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextLunar(after eclipse: LunarEclipse) throws -> LunarEclipse {
        LunarEclipse(try Engine.Events.nextLunarEclipse(afterPeak: eclipse.peak.engine))
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
        GlobalSolarEclipse(try Engine.Events.searchGlobalSolarEclipse(after: startTime.engine))
    }

    /// Finds the next global solar eclipse after a given eclipse.
    ///
    /// - Parameter eclipse: The previous solar eclipse.
    /// - Returns: The next global solar eclipse.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextGlobalSolar(
        after eclipse: GlobalSolarEclipse
    ) throws -> GlobalSolarEclipse {
        GlobalSolarEclipse(try Engine.Events.nextGlobalSolarEclipse(afterPeak: eclipse.peak.engine))
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
        try observer.validate()
        return LocalSolarEclipse(try Engine.Events.searchLocalSolarEclipse(after: startTime.engine, from: observer))
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
        try observer.validate()
        return LocalSolarEclipse(
            try Engine.Events.nextLocalSolarEclipse(afterPeak: eclipse.peak.time.engine, from: observer))
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
