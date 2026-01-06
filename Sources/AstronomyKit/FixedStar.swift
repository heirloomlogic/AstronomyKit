//
//  FixedStar.swift
//  AstronomyKit
//
//  Position calculations for user-defined fixed stars.
//

import CLibAstronomy
import Foundation

/// A fixed star defined by its J2000 equatorial coordinates.
///
/// Fixed stars are celestial objects whose positions are essentially constant
/// on the celestial sphere. This struct stores catalog coordinates and provides
/// position calculations at any time.
///
/// Unlike solar system bodies (which require orbital calculations), fixed stars
/// are defined by their J2000 mean equator coordinates and distance. The library
/// handles precession, nutation, and aberration automatically.
///
/// ## Example
///
/// ```swift
/// let algol = FixedStar(
///     name: "Algol",
///     ra: 3.136148,      // J2000 RA in hours
///     dec: 40.9556,      // J2000 Dec in degrees
///     distance: 92.95    // Light-years
/// )
///
/// let longitude = try algol.eclipticLongitude(at: .now)
/// print("Algol is at \(longitude)°")
/// ```
///
/// ## Coordinate Sources
///
/// J2000 coordinates can be found from:
/// - [SIMBAD Astronomical Database](https://simbad.cds.unistra.fr/simbad/)
/// - Hipparcos Catalog
/// - Yale Bright Star Catalog
public struct FixedStar: Sendable, Hashable {

    // MARK: - Properties

    /// The star's display name.
    public let name: String

    /// J2000 right ascension in sidereal hours (0-24).
    public let rightAscension: Double

    /// J2000 declination in degrees (-90 to +90).
    public let declination: Double

    /// Distance from Earth in light-years.
    public let distance: Double

    // MARK: - Internal State

    /// Lock protecting the shared calculation slot.
    /// All position calculations use a single C library slot, protected by this mutex.
    private static let calculationLock = NSLock()

    /// The C library body used for calculations.
    private static let calculationSlot = BODY_STAR1

    // MARK: - Initialization

    /// Creates a fixed star from J2000 catalog coordinates.
    ///
    /// - Parameters:
    ///   - name: A display name for the star.
    ///   - ra: Right ascension in sidereal hours (0-24).
    ///   - dec: Declination in degrees (-90 to +90).
    ///   - distance: Distance from Earth in light-years (minimum 1.0).
    public init(name: String, ra: Double, dec: Double, distance: Double) {
        self.name = name
        self.rightAscension = ra
        self.declination = dec
        self.distance = distance
    }

    // MARK: - Private Helpers

    /// Configures the calculation slot with this star's coordinates.
    /// Must be called while holding `calculationLock`.
    private func configureSlot() throws {
        let status = Astronomy_DefineStar(
            Self.calculationSlot,
            rightAscension,
            declination,
            distance
        )
        if let error = AstronomyError(status: status) {
            throw error
        }
    }

    /// The Swift body wrapper for the calculation slot.
    private static var slotBody: CelestialBody {
        .star1
    }

    // MARK: - Position Calculations

    /// Calculates the star's equatorial coordinates at a given time.
    ///
    /// Returns the right ascension and declination as seen from Earth.
    /// Since this is a fixed star, the J2000 coordinates are essentially
    /// constant, though minor variations occur due to precession and nutation
    /// when using `equatorDate: .ofDate`.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The observer location. Defaults to Earth's center.
    ///   - equatorDate: The equinox reference. Defaults to J2000.
    /// - Returns: The equatorial coordinates (RA/Dec).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func equatorial(
        at time: AstroTime,
        from observer: Observer = .primeMeridian,
        equatorDate: EquatorDate = .j2000
    ) throws -> Equatorial {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()
        return try Self.slotBody.equatorial(at: time, from: observer, equatorDate: equatorDate)
    }

    /// Calculates the star's ecliptic longitude at a given time.
    ///
    /// This is the value commonly used in astrological calculations.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()

        // Get geocentric position
        let geo = Astronomy_GeoVector(Self.calculationSlot, time.raw, ABERRATION)
        guard geo.status == ASTRO_SUCCESS else {
            throw AstronomyError(status: geo.status)!
        }

        // Rotate from equatorial J2000 to ecliptic
        let rotation = Astronomy_Rotation_EQJ_ECL()
        let rotated = Astronomy_RotateVector(rotation, geo)

        // Calculate longitude from rotated vector
        var longitude = atan2(rotated.y, rotated.x) * 180.0 / .pi
        if longitude < 0 {
            longitude += 360.0
        }

        return longitude
    }

    /// Calculates the star's ecliptic latitude at a given time.
    ///
    /// - Parameter time: The time at which to calculate the latitude.
    /// - Returns: The ecliptic latitude in degrees (-90 to +90).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func eclipticLatitude(at time: AstroTime) throws -> Double {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()

        let geo = Astronomy_GeoVector(Self.calculationSlot, time.raw, ABERRATION)
        guard geo.status == ASTRO_SUCCESS else {
            throw AstronomyError(status: geo.status)!
        }

        let rotation = Astronomy_Rotation_EQJ_ECL()
        let rotated = Astronomy_RotateVector(rotation, geo)
        let dist = sqrt(rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z)

        return asin(rotated.z / dist) * 180.0 / .pi
    }

    /// Calculates the star's full ecliptic coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates (longitude, latitude, distance).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func ecliptic(at time: AstroTime) throws -> Ecliptic {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()

        let geo = Astronomy_GeoVector(Self.calculationSlot, time.raw, ABERRATION)
        guard geo.status == ASTRO_SUCCESS else {
            throw AstronomyError(status: geo.status)!
        }

        let rotation = Astronomy_Rotation_EQJ_ECL()
        let rotated = Astronomy_RotateVector(rotation, geo)
        let dist = sqrt(rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z)

        var longitude = atan2(rotated.y, rotated.x) * 180.0 / .pi
        if longitude < 0 {
            longitude += 360.0
        }

        let latitude = asin(rotated.z / dist) * 180.0 / .pi

        return Ecliptic(latitude: latitude, longitude: longitude, distance: dist)
    }

    /// Calculates the star's horizontal coordinates for an observer.
    ///
    /// Returns where the star appears in the local sky (altitude and azimuth).
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The geographic observer location.
    ///   - refraction: Atmospheric refraction correction. Defaults to `.normal`.
    /// - Returns: The horizon coordinates (altitude/azimuth).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func horizon(
        at time: AstroTime,
        from observer: Observer,
        refraction: Refraction = .normal
    ) throws -> Horizon {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()
        return try Self.slotBody.horizon(at: time, from: observer, refraction: refraction)
    }

    /// Determines which constellation contains the star.
    ///
    /// - Parameter time: The time at which to determine the constellation.
    /// - Returns: The constellation containing the star.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func constellation(at time: AstroTime) throws -> Constellation {
        Self.calculationLock.lock()
        defer { Self.calculationLock.unlock() }

        try configureSlot()
        return try Self.slotBody.constellation(at: time)
    }
}

// MARK: - CustomStringConvertible

extension FixedStar: CustomStringConvertible {
    public var description: String { name }
}
