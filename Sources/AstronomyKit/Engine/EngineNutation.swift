//
//  EngineNutation.swift
//  AstronomyKit
//
//  Pure-Swift 77-term IAU 2000B nutation series (McCarthy & Luzum, 2003),
//  evaluating the five fundamental angles once and building all 77 arguments
//  by angle addition. Uses FMA SIMD2 polynomials in Release / non-Apple builds
//  and thread-local Accelerate batching in Apple Debug builds.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
import Accelerate
#endif

#if !(ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate))
private struct NutationTerm {
    var psi: SIMD2<Double>  // (pc, ps)
    var eps: SIMD2<Double>  // (ec, es)
    var rate: SIMD2<Double>  // (ect, pst)
    var anomaly: Int
    var node: Int
}
#endif

private struct NutationTableStorage: @unchecked Sendable {
    static let termCount = 77

    let rateCount: Int

    #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
    let pc: UnsafePointer<Double>
    let ps: UnsafePointer<Double>
    let ec: UnsafePointer<Double>
    let es: UnsafePointer<Double>
    let ect: UnsafePointer<Double>
    let pst: UnsafePointer<Double>
    let aIdxD: UnsafePointer<Double>
    let nIdxD: UnsafePointer<Double>
    let aIdx: UnsafePointer<Int>
    let nIdx: UnsafePointer<Int>
    #else
    let terms: UnsafePointer<NutationTerm>
    #endif

    static let shared: NutationTableStorage = build()

    private static func anomalyIndex(_ l: Int, _ lp: Int) -> Int {
        switch (l, lp) {
        case (0, 0): return 0
        case (1, 0): return 1
        case (-1, 0): return 2
        case (2, 0): return 3
        case (-2, 0): return 4
        case (3, 0): return 5
        case (0, 1): return 6
        case (0, -1): return 7
        case (0, 2): return 8
        case (0, -2): return 9
        case (1, 1): return 10
        case (-1, -1): return 11
        case (1, -1): return 12
        case (-1, 1): return 13
        default: fatalError("Unexpected IAU 2000B anomaly pair (\(l), \(lp))")
        }
    }

    private static func nodeIndex(_ f: Int, _ d: Int, _ om: Int) -> Int {
        switch (f, d, om) {
        case (0, 0, 0): return 0
        case (0, 0, 1): return 1
        case (0, 0, 2): return 2
        case (2, 0, 0): return 3
        case (2, 0, 1): return 4
        case (2, 0, 2): return 5
        case (0, 1, 0): return 6
        case (0, 1, 1): return 7
        case (0, 2, 0): return 8
        case (0, 2, 1): return 9
        case (0, -2, 1): return 10
        case (2, -2, 1): return 11
        case (2, -2, 2): return 12
        case (-2, 2, 0): return 13
        case (2, 1, 2): return 14
        case (2, 2, 1): return 15
        case (2, 2, 2): return 16
        case (2, 4, 2): return 17
        default: fatalError("Unexpected IAU 2000B node triple (\(f), \(d), \(om))")
        }
    }

