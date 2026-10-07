//
//  EngineRotations.swift
//  AstronomyKit
//
//  The mean-of-date frame, and rotations that change with time.
//

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
