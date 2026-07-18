//
//  FixedStar.swift
//  AstronomyKit
//
//  Position calculations for user-defined fixed stars.
//

import CLibAstronomy
import Foundation
import Synchronization

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
///     rightAscension: 3.136148,  // J2000 RA in hours
///     declination: 40.9556,      // J2000 Dec in degrees
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
///
/// ## Concurrency
///
/// The C library exposes eight user-defined star slots (`BODY_STAR1`…`BODY_STAR8`),
/// each an independent record. Calculations map a star to a slot by a stable hash of
/// its coordinates, so up to eight distinct stars can be computed fully in parallel.
/// A slot is only redefined when the star currently loaded in it differs, so repeated
/// calls for the same star skip the redefinition entirely. Stars whose hashes collide
/// on the same slot serialize on that slot's mutex (correct, just slower).
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

    /// The coordinates currently loaded into a C star slot.
    private struct StarDefinition: Equatable {
        let rightAscension, declination, distance: Double
    }

    /// Boxes a per-slot mutex so it can live in an `Array` (`Mutex` is non-copyable and
    /// cannot be stored in an array directly).
    private final class Slot: Sendable {
        /// The definition currently loaded in this C star slot, or `nil` if unused.
        let mutex = Mutex<StarDefinition?>(nil)
    }

    /// One mutex per C star slot; the payload is the definition currently loaded in that slot.
    private static let slots: [Slot] = (0..<8).map { _ in Slot() }

    // MARK: - Initialization

    /// Creates a fixed star from J2000 catalog coordinates.
    ///
    /// - Parameters:
    ///   - name: A display name for the star.
    ///   - rightAscension: Right ascension in sidereal hours (0-24).
    ///   - declination: Declination in degrees (-90 to +90).
    ///   - distance: Distance from Earth in light-years (minimum 1.0).
    public init(name: String, rightAscension: Double, declination: Double, distance: Double) {
        self.name = name
        self.rightAscension = rightAscension
        self.declination = declination
        self.distance = distance
    }

    // MARK: - Private Helpers

    /// Runs `body` with a C star slot configured for this star's coordinates.
    ///
    /// A slot index is chosen from a stable hash of the coordinates, so distinct stars
    /// use distinct slots and can run concurrently. The slot is redefined only when it
    /// currently holds a different star, so repeated calls for the same star skip the
    /// `Astronomy_DefineStar` call.
    private func withSlot<T>(_ body: (astro_body_t) throws -> T) throws -> T {
        let definition = StarDefinition(
            rightAscension: rightAscension,
            declination: declination,
            distance: distance
        )
        var hasher = Hasher()
        hasher.combine(rightAscension)
        hasher.combine(declination)
        hasher.combine(distance)
        // Map into 0..<8 without risking `abs(Int.min)`, which traps.
        let index = ((hasher.finalize() % 8) + 8) % 8
        let cBody = astro_body_t(rawValue: BODY_STAR1.rawValue + Int32(index))

        return try Self.slots[index].mutex.withLock { cached in
            if cached != definition {
                let status = Astronomy_DefineStar(
                    cBody,
                    rightAscension,
                    declination,
                    distance
                )
                if let error = AstronomyError(status: status) {
                    throw error
                }
                cached = definition
            }
            return try body(cBody)
        }
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
        from observer: Observer = .geocentric,
        equatorDate: EquatorDate = .j2000
    ) throws -> Equatorial {
        try withSlot { cBody in
            var rawTime = time.raw
            let result = Astronomy_Equator(
                cBody,
                &rawTime,
                try observer.validatedRaw(),
                equatorDate.raw,
                ABERRATION
            )
            return try Equatorial(result, time: time)
        }
    }

    /// Calculates the star's ecliptic longitude at a given time.
    ///
    /// This is the value commonly used in astrological calculations.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func eclipticLongitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).longitude
    }

    /// Calculates the star's ecliptic latitude at a given time.
    ///
    /// - Parameter time: The time at which to calculate the latitude.
    /// - Returns: The ecliptic latitude in degrees (-90 to +90).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func eclipticLatitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).latitude
    }

    /// Calculates the star's full ecliptic coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates (longitude, latitude, distance).
    /// - Throws: `AstronomyError` if the calculation fails.
    public func ecliptic(at time: AstroTime) throws -> Ecliptic {
        try withSlot { cBody in
            let geo = Astronomy_GeoVector(cBody, time.raw, ABERRATION)
            guard geo.status == ASTRO_SUCCESS else {
                if let error = AstronomyError(status: geo.status) {
                    throw error
                }
                throw AstronomyError.internalError
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
        try withSlot { cBody in
            var rawTime = time.raw
            let eqResult = Astronomy_Equator(
                cBody,
                &rawTime,
                try observer.validatedRaw(),
                EQUATOR_OF_DATE,
                ABERRATION
            )
            let eq = try Equatorial(eqResult, time: time)
            let result = Astronomy_Horizon(
                &rawTime,
                try observer.validatedRaw(),
                eq.rightAscension,
                eq.declination,
                refraction.raw
            )
            return Horizon(result)
        }
    }

    /// Determines which constellation contains the star.
    ///
    /// - Parameter time: The time at which to determine the constellation.
    /// - Returns: The constellation containing the star.
    /// - Throws: `AstronomyError` if the calculation fails.
    public func constellation(at time: AstroTime) throws -> Constellation {
        try withSlot { cBody in
            var rawTime = time.raw
            let result = Astronomy_Equator(
                cBody,
                &rawTime,
                try Observer.geocentric.validatedRaw(),
                EQUATOR_J2000,
                ABERRATION
            )
            let eq = try Equatorial(result, time: time)
            return try Constellation.find(
                rightAscension: eq.rightAscension,
                declination: eq.declination
            )
        }
    }
}

// MARK: - CustomStringConvertible

extension FixedStar: CustomStringConvertible {
    /// The display name of the star.
    public var description: String { name }
}
