//
//  EngineFrameBias.swift
//  AstronomyKit
//
//  The frame bias between the ICRS and the mean equator and equinox of J2000.
//

import Foundation

extension Engine {
    /// The axes of the International Celestial Reference System, which the
    /// JPL ephemerides use.
    enum ICRS: Frame {}

    /// The frame bias: the small fixed rotation, about 23 mas, from the ICRS
    /// to the mean equator and equinox of J2000 (EQJ).
    enum FrameBias {}
}

extension Engine.FrameBias {
    /// SOFA's `iauFw2m`: the matrix R1(−ε)·R3(−ψ)·R1(φ)·R3(γ) from four
    /// Fukushima-Williams angles in radians, in SOFA's row order, so that the
    /// matrix times a column vector rotates it.
    static func fukushimaWilliams(gamma: Double, phi: Double, psi: Double, epsilon: Double) -> [[Double]] {
        var r: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        rotateZ(gamma, &r)
        rotateX(phi, &r)
        rotateZ(-psi, &r)
        rotateX(-epsilon, &r)
        return r
    }

    /// The rotation from the ICRS to EQJ: SOFA's `iauPmat06` at J2000, the
    /// Fukushima-Williams matrix at the IAU 2006 angles for t = 0 (Hilton et
    /// al. 2006, as in `iauPfw06` and `iauObl06`). At t = 0 precession is the
    /// identity, so this is the frame bias alone.
    static let icrsToEqj: Engine.Rotation<Engine.ICRS, Engine.EQJ> = {
        let arcsecond = Engine.radiansPerArcsecond
        let r = fukushimaWilliams(
            gamma: -0.052928 * arcsecond, phi: 84_381.412819 * arcsecond,
            psi: -0.041775 * arcsecond, epsilon: 84_381.406 * arcsecond)
        // `rot[j][i]` is SOFA's `r[i][j]`.
        return Engine.Rotation(
            rot: (
                (r[0][0], r[1][0], r[2][0]),
                (r[0][1], r[1][1], r[2][1]),
                (r[0][2], r[1][2], r[2][2])
            )
        )
    }()

    /// `vector` on ICRS axes rotated to EQJ, as ``icrsToEqj`` rotates a vector.
    static func toEqj(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let r = icrsToEqj.rot
        return SIMD3(
            r.0.0 * vector.x + r.1.0 * vector.y + r.2.0 * vector.z,
            r.0.1 * vector.x + r.1.1 * vector.y + r.2.1 * vector.z,
            r.0.2 * vector.x + r.1.2 * vector.y + r.2.2 * vector.z)
    }

    /// SOFA's `iauRx`: rotates `r` by `angle` radians about the x axis.
    private static func rotateX(_ angle: Double, _ r: inout [[Double]]) {
        let s = sin(angle)
        let c = cos(angle)
        let row1 = (0..<3).map { c * r[1][$0] + s * r[2][$0] }
        let row2 = (0..<3).map { -s * r[1][$0] + c * r[2][$0] }
        r[1] = row1
        r[2] = row2
    }

    /// SOFA's `iauRz`: rotates `r` by `angle` radians about the z axis.
    private static func rotateZ(_ angle: Double, _ r: inout [[Double]]) {
        let s = sin(angle)
        let c = cos(angle)
        let row0 = (0..<3).map { c * r[0][$0] + s * r[1][$0] }
        let row1 = (0..<3).map { -s * r[0][$0] + c * r[1][$0] }
        r[0] = row0
        r[1] = row1
    }
}
