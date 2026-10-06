//
//  EngineVector.swift
//  AstronomyKit
//
//  Vector, state and rotation values of the native engine, and their arithmetic.
//

import Foundation

extension Engine {
    /// A position in AU, with axes in frame `F`, valid at `time`.
    struct Vector<F: Frame>: Sendable {
        var x: Double
        var y: Double
        var z: Double
        var time: Time
    }

    /// A position in AU and a velocity in AU per TT day, with axes in frame
    /// `F`, valid at `time`.
    struct State<F: Frame>: Sendable {
        var x: Double
        var y: Double
        var z: Double
        var vx: Double
        var vy: Double
        var vz: Double
        var time: Time
    }

    /// A rotation from frame `From` to frame `To`.
    ///
    /// `rot` keeps the C engine's index order, which the public
    /// `RotationMatrix[row:col:]` exposes unchanged. Applied to a vector `v`,
    /// component `j` of the result is `rot[0][j]·v.x + rot[1][j]·v.y + rot[2][j]·v.z`.
    struct Rotation<From: Frame, To: Frame>: Sendable {
        typealias Row = (Double, Double, Double)

        var rot: (Row, Row, Row)

        /// The element `rot[i][j]`; traps outside 0...2.
        subscript(i: Int, j: Int) -> Double {
            let row: Row
            switch i {
            case 0: row = rot.0
            case 1: row = rot.1
            case 2: row = rot.2
            default: preconditionFailure("Rotation index (\(i), \(j)) out of range")
            }
            switch j {
            case 0: return row.0
            case 1: return row.1
            case 2: return row.2
            default: preconditionFailure("Rotation index (\(i), \(j)) out of range")
            }
        }
    }
}

extension Engine.Rotation where From == To {
    /// The rotation that leaves a vector unchanged.
    static var identity: Self {
        Self(rot: ((1, 0, 0), (0, 1, 0), (0, 0, 1)))
    }
}

// MARK: - Arithmetic

extension Engine.Vector {
    /// The length in AU, `sqrt(x² + y² + z²)`.
    var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// The angle in degrees, from 0 through 180, between this vector and
    /// `other`, measured in the plane that holds both.
    ///
    /// - Throws: `AstronomyError.badVector` when the product of the two
    ///   lengths is below 1e-8 or is not finite, which covers a zero vector
    ///   and a component that is not finite.
    func angle(to other: Self) throws -> Double {
        let r = length * other.length
        guard r >= 1.0e-8, r.isFinite else { throw AstronomyError.badVector }
        let dot = (x * other.x + y * other.y + z * other.z) / r
        if dot <= -1.0 { return 180.0 }
        if dot >= 1.0 { return 0.0 }
        return Engine.degreesPerRadian * acos(dot)
    }
}

extension Engine.State {
    /// The position part of the state, at the same time.
    var position: Engine.Vector<F> {
        Engine.Vector(x: x, y: y, z: z, time: time)
    }
}

extension Engine.Rotation {
    /// `vector` with its axes rotated into frame `To`, at the same time.
    func apply(to vector: Engine.Vector<From>) -> Engine.Vector<To> {
        Engine.Vector(
            x: rot.0.0 * vector.x + rot.1.0 * vector.y + rot.2.0 * vector.z,
            y: rot.0.1 * vector.x + rot.1.1 * vector.y + rot.2.1 * vector.z,
            z: rot.0.2 * vector.x + rot.1.2 * vector.y + rot.2.2 * vector.z,
            time: vector.time
        )
    }

    /// `state` with its position and velocity rotated into frame `To`, at
    /// the same time.
    func apply(to state: Engine.State<From>) -> Engine.State<To> {
        Engine.State(
            x: rot.0.0 * state.x + rot.1.0 * state.y + rot.2.0 * state.z,
            y: rot.0.1 * state.x + rot.1.1 * state.y + rot.2.1 * state.z,
            z: rot.0.2 * state.x + rot.1.2 * state.y + rot.2.2 * state.z,
            vx: rot.0.0 * state.vx + rot.1.0 * state.vy + rot.2.0 * state.vz,
            vy: rot.0.1 * state.vx + rot.1.1 * state.vy + rot.2.1 * state.vz,
            vz: rot.0.2 * state.vx + rot.1.2 * state.vy + rot.2.2 * state.vz,
            time: state.time
        )
    }
}
