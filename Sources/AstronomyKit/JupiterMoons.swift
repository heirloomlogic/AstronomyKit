//
//  JupiterMoons.swift
//  AstronomyKit
//
//  Jupiter's Galilean moons state calculations.
//

// MARK: - Jupiter Moons

/// State vectors for Jupiter's four Galilean moons.
///
/// Contains the position and velocity of Io, Europa, Ganymede, and Callisto
/// relative to Jupiter's center, expressed in the J2000 equatorial system.
///
/// ## Example
///
/// ```swift
/// let moons = Jupiter.moons(at: .now)
/// print("Io position: \(moons.io.position)")
/// print("Europa velocity: \(moons.europa.velocity)")
/// ```
public struct JupiterMoons: Sendable, Equatable {
    /// The state of Io.
    public let io: StateVector

    /// The state of Europa.
    public let europa: StateVector

    /// The state of Ganymede.
    public let ganymede: StateVector

    /// The state of Callisto.
    public let callisto: StateVector

    init(_ value: Engine.JupiterMoons.States, at time: AstroTime) {
        self.io = StateVector(value.io, at: time)
        self.europa = StateVector(value.europa, at: time)
        self.ganymede = StateVector(value.ganymede, at: time)
        self.callisto = StateVector(value.callisto, at: time)
    }
}

extension JupiterMoons: CustomStringConvertible {
    /// A textual representation showing the position of each Galilean moon.
    public var description: String {
        """
        Io: \(io.position)
        Europa: \(europa.position)
        Ganymede: \(ganymede.position)
        Callisto: \(callisto.position)
        """
    }
}

// MARK: - Jupiter Namespace

/// Jupiter-specific calculations.
public enum Jupiter {
    /// Calculates the state vectors of Jupiter's four Galilean moons.
    ///
    /// Returns positions and velocities relative to Jupiter's center,
    /// expressed in the J2000 equatorial system (EQJ).
    ///
    /// - Parameter time: The time at which to calculate the moon states.
    /// - Returns: State vectors for Io, Europa, Ganymede, and Callisto.
    /// - Throws: `AstronomyError.badTime` if `time` is outside the accepted range
    ///   (see ``AstroTime``), or another `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let moons = try Jupiter.moons(at: .now)
    ///
    /// // Check if Io is on the Jupiter-facing side
    /// if moons.io.position.x > 0 {
    ///     print("Io is east of Jupiter")
    /// }
    /// ```
    public static func moons(at time: AstroTime) throws -> JupiterMoons {
        JupiterMoons(try Engine.JupiterMoons.states(at: time.coordinateTime), at: time)
    }
}