    private static func build() -> NutationTableStorage {
        // Published IAU 2000B table: (l, lp, f, d, om, ps, pst, pc, ec, ect, es)
        // in units of 0.1 microarcsecond (and per Julian century for pst, ect).
        let raw: [Int32] = [
            0, 0, 0, 0, 1, -172_064_161, -174_666, 33_386, 92_052_331, 9_086, 15_377,
            0, 0, 2, -2, 2, -13_170_906, -1_675, -13_696, 5_730_336, -3_015, -4_587,
            0, 0, 2, 0, 2, -2_276_413, -234, 2_796, 978_459, -485, 1_374,
            0, 0, 0, 0, 2, 2_074_554, 207, -698, -897_492, 470, -291,
            0, 1, 0, 0, 0, 1_475_877, -3_633, 11_817, 73_871, -184, -1_924,
            0, 1, 2, -2, 2, -516_821, 1_226, -524, 224_386, -677, -174,
            1, 0, 0, 0, 0, 711_159, 73, -872, -6_750, 0, 358,
            0, 0, 2, 0, 1, -387_298, -367, 380, 200_728, 18, 318,
            1, 0, 2, 0, 2, -301_461, -36, 816, 129_025, -63, 367,
            0, -1, 2, -2, 2, 215_829, -494, 111, -95_929, 299, 132,
            0, 0, 2, -2, 1, 128_227, 137, 181, -68_982, -9, 39,
            -1, 0, 2, 0, 2, 123_457, 11, 19, -53_311, 32, -4,
            -1, 0, 0, 2, 0, 156_994, 10, -168, -1_235, 0, 82,
            1, 0, 0, 0, 1, 63_110, 63, 27, -33_228, 0, -9,
            -1, 0, 0, 0, 1, -57_976, -63, -189, 31_429, 0, -75,
            -1, 0, 2, 2, 2, -59_641, -11, 149, 25_543, -11, 66,
            1, 0, 2, 0, 1, -51_613, -42, 129, 26_366, 0, 78,
            -2, 0, 2, 0, 1, 45_893, 50, 31, -24_236, -10, 20,
            0, 0, 0, 2, 0, 63_384, 11, -150, -1_220, 0, 29,
            0, 0, 2, 2, 2, -38_571, -1, 158, 16_452, -11, 68,
            0, -2, 2, -2, 2, 32_481, 0, 0, -13_870, 0, 0,
            -2, 0, 0, 2, 0, -47_722, 0, -18, 477, 0, -25,
            2, 0, 2, 0, 2, -31_046, -1, 131, 13_238, -11, 59,
            1, 0, 2, -2, 2, 28_593, 0, -1, -12_338, 10, -3,
            -1, 0, 2, 0, 1, 20_441, 21, 10, -10_758, 0, -3,
            2, 0, 0, 0, 0, 29_243, 0, -74, -609, 0, 13,
            0, 0, 2, 0, 0, 25_887, 0, -66, -550, 0, 11,
            0, 1, 0, 0, 1, -14_053, -25, 79, 8_551, -2, -45,
            -1, 0, 0, 2, 1, 15_164, 10, 11, -8_001, 0, -1,
            0, 2, 2, -2, 2, -15_794, 72, -16, 6_850, -42, -5,
            0, 0, -2, 2, 0, 21_783, 0, 13, -167, 0, 13,
            1, 0, 0, -2, 1, -12_873, -10, -37, 6_953, 0, -14,
            0, -1, 0, 0, 1, -12_654, 11, 63, 6_415, 0, 26,
            -1, 0, 2, 2, 1, -10_204, 0, 25, 5_222, 0, 15,
            0, 2, 0, 0, 0, 16_707, -85, -10, 168, -1, 10,
            1, 0, 2, 2, 2, -7_691, 0, 44, 3_268, 0, 19,
            -2, 0, 2, 0, 0, -11_024, 0, -14, 104, 0, 2,
            0, 1, 2, 0, 2, 7_566, -21, -11, -3_250, 0, -5,
            0, 0, 2, 2, 1, -6_637, -11, 25, 3_353, 0, 14,
            0, -1, 2, 0, 2, -7_141, 21, 8, 3_070, 0, 4,
            0, 0, 0, 2, 1, -6_302, -11, 2, 3_272, 0, 4,
            1, 0, 2, -2, 1, 5_800, 10, 2, -3_045, 0, -1,
            2, 0, 2, -2, 2, 6_443, 0, -7, -2_768, 0, -4,
            -2, 0, 0, 2, 1, -5_774, -11, -15, 3_041, 0, -5,
            2, 0, 2, 0, 1, -5_350, 0, 21, 2_695, 0, 12,
            0, -1, 2, -2, 1, -4_752, -11, -3, 2_719, 0, -3,
            0, 0, 0, -2, 1, -4_940, -11, -21, 2_720, 0, -9,
            -1, -1, 0, 2, 0, 7_350, 0, -8, -51, 0, 4,
            2, 0, 0, -2, 1, 4_065, 0, 6, -2_206, 0, 1,
            1, 0, 0, 2, 0, 6_579, 0, -24, -199, 0, 2,
            0, 1, 2, -2, 1, 3_579, 0, 5, -1_900, 0, 1,
            1, -1, 0, 0, 0, 4_725, 0, -6, -41, 0, 3,
            -2, 0, 2, 0, 2, -3_075, 0, -2, 1_313, 0, -1,
            3, 0, 2, 0, 2, -2_904, 0, 15, 1_233, 0, 7,
            0, -1, 0, 2, 0, 4_348, 0, -10, -81, 0, 2,
            1, -1, 2, 0, 2, -2_878, 0, 8, 1_232, 0, 4,
            0, 0, 0, 1, 0, -4_230, 0, 5, -20, 0, -2,
            -1, -1, 2, 2, 2, -2_819, 0, 7, 1_207, 0, 3,
            -1, 0, 2, 0, 0, -4_056, 0, 5, 40, 0, -2,
            0, -1, 2, 2, 2, -2_647, 0, 11, 1_129, 0, 5,
            -2, 0, 0, 0, 1, -2_294, 0, -10, 1_266, 0, -4,
            1, 1, 2, 0, 2, 2_481, 0, -7, -1_062, 0, -3,
            2, 0, 0, 0, 1, 2_179, 0, -2, -1_129, 0, -2,
            -1, 1, 0, 1, 0, 3_276, 0, 1, -9, 0, 0,
            1, 1, 0, 0, 0, -3_389, 0, 5, 35, 0, -2,
            1, 0, 2, 0, 0, 3_339, 0, -13, -107, 0, 1,
            -1, 0, 2, -2, 1, -1_987, 0, -6, 1_073, 0, -2,
            1, 0, 0, 0, 2, -1_981, 0, 0, 854, 0, 0,
            -1, 0, 0, 1, 0, 4_026, 0, -353, -553, 0, -139,
            0, 0, 2, 1, 2, 1_660, 0, -5, -710, 0, -2,
            -1, 0, 2, 4, 2, -1_521, 0, 9, 647, 0, 4,
            -1, 1, 0, 1, 1, 1_314, 0, 0, -700, 0, 0,
            0, -2, 2, -2, 1, -1_283, 0, 0, 672, 0, 0,
            1, 0, 2, 2, 1, -1_331, 0, 8, 663, 0, 4,
            -2, 0, 2, 2, 2, 1_383, 0, -2, -594, 0, -2,
            -1, 0, 0, 0, 2, 1_405, 0, 4, -610, 0, 2,
            1, 1, 2, -2, 2, 1_290, 0, 0, -556, 0, 0,
        ]
        precondition(raw.count == termCount * 11)

        var lastRate = 0
        var i = 0
        while i < termCount {
            let b = i &* 11
            if raw[b &+ 6] != 0 || raw[b &+ 9] != 0 {
                lastRate = i &+ 1
            }
            i &+= 1
        }

        #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
        let pc = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let ps = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let ec = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let es = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let ect = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let pst = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let aIdxD = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let nIdxD = UnsafeMutablePointer<Double>.allocate(capacity: termCount)
        let aIdx = UnsafeMutablePointer<Int>.allocate(capacity: termCount)
        let nIdx = UnsafeMutablePointer<Int>.allocate(capacity: termCount)

        i = 0
        while i < termCount {
            let b = i &* 11
            let ai = anomalyIndex(Int(raw[b]), Int(raw[b &+ 1]))
            let ni = nodeIndex(Int(raw[b &+ 2]), Int(raw[b &+ 3]), Int(raw[b &+ 4]))
            ps[i] = Double(raw[b &+ 5])
            pst[i] = Double(raw[b &+ 6])
            pc[i] = Double(raw[b &+ 7])
            ec[i] = Double(raw[b &+ 8])
            ect[i] = Double(raw[b &+ 9])
            es[i] = Double(raw[b &+ 10])
            aIdxD[i] = Double(ai)
            nIdxD[i] = Double(ni)
            aIdx[i] = ai
            nIdx[i] = ni
            i &+= 1
        }
        return NutationTableStorage(
            rateCount: lastRate,
            pc: UnsafePointer(pc),
            ps: UnsafePointer(ps),
            ec: UnsafePointer(ec),
            es: UnsafePointer(es),
            ect: UnsafePointer(ect),
            pst: UnsafePointer(pst),
            aIdxD: UnsafePointer(aIdxD),
            nIdxD: UnsafePointer(nIdxD),
            aIdx: UnsafePointer(aIdx),
            nIdx: UnsafePointer(nIdx)
        )
        #else
        let terms = UnsafeMutablePointer<NutationTerm>.allocate(capacity: termCount)
        i = 0
        while i < termCount {
            let b = i &* 11
            let ai = anomalyIndex(Int(raw[b]), Int(raw[b &+ 1]))
            let ni = nodeIndex(Int(raw[b &+ 2]), Int(raw[b &+ 3]), Int(raw[b &+ 4]))
            terms[i] = NutationTerm(
                psi: SIMD2<Double>(Double(raw[b &+ 7]), Double(raw[b &+ 5])),
                eps: SIMD2<Double>(Double(raw[b &+ 8]), Double(raw[b &+ 10])),
                rate: SIMD2<Double>(Double(raw[b &+ 9]), Double(raw[b &+ 6])),
                anomaly: ai,
                node: ni &+ 14
            )
            i &+= 1
        }
        return NutationTableStorage(rateCount: lastRate, terms: UnsafePointer(terms))
        #endif
    }
}

