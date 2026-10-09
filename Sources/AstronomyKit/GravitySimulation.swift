//
//  GravitySimulation.swift
//  AstronomyKit
//
//  N-body gravity simulation.
//

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
/// let state = try sim.state(of: .solarSystemBarycenter)
/// ```
///
/// - Note: This uses a class (reference semantics) because the underlying
///         simulation owns the current and previous integration states.
public final class GravitySimulation: @unchecked Sendable {
    private struct SimState {
        let simulation: Engine.GravitySimulation
        var time: AstroTime
        var currentTime: AstroTime
        var previousTime: AstroTime
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
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the simulation cannot be
    ///   initialized.
    public init(
        origin: CelestialBody,
        time: AstroTime,
        initialState: StateVector
    ) throws {
        self.origin = origin
        let nativeTime = time.coordinateTime
        let simulation = try Engine.GravitySimulation(
            origin: origin, time: nativeTime, states: [initialState.engineState(at: nativeTime)])
        self.lock = Mutex(SimState(simulation: simulation, time: time, currentTime: time, previousTime: time))
    }

    /// Updates the simulation to a new time.
    ///
    /// This advances (or rewinds) the simulation, calculating the
    /// gravitational effects on all tracked bodies.
    ///
    /// - Parameter newTime: The target time for the simulation.
    /// - Returns: The updated state vector for the tracked body.
    /// - Throws: `AstronomyError.badTime` if `newTime` is outside the accepted range
    ///   (see ``AstroTime``), which leaves the simulation unchanged, or another
    ///   `AstronomyError` if the update fails.
    @discardableResult
    public func update(to newTime: AstroTime) throws -> StateVector {
        try lock.withLock { storage in
            let result = try storage.simulation.update(to: newTime.coordinateTime)[0]
            storage.previousTime = storage.currentTime
            if newTime.terrestrialTime != storage.currentTime.terrestrialTime {
                storage.currentTime = newTime
            }
            storage.time = newTime
            return StateVector(result, at: newTime)
        }
    }

    /// Gets the current state of a body relative to the origin.
    ///
    /// - Parameter body: The body to get the state for.
    /// - Returns: The current position and velocity.
    /// - Throws: `AstronomyError` if the state cannot be retrieved.
    public func state(of body: CelestialBody) throws -> StateVector {
        try lock.withLock { storage in
            StateVector(try storage.simulation.state(of: body), at: storage.currentTime)
        }
    }

    /// Gets the current simulation time.
    ///
    /// - Returns: The time of the simulation.
    public func currentTime() -> AstroTime {
        lock.withLock { $0.currentTime }
    }

    /// The number of bodies being simulated.
    public var bodyCount: Int {
        lock.withLock { $0.simulation.bodyCount }
    }

    /// Swaps the direction of the simulation.
    ///
    /// After calling this, time updates will move backward instead of forward
    /// (or vice versa).
    public func swap() {
        lock.withLock { storage in
            storage.simulation.swap()
            (storage.currentTime, storage.previousTime) = (storage.previousTime, storage.currentTime)
        }
    }
}

extension GravitySimulation: CustomStringConvertible {
    /// A textual representation including the origin body, time, and body count.
    public var description: String {
        // One lock acquisition so time and body count are a consistent snapshot.
        let (time, bodies) = lock.withLock { simState in
            (simState.time, simState.simulation.bodyCount)
        }
        return "GravitySimulation(origin: \(origin), time: \(time), bodies: \(bodies))"
    }
}
