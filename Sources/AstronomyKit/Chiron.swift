//
//  Chiron.swift
//  AstronomyKit
//
//  Position calculations for 2060 Chiron using gravity simulation.
//

import CLibAstronomy
import Foundation

// MARK: - Chiron

/// Provides position calculations for 2060 Chiron.
///
/// Chiron is a minor planet (centaur) orbiting between Saturn and Uranus.
/// Since Astronomy Engine doesn't include Chiron as a built-in body,
/// positions are calculated using gravity simulation with pre-computed
/// state vectors from JPL Horizons.
///
/// ## Overview
///
/// Chiron's position is computed by:
/// 1. Selecting the nearest reference epoch to the requested time
/// 2. Initializing a gravity simulation at that epoch
/// 3. Propagating to the requested time
/// 4. Converting to the desired coordinate system
///
/// ## Accuracy
///
/// Accuracy is highest near the reference epochs (2000, 2010, 2020, 2030, 2040)
/// and degrades slightly as distance from these epochs increases due to
/// numerical integration error. For typical usage within ±5 years of an epoch,
/// error is expected to be less than 1 arcminute.
///
/// ## Example
///
/// ```swift
/// // Get Chiron's ecliptic longitude
/// let longitude = try Chiron.eclipticLongitude(at: .now)
/// print("Chiron is at \(longitude)°")
///
/// // Get Chiron's geocentric position
/// let position = try Chiron.geoPosition(at: .now)
/// print("Chiron position: \(position)")
/// ```
public enum Chiron {

    // MARK: - Reference Epoch Data

    /// Reference epochs with pre-computed state vectors from JPL Horizons.
    /// Data source: JPL HORIZONS, heliocentric ICRF/J2000, AU and AU/day.
    private static let referenceEpochs: [(time: AstroTime, state: StateVector)] = {
        // 2000-01-01 00:00:00 TDB (JD 2451544.5)
        let epoch2000 = AstroTime(year: 2_000, month: 1, day: 1)
        let state2000 = StateVector(
            position: Vector3D(
                x: -3.532082802845036,
                y: -8.673587566387649,
                z: -2.935491685233997,
                time: epoch2000
            ),
            velocity: Vector3D(
                x: 4.970678433106630e-03,
                y: -3.627773229067521e-03,
                z: -8.262541278709376e-04,
                time: epoch2000
            ),
            time: epoch2000
        )

        // 2010-01-01 00:00:00 TDB (JD 2455197.5)
        let epoch2010 = AstroTime(year: 2_010, month: 1, day: 1)
        let state2010 = StateVector(
            position: Vector3D(
                x: 13.19148992863117,
                y: -9.058771972133892,
                z: -2.018744306999665,
                time: epoch2010
            ),
            velocity: Vector3D(
                x: 3.172737184697467e-03,
                y: 2.077241872967885e-03,
                z: 8.475052013853388e-04,
                time: epoch2010
            ),
            time: epoch2010
        )

        // 2020-01-01 00:00:00 TDB (JD 2458849.5)
        let epoch2020 = AstroTime(year: 2_020, month: 1, day: 1)
        let state2020 = StateVector(
            position: Vector3D(
                x: 18.74979015626275,
                y: 0.9060856547258316,
                z: 1.445166327129911,
                time: epoch2020
            ),
            velocity: Vector3D(
                x: -5.188250744254794e-05,
                y: 2.988627504002276e-03,
                z: 9.318734038577373e-04,
                time: epoch2020
            ),
            time: epoch2020
        )

        // 2030-01-01 00:00:00 TDB (JD 2462502.5)
        let epoch2030 = AstroTime(year: 2_030, month: 1, day: 1)
        let state2030 = StateVector(
            position: Vector3D(
                x: 13.13185175469694,
                y: 10.45171373019759,
                z: 4.086005508618447,
                time: epoch2030
            ),
            velocity: Vector3D(
                x: -2.967275252793649e-03,
                y: 1.899724574528414e-03,
                z: 4.099535209360336e-04,
                time: epoch2030
            ),
            time: epoch2030
        )

        // 2040-01-01 00:00:00 TDB (JD 2466154.5)
        let epoch2040 = AstroTime(year: 2_040, month: 1, day: 1)
        let state2040 = StateVector(
            position: Vector3D(
                x: -1.878330124332237,
                y: 10.99286850835428,
                z: 3.325776674355994,
                time: epoch2040
            ),
            velocity: Vector3D(
                x: -4.676386182330938e-03,
                y: -2.507129241195810e-03,
                z: -1.075315590956888e-03,
                time: epoch2040
            ),
            time: epoch2040
        )

        return [
            (epoch2000, state2000),
            (epoch2010, state2010),
            (epoch2020, state2020),
            (epoch2030, state2030),
            (epoch2040, state2040),
        ]
    }()

