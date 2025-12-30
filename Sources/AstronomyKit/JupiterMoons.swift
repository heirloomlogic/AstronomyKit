//
//  JupiterMoons.swift
//  AstronomyKit
//
//  Jupiter's Galilean moons state calculations.
//

import CLibAstronomy

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

    /// Creates Jupiter moons data from the C structure.
    internal init(_ raw: astro_jupiter_moons_t) throws {
        self.io = try StateVector(raw.io)
        self.europa = try StateVector(raw.europa)
        self.ganymede = try StateVector(raw.ganymede)
        self.callisto = try StateVector(raw.callisto)
    }
}

extension JupiterMoons: CustomStringConvertible {
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
    /// - Throws: `AstronomyError` if the calculation fails.
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
        let result = Astronomy_JupiterMoons(time.raw)
        return try JupiterMoons(result)
    }
}
