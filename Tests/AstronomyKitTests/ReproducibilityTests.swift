// Numerical regression fixtures shared by Apple and Linux.
// Expected values are frozen reference bit patterns; comparisons allow
// native-libm rounding differences within tight budgets.
// These tight regression budgets are not absolute astronomical accuracy claims.
// Independent JPL/Audit and event references remain unchanged.

import Testing

@testable import AstronomyKit

@Suite("Numerical regression (platform-native math)")
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

    /// Rejects nonfinite results and compares periodic quantities across wraparound.
    private func close(_ actual: Double, _ expected: Double, tolerance: Double, period: Double? = nil) -> Bool {
        guard actual.isFinite, expected.isFinite else { return false }
        var difference = actual - expected
        if let period {
            difference = difference.remainder(dividingBy: period)
        }
        return abs(difference) <= tolerance
    }

    private func closeDistance(_ actual: Double, _ pattern: UInt64) -> Bool {
        let expected = Self.exact(pattern)
        return close(actual, expected, tolerance: max(1e-12, abs(expected) * 1e-12))
    }

    /// Compares ecliptic angles in degrees and distances in AU.
    private func expectEcliptic(
        _ ecliptic: Ecliptic,
        lon: UInt64,
        lat: UInt64,
        dist: UInt64,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            close(ecliptic.longitude, Self.exact(lon), tolerance: 1e-8, period: 360),
            "\(label): ecliptic longitude drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            close(ecliptic.latitude, Self.exact(lat), tolerance: 1e-8),
            "\(label): ecliptic latitude drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            closeDistance(ecliptic.distance, dist),
            "\(label): ecliptic distance drifted",
            sourceLocation: sourceLocation
        )
    }

    /// Compares right ascension in hours, declination in degrees, and distance in AU.
    private func expectEquatorial(
        _ equatorial: Equatorial,
        ra: UInt64,
        dec: UInt64,
        dist: UInt64,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            close(equatorial.rightAscension, Self.exact(ra), tolerance: 1e-8 / 15, period: 24),
            "\(label): right ascension drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            close(equatorial.declination, Self.exact(dec), tolerance: 1e-8),
            "\(label): declination drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            closeDistance(equatorial.distance, dist),
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
            close(sunrise.universalTime, Self.exact(0x40c2_f278_3d3f_d62f), tolerance: 0.01 / 86_400),
            "Sunrise UT drifted"
        )

        let sunset = try #require(
            try CelestialBody.sun.setTime(after: Self.t2026, from: Self.asheville)
        )
        #expect(
            close(sunset.universalTime, Self.exact(0x40c2_f243_a77e_541c), tolerance: 0.01 / 86_400),
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
            close(fullMoon.universalTime, Self.exact(0x40c2_f50d_e615_4cc1), tolerance: 0.01 / 86_400),
            "Full-moon search UT drifted"
        )

        // Illumination at a fixed 45° phase angle exercises the Swift-side cosine directly.
        #expect(
            close(Moon.illumination(for: 45.0), Self.exact(0x3fc2_bec3_3301_8866), tolerance: 1e-14),
            "Moon illumination at 45° drifted"
        )
    }

    // MARK: - 5. FixedStar Ecliptic Conversion

    /// Exercises the FixedStar ecliptic path (Swift-side atan2 / asin) end to end.
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

    // MARK: - 7. Geocentric Ecliptic Rates

    /// Compares ecliptic rates in degrees per day and AU per day. The Moon's rates
    /// come from a central difference of the lunar series inside the engine and
    /// carry that stencil's platform noise, so they get a wider budget.
    private func expectEclipticRates(
        _ state: EclipticState,
        lonRate: UInt64,
        latRate: UInt64,
        distRate: UInt64,
        _ label: String,
        moon: Bool = false,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let angleTolerance = moon ? 5e-7 : 1e-9
        let distanceTolerance = moon ? 1e-10 : 1e-12
        #expect(
            close(state.longitudeRate, Self.exact(lonRate), tolerance: angleTolerance),
            "\(label): longitude rate drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            close(state.latitudeRate, Self.exact(latRate), tolerance: angleTolerance),
            "\(label): latitude rate drifted",
            sourceLocation: sourceLocation
        )
        #expect(
            close(state.distanceRate, Self.exact(distRate), tolerance: distanceTolerance),
            "\(label): distance rate drifted",
            sourceLocation: sourceLocation
        )
    }

    @Test("Geocentric ecliptic rates at 1980-03-20T12:00Z")
    func eclipticRates1980() throws {
        let t = Self.t1980
        expectEclipticRates(
            try CelestialBody.sun.geocentricEclipticState(at: t),
            lonRate: 0x3fef_caca_3ed2_750c, latRate: 0xbedb_c838_b73b_198e, distRate: 0x3f32_1522_ce5d_f67a,
            "Sun 1980"
        )
        expectEclipticRates(
            try CelestialBody.moon.geocentricEclipticState(at: t),
            lonRate: 0x402c_abd6_e5ce_c5ee, latRate: 0xbfc4_6b93_5c96_43a2, distRate: 0x3f03_9b80_3865_64a1,
            "Moon 1980",
            moon: true
        )
        expectEclipticRates(
            try CelestialBody.mercury.geocentricEclipticState(at: t),
            lonRate: 0x3fb6_d999_8b14_9a8f, latRate: 0xbfce_ba52_45be_0c0b, distRate: 0x3f89_0231_0a81_e718,
            "Mercury 1980"
        )
        expectEclipticRates(
            try CelestialBody.venus.geocentricEclipticState(at: t),
            lonRate: 0x3ff1_3804_c4a7_cef7, latRate: 0x3fb3_279f_42a5_d56c, distRate: 0xbf7e_e7fd_9a3b_d5f6,
            "Venus 1980"
        )
        expectEclipticRates(
            try CelestialBody.mars.geocentricEclipticState(at: t),
            lonRate: 0xbfcb_bf85_f2c0_4a3e, latRate: 0xbfa3_f1c5_639c_6592, distRate: 0x3f73_3320_6bf3_62fe,
            "Mars 1980"
        )
        expectEclipticRates(
            try CelestialBody.jupiter.geocentricEclipticState(at: t),
            lonRate: 0xbfba_9c56_94df_e21f, latRate: 0xbf4f_6013_7b69_2a5b, distRate: 0x3f7e_4467_c9fc_2411,
            "Jupiter 1980"
        )
        expectEclipticRates(
            try CelestialBody.saturn.geocentricEclipticState(at: t),
            lonRate: 0xbfb4_0c84_a367_05cc, latRate: 0x3f34_ead7_0c6c_b954, distRate: 0x3f60_88d7_f291_5759,
            "Saturn 1980"
        )
        expectEclipticRates(
            try CelestialBody.uranus.geocentricEclipticState(at: t),
            lonRate: 0xbf91_ed92_823f_52f7, latRate: 0x3f10_d8ce_a5aa_6fbb, distRate: 0xbf8c_bf76_313e_3cbd,
            "Uranus 1980"
        )
        expectEclipticRates(
            try CelestialBody.neptune.geocentricEclipticState(at: t),
            lonRate: 0x3f63_4b70_25d0_b13c, latRate: 0x3f45_c532_ff32_922c, distRate: 0xbf91_7c02_82ae_c475,
            "Neptune 1980"
        )
        expectEclipticRates(
            try CelestialBody.pluto.geocentricEclipticState(at: t),
            lonRate: 0xbf9a_55b8_e7d9_af59, latRate: 0x3f6f_4046_383d_f5d3, distRate: 0xbf7a_3a08_10bf_e6d6,
            "Pluto 1980"
        )
        expectEclipticRates(
            try Sun.eclipticState(at: t),
            lonRate: 0x3fef_cacd_70b1_2a17, latRate: 0xbedb_c87f_47db_62d9, distRate: 0x3f32_1524_adec_5fc1,
            "Sun.eclipticState 1980"
        )
        expectEclipticRates(
            try Moon.eclipticState(at: t),
            lonRate: 0x402c_abd6_e5ce_c5ee, latRate: 0xbfc4_6b93_5c96_43be, distRate: 0x3f03_9b80_358b_ec00,
            "Moon.eclipticState 1980",
            moon: true
        )
    }

    @Test("Geocentric ecliptic rates at 2000-01-01T00:00Z")
    func eclipticRates2000() throws {
        let t = Self.t2000
        expectEclipticRates(
            try CelestialBody.sun.geocentricEclipticState(at: t),
            lonRate: 0x3ff0_4f63_f625_53d0, latRate: 0xbec3_3b9a_bddc_58a6, distRate: 0xbee4_2626_fb8a_1c84,
            "Sun 2000"
        )
        expectEclipticRates(
            try CelestialBody.moon.geocentricEclipticState(at: t),
            lonRate: 0x4028_34d9_c073_528b, latRate: 0xbfb0_4c15_f8dd_a24f, distRate: 0x3ef7_18ec_11b5_771c,
            "Moon 2000",
            moon: true
        )
        expectEclipticRates(
            try CelestialBody.mercury.geocentricEclipticState(at: t),
            lonRate: 0x3ff8_dbad_dcbf_f535, latRate: 0xbfb9_5b60_172b_5ff5, distRate: 0x3f74_077c_0869_b977,
            "Mercury 2000"
        )
        expectEclipticRates(
            try CelestialBody.venus.geocentricEclipticState(at: t),
            lonRate: 0x3ff3_55e0_d871_f6d4, latRate: 0xbf9c_18d7_2615_478d, distRate: 0x3f7a_9e09_5746_596c,
            "Venus 2000"
        )
        expectEclipticRates(
            try CelestialBody.mars.geocentricEclipticState(at: t),
            lonRate: 0x3fe8_d22f_33e1_654d, latRate: 0x3f89_8040_46cf_2382, distRate: 0x3f76_34b8_54ed_ddbe,
            "Mars 2000"
        )
        expectEclipticRates(
            try CelestialBody.jupiter.geocentricEclipticState(at: t),
            lonRate: 0x3fa4_00e9_d9ed_bcb1, latRate: 0x3f75_3aac_ae6e_e501, distRate: 0x3f8f_b5ca_4472_cd11,
            "Jupiter 2000"
        )
        expectEclipticRates(
            try CelestialBody.saturn.geocentricEclipticState(at: t),
            lonRate: 0xbf95_5bc0_197d_2c9f, latRate: 0x3f73_6349_ec63_ae52, distRate: 0x3f8d_49fc_429e_907d,
            "Saturn 2000"
        )
        expectEclipticRates(
            try CelestialBody.uranus.geocentricEclipticState(at: t),
            lonRate: 0x3fa9_a945_79fa_4a52, latRate: 0x3f30_5efd_72c9_db94, distRate: 0x3f84_884e_5e8d_436c,
            "Uranus 2000"
        )
        expectEclipticRates(
            try CelestialBody.neptune.geocentricEclipticState(at: t),
            lonRate: 0x3fa2_27da_2d7f_b3ff, latRate: 0xbf2e_19af_a012_3a5b, distRate: 0x3f7c_36b1_2bc5_4cf9,
            "Neptune 2000"
        )
        expectEclipticRates(
            try CelestialBody.pluto.geocentricEclipticState(at: t),
            lonRate: 0x3fa2_0fac_7cf9_2933, latRate: 0x3f57_35a3_4531_a28b, distRate: 0xbf7f_e768_edbd_3f78,
            "Pluto 2000"
        )
        expectEclipticRates(
            try Sun.eclipticState(at: t),
            lonRate: 0x3ff0_4f63_d721_796c, latRate: 0xbec3_39f0_38c9_71c7, distRate: 0xbee4_2662_a279_9024,
            "Sun.eclipticState 2000"
        )
        expectEclipticRates(
            try Moon.eclipticState(at: t),
            lonRate: 0x4028_34d9_c073_5289, latRate: 0xbfb0_4c15_f8dd_a247, distRate: 0x3ef7_18ec_1009_c000,
            "Moon.eclipticState 2000",
            moon: true
        )
    }

    @Test("Geocentric ecliptic rates at 2026-07-24T00:00Z")
    func eclipticRates2026() throws {
        let t = Self.t2026
        expectEclipticRates(
            try CelestialBody.sun.geocentricEclipticState(at: t),
            lonRate: 0x3fee_8e80_fbf7_1452, latRate: 0xbeaf_33ab_a495_2bea, distRate: 0xbf18_5f28_4b97_d3f7,
            "Sun 2026"
        )
        expectEclipticRates(
            try CelestialBody.moon.geocentricEclipticState(at: t),
            lonRate: 0x4027_d8bc_7c3d_b0c7, latRate: 0xbf8d_6eef_5a6b_b91f, distRate: 0x3ee9_621d_e550_637b,
            "Moon 2026",
            moon: true
        )
        expectEclipticRates(
            try CelestialBody.mercury.geocentricEclipticState(at: t),
            lonRate: 0x3f70_b9be_79df_c4f8, latRate: 0x3fc8_c469_64c9_e433, distRate: 0x3f91_0c83_76f6_3340,
            "Mercury 2026"
        )
        expectEclipticRates(
            try CelestialBody.venus.geocentricEclipticState(at: t),
            lonRate: 0x3ff1_22bd_3147_0507, latRate: 0xbfb2_5762_c0be_7479, distRate: 0xbf80_4bfa_c25c_1a57,
            "Venus 2026"
        )
        expectEclipticRates(
            try CelestialBody.mars.geocentricEclipticState(at: t),
            lonRate: 0x3fe5_ed1a_a492_a7ea, latRate: 0x3f8a_c632_297a_024e, distRate: 0xbf6e_fb7e_a706_4f4f,
            "Mars 2026"
        )
        expectEclipticRates(
            try CelestialBody.jupiter.geocentricEclipticState(at: t),
            lonRate: 0x3fcc_5403_6a48_10fc, latRate: 0x3f55_9b24_d109_6c01, distRate: 0x3f56_1458_d2b3_34ed,
            "Jupiter 2026"
        )
        expectEclipticRates(
            try CelestialBody.saturn.geocentricEclipticState(at: t),
            lonRate: 0x3f73_b779_c1e3_5f81, latRate: 0xbf73_1f3b_784c_dae5, distRate: 0xbf90_4fe1_ba63_0f97,
            "Saturn 2026"
        )
        expectEclipticRates(
            try CelestialBody.uranus.geocentricEclipticState(at: t),
            lonRate: 0x3fa3_6267_8af9_5d52, latRate: 0x3f04_43d8_4e8c_b774, distRate: 0xbf8c_fa9f_3747_1640,
            "Uranus 2026"
        )
        expectEclipticRates(
            try CelestialBody.neptune.geocentricEclipticState(at: t),
            lonRate: 0xbf81_e9b9_d926_f1c4, latRate: 0xbf4b_1ded_62ef_5f5e, distRate: 0xbf8e_c022_293b_c243,
            "Neptune 2026"
        )
        expectEclipticRates(
            try CelestialBody.pluto.geocentricEclipticState(at: t),
            lonRate: 0xbf97_eea6_51e2_d452, latRate: 0xbf58_b942_8a14_5396, distRate: 0xbf2b_9337_758b_ff50,
            "Pluto 2026"
        )
        expectEclipticRates(
            try Sun.eclipticState(at: t),
            lonRate: 0x3fee_8e7f_d113_e993, latRate: 0xbeaf_2d71_7e31_697b, distRate: 0xbf18_5f2d_a0d8_33fa,
            "Sun.eclipticState 2026"
        )
        expectEclipticRates(
            try Moon.eclipticState(at: t),
            lonRate: 0x4027_d8bc_7c3d_b0c8, latRate: 0xbf8d_6eef_5a6b_ba53, distRate: 0x3ee9_621d_e3e5_2000,
            "Moon.eclipticState 2026",
            moon: true
        )
    }

    @Test("Geocentric ecliptic rates at 2050-12-21T06:00Z")
    func eclipticRates2050() throws {
        let t = Self.t2050
        expectEclipticRates(
            try CelestialBody.sun.geocentricEclipticState(at: t),
            lonRate: 0x3ff0_4a74_18f2_0e17, latRate: 0xbeff_31f7_965f_8da1, distRate: 0xbf14_7c66_6379_36c5,
            "Sun 2050"
        )
        expectEclipticRates(
            try CelestialBody.moon.geocentricEclipticState(at: t),
            lonRate: 0x402c_3d4e_99d9_a43d, latRate: 0xbfef_04d1_3f09_a25b, distRate: 0x3ebc_2f6d_9e7b_399e,
            "Moon 2050",
            moon: true
        )
        expectEclipticRates(
            try CelestialBody.mercury.geocentricEclipticState(at: t),
            lonRate: 0xbfa3_6b85_da3e_6de4, latRate: 0xbf9c_1d30_3fe7_a17d, distRate: 0x3f95_9207_fba2_9ba8,
            "Mercury 2050"
        )
        expectEclipticRates(
            try CelestialBody.venus.geocentricEclipticState(at: t),
            lonRate: 0x3fef_12de_9d84_9f6c, latRate: 0x3f9f_b225_1ed4_3ea7, distRate: 0x3f7e_f39d_9b24_97e9,
            "Venus 2050"
        )
        expectEclipticRates(
            try CelestialBody.mars.geocentricEclipticState(at: t),
            lonRate: 0x3fe4_1364_308c_df39, latRate: 0x3f9b_d37f_7d0c_84b2, distRate: 0x3f81_5e61_52f8_62fb,
            "Mars 2050"
        )
        expectEclipticRates(
            try CelestialBody.jupiter.geocentricEclipticState(at: t),
            lonRate: 0x3f50_26c9_7e03_6e55, latRate: 0x3f72_1bc4_d222_ea89, distRate: 0xbf8d_a463_cb64_fe3c,
            "Jupiter 2050"
        )
        expectEclipticRates(
            try CelestialBody.saturn.geocentricEclipticState(at: t),
            lonRate: 0x3fba_77e9_b893_a3c8, latRate: 0xbf43_539d_10d8_159d, distRate: 0x3f84_76a8_2b63_d03a,
            "Saturn 2050"
        )
        expectEclipticRates(
            try CelestialBody.uranus.geocentricEclipticState(at: t),
            lonRate: 0x3f82_5be4_8fe8_0a33, latRate: 0x3f46_fb7f_ea50_410b, distRate: 0xbf91_9f73_a918_b9d8,
            "Uranus 2050"
        )
        expectEclipticRates(
            try CelestialBody.neptune.geocentricEclipticState(at: t),
            lonRate: 0xbf97_13bd_729e_8f9f, latRate: 0x3f44_a06e_f66f_2f65, distRate: 0x3f83_a5c0_ede9_ee3a,
            "Neptune 2050"
        )
        expectEclipticRates(
            try CelestialBody.pluto.geocentricEclipticState(at: t),
            lonRate: 0x3f89_0952_68dc_6602, latRate: 0x3f71_b6a1_1ae6_e856, distRate: 0x3f90_e199_108e_7e6f,
            "Pluto 2050"
        )
        expectEclipticRates(
            try Sun.eclipticState(at: t),
            lonRate: 0x3ff0_4a73_98ca_b12f, latRate: 0xbeff_31cf_d804_d70e, distRate: 0xbf14_7c6d_c10a_d293,
            "Sun.eclipticState 2050"
        )
        expectEclipticRates(
            try Moon.eclipticState(at: t),
            lonRate: 0x402c_3d4e_99d9_a43d, latRate: 0xbfef_04d1_3f09_a25b, distRate: 0x3ebc_2f6d_9b31_c000,
            "Moon.eclipticState 2050",
            moon: true
        )
    }
}
