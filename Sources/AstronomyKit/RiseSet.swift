//
//  RiseSet.swift
//  AstronomyKit
//
//  Rise, set, and culmination time calculations.
//

import CLibAstronomy

// MARK: - Direction

/// The direction of motion for rise/set searches.
public enum RiseSetDirection: Int32, Sendable {
    /// Rising above the horizon.
    case rise = 1
    
    /// Setting below the horizon.
    case set = -1
    
    internal var raw: astro_direction_t {
        astro_direction_t(rawValue: rawValue)
    }
}

// MARK: - Rise/Set Results

extension CelestialBody {
    /// Searches for the next rise or set time.
    ///
    /// - Parameters:
    ///   - direction: Whether to search for rising or setting.
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    ///   - limitDays: Maximum days to search. Defaults to 366.
    ///   - metersAboveGround: Observer height above ground (affects horizon). Defaults to 0.
    /// - Returns: The time when the body rises or sets, or `nil` if not found.
    /// - Throws: `AstronomyError` if the search encounters an error.
    public func searchRiseSet(
        direction: RiseSetDirection,
        after startTime: AstroTime,
        from observer: Observer,
        limitDays: Double = 366,
        metersAboveGround: Double = 0
    ) throws -> AstroTime? {
        let result = Astronomy_SearchRiseSetEx(
            raw,
            observer.raw,
            direction.raw,
            startTime.raw,
            limitDays,
            metersAboveGround
        )
        
        // ASTRO_SEARCH_FAILURE means no event found in the time range
        if result.status == ASTRO_SEARCH_FAILURE {
            return nil
        }
        
        if let error = AstronomyError(status: result.status) {
            throw error
        }
        
        return AstroTime(raw: result.time)
    }
    
    /// Finds the next time this body rises above the horizon.
    ///
    /// - Parameters:
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    ///   - limitDays: Maximum days to search. Defaults to 366.
    /// - Returns: The rise time, or `nil` if not found.
    /// - Throws: `AstronomyError` if the search encounters an error.
    public func riseTime(
        after startTime: AstroTime,
        from observer: Observer,
        limitDays: Double = 366
    ) throws -> AstroTime? {
        try searchRiseSet(
            direction: .rise,
            after: startTime,
            from: observer,
            limitDays: limitDays
        )
    }
    
    /// Finds the next time this body sets below the horizon.
    ///
    /// - Parameters:
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    ///   - limitDays: Maximum days to search. Defaults to 366.
    /// - Returns: The set time, or `nil` if not found.
    /// - Throws: `AstronomyError` if the search encounters an error.
    public func setTime(
        after startTime: AstroTime,
        from observer: Observer,
        limitDays: Double = 366
    ) throws -> AstroTime? {
        try searchRiseSet(
            direction: .set,
            after: startTime,
            from: observer,
            limitDays: limitDays
        )
    }
}

// MARK: - Hour Angle Search

/// The result of an hour angle search.
public struct HourAngleEvent: Sendable, Equatable {
    /// The time when the body reaches the specified hour angle.
    public let time: AstroTime
    
    /// The horizontal coordinates at that time.
    public let horizon: Horizon
    
    /// Creates an event from the C structure.
    internal init(_ raw: astro_hour_angle_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.time = AstroTime(raw: raw.time)
        self.horizon = Horizon(raw.hor)
    }
}

extension CelestialBody {
    /// Searches for when this body reaches a specific hour angle.
    ///
    /// - Parameters:
    ///   - hourAngle: The desired hour angle (0-24 hours). 0 = upper culmination.
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    ///   - direction: Search forward (+1) or backward (-1). Defaults to forward.
    /// - Returns: The hour angle event.
    /// - Throws: `AstronomyError` if the search fails.
    public func searchHourAngle(
        _ hourAngle: Double,
        after startTime: AstroTime,
        from observer: Observer,
        direction: Int32 = 1
    ) throws -> HourAngleEvent {
        let result = Astronomy_SearchHourAngleEx(
            raw,
            observer.raw,
            hourAngle,
            startTime.raw,
            direction
        )
        return try HourAngleEvent(result)
    }
    
    /// Finds the next upper culmination (transit/meridian crossing).
    ///
    /// Upper culmination is when the body crosses the meridian at its highest point.
    ///
    /// - Parameters:
    ///   - startTime: The time to start searching from.
    ///   - observer: The geographic observer location.
    /// - Returns: The culmination event with time and altitude.
    /// - Throws: `AstronomyError` if the search fails.
    public func culmination(
        after startTime: AstroTime,
        from observer: Observer
    ) throws -> HourAngleEvent {
        try searchHourAngle(0, after: startTime, from: observer)
    }
}

// MARK: - Daily Events

/// A collection of daily rise, set, and culmination times for a body.
public struct DailyEvents: Sendable {
    /// The celestial body.
    public let body: CelestialBody
    
    /// The observer location.
    public let observer: Observer
    
    /// The date for these events.
    public let date: AstroTime
    
    /// The rise time, if any.
    public let rise: AstroTime?
    
    /// The set time, if any.
    public let set: AstroTime?
    
    /// The upper culmination (transit).
    public let culmination: HourAngleEvent?
    
    /// Creates daily events for a body at a location.
    ///
    /// - Parameters:
    ///   - body: The celestial body.
    ///   - date: The date (events starting from midnight UTC).
    ///   - observer: The geographic observer location.
    public init(body: CelestialBody, date: AstroTime, from observer: Observer) throws {
        self.body = body
        self.observer = observer
        self.date = date
        
        // Search within a 1-day window
        self.rise = try? body.riseTime(after: date, from: observer, limitDays: 1)
        self.set = try? body.setTime(after: date, from: observer, limitDays: 1)
        self.culmination = try? body.culmination(after: date, from: observer)
    }
    
    /// Whether the body is visible at some point during this day.
    public var isVisible: Bool {
        rise != nil || set != nil || (culmination?.horizon.isAboveHorizon ?? false)
    }
}
