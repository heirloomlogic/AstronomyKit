import CLibAstronomy
import Foundation
import Testing

@Suite("Bundled ephemeris")
struct BundledEphemerisTests {
    @Test("Moon state reports the position at the requested instant exactly")
    func moonStatePositionIdentity() {
        for tt in [-36_524.5, -123.25, 0, 12_345.625, 47_846.5] {
            let time = Astronomy_TerrestrialTime(tt)
            let position = Astronomy_GeoMoon(time)
            let state = Astronomy_GeoMoonState(time)
            #expect(position.status == ASTRO_SUCCESS)
            #expect(state.status == ASTRO_SUCCESS)
            #expect(position.x.bitPattern == state.x.bitPattern)
            #expect(position.y.bitPattern == state.y.bitPattern)
            #expect(position.z.bitPattern == state.z.bitPattern)
        }
    }
}

extension BundledEphemerisTests {
    @Test("Chebyshev value and derivative agree across records with an exclusive end")
    func polynomialRecords() {
        let coefficients: [Double] = [
            1.5, 2, 0.5, 3, 4, 1, -1.5, -2, -0.5, 9.5, 6, 0.5, 19, 12, 1, -9.5, -6, -0.5,
        ]
        coefficients.withUnsafeBufferPointer { buffer in
            var table = astronomy_ephemeris_table_t(
                start_tdb: 0, step_days: 2, record_count: 2, coefficient_count: 3,
                coefficients: buffer.baseAddress)
            var p = [Double](repeating: .nan, count: 3)
            var v = p
            for t in [0.0, 0.5, 1, 2.nextDown, 2, 2.nextUp, 3, 4.nextDown] {
                #expect(Astronomy_EphemerisEvaluate(&table, t, &p, &v) == 1)
                for (axis, scale) in [1.0, 2, -1].enumerated() {
                    #expect(abs(p[axis] - scale * t * t) < 2e-14)
                    #expect(abs(v[axis] - 2 * scale * t) < 2e-14)
                }
            }
            for t in [-Double.leastNonzeroMagnitude, 4, .nan, .infinity, -.infinity] {
                #expect(Astronomy_EphemerisEvaluate(&table, t, &p, &v) == 0)
            }
        }
    }

    @Test("Exterior transition preserves full weight throughout the accuracy interval")
    func exteriorTransition() {
        var rate = Double.nan
        for t in [-36_524.5, (-36_524.5).nextUp, 0, 47_846.5.nextDown, 47_846.5] {
            #expect(Astronomy_EphemerisWeight(t, &rate) == 1)
            #expect(rate == 0)
        }
        for t in [-36_556.5, 47_878.5, -.infinity, .infinity, .nan] {
            #expect(Astronomy_EphemerisWeight(t, &rate) == 0)
            #expect(rate == 0)
        }
        for (t, sign) in [(-36_540.5, 1.0), (47_862.5, -1.0)] {
            #expect(Astronomy_EphemerisWeight(t, &rate) == 0.5)
            #expect(abs(rate - sign * 1.875 / 32) < 1e-15)
        }
    }

    @Test("Moon and Pluto public velocities differentiate positions at transition and data seams")
    func stateDerivatives() {
        let h = 1.0 / 256
        let epochs = [
            -36_556.5, -36_548.5, -36_540.5, -36_524.5, (-36_524.5).nextUp, -1, 0, 1, 47_846.5, 47_854.5,
            47_862.5, 47_878.5,
        ]
        for tt in epochs {
            for body in [BODY_MOON, BODY_PLUTO] {
                func position(_ t: Double) -> [Double] {
                    let time = Astronomy_TerrestrialTime(t)
                    let p = body == BODY_MOON ? Astronomy_GeoMoon(time) : Astronomy_HelioVector(body, time)
                    #expect(p.status == ASTRO_SUCCESS)
                    return [p.x, p.y, p.z]
                }
                let time = Astronomy_TerrestrialTime(tt)
                let s = body == BODY_MOON ? Astronomy_GeoMoonState(time) : Astronomy_HelioState(body, time)
                #expect(s.status == ASTRO_SUCCESS)
                let a = position(tt - 2 * h)
                let b = position(tt - h)
                let c = position(tt + h)
                let d = position(tt + 2 * h)
                let velocity = [s.vx, s.vy, s.vz]
                for axis in 0..<3 {
                    let difference = (a[axis] - 8 * b[axis] + 8 * c[axis] - d[axis]) / (12 * h)
                    #expect(
                        abs(velocity[axis] - difference) < 2e-9, "body \(body.rawValue), tt \(tt), axis \(axis)"
                    )
                }
            }
        }
    }
}