enum EngineNutation {
    private static let asecPerTurn = 1_296_000.0
    private static let twoPi = 2.0 * EngineConstants.pi

    @inline(__always)
    private static func nutTurns(_ asec: Double, _ rate: Double, t: Double) -> Double {
        (asec / asecPerTurn).addingProduct(t, rate / asecPerTurn)
    }

    #if ASTRONOMYKIT_SERIES_ACCELERATE && canImport(Accelerate)
    @inline(__always)
    private static func fillAngleTables(
        lC: Double,
        lS: Double,
        lpC: Double,
        lpS: Double,
        f2C: Double,
        f2S: Double,
        dC: Double,
        dS: Double,
        omC: Double,
        omS: Double,
        anomC: UnsafeMutablePointer<Double>,
        anomS: UnsafeMutablePointer<Double>,
        nodeC: UnsafeMutablePointer<Double>,
        nodeS: UnsafeMutablePointer<Double>
    ) {
        // 14 anomaly (l, lp) pairs
        let l2C = lC * lC - lS * lS
        let l2S = 2.0 * lC * lS
        let l3C = l2C * lC - l2S * lS
        let l3S = l2C * lS + l2S * lC
        let lp2C = lpC * lpC - lpS * lpS
        let lp2S = 2.0 * lpC * lpS
        let lplC = lC * lpC - lS * lpS
        let lplS = lC * lpS + lS * lpC
        let lmlC = lC * lpC + lS * lpS
        let lmlS = -lC * lpS + lS * lpC

        anomC[0] = 1.0
        anomS[0] = 0.0  // (0, 0)
        anomC[1] = lC
        anomS[1] = lS  // (1, 0)
        anomC[2] = lC
        anomS[2] = -lS  // (-1, 0)
        anomC[3] = l2C
        anomS[3] = l2S  // (2, 0)
        anomC[4] = l2C
        anomS[4] = -l2S  // (-2, 0)
        anomC[5] = l3C
        anomS[5] = l3S  // (3, 0)
        anomC[6] = lpC
        anomS[6] = lpS  // (0, 1)
        anomC[7] = lpC
        anomS[7] = -lpS  // (0, -1)
        anomC[8] = lp2C
        anomS[8] = lp2S  // (0, 2)
        anomC[9] = lp2C
        anomS[9] = -lp2S  // (0, -2)
        anomC[10] = lplC
        anomS[10] = lplS  // (1, 1)
        anomC[11] = lplC
        anomS[11] = -lplS  // (-1, -1)
        anomC[12] = lmlC
        anomS[12] = lmlS  // (1, -1)
        anomC[13] = lmlC
        anomS[13] = -lmlS  // (-1, 1)

        // 18 node (F, D, Om) triples
        let d2C = dC * dC - dS * dS
        let d2S = 2.0 * dC * dS
        let om2C = omC * omC - omS * omS
        let om2S = 2.0 * omC * omS
        let f2d2C = f2C * d2C + f2S * d2S  // 2F - 2D
        let f2d2S = -f2C * d2S + f2S * d2C
        let f2omC = f2C * omC - f2S * omS
        let f2omS = f2C * omS + f2S * omC
        let f2om2C = f2C * om2C - f2S * om2S
        let f2om2S = f2C * om2S + f2S * om2C
        let n16C = f2om2C * d2C - f2om2S * d2S  // (2, 2, 2)
        let n16S = f2om2C * d2S + f2om2S * d2C

        nodeC[0] = 1.0
        nodeS[0] = 0.0  // (0, 0, 0)
        nodeC[1] = omC
        nodeS[1] = omS  // (0, 0, 1)
        nodeC[2] = om2C
        nodeS[2] = om2S  // (0, 0, 2)
        nodeC[3] = f2C
        nodeS[3] = f2S  // (2, 0, 0)
        nodeC[4] = f2omC
        nodeS[4] = f2omS  // (2, 0, 1)
        nodeC[5] = f2om2C
        nodeS[5] = f2om2S  // (2, 0, 2)
        nodeC[6] = dC
        nodeS[6] = dS  // (0, 1, 0)
        nodeC[7] = dC * omC - dS * omS
        nodeS[7] = dC * omS + dS * omC  // (0, 1, 1)
        nodeC[8] = d2C
        nodeS[8] = d2S  // (0, 2, 0)
        nodeC[9] = d2C * omC - d2S * omS
        nodeS[9] = d2C * omS + d2S * omC  // (0, 2, 1)
        nodeC[10] = d2C * omC + d2S * omS
        nodeS[10] = d2C * omS - d2S * omC  // (0, -2, 1)
        nodeC[11] = f2d2C * omC - f2d2S * omS
        nodeS[11] = f2d2C * omS + f2d2S * omC  // (2, -2, 1)
        nodeC[12] = f2d2C * om2C - f2d2S * om2S
        nodeS[12] = f2d2C * om2S + f2d2S * om2C  // (2, -2, 2)
        nodeC[13] = f2d2C
        nodeS[13] = -f2d2S  // (-2, 2, 0)
        nodeC[14] = f2om2C * dC - f2om2S * dS
        nodeS[14] = f2om2C * dS + f2om2S * dC  // (2, 1, 2)
        nodeC[15] = f2omC * d2C - f2omS * d2S
        nodeS[15] = f2omC * d2S + f2omS * d2C  // (2, 2, 1)
        nodeC[16] = n16C
        nodeS[16] = n16S  // (2, 2, 2)
        nodeC[17] = n16C * d2C - n16S * d2S
        nodeS[17] = n16C * d2S + n16S * d2C  // (2, 4, 2)
    }

