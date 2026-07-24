//
//  ReproducibilityTests.swift
//  AstronomyKit
//
//  Bit-exact golden reproducibility suite (GitHub issue #28).
//
//  Purpose
//  -------
//  As of issue #28 the ephemeris transcendentals (sin/cos/tan/asin/atan2/…) are
//  served by vendored, deterministic musl implementations (`ak_*` in
//  `Sources/CLibAstronomy/detmath/`) rather than the platform libm. The stated
//  guarantee is that computed positions are *bit-identical* across macOS
//  versions, Linux, and Swift toolchains — and, critically, across optimization
//  levels (debug vs. release).
//
//  These tests lock that guarantee in. Every expected value below is stored as a
//  raw `UInt64` IEEE-754 bit pattern and compared with the computed `Double`
//  using exact `==` (never a tolerance). The human-readable decimal appears in a
//  trailing comment on each line purely for review; the bit pattern is the
//  source of truth. `Double.==` treats NaN as unequal, but none of these
//  quantities are NaN, so `==` is exactly bitwise identity here.
//
//  If a value legitimately changes
//  -------------------------------
//  A failure here is expected ONLY when the numerical basis intentionally moves:
//  a musl/detmath update, or an upstream astronomy-engine resync. In that case
//  the values are being re-baselined, not "fixed":
//
//    1. Regenerate every constant from a single deterministic run (do not
//       hand-edit individual bit patterns).
//    2. Record the change in CHANGELOG as a downstream re-baselining event,
//       noting the triggering upstream/musl change.
//
//  Do NOT loosen these comparisons to tolerances to make a failure pass. A
//  debug-vs-release disagreement in particular is a correctness bug in the
//  determinism guarantee, not a rounding artifact to be papered over.
//
//  All inputs are fixed instants (explicit UTC calendar components), never
//  "now", so the suite is fully reproducible.
//

import Testing

@testable import AstronomyKit

@Suite("Reproducibility (bit-exact golden values, issue #28)")
struct ReproducibilityTests {
    // MARK: - Fixed Inputs

    /// Fixed instants spanning four decades. Constructed from explicit UTC
    /// calendar components so they never depend on the wall clock.
    static let t1980 = AstroTime(year: 1_980, month: 3, day: 20, hour: 12, minute: 0, second: 0)
    static let t2000 = AstroTime(year: 2_000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
    static let t2026 = AstroTime(year: 2_026, month: 7, day: 24, hour: 0, minute: 0, second: 0)
    static let t2050 = AstroTime(year: 2_050, month: 12, day: 21, hour: 6, minute: 0, second: 0)

    /// Asheville, NC — the fixed surface observer used elsewhere in the suite.
    static let asheville = Observer(latitude: 35.5951, longitude: -82.5515, height: 650)

    // MARK: - Comparison Helpers

    /// Decodes an expected value from its exact IEEE-754 bit pattern.
    private static func exact(_ pattern: UInt64) -> Double { Double(bitPattern: pattern) }

    /// Asserts every component of an ecliptic position matches bit-for-bit.
    private func expectEcliptic(
        _ ecliptic: Ecliptic,
        lon: UInt64,
        lat: UInt64,
        dist: UInt64,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            ecliptic.longitude == Self.exact(lon),
            "\(label): ecliptic longitude drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            ecliptic.latitude == Self.exact(lat),
            "\(label): ecliptic latitude drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            ecliptic.distance == Self.exact(dist),
            "\(label): ecliptic distance drifted",
            sourceLocation: sourceLocation
        )
    }

