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
/// Calculations are supported for years 1900 through 2150. Integration error
/// grows with distance from the reference epochs, so times outside this range
/// throw ``AstronomyError/badTime``. The range is checked on the time's
/// ``AstroTime/terrestrialTime``, which the simulation steps in: from
/// 1900-01-01 00:00 UT, as TT with the time's Delta T model, through
/// 2150-01-01 00:00 UTC.
///
/// ## Example
///
/// ```swift
/// // Get Chiron's ecliptic longitude
/// let longitude = try Chiron.eclipticLongitude(at: .now)
/// print("Chiron is at \(longitude)°")
///
/// // Get Chiron's geocentric position
/// let position = try Chiron.geocentricPosition(at: .now)
/// print("Chiron position: \(position)")
/// ```
public enum Chiron {
    /// Maximum gravity-solver step, matching the pinned upstream validation harness.
    private static let integrationStepDays = 0.5

    // MARK: - Supported Range

    /// The earliest time Chiron calculations support.
    private static let earliestSupportedTime = AstroTime(year: 1_900, month: 1, day: 1)

    /// The latest time Chiron calculations support.
    private static let latestSupportedTime = AstroTime(year: 2_150, month: 1, day: 1)

    /// Throws unless `time`'s TT is from 1900-01-01 00:00 UT, as TT with
    /// `time`'s Delta T model, through 2150-01-01 00:00 UTC.
    ///
    /// The simulation steps in TT, so `time`'s UT is not checked. For a time
    /// made with ``AstroTime/init(tt:ut:deltaTModel:)`` it need not agree
    /// with the TT.
    ///
    /// - Throws: ``AstronomyError/badTime`` outside that span, including for
    ///   a time that is not valid.
    static func checkSupported(_ time: AstroTime) throws {
        let earliest = AstroTime(ut: earliestSupportedTime.universalTime, deltaTModel: time.deltaTModel)
        guard time.terrestrialTime >= earliest.terrestrialTime,
            time.terrestrialTime <= latestSupportedTime.terrestrialTime
        else { throw AstronomyError.badTime }
    }

    // MARK: - Reference Epoch Data

    /// Reference epochs with pre-computed state vectors from JPL Horizons.
    ///
    /// Data source: JPL HORIZONS, heliocentric ICRF/J2000, AU and AU/day.
    ///
    /// The Horizons states are tabulated at 00:00 TDB while the epochs below
    /// are constructed as 00:00 UTC, an offset of ~64-69 seconds. Chiron moves
    /// up to about 0.14″ around the Sun in that time, at perihelion; the
    /// offset is ignored here.
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
    public static func heliocentricPosition(at time: AstroTime) throws -> Vector3D {
        let state = try simulatedState(at: time)
        return state.position
    }

    /// Calculates Chiron's geocentric position at a given time.
    ///
    /// Returns the position vector as seen from Earth's center,
    /// corrected for light travel time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The geocentric position vector in AU (J2000 equatorial frame).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geocentricPosition(at time: AstroTime) throws -> Vector3D {
        let helioEarth = try CelestialBody.earth.heliocentricPosition(at: time)

        // Reuse one simulation across the light-travel iterations. The instance
        // is local to this call, so it is never shared between threads.
        let chiron = ReusableSimulation()