    // MARK: - Position Calculations

    /// Calculates Chiron's heliocentric position at a given time.
    ///
    /// Returns the position vector relative to the Sun's center.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The heliocentric position vector in AU (J2000 equatorial frame).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func helioPosition(at time: AstroTime) throws -> Vector3D {
        let state = try simulatedState(at: time)
        return state.position
    }

    /// Calculates Chiron's geocentric position at a given time.
    ///
    /// Returns the position vector as seen from Earth's center.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The geocentric position vector in AU (J2000 equatorial frame).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geoPosition(at time: AstroTime) throws -> Vector3D {
        let helioChiron = try helioPosition(at: time)
        let helioEarth = try CelestialBody.earth.helioPosition(at: time)

        // Geocentric = Chiron heliocentric - Earth heliocentric
        return Vector3D(
            x: helioChiron.x - helioEarth.x,
            y: helioChiron.y - helioEarth.y,
            z: helioChiron.z - helioEarth.z,
            time: time
        )
    }

    /// Calculates Chiron's geocentric state (position and velocity) at a given time.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric state vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geoState(at time: AstroTime) throws -> StateVector {
        let helioState = try simulatedState(at: time)
        let helioEarth = try CelestialBody.earth.helioPosition(at: time)

        // Get Earth's velocity via finite difference
        let dt = 1.0 / 86_400.0  // 1 second in days
        let earthBefore = try CelestialBody.earth.helioPosition(at: time.addingDays(-dt))
        let earthAfter = try CelestialBody.earth.helioPosition(at: time.addingDays(dt))
        let earthVelocity = Vector3D(
            x: (earthAfter.x - earthBefore.x) / (2 * dt),
            y: (earthAfter.y - earthBefore.y) / (2 * dt),
            z: (earthAfter.z - earthBefore.z) / (2 * dt),
            time: time
        )

        return StateVector(
            position: Vector3D(
                x: helioState.position.x - helioEarth.x,
                y: helioState.position.y - helioEarth.y,
                z: helioState.position.z - helioEarth.z,
                time: time
            ),
            velocity: Vector3D(
                x: helioState.velocity.x - earthVelocity.x,
                y: helioState.velocity.y - earthVelocity.y,
                z: helioState.velocity.z - earthVelocity.z,
                time: time
            ),
            time: time
        )
    }

    /// Calculates Chiron's equatorial coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The equatorial coordinates (RA/Dec) in J2000.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func equatorial(at time: AstroTime) throws -> Equatorial {
        let geo = try geoPosition(at: time)
        let distance = geo.magnitude

        // Convert Cartesian to spherical (RA/Dec)
        let ra = atan2(geo.y, geo.x) * 12.0 / .pi  // Convert radians to hours
        let raPositive = ra < 0 ? ra + 24.0 : ra

        let dec = asin(geo.z / distance) * 180.0 / .pi  // Convert radians to degrees

        return Equatorial(
            rightAscension: raPositive,
            declination: dec,
            distance: distance,
            time: time
        )
    }

    /// Calculates Chiron's ecliptic longitude at a given time.
    ///
    /// This is the value commonly used in astrological calculations.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLongitude(at time: AstroTime) throws -> Double {
        let geo = try geoPosition(at: time)

        // Get the rotation matrix from equatorial J2000 to ecliptic
        let rotation = Astronomy_Rotation_EQJ_ECL()

        // Create a C vector for rotation
        let cVector = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: geo.x,
            y: geo.y,
            z: geo.z,
            t: time.raw
        )

        // Rotate to ecliptic coordinates
        let rotated = Astronomy_RotateVector(rotation, cVector)

        // Calculate ecliptic longitude from rotated vector
        var longitude = atan2(rotated.y, rotated.x) * 180.0 / .pi
        if longitude < 0 {
            longitude += 360.0
        }

        return longitude
    }

    /// Calculates Chiron's ecliptic latitude at a given time.
    ///
    /// - Parameter time: The time at which to calculate the latitude.
    /// - Returns: The ecliptic latitude in degrees (-90 to +90).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLatitude(at time: AstroTime) throws -> Double {
        let geo = try geoPosition(at: time)

        // Get the rotation matrix from equatorial J2000 to ecliptic
        let rotation = Astronomy_Rotation_EQJ_ECL()

        // Create a C vector for rotation
        let cVector = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: geo.x,
            y: geo.y,
            z: geo.z,
            t: time.raw
        )

        // Rotate to ecliptic coordinates
        let rotated = Astronomy_RotateVector(rotation, cVector)
        let distance = sqrt(rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z)

        return asin(rotated.z / distance) * 180.0 / .pi
    }

    /// Calculates Chiron's full ecliptic coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates (longitude, latitude, distance).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func ecliptic(at time: AstroTime) throws -> Ecliptic {
        let geo = try geoPosition(at: time)

        // Get the rotation matrix from equatorial J2000 to ecliptic
        let rotation = Astronomy_Rotation_EQJ_ECL()

        // Create a C vector for rotation
        let cVector = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: geo.x,
            y: geo.y,
            z: geo.z,
            t: time.raw
        )

        // Rotate to ecliptic coordinates
        let rotated = Astronomy_RotateVector(rotation, cVector)
        let distance = sqrt(rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z)

        var longitude = atan2(rotated.y, rotated.x) * 180.0 / .pi
        if longitude < 0 {
            longitude += 360.0
        }

        let latitude = asin(rotated.z / distance) * 180.0 / .pi

        return Ecliptic(latitude: latitude, longitude: longitude, distance: distance)
    }

    /// Calculates Chiron's horizontal coordinates for an observer.
    ///
    /// - Parameters:
    ///   - time: The time at which to calculate the position.
    ///   - observer: The geographic observer location.
    ///   - refraction: Atmospheric refraction correction. Defaults to `.normal`.
    /// - Returns: The horizon coordinates (altitude/azimuth).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func horizon(
        at time: AstroTime,
        from observer: Observer,
        refraction: Refraction = .normal
    ) throws -> Horizon {
        let eq = try equatorial(at: time)
        var t = time.raw
        let result = Astronomy_Horizon(
            &t, observer.raw, eq.rightAscension, eq.declination, refraction.raw)
        return Horizon(result)
    }

    // MARK: - Private Helpers

    /// Selects the closest reference epoch and simulates to the target time.
    private static func simulatedState(at time: AstroTime) throws -> StateVector {
        // Find the closest reference epoch
        let (epochTime, closestState) = referenceEpochs.min { lhs, rhs in
            abs(lhs.time.ut - time.ut) < abs(rhs.time.ut - time.ut)
        }!

        // If we're very close to the epoch (within 1 day), return the epoch state directly
        if abs(closestState.time.ut - time.ut) < 1.0 {
            return closestState
        }

        // Create and run the gravity simulation
        let sim = try GravitySimulation(
            origin: .sun,
            time: epochTime,
            initialState: closestState
        )

        // Update returns the simulated small body state
        return try sim.update(to: time)
    }
}