extension BundledEphemerisTests {
    @Test("Public lunar apsis and node searches retain the independent event direction and minute target")
    func lunarEventRegression() {
        // Lunar perigee and ascending node of 1903 July (TT), located from geometric
        // geocentric JPL Horizons DE441 Moon states; the node uses the IAU 2006 mean
        // ecliptic of date.
        let pericenter = 2_416_319.984182304 - 2_451_545.0
        let ascending = 2_416_324.69497546 - 2_451_545.0
        let apsis = Astronomy_SearchLunarApsis(Astronomy_TerrestrialTime(pericenter - 3))
        #expect(apsis.status == ASTRO_SUCCESS)
        #expect(apsis.kind == APSIS_PERICENTER)
        #expect(abs(apsis.time.tt - pericenter) * 86_400 < 60)
        let node = Astronomy_SearchMoonNode(Astronomy_TerrestrialTime(ascending - 3))
        #expect(node.status == ASTRO_SUCCESS)
        #expect(node.kind == ASCENDING_NODE)
        #expect(abs(node.time.tt - ascending) * 86_400 < 60)
    }

    @Test("Bundled Moon and Pluto concurrent first calls match serial state bits")
    func concurrentStates() async {
        func bits(_ tt: Double) -> [UInt64] {
            let time = Astronomy_TerrestrialTime(tt)
            let moon = Astronomy_GeoMoonState(time)
            let pluto = Astronomy_HelioState(BODY_PLUTO, time)
            return [
                moon.x, moon.y, moon.z, moon.vx, moon.vy, moon.vz, pluto.x, pluto.y, pluto.z, pluto.vx, pluto.vy,
                pluto.vz,
            ].map(\.bitPattern)
        }
        let epochs = [-36_524.5, -3.875, 11_237.625, 47_846.5]
        let expected = epochs.map(bits)
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let slot = index % epochs.count
                    return bits(epochs[slot]) == expected[slot]
                }
            }
            for await agrees in group { #expect(agrees) }
        }
    }
}

extension BundledEphemerisTests {
    @Test("Moon and Pluto positions retain the legacy model beyond the exterior transition")
    func legacyPositionsOutsideBundle() {
        // Captured from ec134360 astronomy.c with clang -O2 -ffp-contract=off,
        // before the bundled integration. These epochs are outside either buffer.
        let rows: [(Double, [Double])] = [
            (
                -60_000,
                [
                    -0.002368351709875051, -0.00061267342080559924, -8.6948868382327168e-05, 43.606220622631845,
                    17.092899513190233, -7.8028764312531846,
                ]
            ),
            (
                -40_000,
                [
                    -0.0024870500445998843, -0.00078685466403433644, -9.7917391735911522e-05, 17.621398712643295,
                    43.941347184028977, 8.4005099928470131,
                ]
            ),
            (
                60_000,
                [
                    -0.0013708086225745735, -0.0019658731385987561, -0.00065941714241063583, -2.8919927829140066,
                    41.912977122107002, 13.953274495467248,
                ]
            ),
        ]
        for (tt, expected) in rows {
            let time = Astronomy_TerrestrialTime(tt)
            let moon = Astronomy_GeoMoon(time)
            let pluto = Astronomy_HelioVector(BODY_PLUTO, time)
            #expect(moon.status == ASTRO_SUCCESS)
            #expect(pluto.status == ASTRO_SUCCESS)
            for (actual, reference) in zip([moon.x, moon.y, moon.z, pluto.x, pluto.y, pluto.z], expected) {
                #expect(abs(actual - reference) <= max(1e-12, abs(reference) * 1e-12))
            }
        }
    }
}