    static func iau2000b(tt: Double) -> (psi: Double, eps: Double) {
        let t = tt / 36525.0
        let table = NutationTableStorage.shared

        let tL = nutTurns(485_868.249036, 1_717_915_923.2178, t: t)
        let tLp = nutTurns(1_287_104.79305, 129_596_581.0481, t: t)
        let tF2 = 2.0 * nutTurns(335_779.526232, 1_739_527_262.8478, t: t)
        let tD = nutTurns(1_072_260.70369, 1_602_961_601.2090, t: t)
        let tOm = nutTurns(450_160.398036, -6_962_890.5431, t: t)

        let yL = (tL - rint(tL)) * twoPi
        let yLp = (tLp - rint(tLp)) * twoPi
        let yF2 = (tF2 - rint(tF2)) * twoPi
        let yD = (tD - rint(tD)) * twoPi
        let yOm = (tOm - rint(tOm)) * twoPi

        if let scratch = VsopDebugScratch.buffer() {
            // Scratch has 912 doubles; iau2000b is a leaf function needing 581 doubles.
            let inAngles = scratch
            let fundS = scratch + 8
            let fundC = scratch + 16
            let anomC = scratch + 24
            let anomS = scratch + 40
            let nodeC = scratch + 56
            let nodeS = scratch + 80
            let gaC = scratch + 104
            let gaS = scratch + 184
            let gnC = scratch + 264
            let gnS = scratch + 344
            let gzC = scratch + 424
            let gzS = scratch + 504

            inAngles[0] = yL
            inAngles[1] = yLp
            inAngles[2] = yF2
            inAngles[3] = yD
            inAngles[4] = yOm
            var n5: Int32 = 5
            vvsincos(fundS, fundC, inAngles, &n5)

            fillAngleTables(
                lC: fundC[0], lS: fundS[0],
                lpC: fundC[1], lpS: fundS[1],
                f2C: fundC[2], f2S: fundS[2],
                dC: fundC[3], dS: fundS[3],
                omC: fundC[4], omS: fundS[4],
                anomC: anomC, anomS: anomS,
                nodeC: nodeC, nodeS: nodeS
            )

            let n77 = vDSP_Length(NutationTableStorage.termCount)
            vDSP_vindexD(anomC, table.aIdxD, 1, gaC, 1, n77)
            vDSP_vindexD(anomS, table.aIdxD, 1, gaS, 1, n77)
            vDSP_vindexD(nodeC, table.nIdxD, 1, gnC, 1, n77)
            vDSP_vindexD(nodeS, table.nIdxD, 1, gnS, 1, n77)

            var ga = DSPDoubleSplitComplex(realp: gaC, imagp: gaS)
            var gn = DSPDoubleSplitComplex(realp: gnC, imagp: gnS)
            var gz = DSPDoubleSplitComplex(realp: gzC, imagp: gzS)
            vDSP_zvmulD(&ga, 1, &gn, 1, &gz, 1, n77, 1)

            var psiC = 0.0
            var psiS = 0.0
            var epsC = 0.0
            var epsS = 0.0
            var rateE = 0.0
            var rateP = 0.0
            let nRate = vDSP_Length(table.rateCount)
            vDSP_dotprD(table.pc, 1, gzC, 1, &psiC, n77)
            vDSP_dotprD(table.ps, 1, gzS, 1, &psiS, n77)
            vDSP_dotprD(table.ec, 1, gzC, 1, &epsC, n77)
            vDSP_dotprD(table.es, 1, gzS, 1, &epsS, n77)
            vDSP_dotprD(table.ect, 1, gzC, 1, &rateE, nRate)
            vDSP_dotprD(table.pst, 1, gzS, 1, &rateP, nRate)

            let psi = -0.000135 + ((psiC + psiS + t * rateP) * 1.0e-7)
            let eps = +0.000388 + ((epsC + epsS + t * rateE) * 1.0e-7)
            return (psi, eps)
        }

        // Fallback if thread-local scratch allocation fails.
        let buf = UnsafeMutablePointer<Double>.allocate(capacity: 64)
        defer { buf.deallocate() }
        let anomC = buf
        let anomS = buf + 14
        let nodeC = buf + 28
        let nodeS = buf + 46
        fillAngleTables(
            lC: cos(yL), lS: sin(yL),
            lpC: cos(yLp), lpS: sin(yLp),
            f2C: cos(yF2), f2S: sin(yF2),
            dC: cos(yD), dS: sin(yD),
            omC: cos(yOm), omS: sin(yOm),
            anomC: anomC, anomS: anomS,
            nodeC: nodeC, nodeS: nodeS
        )
        var psiSum = 0.0
        var epsSum = 0.0
        var rateE = 0.0
        var rateP = 0.0
        var k = 0
        while k < NutationTableStorage.termCount {
            let ai = table.aIdx[k]
            let ni = table.nIdx[k]
            let ac = anomC[ai]
            let aS = anomS[ai]
            let nc = nodeC[ni]
            let nS = nodeS[ni]
            let zc = ac * nc - aS * nS
            let zs = ac * nS + aS * nc
            psiSum += table.pc[k] * zc + table.ps[k] * zs
            epsSum += table.ec[k] * zc + table.es[k] * zs
            if k < table.rateCount {
                rateE += table.ect[k] * zc
                rateP += table.pst[k] * zs
            }
            k &+= 1
        }
        let psi = -0.000135 + ((psiSum + t * rateP) * 1.0e-7)
        let eps = +0.000388 + ((epsSum + t * rateE) * 1.0e-7)
        return (psi, eps)
    }

