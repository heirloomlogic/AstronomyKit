//
//  LagrangePoint.swift
//  AstronomyKit
//
//  Lagrange point calculations.
//

import CLibAstronomy

// MARK: - Lagrange Point ID

/// Identifies one of the five Lagrange points.
public enum LagrangePointID: Int32, Sendable, CaseIterable {
    /// L1: Between the two bodies, closer to the smaller one.
    case l1 = 1

    /// L2: Beyond the smaller body, opposite from the larger one.
    case l2 = 2

    /// L3: Beyond the larger body, opposite from the smaller one.
    case l3 = 3

    /// L4: 60° ahead of the smaller body in its orbit.
    case l4 = 4

    /// L5: 60° behind the smaller body in its orbit.
    case l5 = 5

    /// The human-readable name.
    public var name: String {
        switch self {
        case .l1: return "L1"
        case .l2: return "L2"
        case .l3: return "L3"
        case .l4: return "L4"
        case .l5: return "L5"
        }
    }
}

extension LagrangePointID: CustomStringConvertible {
    public var description: String { name }
}

// MARK: - State Vector

/// A position and velocity state vector.
///
/// State vectors are used to describe the complete motion state of an object,
/// including both where it is and how fast it's moving.
public struct StateVector: Sendable, Equatable {
    /// The position in AU.
    public let position: Vector3D

    /// The velocity in AU/day.
    public let velocity: Vector3D

    /// The time at which this state is valid.
    public let time: AstroTime

    /// Creates a state vector from the C structure.
    internal init(_ raw: astro_state_vector_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.time = AstroTime(raw: raw.t)
        self.position = Vector3D(
            x: raw.x,
            y: raw.y,
            z: raw.z,
            time: AstroTime(raw: raw.t)
        )
        self.velocity = Vector3D(
            x: raw.vx,
            y: raw.vy,
            z: raw.vz,
            time: AstroTime(raw: raw.t)
        )
    }
}

extension StateVector: CustomStringConvertible {
    public var description: String {
        "Position: \(position), Velocity: (\(velocity.x), \(velocity.y), \(velocity.z)) AU/day"
    }
}

// MARK: - Lagrange Point Calculations

/// Lagrange point calculation functions.
public enum LagrangePoint {
    /// Calculates the state vector of a Lagrange point.
    ///
    /// Lagrange points are locations in a two-body gravitational system where
    /// the combined gravitational pull provides the centripetal force needed
    /// for a small object to orbit with the same period as the larger bodies.
    ///
    /// - Parameters:
    ///   - point: Which Lagrange point to calculate (L1-L5).
    ///   - time: The time at which to calculate the position.
    ///   - majorBody: The larger body (e.g., Sun).
    ///   - minorBody: The smaller body (e.g., Earth).
    /// - Returns: The state vector of the Lagrange point.
    /// - Throws: `AstronomyError` if the calculation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Calculate the Sun-Earth L2 point (where JWST orbits)
    /// let l2 = try LagrangePoint.calculate(
    ///     point: .l2,
    ///     at: .now,
    ///     majorBody: .sun,
    ///     minorBody: .earth
    /// )
    /// print("L2 position: \(l2.position)")
    /// ```
    public static func calculate(
        point: LagrangePointID,
        at time: AstroTime,
        majorBody: CelestialBody,
        minorBody: CelestialBody
    ) throws -> StateVector {
        let result = Astronomy_LagrangePoint(
            point.rawValue,
            time.raw,
            majorBody.raw,
            minorBody.raw
        )
        return try StateVector(result)
    }
}
