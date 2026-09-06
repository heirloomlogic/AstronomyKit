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
//  using exact `==` (never a tolerance). The before/after numeric audit records decimal values for review;
//  the bit pattern is the source of truth. `Double.==` treats NaN as unequal, but none of these
//  quantities are NaN, so `==` is exactly bitwise identity here.
//
//  If a value legitimately changes
//  -------------------------------
//  A failure here is expected ONLY when the numerical basis intentionally moves:
//  a musl/detmath update, a physical-model or time-contract change, or an upstream resync. In that case
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
            lon: 0x3fa1_c6e6_4d1b_3121, lat: 0xbf20_7daf_6873_b028, dist: 0x3fef_e036_bb4a_178b,
            "Sun 1980"
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4075_172f_8d75_095e, lat: 0x3fe9_730b_052b_d768, dist: 0x3fe6_71b1_7d8a_2cd5,
            "Mercury 1980"
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4046_9156_3aa5_cdab, lat: 0x4001_6102_8f4f_afc4, dist: 0x3fea_bbef_6fa9_dc8a,
            "Venus 1980"
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4062_75ce_91d3_23b6, lat: 0x400d_de3f_d9e0_2ea5, dist: 0x3fe7_8292_33b1_1d74,
            "Mars 1980"
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4063_0889_7773_86db, lat: 0x3ff5_05d5_17e9_3cc5, dist: 0x4011_fc1f_bdde_c7e9,
            "Jupiter 1980"
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4065_a493_1c94_7233, lat: 0x4003_504e_d6de_e974, dist: 0x4020_e89f_552f_16b4,
            "Saturn 1980"
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406d_6c77_268c_30e0, lat: 0x3fd2_5d6f_708b_3bf8, dist: 0x4032_2813_491a_1b4d,
            "Uranus 1980"
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_6abc_2635_daa2, lat: 0x3ff6_106f_fc61_5cad, dist: 0x403e_2392_fbe0_0a90,
            "Neptune 1980"
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4069_1ecd_b20a_686b, lat: 0x4031_acb6_1b57_6d3a, dist: 0x403d_4685_050d_75e2,
            "Pluto 1980"
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x4049_ebaf_f82c_f0bd, lat: 0xc014_b8bc_ba13_51f7, dist: 0x3f64_2f33_ff34_649c,
            "Moon 1980"
        )
    }

    @Test("Geocentric ecliptic positions at 2000-01-01T00:00Z")
    func eclipticPositions2000() throws {
        let t = Self.t2000
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4071_7dbf_551b_8fe2, lat: 0x3f2e_3715_4de9_05d2, dist: 0x3fef_7774_9773_0894,
            "Sun 2000"
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_f1c9_fbdb_1cec, lat: 0xbfee_4319_dfc5_8eed, dist: 0x3ff6_9c1d_ad61_38e3,
            "Mercury 2000"
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406e_1ec3_df68_8186, lat: 0x4000_a44c_f254_f87f, dist: 0x3ff2_2686_861d_72a8,
            "Venus 2000"
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4074_7935_1eec_1d73, lat: 0xbff1_2f22_2e44_d1ff, dist: 0x3ffd_8ca7_0464_a0d6,
            "Mars 2000"
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4039_3bb1_446f_e662, lat: 0xbff4_3c69_9957_279e, dist: 0x4012_73af_215f_00ed,
            "Jupiter 2000"
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4044_33f3_3382_00ec, lat: 0xc003_93e8_7991_25b8, dist: 0x4021_4a2c_867a_47af,
            "Saturn 2000"
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_ac8b_c9a5_84c9, lat: 0xbfe5_11f4_dc68_d0a7, dist: 0x4034_b895_1b20_10be,
            "Uranus 2000"
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4072_f2ce_8d20_ce3d, lat: 0x3fce_1848_7fb6_8432, dist: 0x403f_0513_0a07_080b,
            "Neptune 2000"
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406f_6dfd_54e8_3564, lat: 0x4025_b580_4abb_32fa, dist: 0x403f_11e0_fcfd_fdea,
            "Pluto 2000"
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x406b_2964_0deb_8e71, lat: 0x4014_eceb_4be9_f652, dist: 0x3f65_f45f_8d09_b34e,
            "Moon 2000"
        )
    }

    @Test("Geocentric ecliptic positions at 2026-07-24T00:00Z")
    func eclipticPositions2026() throws {
        let t = Self.t2026
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405e_4948_df04_9697, lat: 0xbf21_c98f_4f71_9b44, dist: 0x3ff0_40cc_0033_6096,
            "Sun 2026"
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405a_9443_6ef9_3167, lat: 0xc010_2c4b_d7ec_4f1b, dist: 0x3fe5_e242_f1d3_ccfb,
            "Mercury 2026"
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4064_b3cb_db8b_584f, lat: 0x3fe3_8ba5_7dc5_b81a, dist: 0x3feb_a6a0_97fd_d6e7,
            "Venus 2026"
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4053_67ff_f626_59fb, lat: 0xbf8b_16d4_7447_1a39, dist: 0x4000_3ba0_4de2_a484,
            "Mars 2026"
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x405f_4c2d_1425_e33c, lat: 0x3fdd_d26c_43f6_cf94, dist: 0x4019_2fdd_02f7_7a21,
            "Jupiter 2026"
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x402d_7c7f_bd4a_63e1, lat: 0xc003_e941_17dc_2bd3, dist: 0x4022_3d36_7806_f729,
            "Saturn 2026"
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4050_2e8b_1741_9316, lat: 0xbfc3_dc41_ac1a_7703, dist: 0x4033_ffb4_07f2_aae3,
            "Uranus 2026"
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4011_61ab_b760_a14a, lat: 0xbff6_2e51_91b9_5e13, dist: 0x403d_6913_d381_de23,
            "Neptune 2026"
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_05cb_6a2e_93d9, lat: 0xc011_1225_05c8_ef3c, dist: 0x4041_46a0_753a_d328,
            "Pluto 2026"
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x406d_ee3e_9b8c_53ac, lat: 0xc014_d5ad_5b88_3111, dist: 0x3f66_2012_8e5d_6597,
            "Moon 2026"
        )
    }

    @Test("Geocentric ecliptic positions at 2050-12-21T06:00Z")
    func eclipticPositions2050() throws {
        let t = Self.t2050
        expectEcliptic(
            try CelestialBody.sun.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4070_d8c5_9ec4_ed43, lat: 0x3f25_9c51_1951_f286, dist: 0x3fef_7b71_913d_4c64,
            "Sun 2050"
        )
        expectEcliptic(
            try CelestialBody.mercury.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406f_7009_0870_6a6d, lat: 0x4007_6782_4859_b8be, dist: 0x3fe9_a9f7_54e2_2e86,
            "Mercury 2050"
        )
        expectEcliptic(
            try CelestialBody.venus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x406b_dad8_2db0_b9fa, lat: 0x4008_7831_1bb9_9d5a, dist: 0x3fe4_19d8_c2c2_83c5,
            "Venus 2050"
        )
        expectEcliptic(
            try CelestialBody.mars.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4076_6a90_4d34_faf4, lat: 0xbfd7_ccd6_a238_d5ac, dist: 0x3ff1_5296_6f77_42e3,
            "Mars 2050"
        )
        expectEcliptic(
            try CelestialBody.jupiter.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4063_7bb7_ca02_232f, lat: 0x3ff0_309f_4b1a_bd5d, dist: 0x4013_8a1d_a212_52ca,
            "Jupiter 2050"
        )
        expectEcliptic(
            try CelestialBody.saturn.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4073_2a1d_d291_9c06, lat: 0xbfe4_5654_1497_4590, dist: 0x4025_63fb_9111_e429,
            "Saturn 2050"
        )
        expectEcliptic(
            try CelestialBody.uranus.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4065_f016_2072_56cd, lat: 0x3fe8_9b5c_5e5f_3d70, dist: 0x4032_3074_f62c_4aa5,
            "Uranus 2050"
        )
        expectEcliptic(
            try CelestialBody.neptune.geocentricPosition(at: t).toEcliptic(),
            lon: 0x404c_0f1f_bc4f_35fd, lat: 0xbffc_1684_a152_574d, dist: 0x403c_fd56_729e_e71e,
            "Neptune 2050"
        )
        expectEcliptic(
            try CelestialBody.pluto.geocentricPosition(at: t).toEcliptic(),
            lon: 0x4075_2a6b_ff2c_a79d, lat: 0xc029_fa23_c6c6_359d, dist: 0x4044_fe55_caf2_ec61,
            "Pluto 2050"
        )
        expectEcliptic(
            try Moon.ecliptic(at: t),
            lon: 0x3fe0_09eb_91d0_faa4, lat: 0x400a_8967_f90b_4bbc, dist: 0x3f64_47ba_2615_afec,
            "Moon 2050"
        )
    }

    // MARK: - 2. Equatorial Positions (Geocentric & Topocentric)

    @Test("Geocentric equatorial (RA/Dec/dist, J2000) at 2026-07-24T00:00Z")
    func equatorialGeocentric2026() throws {
        let t = Self.t2026
        expectEquatorial(
            try CelestialBody.sun.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4020_65d1_56d7_8f5a, dec: 0x4033_fb72_64fc_81e7, dist: 0x3ff0_40cc_0033_3460,
            "Sun (geo) 2026"
        )
        expectEquatorial(
            try CelestialBody.moon.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x402f_6a02_93e2_3bd7, dec: 0xc039_0707_f55d_10b9, dist: 0x3f66_2012_8e80_7239,
            "Moon (geo) 2026"
        )
        expectEquatorial(
            try CelestialBody.mars.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4014_4e71_2596_ec73, dec: 0x4036_cfcc_ced7_41b1, dist: 0x4000_3ba0_4de2_953c,
            "Mars (geo) 2026"
        )
        expectEquatorial(
            try CelestialBody.jupiter.equatorial(at: t, from: .geocentric, equatorDate: .j2000),
            ra: 0x4020_f87f_7a11_1824, dec: 0x4033_82a2_fb08_fd07, dist: 0x4019_2fdd_02f7_6f19,
            "Jupiter (geo) 2026"
        )
    }

    @Test("Topocentric equatorial Moon from Asheville (J2000) at 2026-07-24T00:00Z")
    func equatorialTopocentric2026() throws {
        expectEquatorial(
            try CelestialBody.moon.equatorial(at: Self.t2026, from: Self.asheville, equatorDate: .j2000),
            ra: 0x402f_7217_4477_5a07, dec: 0xc039_ce7b_4cc1_0222, dist: 0x3f65_f783_2f9f_49ab,
            "Moon (topo Asheville) 2026"
        )
    }

    // MARK: - 3. Rise / Set Searches

    @Test("Sunrise and sunset search times from Asheville after 2026-07-24T00:00Z")
    func riseSet2026() throws {
        let sunrise = try #require(
            try CelestialBody.sun.riseTime(after: Self.t2026, from: Self.asheville)
        )
        #expect(
            sunrise.universalTime == Self.exact(0x40c2_f278_3d3f_d62f),
            "Sunrise UT drifted"
        )

        let sunset = try #require(
            try CelestialBody.sun.setTime(after: Self.t2026, from: Self.asheville)
        )
        #expect(
            sunset.universalTime == Self.exact(0x40c2_f243_a77e_541c),
            "Sunset UT drifted"
        )
    }

    // MARK: - 4. Moon Phase Search & Illumination

    @Test("Full-moon search time and phase-angle illumination")
    func moonPhaseAndIllumination() throws {
        let fullMoon = try #require(
            try Moon.searchPhase(.full, after: Self.t2026)
        )
        #expect(
            fullMoon.universalTime == Self.exact(0x40c2_f50d_e615_4cc1),
            "Full-moon search UT drifted"
        )

        // Illumination at a fixed 45° phase angle exercises ak_cos directly.
        #expect(
            Moon.illumination(for: 45.0) == Self.exact(0x3fc2_bec3_3301_8866),
            "Moon illumination at 45° drifted"
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
            lon: 0x405a_05b4_e327_e577, lat: 0xc043_cd71_c04e_7976, dist: 0x4120_9907_31c0_263a,
            "Sirius 2000"
        )
    }

    // MARK: - 6. Chiron (Gravity-Simulated, Within Bounds)

    @Test("Chiron ecliptic position at 2026-07-24T00:00Z (within 1900–2150 bounds)")
    func chironEcliptic2026() throws {
        expectEcliptic(
            try Chiron.ecliptic(at: Self.t2026),
            lon: 0x403e_e4e4_bfb0_03b2, lat: 0x3fce_bd63_6d4e_176f, dist: 0x4032_44d1_959c_c71d,
            "Chiron 2026"
        )
    }
}