    #else

    @inline(__always)
    private static func nutMul(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
        let rot = SIMD2<Double>(-a.y, a.x)
        return (a * SIMD2<Double>(repeating: b.x))
            .addingProduct(rot, SIMD2<Double>(repeating: b.y))
    }

    @inline(__always)
    private static func nutConj(_ a: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2<Double>(a.x, -a.y)
    }

    @inline(__always)
    private static func nutCosSin(
        _ turnA: Double,
        _ turnB: Double
    ) -> (SIMD2<Double>, SIMD2<Double>) {
        let y = SIMD2<Double>(turnA - rint(turnA), turnB - rint(turnB)) * twoPi
        let w = y * y
        let c = EngineVsop.seriesHalfCos(w)
        let s = y * EngineVsop.seriesHalfSinc(w) * c
        let c2 = SIMD2<Double>(repeating: -1.0).addingProduct(c + c, c)
        return (SIMD2<Double>(c2.x, s.x), SIMD2<Double>(c2.y, s.y))
    }

    static func iau2000b(tt: Double) -> (psi: Double, eps: Double) {
        let t = tt / 36525.0
        let table = NutationTableStorage.shared
        let terms = table.terms
        let rateCount = table.rateCount

        let (l, lp) = nutCosSin(
            nutTurns(485_868.249036, 1_717_915_923.2178, t: t),
            nutTurns(1_287_104.79305, 129_596_581.0481, t: t)
        )
        let (f2, d) = nutCosSin(
            2.0 * nutTurns(335_779.526232, 1_739_527_262.8478, t: t),
            nutTurns(1_072_260.70369, 1_602_961_601.2090, t: t)
        )
        let (om, _) = nutCosSin(
            nutTurns(450_160.398036, -6_962_890.5431, t: t),
            0.0
        )

        let l2 = nutMul(l, l)
        let lp2 = nutMul(lp, lp)
        let lpl = nutMul(l, lp)
        let lml = nutMul(l, nutConj(lp))

        let d2 = nutMul(d, d)
        let om2 = nutMul(om, om)
        let f2d2 = nutMul(f2, nutConj(d2))
        let f2om = nutMul(f2, om)
        let f2om2 = nutMul(f2, om2)
        let n16 = nutMul(f2om2, d2)

        // Single contiguous 32-pair stack table: 0..<14 = anomaly, 14..<32 = node.
        var pairs = (
            SIMD2<Double>(1.0, 0.0),  // 0: (0, 0)
            l,  // 1: (1, 0)
            nutConj(l),  // 2: (-1, 0)
            l2,  // 3: (2, 0)
            nutConj(l2),  // 4: (-2, 0)
            nutMul(l2, l),  // 5: (3, 0)
            lp,  // 6: (0, 1)
            nutConj(lp),  // 7: (0, -1)
            lp2,  // 8: (0, 2)
            nutConj(lp2),  // 9: (0, -2)
            lpl,  // 10: (1, 1)
            nutConj(lpl),  // 11: (-1, -1)
            lml,  // 12: (1, -1)
            nutConj(lml),  // 13: (-1, 1)
            SIMD2<Double>(1.0, 0.0),  // 14: (0, 0, 0)
            om,  // 15: (0, 0, 1)
            om2,  // 16: (0, 0, 2)
            f2,  // 17: (2, 0, 0)
            f2om,  // 18: (2, 0, 1)
            f2om2,  // 19: (2, 0, 2)
            d,  // 20: (0, 1, 0)
            nutMul(d, om),  // 21: (0, 1, 1)
            d2,  // 22: (0, 2, 0)
            nutMul(d2, om),  // 23: (0, 2, 1)
            nutMul(nutConj(d2), om),  // 24: (0, -2, 1)
            nutMul(f2d2, om),  // 25: (2, -2, 1)
            nutMul(f2d2, om2),  // 26: (2, -2, 2)
            nutConj(f2d2),  // 27: (-2, 2, 0)
            nutMul(f2om2, d),  // 28: (2, 1, 2)
            nutMul(f2om, d2),  // 29: (2, 2, 1)
            n16,  // 30: (2, 2, 2)
            nutMul(n16, d2)  // 31: (2, 4, 2)
        )

        return withUnsafePointer(to: &pairs) { pairsRaw in
            let p = UnsafeRawPointer(pairsRaw).assumingMemoryBound(to: SIMD2<Double>.self)

            var psi0 = SIMD2<Double>.zero
            var eps0 = SIMD2<Double>.zero
            var rate0 = SIMD2<Double>.zero
            var psi1 = SIMD2<Double>.zero
            var eps1 = SIMD2<Double>.zero
            var rate1 = SIMD2<Double>.zero

            var k = 0
            while k &+ 1 < rateCount {
                let t0 = terms[k]
                let t1 = terms[k &+ 1]
                let z0 = nutMul(p[t0.anomaly], p[t0.node])
                let z1 = nutMul(p[t1.anomaly], p[t1.node])
                psi0 = psi0.addingProduct(t0.psi, z0)
                eps0 = eps0.addingProduct(t0.eps, z0)
                rate0 = rate0.addingProduct(t0.rate, z0)
                psi1 = psi1.addingProduct(t1.psi, z1)
                eps1 = eps1.addingProduct(t1.eps, z1)
                rate1 = rate1.addingProduct(t1.rate, z1)
                k &+= 2
            }
            if k < rateCount {
                let t0 = terms[k]
                let z0 = nutMul(p[t0.anomaly], p[t0.node])
                psi0 = psi0.addingProduct(t0.psi, z0)
                eps0 = eps0.addingProduct(t0.eps, z0)
                rate0 = rate0.addingProduct(t0.rate, z0)
                k &+= 1
            }
            while k &+ 1 < NutationTableStorage.termCount {
                let t0 = terms[k]
                let t1 = terms[k &+ 1]
                let z0 = nutMul(p[t0.anomaly], p[t0.node])
                let z1 = nutMul(p[t1.anomaly], p[t1.node])
                psi0 = psi0.addingProduct(t0.psi, z0)
                eps0 = eps0.addingProduct(t0.eps, z0)
                psi1 = psi1.addingProduct(t1.psi, z1)
                eps1 = eps1.addingProduct(t1.eps, z1)
                k &+= 2
            }
            if k < NutationTableStorage.termCount {
                let t0 = terms[k]
                let z0 = nutMul(p[t0.anomaly], p[t0.node])
                psi0 = psi0.addingProduct(t0.psi, z0)
                eps0 = eps0.addingProduct(t0.eps, z0)
            }

            psi0 += psi1
            eps0 += eps1
            rate0 += rate1

            let psi = -0.000135 + ((psi0.x + psi0.y + t * rate0.y) * 1.0e-7)
            let eps = +0.000388 + ((eps0.x + eps0.y + t * rate0.x) * 1.0e-7)
            return (psi, eps)
        }
    }
    #endif
}
