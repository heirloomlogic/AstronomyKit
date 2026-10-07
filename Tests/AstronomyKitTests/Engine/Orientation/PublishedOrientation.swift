//
//  PublishedOrientation.swift
//  AstronomyKit
//
//  SOFA reference values for nutation, precession and Earth rotation.
//

import Foundation
import Testing

@testable import AstronomyKit

/// Reference values from the SOFA routines, through ERFA 2.0.1, the BSD
/// edition of SOFA that `THIRD_PARTY_NOTICES` already pins (commit
/// 9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3). Angles are in radians and
/// dates are two-part Julian dates, as SOFA takes them.
enum PublishedOrientation {
    /// Days from the MJD epoch to J2000: JD 2,451,545.0 is MJD 51,544.5.
    static let mjdAtJ2000 = 51_544.5

    // MARK: - ERFA's own test program

    // Values and tolerances from `t_erfa_c.c` at the commit above. Each date
    // is 2400000.5 plus the MJD given.

    /// `t_nut00b`: `eraNut00b(2400000.5, 53736.0)`, tolerance 1e-13.
    static let nut00b = (mjd: 53_736.0, dpsi: -0.963_255_229_114_836_278_3e-5, deps: 0.406_319_710_662_115_936_7e-4)

    /// `t_obl06`: `eraObl06(2400000.5, 54388.0)`, tolerance 1e-14.
    static let obl06 = (mjd: 54_388.0, value: 0.409_074_922_938_725_820_4)

    /// `t_p06e`: `eraP06e(2400000.5, 52541.0)`, tolerance 1e-14.
    static let p06e = (
        mjd: 52_541.0,
        eps0: 0.409_092_600_600_582_871_5,
        psia: 0.666_436_963_019_161_343_1e-3,
        oma: 0.409_092_597_378_325_598_2,
        chia: 0.138_770_337_953_091_536_4e-5
    )

    /// `t_bp06`: the precession matrix `rp` of `eraBp06(2400000.5, 50123.9999)`,
    /// row by row, in SOFA's convention that `rp` times a J2000 vector is the
    /// vector of date. Tolerances 1e-12 on the diagonal and 1e-14 elsewhere.
    static let bp06 = (
        mjd: 50_123.999_9,
        rp: [
            [0.999_999_550_486_496_027_8, 0.869_611_257_885_540_483_2e-3, 0.377_892_929_334_139_012_7e-3],
            [-0.869_611_256_051_018_624_4e-3, 0.999_999_621_888_045_882_0, -0.169_164_616_894_189_628_5e-6],
            [-0.377_892_933_555_760_341_8e-3, -0.159_455_404_078_649_507_6e-6, 0.999_999_928_598_450_122_2],
        ]
    )

    /// `t_numat`: `eraNumat(epsa, dpsi, deps)`, row by row, tolerance 1e-12.
    static let numat = (
        epsa: 0.409_078_976_335_650_990_0,
        dpsi: -0.963_090_910_711_558_239_3e-5,
        deps: 0.406_323_917_400_167_882_6e-4,
        matrix: [
            [0.999_999_999_953_622_794_9, 0.883_623_932_023_625_057_7e-5, 0.383_083_344_745_825_190_8e-5],
            [-0.883_608_365_701_668_858_8e-5, 0.999_999_999_135_465_495_9, -0.406_324_086_536_185_769_8e-4],
            [-0.383_119_248_183_338_522_6e-5, 0.406_323_748_021_693_415_9e-4, 0.999_999_999_167_166_040_7],
        ]
    )

    /// `t_era00`: `eraEra00(2400000.5, 54388.0)`, tolerance 1e-12.
    static let era00 = (mjd: 54_388.0, value: 0.402_283_724_002_815_810_2)

    /// `t_gmst06`: `eraGmst06(2400000.5, 53736.0, 2400000.5, 53736.0)`, UT1
    /// and TT both MJD 53736.0, tolerance 1e-12.
    static let gmst06 = (mjd: 53_736.0, value: 1.754_174_971_870_091_203)

    /// `t_gst06a`: `eraGst06a(2400000.5, 53736.0, 2400000.5, 53736.0)`, the
    /// apparent sidereal time of IAU 2006/2000A with the complementary terms.
    static let gst06a = (mjd: 53_736.0, value: 1.754_166_137_675_019_159)

