//
//  EngineVector.swift
//  AstronomyKit
//
//  Vector, state and rotation values of the native engine.
//

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