        return try AstroSearch.correctLightTravel(at: time) { t in
            let helioChiron = try chiron.state(at: t).position
            return Vector3D(
                x: helioChiron.x - helioEarth.x,
                y: helioChiron.y - helioEarth.y,
                z: helioChiron.z - helioEarth.z,
                time: t
            )
        }
    }

    /// Calculates Chiron's geocentric state (position and velocity) at a given time.
    ///
    /// The state is geometric (instantaneous): unlike ``geocentricPosition(at:)``,
    /// it is not corrected for light travel time.
    ///
    /// - Parameter time: The time at which to calculate the state.
    /// - Returns: The geocentric state vector.
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func geoState(at time: AstroTime) throws -> StateVector {
        let helioState = try simulatedState(at: time)
        let earthState = try CelestialBody.earth.heliocentricState(at: time)

        return StateVector(
            position: Vector3D(
                x: helioState.position.x - earthState.position.x,
                y: helioState.position.y - earthState.position.y,
                z: helioState.position.z - earthState.position.z,
                time: time
            ),
            velocity: Vector3D(
                x: helioState.velocity.x - earthState.velocity.x,
                y: helioState.velocity.y - earthState.velocity.y,
                z: helioState.velocity.z - earthState.velocity.z,
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
        try geocentricPosition(at: time).toEquatorial()
    }

    /// Calculates Chiron's ecliptic longitude at a given time.
    ///
    /// This is the value commonly used in astrological calculations.
    ///
    /// - Parameter time: The time at which to calculate the longitude.
    /// - Returns: The ecliptic longitude in degrees (0-360).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLongitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).longitude
    }

    /// Calculates Chiron's ecliptic latitude at a given time.
    ///
    /// - Parameter time: The time at which to calculate the latitude.
    /// - Returns: The ecliptic latitude in degrees (-90 to +90).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func eclipticLatitude(at time: AstroTime) throws -> Double {
        try ecliptic(at: time).latitude
    }

    /// Calculates Chiron's full ecliptic coordinates at a given time.
    ///
    /// - Parameter time: The time at which to calculate the position.
    /// - Returns: The ecliptic coordinates (longitude, latitude, distance).
    /// - Throws: `AstronomyError` if the calculation fails.
    public static func ecliptic(at time: AstroTime) throws -> Ecliptic {
        try geocentricPosition(at: time).toEcliptic()
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
        var rawTime = time.raw
        let result = Astronomy_Horizon(
            &rawTime,
            try observer.validatedRaw(),
            eq.rightAscension,
            eq.declination,
            refraction.raw
        )
        return Horizon(result)
    }

    // MARK: - Private Helpers

    /// A Chiron gravity simulation scoped to a single computation.
    ///
    /// One instance is created per top-level query and reused across the
    /// iterations of a light-travel correction, then discarded. Because an
    /// instance is never shared between threads, no locking is required and
    /// concurrent Chiron queries cannot corrupt one another's integration.
    ///
    /// Reuse is bounded by the path traveled. The simulation re-anchors at the
    /// reference epoch once its accumulated path would exceed twice the span
    /// of a fresh integration.
    ///
    /// `@unchecked Sendable` lets an instance be captured by the `@Sendable`
    /// light-travel closure. The C solver invokes that closure synchronously
    /// and serially on the calling thread, so the instance is never touched
    /// concurrently.
    final class ReusableSimulation: @unchecked Sendable {
        private(set) var epochIndex: Int?
        private var simulation: GravitySimulation?
        private(set) var pathDays = 0.0

        /// Simulates Chiron's heliocentric state at the target time, reusing
        /// the anchored simulation when the error budget allows.
        func state(at time: AstroTime) throws -> StateVector {
            try checkSupported(time)

            // Find the closest reference epoch.
            guard
                let (index, epoch) = referenceEpochs.enumerated().min(by: { lhs, rhs in
                    abs(lhs.element.time.universalTime - time.universalTime)
                        < abs(rhs.element.time.universalTime - time.universalTime)
                })
            else {
                throw AstronomyError.internalError
            }

            let targetTT = time.terrestrialTime
            let freshPath = abs(targetTT - epoch.time.terrestrialTime)

            // Reuse the anchored simulation when it sits at the same epoch and
            // stepping it stays within the error budget.
            if let simulation, let epochIndex, epochIndex == index {
                let startTT = simulation.time.terrestrialTime
                if pathDays + abs(targetTT - startTT) <= max(2 * freshPath, 365) {
                    // Counts the days the simulation moved, which a failure
                    // partway leaves short of the request.
                    defer { pathDays += abs(simulation.time.terrestrialTime - startTT) }
                    return try advance(simulation, to: time)
                }
            }

            // Start fresh from the reference epoch.
            let simulation = try GravitySimulation(
                origin: .sun,
                time: epoch.time,
                initialState: epoch.state
            )
            let state = try advance(simulation, to: time)
            self.simulation = simulation
            epochIndex = index
            pathDays = freshPath
            return state
        }
    }

    /// Advances the solver in half-day-or-smaller Terrestrial Time increments.
    private static func advance(
        _ simulation: GravitySimulation,
        to target: AstroTime
    ) throws -> StateVector {
        let startTT = simulation.time.terrestrialTime
        let interval = target.terrestrialTime - startTT
        let stepCount = max(1, Int(ceil(abs(interval) / integrationStepDays)))

        for step in 1..<stepCount {
            let nextTime = AstroTime(
                tt: startTT + interval * Double(step) / Double(stepCount),
                deltaTModel: target.deltaTModel
            )
            try simulation.update(to: nextTime)
        }

        return try simulation.update(to: target)
    }

    /// Selects the closest reference epoch and simulates to the target time.
    ///
    /// Each call runs an independent simulation, so it holds no shared mutable
    /// state and is safe to call concurrently.
    private static func simulatedState(at time: AstroTime) throws -> StateVector {
        try ReusableSimulation().state(at: time)
    }
}