    /// Asserts every component of an equatorial position matches bit-for-bit.
    private func expectEquatorial(
        _ equatorial: Equatorial,
        ra: UInt64,
        dec: UInt64,
        dist: UInt64,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            equatorial.rightAscension == Self.exact(ra),
            "\(label): right ascension drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            equatorial.declination == Self.exact(dec),
            "\(label): declination drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            equatorial.distance == Self.exact(dist),
            "\(label): distance drifted",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - 1. Geocentric Ecliptic Positions

    /// Geocentric ecliptic (longitude/latitude/distance) for every principal
    /// body at each fixed instant. Sun and planets use the equatorial-to-ecliptic
    /// conversion of the geocentric vector; the Moon uses the unified
    /// `Moon.ecliptic(_:)` API. Pluto exercises the cached state-table path
    /// (all four instants lie well inside the tabulated range).

    @Test("Geocentric ecliptic positions at 1980-03-20T12:00Z")
    func eclipticPositions1980() throws {
        let t = Self.t1980
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x3fa1_cccb_bf97_a4b2, lat: 0xbefd_af5e_35fe_7ad9, dist: 0x3fef_e040_41fd_a1f3,
            "Sun 1980"  // λ 0.03476559366010558, β -2.8309851927250634e-05, d 0.9961243904954799
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4075_172f_b005_2c4d, lat: 0x3fe9_7521_5d80_db8b, dist: 0x3fe6_71a2_922c_1add,
            "Mercury 1980"  // λ 337.4491424753258, β 0.7955481363522819, d 0.7013714651992263
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4046_914f_6d22_1716, lat: 0x4001_615b_6111_6916, dist: 0x3fea_bbe8_ea18_27f5,
            "Venus 1980"  // λ 45.13523639835891, β 2.172537573188616, d 0.8354382106929267
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4062_75ce_e74c_433c, lat: 0x400d_dfbd_62fc_7b33, dist: 0x3fe7_8261_0a61_5b27,
            "Mars 1980"  // λ 147.68150677580877, β 3.7342479451466715, d 0.7346654131641558
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4063_0888_e467_d1ec, lat: 0x3ff5_0147_543a_2c05, dist: 0x4011_fbe3_fcda_64cc,
            "Jupiter 1980"  // λ 152.2667104747519, β 1.3128121652723632, d 4.495986891584106
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4065_a484_fef2_f92f, lat: 0x4003_53f4_9eb4_e65f, dist: 0x4020_e8a4_0071_f1bf,
            "Saturn 1980"  // λ 173.14123485046136, β 2.41599391927302, d 8.45437623396799
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406d_6c6b_274d_b29d, lat: 0x3fd2_800b_ffb2_5d77, dist: 0x4032_2828_1316_8d46,
            "Uranus 1980"  // λ 235.38808026480993, β 0.2890653607405151, d 18.156861489301512
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_6aac_9989_ecd6, lat: 0x3ff6_0e9e_aa5b_6211, dist: 0x403e_239b_e7ba_fb9d,
            "Neptune 1980"  // λ 262.6671386134816, β 1.3785692839211416, d 30.13909767451297
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4069_1ecd_b365_de2d, lat: 0x4031_acb6_9ae9_003d, dist: 0x403d_4684_c8a6_a007,
            "Pluto 1980"  // λ 200.96260995765752, β 17.674661332974427, d 29.275463619880636
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x4049_ebad_3ce7_36b3, lat: 0xc014_b8bc_7b60_b5a9, dist: 0x3f64_2f33_e11a_920b,
            "Moon 1980"  // λ 51.84122430124025, β -5.1804065015580045, d 0.0024639142291837993
        )
    }

