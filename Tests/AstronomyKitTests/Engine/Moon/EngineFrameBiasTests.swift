//
//  EngineFrameBiasTests.swift
//  AstronomyKit
//
//  The ICRS to EQJ rotation against SOFA and the IERS Conventions.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine frame bias")
struct EngineFrameBiasTests {
    @Test("ERFA's t_fw2m: the matrix from four angles, within its 1e-12 and much closer")
    func erfaTestProgram() {
        // t_erfa_c.c at ERFA 9915ba38.
        let r = Engine.FrameBias.fukushimaWilliams(
            gamma: -0.224_338_767_099_799_236_8e-5, phi: 0.409_101_460_239_131_298_2,
            psi: -0.950_195_417_801_301_509_2e-3, epsilon: 0.409_101_431_658_736_747_2)
        let expected: [[Double]] = [
            [0.999_999_550_517_600_704_7, 0.869_540_461_734_819_295_7e-3, 0.377_973_520_186_558_257_1e-3],
            [-0.869_540_472_377_201_603_8e-3, 0.999_999_621_949_602_716_1, -0.136_175_249_688_710_002_6e-6],
            [-0.377_973_495_703_408_279_0e-3, -0.192_488_084_808_761_565_1e-6, 0.999_999_928_567_997_195_8],
        ]
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(abs(r[i][j] - expected[i][j]) <= 1e-15, "r[\(i)][\(j)]")
            }
        }
    }

    /// pyerfa 2.0.1.5 `pmat06(2451545.0, 0.0)`, row by row: SOFA's
    /// bias-precession matrix at J2000, which is the frame bias alone.
    static let pmat06AtJ2000: [[Double]] = [
        [0.999_999_999_999_994_1, -7.078_368_960_971_559e-08, 8.056_213_977_613_186e-08],
        [7.078_368_694_637_678e-08, 0.999_999_999_999_996_9, 3.305_943_738_009_795e-08],
        [-8.056_214_211_620_057e-08, -3.305_943_169_468_331e-08, 0.999_999_999_999_996_2],
    ]

    /// Each element comes from products of unit size, so it is good to the
    /// rounding of 1, 2.2e-16, however small the element.
    @Test("ICRS to EQJ is SOFA's matrix at J2000 within 1e-16")
    func matchesSOFA() {
        let bias = Engine.FrameBias.icrsToEqj
        for i in 0..<3 {
            for j in 0..<3 {
                // `rot[j][i]` is SOFA's `r[i][j]`.
                #expect(abs(bias[j, i] - Self.pmat06AtJ2000[i][j]) <= 1e-16, "r[\(i)][\(j)]")
            }
        }
    }

    /// IERS Conventions (2010), section 5.4.4: the celestial pole offsets
    /// ξ0 = −16.617 mas and η0 = −6.819 mas, and the equinox offset
    /// dα0 = −14.6 mas. To first order the bias matrix is
    /// [[1, dα0, −ξ0], [−dα0, 1, −η0], [ξ0, η0, 1]]; the second-order terms
    /// are below 1e-14 rad.
    @Test("The rotation's small angles are the IERS 2010 frame bias to their printed precision")
    func iersOffsets() {
        let bias = Engine.FrameBias.icrsToEqj
        let mas = Engine.radiansPerArcsecond / 1_000
        // r[0][1] is dα0, printed to 0.1 mas; r[0][2] is −ξ0 and r[1][2] is −η0, to 0.001 mas.
        #expect(abs(bias[1, 0] - -14.6 * mas) <= 0.05 * mas)
        #expect(abs(bias[0, 1] - 14.6 * mas) <= 0.05 * mas)
        #expect(abs(bias[2, 0] - 16.617 * mas) <= 0.0005 * mas)
        #expect(abs(bias[0, 2] - -16.617 * mas) <= 0.0005 * mas)
        #expect(abs(bias[2, 1] - 6.819 * mas) <= 0.0005 * mas)
        #expect(abs(bias[1, 2] - -6.819 * mas) <= 0.0005 * mas)
    }

    @Test("A rotation applied to SIMD components gives the vector's result")
    func simdForm() {
        let vector = SIMD3(0.002_674_037, -0.000_153_161, -0.000_315_016)
        let rotated = Engine.FrameBias.icrsToEqj.apply(
            to: Engine.Vector<Engine.ICRS>(x: vector.x, y: vector.y, z: vector.z, time: .invalid))
        let simd = Engine.FrameBias.icrsToEqj.apply(to: vector)
        #expect([simd.x, simd.y, simd.z] == [rotated.x, rotated.y, rotated.z])
    }
}