    /// The matrix `t_rx`, `t_ry` and `t_rz` rotate, row by row.
    static let rotationInput: [[Double]] = [[2, 3, 2], [3, 2, 3], [3, 4, 5]]

    /// `t_rx`, `t_ry` and `t_rz`: `eraRx`, `eraRy` and `eraRz` by 0.3456789
    /// rad applied to ``rotationInput``, tolerance 1e-12. Index 0, 1 and 2
    /// are the x, y and z axes.
    static let axisRotations = (
        angle: 0.345_678_9,
        results: [
            [
                [2, 3, 2],
                [3.839_043_388_235_612_460, 3.237_033_249_594_111_899, 4.516_714_379_005_982_719],
                [1.806_030_415_924_501_684, 3.085_711_545_336_372_503, 3.687_721_683_977_873_065],
            ],
            [
                [0.865_184_781_897_815_993_0, 1.467_194_920_539_316_554, 0.187_513_791_127_445_734_2],
                [3, 2, 3],
                [3.500_207_892_850_427_330, 4.779_889_022_262_298_150, 5.381_899_160_903_798_712],
            ],
            [
                [2.898_197_754_208_926_769, 3.500_207_892_850_427_330, 2.898_197_754_208_926_769],
                [2.144_865_911_309_686_813, 0.865_184_781_897_815_993, 2.144_865_911_309_686_813],
                [3, 4, 5],
            ],
        ] as [[[Double]]]
    )

    /// `t_c2s` and `t_p2s`: the direction of (100, −50, 25), tolerance 1e-14
    /// on the angles and 1e-9 on the length.
    static let p2s = (
        vector: (x: 100.0, y: -50.0, z: 25.0),
        theta: -0.463_647_609_000_806_116_2,
        phi: 0.219_987_977_395_459_446_3,
        r: 114.564_392_373_896_000_2
    )

    /// `t_s2c`: the unit vector at θ = 3.0123, φ = −0.999, tolerance 1e-12.
    static let s2c = (
        theta: 3.012_3,
        phi: -0.999,
        vector: [-0.536_626_766_726_052_390_6, 0.069_771_110_976_514_536_5, -0.840_930_261_856_621_404_1]
    )

    /// `t_s2p`: the vector at θ = −3.21, φ = 0.123, r = 0.456, tolerance 1e-12.
    static let s2p = (
        theta: -3.21, phi: 0.123, r: 0.456,
        vector: [-0.451_496_467_388_016_522_8, 0.030_933_942_773_425_868_8, 0.055_946_681_051_087_793_3]
    )

    /// `t_hd2ae`: hour angle 1.1 and declination 1.2 seen from latitude 0.3
    /// are at azimuth 5.916889243730066194 (tolerance 1e-13) and elevation
    /// 0.4472186304990486228 (tolerance 1e-14).
    static let hd2ae = (
        ha: 1.1,
        dec: 1.2,
        latitude: 0.3,
        azimuth: 5.916_889_243_730_066_194,
        elevation: 0.447_218_630_499_048_622_8
    )

    /// `t_icrs2g`: right ascension 5.9338074302227188048671087 and
    /// declination −1.1784870613579944551540570 are at galactic longitude
    /// 5.5850536063818546461558 and latitude −0.7853981633974483096157,
    /// tolerance 1e-14.
    static let icrs2g = (
        ra: 5.933_807_430_222_718_804_867_108_7, dec: -1.178_487_061_357_994_455_154_057_0,
        longitude: 5.585_053_606_381_854_646_155_8, latitude: -0.785_398_163_397_448_309_615_7
    )

    /// The equatorial-to-galactic matrix of `eraIcrs2g`, row by row: row i is
    /// galactic axis i in J2000 equatorial coordinates, to 30 digits.
    static let galacticMatrix: [[Double]] = [
        [
            -0.054_875_560_416_215_368_492_398_900_454,
            -0.873_437_090_234_885_048_760_383_168_409,
            -0.483_835_015_548_713_226_831_774_175_116,
        ],
        [
            0.494_109_427_875_583_673_525_222_371_358,
            -0.444_829_629_960_011_178_146_614_061_616,
            0.746_982_244_497_218_890_527_388_004_556,
        ],
        [
            -0.867_666_149_019_004_701_181_616_534_570,
            -0.198_076_373_431_201_528_180_486_091_412,
            0.455_983_776_175_066_922_272_100_478_348,
        ],
    ]

