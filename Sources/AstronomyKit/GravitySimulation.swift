//
//  GravitySimulation.swift
//  AstronomyKit
//
//  N-body gravity simulation.
//

import CLibAstronomy
import Synchronization

// MARK: - Gravity Simulation

/// An n-body gravity simulation for tracking object trajectories.
///
/// This class provides a way to simulate the motion of objects under
/// the gravitational influence of the major bodies in the solar system.
///
/// ## Example
///
/// ```swift
/// // Create a simulation with initial state for a small body
/// let sim = try GravitySimulation(
///     origin: .sun,
///     time: .now,
///     initialState: initialState
/// )
///
/// // Advance the simulation 30 days
/// try sim.update(to: .now.addingDays(30))
///
/// // Get the updated state
/// let state = try sim.state(of: .ssb)
/// ```
///
/// - Note: This uses a class (reference semantics) because the underlying
///         C simulation object has state that must be managed across updates.
public final class GravitySimulation: @unchecked Sendable {
    private struct SimState: ~Copyable {
        var handle: OpaquePointer?
        var time: AstroTime

        deinit {
            if let handle {
                Astronomy_GravSimFree(handle)
            }
        }
    }

    private let lock: Mutex<SimState>

    /// The simulation's origin body.
    public let origin: CelestialBody

    /// The current simulation time.
    public var time: AstroTime {
        lock.withLock { $0.time }
    }

    /// Creates a new gravity simulation.
    ///
    /// The simulation will track the motion of a small body under the
    /// gravitational influence of the major bodies in the solar system.
    ///
    /// - Parameters:
    ///   - origin: The body to use as the reference origin for state vectors.
    ///   - time: The starting time for the simulation.
    ///   - initialState: The initial state vector of the body to track.
    /// - Throws: `AstronomyError` if the simulation cannot be initialized.
    public init(
        origin: CelestialBody,
        time: AstroTime,
        initialState: StateVector
    ) throws {
        self.origin = origin

        var state = astro_state_vector_t(
            status: ASTRO_SUCCESS,
            x: initialState.position.x,
            y: initialState.position.y,
            z: initialState.position.z,
            vx: initialState.velocity.x,
            vy: initialState.velocity.y,
            vz: initialState.velocity.z,
            t: time.raw
        )

        var sim: OpaquePointer?
        let status = Astronomy_GravSimInit(&sim, origin.raw, time.raw, 1, &state)

        if let error = AstronomyError(status: status) {
            throw error
        }

        self.lock = Mutex(SimState(handle: sim, time: time))
    }

    /// Updates the simulation to a new time.
    ///
    /// This advances (or rewinds) the simulation, calculating the
    /// gravitational effects on all tracked bodies.
    ///
    /// - Parameter newTime: The target time for the simulation.
    /// - Returns: The updated state vector for the tracked body.
    /// - Throws: `AstronomyError` if the update fails.
    @discardableResult
    public func update(to newTime: AstroTime) throws -> StateVector {
        try lock.withLock { simState in
            guard let handle = simState.handle else {
                throw AstronomyError.notInitialized
            }

            var state = astro_state_vector_t()
            let status = Astronomy_GravSimUpdate(handle, newTime.raw, 1, &state)

            if let error = AstronomyError(status: status) {
                throw error
            }

            simState.time = newTime
            return try StateVector(state)
        }
    }

    /// Gets the current state of a body relative to the origin.
    ///
    /// - Parameter body: The body to get the state for.
    /// - Returns: The current position and velocity.
    /// - Throws: `AstronomyError` if the state cannot be retrieved.
    public func state(of body: CelestialBody) throws -> StateVector {
        try lock.withLock { simState in
            guard let handle = simState.handle else {
                throw AstronomyError.notInitialized
            }

            let result = Astronomy_GravSimBodyState(handle, body.raw)
            return try StateVector(result)
        }
    }

    /// Gets the current simulation time.
    ///
    /// - Returns: The time of the simulation.
    public func currentTime() -> AstroTime {
        lock.withLock { simState in
            guard let handle = simState.handle else {
                return simState.time
            }

            let t = Astronomy_GravSimTime(handle)
            return AstroTime(raw: t)
        }
    }

    /// The number of bodies being simulated.
    public var bodyCount: Int {
        lock.withLock { simState in
            guard let handle = simState.handle else { return 0 }
            return Int(Astronomy_GravSimNumBodies(handle))
        }
    }

    /// Swaps the direction of the simulation.
    ///
    /// After calling this, time updates will move backward instead of forward
    /// (or vice versa).
    public func swap() {
        lock.withLock { simState in
            guard let handle = simState.handle else { return }
            Astronomy_GravSimSwap(handle)
        }
    }
}

extension GravitySimulation: CustomStringConvertible {
    /// A textual representation including the origin body, time, and body count.
    public var description: String {
        "GravitySimulation(origin: \(origin), time: \(time), bodies: \(bodyCount))"
    }
}
