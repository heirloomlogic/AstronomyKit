//
//  EngineRotations.swift
//  AstronomyKit
//
//  Rotation algebra, the mean-of-date frame, and rotations that change with time.
//

import Foundation

extension Engine {
    /// Mean equator and equinox of the vector's time: J2000 axes carried
    /// forward by precession, without nutation (the C engine's internal EQM).
    enum EQM: Frame {}

    /// The derivative per TT day of a rotation from `From` to `To`, element by
    /// element, in the slots of the rotation it differentiates.
    struct RotationRate<From: Frame, To: Frame>: Sendable {
        var rot: (Rotation<From, To>.Row, Rotation<From, To>.Row, Rotation<From, To>.Row)

        /// The element `rot[i][j]`; traps outside 0...2.
        subscript(i: Int, j: Int) -> Double {
            Rotation<From, To>(rot: rot)[i, j]
        }
    }
}

extension Engine.Rotation {
    /// `state` carried through a rotation that changes with time: the
    /// position rotated, and the velocity rotated plus `rate` applied to the
    /// position. The result keeps the input's time.
    func apply(to state: Engine.State<From>, rate: Engine.RotationRate<From, To>) -> Engine.State<To> {
        let moved = apply(to: state)
        let carried = Engine.Rotation<From, To>(rot: rate.rot).apply(to: state.position)
        return Engine.State(
            x: moved.x,
            y: moved.y,
            z: moved.z,
            vx: moved.vx + carried.x,
            vy: moved.vy + carried.y,
            vz: moved.vz + carried.z,
            time: state.time
        )
    }
}

// MARK: - Algebra

extension Engine.Rotation {
    /// The rotation back from `To` to `From`: the transpose.
    var inverse: Engine.Rotation<To, From> {
        Engine.Rotation<To, From>(
            rot: (
                (rot.0.0, rot.1.0, rot.2.0),
                (rot.0.1, rot.1.1, rot.2.1),
                (rot.0.2, rot.1.2, rot.2.2)
            )
        )
    }

    /// This rotation followed by `next`, as `Astronomy_CombineRotation(self, next)`
    /// computes it: the matrix product `next · self`.
    func then<Next: Engine.Frame>(_ next: Engine.Rotation<To, Next>) -> Engine.Rotation<From, Next> {
        let a = rot
        let b = next.rot
        return Engine.Rotation<From, Next>(
            rot: (
                (
                    b.0.0 * a.0.0 + b.1.0 * a.0.1 + b.2.0 * a.0.2,
                    b.0.1 * a.0.0 + b.1.1 * a.0.1 + b.2.1 * a.0.2,
                    b.0.2 * a.0.0 + b.1.2 * a.0.1 + b.2.2 * a.0.2
                ),
                (
                    b.0.0 * a.1.0 + b.1.0 * a.1.1 + b.2.0 * a.1.2,
                    b.0.1 * a.1.0 + b.1.1 * a.1.1 + b.2.1 * a.1.2,
                    b.0.2 * a.1.0 + b.1.2 * a.1.1 + b.2.2 * a.1.2
                ),
                (
                    b.0.0 * a.2.0 + b.1.0 * a.2.1 + b.2.0 * a.2.2,
                    b.0.1 * a.2.0 + b.1.1 * a.2.1 + b.2.1 * a.2.2,
                    b.0.2 * a.2.0 + b.1.2 * a.2.1 + b.2.2 * a.2.2
                )
            )
        )
    }

    /// This rotation followed by turning every vector `angle` degrees about
    /// coordinate axis `axis` (0, 1 or 2 for x, y or z), counterclockwise
    /// seen from the positive end of the axis, as `Astronomy_Pivot` does.
    ///
    /// - Throws: `AstronomyError.invalidParameter` for an axis outside 0...2
    ///   or an angle that is not finite.
    func pivoted(axis: Int, angle: Double) throws -> Self {
        guard (0...2).contains(axis), angle.isFinite else { throw AstronomyError.invalidParameter }
        return turned(axis: axis, degrees: angle)
    }

    /// ``pivoted(axis:angle:)`` for an axis in 0...2 and a finite angle.
    func turned(axis: Int, degrees: Double) -> Self {
        let radians = degrees * Engine.radiansPerDegree
        let c = cos(radians)
        let s = sin(radians)
        // Row n is where the turn takes unit vector n.
        let turn: Engine.Rotation<To, To>
        switch axis {
        case 0: turn = Engine.Rotation(rot: ((1, 0, 0), (0, c, s), (0, -s, c)))
        case 1: turn = Engine.Rotation(rot: ((c, 0, -s), (0, 1, 0), (s, 0, c)))
        default: turn = Engine.Rotation(rot: ((c, s, 0), (-s, c, 0), (0, 0, 1)))
        }
        return then(turn)
    }
}