    // MARK: - Other epochs

    /// One epoch of `references`.
    struct Reference: Sendable, CustomTestStringConvertible {
        let year: Int
        /// TT days from J2000.
        let tt: Double
        /// UT1 days from J2000.
        let ut: Double
        let dpsi: Double
        let deps: Double
        let obl06: Double
        let psia: Double
        let oma: Double
        let chia: Double
        let era00: Double
        let gmst06: Double

        var testDescription: String { "\(year)" }
    }

    /// pyerfa 2.0.1.5 (ERFA 2.0.1) at eight epochs from 1600 to 2500, with
    /// both dates passed as `(2400000.5, mjd)`: `nut00b` and `obl06` at TT,
    /// `psia`, `oma` and `chia` of `p06e` at TT, `era00` at UT1, and `gmst06`
    /// at UT1 and TT.
    ///
    /// TT is the whole day nearest the year's offset from J2000 at 365.25
    /// days a year, plus 0.375; UT1 is TT less 2⁻¹⁰ day, about 84 s. Both are
    /// exact doubles in days from J2000 and as MJDs, so the engine and SOFA
    /// read the same instant.
    static let references: [Reference] = [
        Reference(
            year: 1600, tt: -146_099.625, ut: -146_099.625_976_562_5,
            dpsi: 7.143045530400423e-05, deps: 2.0315303234601977e-05, obl06: 0.4100002462107326,
            psia: -0.09779191899899659, oma: 0.40909947111431105, chia: -0.0003888538455602486,
            era00: 1.003955419747946, gmst06: 0.9146221640053135
        ),
        Reference(
            year: 1800, tt: -73_049.625, ut: -73_049.625_976_562_5,
            dpsi: -4.117260473510175e-05, deps: 3.480058916579972e-05, obl06: 0.4095466591075139,
            psia: -0.04887511446497705, oma: 0.4090941439369108, chia: -0.00014847849820326527,
            era00: 0.9861119553851623, gmst06: 0.9414185072786658
        ),
        Reference(
            year: 1900, tt: -36_524.625, ut: -36_524.625_976_562_5,
            dpsi: 8.441315225518046e-05, deps: -1.1109477992455519e-05, obl06: 0.40931965873044374,
            psia: -0.024432221765266583, oma: 0.4090930114267239, chia: -6.271691477095782e-05,
            era00: 0.9771902232036354, gmst06: 0.9548369035292528
        ),
        Reference(
            year: 1950, tt: -18_261.625, ut: -18_261.625_976_562_5,
            dpsi: -1.5495563599045854e-05, deps: 4.0237080496701265e-05, obl06: 0.4092061292567849,
            psia: -0.012214345585818812, oma: 0.4090927298333922, chia: -2.8473527919685187e-05,
            era00: 0.9813304469005857, gmst06: 0.9701525564356148
        ),
        Reference(
            year: 2026, tt: 9_496.375, ut: 9_496.374_023_437_5,
            dpsi: 2.6168764822730146e-05, deps: 3.91280226330375e-05, obl06: 0.40903356301176197,
            psia: 0.006350647083266954, oma: 0.4090925842794122, chia: 1.2525780828907235e-05,
            era00: 0.9573477508673989, gmst06: 0.9631618958527517
        ),
        Reference(
            year: 2100, tt: 36_525.375, ut: 36_525.374_023_437_5,
            dpsi: 1.577672967920867e-05, deps: 4.167756036154639e-05, obl06: 0.4088655360276974,
            psia: 0.024422262293136224, oma: 0.4090926868183303, chia: 3.962863096775812e-05,
            era00: 0.9593467588407378, gmst06: 0.9817141711808258
        ),
        Reference(
            year: 2200, tt: 73_050.375, ut: 73_050.374_023_437_5,
            dpsi: 5.4422216644425085e-05, deps: -3.8630764631854145e-05, obl06: 0.408638530242483,
            psia: 0.048833787275791, oma: 0.4090930453931641, chia: 5.6142067835727994e-05,
            era00: 0.9504250266593459, gmst06: 0.995173042545416
        ),
        Reference(
            year: 2500, tt: 182_625.375, ut: 182_625.374_023_437_5,
            dpsi: -4.161705872784254e-06, deps: -4.71720536493255e-05, obl06: 0.4079584324565731,
            psia: 0.12200541923569676, oma: 0.40909351160789165, chia: -3.296179399605119e-05,
            era00: 0.9236598301147154, gmst06: 1.0356305329295554
        ),
    ]