    @Test("Geocentric ecliptic positions at 2000-01-01T00:00Z")
    func eclipticPositions2000() throws {
        let t = Self.t2000
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4071_7dbe_9d61_ac65, lat: 0x3eb1_1f64_b7bc_c6de, dist: 0x3fef_7757_a293_2d91,
            "Sun 2000"  // λ 279.8590368094795, β 1.0205883133714958e-06, d 0.9833181548396387
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_f1c8_70f9_2086, lat: 0xbfee_459e_4ff4_e901, dist: 0x3ff6_9c15_78f7_6f14,
            "Mercury 2000"  // λ 271.111435864594, β -0.9459983407644189, d 1.4131064152961175
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406e_1ebf_54ef_9e58, lat: 0x4000_a38e_155a_c312, dist: 0x3ff2_267e_2ae9_f816,
            "Venus 2000"  // λ 240.96085593033308, β 2.0798608463595736, d 1.134397666580758
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4074_7937_8f51_d13d, lat: 0xbff1_305f_62c4_9a61, dist: 0x3ffd_8c8c_0ea5_ada6,
            "Mars 2000"  // λ 327.5760644145956, β -1.0743097169994587, d 1.8468132564692978
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4039_3bf7_806a_f66f, lat: 0xbff4_356a_c519_684d, dist: 0x4012_73c8_54a3_3ab3,
            "Jupiter 2000"  // λ 25.234245325197147, β -1.2630412768544546, d 4.613068888151861
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4044_3402_5f93_4094, lat: 0xc003_93d3_377c_5046, dist: 0x4021_4a10_7aa4_aa07,
            "Saturn 2000"  // λ 40.40632242860843, β -2.4471802077114573, d 8.644656975365264
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_ac7e_ed58_cfdf, lat: 0xbfe5_1cf6_3ad6_d21b, dist: 0x4034_b894_640f_3c06,
            "Uranus 2000"  // λ 314.78098807041346, β -0.6597853802873631, d 20.721014264792778
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4072_f2d7_cb6a_0627, lat: 0x3fce_5ea2_5d87_00bf, dist: 0x403f_050c_b0ec_1942,
            "Neptune 2000"  // λ 303.17768422523153, β 0.23726300780072582, d 31.019724900857234
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406f_6dfc_f3ca_de92, lat: 0x4025_b57f_db5b_9d2b, dist: 0x403f_11e0_3b56_ddce,
            "Pluto 2000"  // λ 251.43712796805318, β 10.854491095479338, d 31.069827755649207
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x406b_2963_6c0a_e3a1, lat: 0x4014_eceb_5c98_901b, dist: 0x3f65_f45f_8137_67ce,
            "Moon 2000"  // λ 217.29338647963326, β 5.231366583644582, d 0.0026800027205639903
        )
    }

    @Test("Geocentric ecliptic positions at 2026-07-24T00:00Z")
    func eclipticPositions2026() throws {
        let t = Self.t2026
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405e_4945_6e86_37c6, lat: 0x3f09_10a8_f811_2330, dist: 0x3ff0_40ce_426a_946c,
            "Sun 2026"  // λ 121.14486277682508, β 4.7807842755326325e-05, d 1.0158217043292792
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405a_9451_5567_bbb4, lat: 0xc010_2cc2_22e5_44fd, dist: 0x3fe5_e247_be9d_f4f3,
            "Mercury 2026"  // λ 106.31746420984456, β -4.043709321254252, d 0.683872101115098
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4064_b3c8_da51_a53c, lat: 0x3fe3_8f6c_7515_793d, dist: 0x3feb_a68c_b8ee_cadf,
            "Venus 2026"  // λ 165.61826816507698, β 0.6112577711863093, d 0.8640807735412998
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4053_67fd_1bbf_2008, lat: 0xbf8b_e469_3a2f_23bd, dist: 0x4000_3ba8_72c8_63d8,
            "Mars 2026"  // λ 77.62482350983203, β -0.013619253242625246, d 2.0291298835186176
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405f_4c23_40dc_d12a, lat: 0x3fdd_cd2c_2d05_f5e7, dist: 0x4019_2ff8_e3fa_74bb,
            "Jupiter 2026"  // λ 125.18965169490971, β 0.4656477393799307, d 6.296847879563923
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x402d_7b26_da6e_d84a, lat: 0xc003_e81a_591c_08e8, dist: 0x4022_3d36_e1f3_b520,
            "Saturn 2026"  // λ 14.74053080180251, β -2.488331504982046, d 9.119559346198514
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4050_2e8c_c473_861e, lat: 0xbfc3_ad3e_0d7c_ba08, dist: 0x4033_ffa6_5efe_67dc,
            "Uranus 2026"  // λ 64.72734175950652, β -0.1537244382720504, d 19.998632371054427
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4011_64a1_d53a_de7e, lat: 0xbff6_2384_fc92_18aa, dist: 0x403d_6941_8a4c_6e56,
            "Neptune 2026"  // λ 4.348273593633733, β -1.3836717477839025, d 29.41115631452552
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_05cb_6c2d_5b3f, lat: 0xc011_1224_7d49_fa2a, dist: 0x4041_46a0_549f_9ffb,
            "Pluto 2026"  // λ 304.36216371266704, β -4.267717321052752, d 34.55176790041147
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x406d_ee45_9c53_2e36, lat: 0xc014_d5ad_a0d3_f33b, dist: 0x3f66_2013_05f3_73d0,
            "Moon 2026"  // λ 239.44599739309496, β -5.208670151649865, d 0.0027008410976194566
        )
    }

    @Test("Geocentric ecliptic positions at 2050-12-21T06:00Z")
    func eclipticPositions2050() throws {
        let t = Self.t2050
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_d8c7_d92e_09b2, lat: 0x3f1b_b7b4_e430_12e0, dist: 0x3fef_7b72_dec0_c2a7,
            "Sun 2050"  // λ 269.5487911032061, β 0.0001057342679332096, d 0.9838194227832745
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406f_7004_4a31_b064, lat: 0x4007_67d1_daf6_4aae, dist: 0x3fe9_aa2b_857a_968d,
            "Mercury 2050"  // λ 251.50052365975273, β 2.9256932360088603, d 0.8020227057465533
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406b_dadd_d13f_bd53, lat: 0x4008_7828_bb18_37cd, dist: 0x3fe4_19ef_fc2f_407d,
            "Venus 2050"  // λ 222.83957731675272, β 3.05867143790872, d 0.628166191623691
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4076_6a94_8226_d247, lat: 0xbfd7_e67d_fd98_efc7, dist: 0x3ff1_528f_5ff7_9feb,
            "Mars 2050"  // λ 358.6612569347821, β -0.3734431244408793, d 1.0826562641832378
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4063_7bbc_4423_99e6, lat: 0x3ff0_2d06_a8c5_cde3, dist: 0x4013_8a2f_3c56_93de,
            "Jupiter 2050"  // λ 155.8667317099891, β 1.0109926788980992, d 4.884945814880636
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_2a1b_1ac7_bcdd, lat: 0xbfe4_65d3_c28b_4b55, dist: 0x4025_6419_53f1_17b5,
            "Saturn 2050"  // λ 306.6316173364883, β -0.637430076569539, d 10.695505736522913
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4065_f01e_4d5d_9253, lat: 0x3fe8_975c_6091_923f, dist: 0x4032_3063_ee2d_ce7d,
            "Uranus 2050"  // λ 175.50369900012683, β 0.7684766660791594, d 18.189024816687823
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x404c_0ef8_754d_bf82, lat: 0xbffc_17d1_4ff9_f330, dist: 0x403c_fd63_6387_5b3c,
            "Neptune 2050"  // λ 56.11695734306615, β -1.755814850242313, d 28.989797802492134
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4075_2a6c_1348_5726, lat: 0xc029_fa24_1312_3482, dist: 0x4044_fe56_08c9_4d51,
            "Pluto 2050"  // λ 338.6513855768011, β -12.988556476566604, d 41.98700055913162
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x3fe0_2c78_3518_508d, lat: 0x400a_88d0_b389_ebd9, dist: 0x3f64_47ba_6ad3_ca7e,
            "Moon 2050"  // λ 0.5054284131060897, β 3.3168043161835894, d 0.0024756089175011478
        )
    }

    // MARK: - 2. Equatorial Positions (Geocentric & Topocentric)

    @Test("Geocentric equatorial (RA/Dec/dist, J2000) at 2026-07-24T00:00Z")
    func equatorialGeocentric2026() throws {
        let t = Self.t2026
        expectEquatorial(
            try CelestialBody.sun.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4020_65cf_d2e9_2e86, dec: 0x4033_fb81_150b_c169, dist: 0x3ff0_40ce_426a_6836,
            "Sun (geo) 2026"  // RA 8.198851195301597 h, Dec 19.982438388223645°, d 1.015821704326766
        )
        expectEquatorial(
            try CelestialBody.moon.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x402f_6a0a_985a_594e, dec: 0xc039_0714_a51d_5a5b, dist: 0x3f66_2013_0616_77bf,
            "Moon (geo) 2026"  // RA 15.707112084416305 h, Dec -25.027658767381904°, d 0.002700841098614653
        )
        expectEquatorial(
            try CelestialBody.mars.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4014_4e6e_9c80_f8ab, dec: 0x4036_cfb2_2799_5175, dist: 0x4000_3ba8_72c8_5491,
            "Mars (geo) 2026"  // RA 5.076593823787486 h, Dec 22.811312174731444°, d 2.0291298835168807
        )
        expectEquatorial(
            try CelestialBody.jupiter.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4020_f879_62e2_9f42, dec: 0x4033_8298_077c_af5e, dist: 0x4019_2ff8_e3fa_69b3,
            "Jupiter (geo) 2026"  // RA 8.48530110374816 h, Dec 19.51013228220051°, d 6.2968478795614145
        )
    }

    @Test("Topocentric equatorial Moon from Asheville (J2000) at 2026-07-24T00:00Z")
    func equatorialTopocentric2026() throws {
        expectEquatorial(
            try CelestialBody.moon.equatorial(at: Self.t2026, from: Self.asheville, equatorDate: .j2000),
            ra: 0x402f_721c_47ba_30c6, dec: 0xc039_ce8a_bc52_1a66, dist: 0x3f65_f781_91f7_0af7,
            "Moon (topo Asheville) 2026"  // RA 15.722872010687194 h, Dec -25.806804437679965°, d 0.0026814966838356563
        )
    }

    // MARK: - 3. Rise / Set Searches

    @Test("Sunrise and sunset search times from Asheville after 2026-07-24T00:00Z")
    func riseSet2026() throws {
        let sunrise = try #require(
            try CelestialBody.sun.riseTime(after: Self.t2026, from: Self.asheville)
        )
        #expect(
            sunrise.universalTime == Self.exact(0x40c2_f278_3d35_6cae),
            "Sunrise UT drifted"  // 9700.939367940966 days since J2000
        )

        let sunset = try #require(
            try CelestialBody.sun.setTime(after: Self.t2026, from: Self.asheville)
        )
        #expect(
            sunset.universalTime == Self.exact(0x40c2_f243_a77d_8738),
            "Sunset UT drifted"  // 9700.528548899674 days since J2000
        )
    }

    // MARK: - 4. Moon Phase Search & Illumination

    @Test("Full-moon search time and phase-angle illumination")
    func moonPhaseAndIllumination() throws {
        let fullMoon = try #require(
            try Moon.searchPhase(.full, after: Self.t2026)
        )
        #expect(
            fullMoon.universalTime == Self.exact(0x40c2_f50d_e513_abc0),
            "Full-moon search UT drifted"  // 9706.108553370344 days since J2000
        )

        // Illumination at a fixed 45° phase angle exercises ak_cos directly.
        #expect(
            Moon.illumination(for: 45.0) == Self.exact(0x3fc2_bec3_3301_8866),
            "Moon illumination at 45° drifted"  // 0.1464466094067262
        )
    }

    // MARK: - 5. FixedStar Ecliptic Conversion

    /// Exercises the FixedStar ecliptic path (ak_atan2 / ak_asin) end to end.
    @Test("FixedStar (Sirius) ecliptic conversion at 2000-01-01T00:00Z")
    func fixedStarEcliptic2000() throws {
        let sirius = FixedStar(
            name: "Sirius",
            rightAscension: 6.752477,
            declination: -16.716116,
            distance: 8.6
        )
        expectEcliptic(
            try sirius.ecliptic(at: Self.t2000),
            lon: 0x405a_05b4_e27b_eb90, lat: 0xc043_cd71_c05c_4689, dist: 0x4120_9907_31d3_764f,
            "Sirius 2000"  // λ 104.08916532613353, β -39.60503391748086, d 543875.5973164531 AU
        )
    }

    // MARK: - 6. Chiron (Gravity-Simulated, Within Bounds)

    @Test("Chiron ecliptic position at 2026-07-24T00:00Z (within 1900–2150 bounds)")
    func chironEcliptic2026() throws {
        expectEcliptic(
            try Chiron.ecliptic(at: Self.t2026),
            lon: 0x403e_e4e5_00e4_efad, lat: 0x3fce_bdba_820d_96aa, dist: 0x4032_44d1_d887_25fc,
            "Chiron 2026"  // λ 30.894119315998683, β 0.2401650557541662, d 18.268826992984017
        )
    }
}