    // MARK: - Helpers

    /// TT days from J2000 for an MJD.
    static func days(mjd: Double) -> Double { mjd - mjdAtJ2000 }

    /// `angle` in radians moved into (−π, π], for comparing angles that may
    /// sit on either side of a wrap.
    static func wrapped(_ angle: Double) -> Double {
        let r = remainder(angle, 2 * Double.pi)
        return r == -Double.pi ? Double.pi : r
    }

    /// The engine rotation as a SOFA matrix: row `i`, column `j` is
    /// `rot[j][i]`, so the matrix times a vector is the rotated vector.
    static func matrix<From, To>(_ rotation: Engine.Rotation<From, To>) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in rotation[j, i] } }
    }

    /// A cache that stores nothing, so a test evaluates the series every time.
    static var uncached: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> {
        .init(capacity: 0, registry: Engine.CacheRegistry())
    }

    /// Checks that `m` is a proper rotation: orthonormal rows and a
    /// determinant of 1, each within 1e-15.
    static func expectProperRotation(_ m: [[Double]], sourceLocation: SourceLocation = #_sourceLocation) {
        for i in 0..<3 {
            for j in 0..<3 {
                let dot = (0..<3).reduce(0.0) { $0 + m[i][$1] * m[j][$1] }
                #expect(abs(dot - (i == j ? 1 : 0)) <= 1e-15, "rows \(i), \(j)", sourceLocation: sourceLocation)
            }
        }
        let determinant =
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        #expect(abs(determinant - 1) <= 1e-15, "determinant", sourceLocation: sourceLocation)
    }

    /// R1(φ) and R3(φ) as SOFA's `iauRx` and `iauRz` apply them.
    static func r1(_ phi: Double) -> [[Double]] {
        [[1, 0, 0], [0, cos(phi), sin(phi)], [0, -sin(phi), cos(phi)]]
    }

    static func r3(_ phi: Double) -> [[Double]] {
        [[cos(phi), sin(phi), 0], [-sin(phi), cos(phi), 0], [0, 0, 1]]
    }

    static func product(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0.0) { $0 + a[i][$1] * b[$1][j] } } }
    }

    static func transposed(_ m: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { m[$0][i] } }
    }

    static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    /// The engine rotation whose SOFA matrix (see ``matrix(_:)``) is `m`.
    static func rotation<From, To>(_ m: [[Double]]) -> Engine.Rotation<From, To> {
        Engine.Rotation(rot: ((m[0][0], m[1][0], m[2][0]), (m[0][1], m[1][1], m[2][1]), (m[0][2], m[1][2], m[2][2])))
    }

    /// The largest absolute element difference of two 3×3 matrices, or NaN
    /// when any difference is NaN, so a comparison with it fails.
    static func maximumDifference(_ a: [[Double]], _ b: [[Double]]) -> Double {
        let differences = zip(a, b).flatMap { zip($0, $1).map { abs($0 - $1) } }
        if differences.contains(where: \.isNaN) { return .nan }
        return differences.max() ?? .infinity
    }

    /// The derivative of `f` at `x` from the five-point stencil with step `h`.
    ///
    /// With `x` and `h` exact binary fractions the stencil points are exact
    /// too, so the difference does not pick up rounding of the sample times.
    static func derivative(at x: Double, step h: Double, _ f: (Double) -> Double) -> Double {
        (f(x - 2 * h) - 8 * f(x - h) + 8 * f(x + h) - f(x + 2 * h)) / (12 * h)
    }
}
