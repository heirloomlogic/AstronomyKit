// Contract tests for the apparent geocentric ecliptic state API:
// positions bit-identical to the position functions each state mirrors,
// rates equal to the derivative of those positions.

import CLibAstronomy
import Testing

@testable import AstronomyKit

@Suite("Ecliptic state")
struct EclipticStateTests {
    static let stateBodies: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    /// Evenly spaced TT instants across the polynomial coverage (1900 through 2100),
    /// snapped to multiples of 1/1024 day so that stencil offsets of 1/64 and 1/32 day
    /// are exact in binary. Off-grid offsets at |tt| ≈ 3e4 days are quantized at
    /// 4e-12 day, a 4e-10 relative error in the stencil width that a finite
    /// difference cannot distinguish from a rate error.
    static func grid(count: Int, from start: Double = -36_524.5, to end: Double = 36_889.5) -> [Double] {
        (0..<count).map { index -> Double in
            let fraction = (Double(index) + 0.5) / Double(count)
            let value = start + (end - start) * fraction
            return (value * 1_024).rounded() / 1_024
        }
    }

    /// Stencil half-widths that are exact binary fractions of a day.
    static let narrowStep = 1.0 / 64
    static let wideStep = 1.0 / 32

    /// Central five-point derivative of a periodic-safe scalar sampled in TT.
    static func fivePoint(_ f: (Double) throws -> Double, at tt: Double, step h: Double) rethrows -> Double {
        let f2p = try f(tt + 2 * h)
        let f1p = try f(tt + h)
        let f1m = try f(tt - h)
        let f2m = try f(tt - 2 * h)
        return (-f2p + 8 * f1p - 8 * f1m + f2m) / (12 * h)
    }

    /// Unwraps a longitude difference across the 0/360 seam.
    static func unwrap(_ degrees: Double, near reference: Double) -> Double {
        reference + (degrees - reference).remainder(dividingBy: 360)
    }

    // MARK: - 1. Position bit identity

    @Test(
        "geocentricEclipticState matches geocentricPosition().toEcliptic() bit for bit",
        arguments: [Aberration.corrected, .none])
    func geocentricIdentity(aberration: Aberration) throws {
        let instants = Self.grid(count: 1_000) + [-55_000, -40_000, 40_000, 55_000]
        for tt in instants {
            let time = AstroTime(tt: tt)
            for body in Self.stateBodies {
                let expected = try body.geocentricPosition(at: time, aberration: aberration).toEcliptic()
                let state = try body.geocentricEclipticState(at: time, aberration: aberration)
                #expect(state.longitude.bitPattern == expected.longitude.bitPattern, "\(body) longitude at tt \(tt)")
                #expect(state.latitude.bitPattern == expected.latitude.bitPattern, "\(body) latitude at tt \(tt)")
                #expect(state.distance.bitPattern == expected.distance.bitPattern, "\(body) distance at tt \(tt)")
                #expect(state.time == time)
            }
        }
    }

    @Test("Sun.eclipticState matches Sun.position bit for bit")
    func sunIdentity() throws {
        for tt in Self.grid(count: 2_000) + [-55_000, 55_000] {
            let time = AstroTime(tt: tt)
            let expected = try Sun.position(at: time)
            let state = try Sun.eclipticState(at: time)
            #expect(state.longitude.bitPattern == expected.longitude.bitPattern, "longitude at tt \(tt)")
            #expect(state.latitude.bitPattern == expected.latitude.bitPattern, "latitude at tt \(tt)")
            #expect(state.distance.bitPattern == expected.distance.bitPattern, "distance at tt \(tt)")
        }
    }

    @Test("Moon.eclipticState matches Moon.ecliptic bit for bit")
    func moonIdentity() throws {
        for tt in Self.grid(count: 2_000) + [-55_000, 55_000] {
            let time = AstroTime(tt: tt)
            let expected = try Moon.ecliptic(at: time)
            let state = try Moon.eclipticState(at: time)
            #expect(state.longitude.bitPattern == expected.longitude.bitPattern, "longitude at tt \(tt)")
            #expect(state.latitude.bitPattern == expected.latitude.bitPattern, "latitude at tt \(tt)")
            #expect(state.distance.bitPattern == expected.distance.bitPattern, "distance at tt \(tt)")
        }
    }

    @Test(
        "Unsupported bodies throw invalidBody",
        arguments: [CelestialBody.earth, .earthMoonBarycenter, .solarSystemBarycenter, .io])
    func unsupportedBodies(body: CelestialBody) {
        #expect(throws: AstronomyError.invalidBody) {
            try body.geocentricEclipticState(at: AstroTime(tt: 0))
        }
    }

    // MARK: - 2. Rates against finite differences of the position path

    struct RateBudget {
        let longitude: Double
        let latitude: Double
        let distance: Double
    }

    /// Budgets are set by the reference, not the state: the position path stops its
    /// light-time iteration at a 1e-9 day residual, so a stencil that straddles an
    /// iteration-count switch sees a step of up to 1e-9 d × velocity, amplified by
    /// 8/(12h) ≈ 67/day. For the outer planets that is ~1.3e-9 AU/day in distance.
    static func budget(for body: CelestialBody) -> RateBudget {
        switch body {
        case .moon: RateBudget(longitude: 5e-7, latitude: 5e-7, distance: 1e-9)
        case .pluto: RateBudget(longitude: 1e-6, latitude: 1e-6, distance: 2e-9)
        default: RateBudget(longitude: 5e-8, latitude: 5e-8, distance: 2e-9)
        }
    }

    /// Tight budgets for instants where two stencil widths agree, which rules out a
    /// straddled light-time switch in the reference.
    static func tightBudget(for body: CelestialBody) -> RateBudget {
        switch body {
        case .moon: RateBudget(longitude: 5e-7, latitude: 5e-7, distance: 1e-9)
        case .pluto: RateBudget(longitude: 2e-9, latitude: 2e-9, distance: 1e-11)
        default: RateBudget(longitude: 2e-9, latitude: 2e-9, distance: 1e-11)
        }
    }

    @Test(
        "Rates equal the five-point derivative of geocentricPosition().toEcliptic()",
        arguments: [Aberration.corrected, .none])
    func geocentricRates(aberration: Aberration) throws {
        let h = Self.narrowStep
        for body in Self.stateBodies {
            let budget = Self.budget(for: body)
            var worst = (longitude: 0.0, latitude: 0.0, distance: 0.0)
            for tt in Self.grid(count: 200, from: -36_000, to: 36_500) {
                let time = AstroTime(tt: tt)
                let state = try body.geocentricEclipticState(at: time, aberration: aberration)
                func ecliptic(_ t: Double) throws -> Ecliptic {
                    try body.geocentricPosition(at: AstroTime(tt: t), aberration: aberration).toEcliptic()
                }
                let lonRate = try Self.fivePoint(
                    { Self.unwrap(try ecliptic($0).longitude, near: state.longitude) }, at: tt, step: h)
                let latRate = try Self.fivePoint({ try ecliptic($0).latitude }, at: tt, step: h)
                let distRate = try Self.fivePoint({ try ecliptic($0).distance }, at: tt, step: h)
                worst.longitude = max(worst.longitude, abs(lonRate - state.longitudeRate))
                worst.latitude = max(worst.latitude, abs(latRate - state.latitudeRate))
                worst.distance = max(worst.distance, abs(distRate - state.distanceRate))
            }
            #expect(worst.longitude <= budget.longitude, "\(body) longitude rate: worst \(worst.longitude) deg/day")
            #expect(worst.latitude <= budget.latitude, "\(body) latitude rate: worst \(worst.latitude) deg/day")
            #expect(worst.distance <= budget.distance, "\(body) distance rate: worst \(worst.distance) AU/day")
        }
    }

    @Test("Rates match tight budgets where the reference stencil is clean", arguments: [Aberration.corrected, .none])
    func geocentricRatesTight(aberration: Aberration) throws {
        for body in Self.stateBodies {
            let budget = Self.tightBudget(for: body)
            var clean = 0
            var worst = (longitude: 0.0, latitude: 0.0, distance: 0.0)
            let instants = Self.grid(count: 200, from: -36_000, to: 36_500)
            for tt in instants {
                let state = try body.geocentricEclipticState(at: AstroTime(tt: tt), aberration: aberration)
                func ecliptic(_ t: Double) throws -> Ecliptic {
                    try body.geocentricPosition(at: AstroTime(tt: t), aberration: aberration).toEcliptic()
                }
                func rates(step h: Double) throws -> (Double, Double, Double) {
                    (
                        try Self.fivePoint(
                            { Self.unwrap(try ecliptic($0).longitude, near: state.longitude) }, at: tt, step: h),
                        try Self.fivePoint({ try ecliptic($0).latitude }, at: tt, step: h),
                        try Self.fivePoint({ try ecliptic($0).distance }, at: tt, step: h)
                    )
                }
                let narrow = try rates(step: Self.narrowStep)
                let wide = try rates(step: Self.wideStep)
                guard abs(narrow.0 - wide.0) < budget.longitude / 2,
                    abs(narrow.1 - wide.1) < budget.latitude / 2,
                    abs(narrow.2 - wide.2) < budget.distance / 2
                else { continue }
                clean += 1
                worst.longitude = max(worst.longitude, abs(narrow.0 - state.longitudeRate))
                worst.latitude = max(worst.latitude, abs(narrow.1 - state.latitudeRate))
                worst.distance = max(worst.distance, abs(narrow.2 - state.distanceRate))
            }
            #expect(clean >= instants.count / 2, "\(body): only \(clean) clean instants of \(instants.count)")
            #expect(
                worst.longitude <= budget.longitude,
                "\(body) longitude rate: worst \(worst.longitude) deg/day over \(clean) instants")
            #expect(worst.latitude <= budget.latitude, "\(body) latitude rate: worst \(worst.latitude) deg/day")
            #expect(worst.distance <= budget.distance, "\(body) distance rate: worst \(worst.distance) AU/day")
        }
    }

    @Test("Sun rates equal the five-point derivative of Sun.position")
    func sunRates() throws {
        var worst = 0.0
        for tt in Self.grid(count: 300, from: -36_000, to: 36_500) {
            let state = try Sun.eclipticState(at: AstroTime(tt: tt))
            let lonRate = try Self.fivePoint(
                { Self.unwrap(try Sun.position(at: AstroTime(tt: $0)).longitude, near: state.longitude) }, at: tt,
                step: Self.narrowStep)
            let latRate = try Self.fivePoint(
                { try Sun.position(at: AstroTime(tt: $0)).latitude }, at: tt, step: Self.narrowStep)
            let distRate = try Self.fivePoint(
                { try Sun.position(at: AstroTime(tt: $0)).distance }, at: tt, step: Self.narrowStep)
            let lonError = abs(lonRate - state.longitudeRate)
            let latError = abs(latRate - state.latitudeRate)
            let distError = abs(distRate - state.distanceRate) * 1e3
            worst = max(worst, lonError, latError, distError)
        }
        #expect(worst <= 5e-8, "worst \(worst)")
    }

    @Test("Moon rates equal the five-point derivative of Moon.ecliptic")
    func moonRates() throws {
        var worst = (longitude: 0.0, latitude: 0.0, distance: 0.0)
        for tt in Self.grid(count: 300, from: -36_000, to: 36_500) {
            let state = try Moon.eclipticState(at: AstroTime(tt: tt))
            let lonRate = try Self.fivePoint(
                { Self.unwrap(try Moon.ecliptic(at: AstroTime(tt: $0)).longitude, near: state.longitude) }, at: tt,
                step: Self.narrowStep)
            let latRate = try Self.fivePoint(
                { try Moon.ecliptic(at: AstroTime(tt: $0)).latitude }, at: tt, step: Self.narrowStep)
            let distRate = try Self.fivePoint(
                { try Moon.ecliptic(at: AstroTime(tt: $0)).distance }, at: tt, step: Self.narrowStep)
            worst.longitude = max(worst.longitude, abs(lonRate - state.longitudeRate))
            worst.latitude = max(worst.latitude, abs(latRate - state.latitudeRate))
            worst.distance = max(worst.distance, abs(distRate - state.distanceRate))
        }
        #expect(worst.longitude <= 5e-7, "longitude worst \(worst.longitude)")
        #expect(worst.latitude <= 5e-7, "latitude worst \(worst.latitude)")
        #expect(worst.distance <= 1e-9, "distance worst \(worst.distance)")
    }

    // MARK: - 3. Frame rotation rate

    @Test("Analytic EQJ→ECT rotation rate matches the differenced rotation matrix")
    func frameRate() throws {
        let h = Self.narrowStep
        var worst = 0.0
        for tt in Self.grid(count: 60, from: -40_000, to: 40_000) {
            for axis in 0..<3 {
                var basis = [0.0, 0.0, 0.0]
                basis[axis] = 1
                let zero = [0.0, 0.0, 0.0]
                let state = _Astronomy_EclipticStateFromEqj(basis, zero, AstroTime(tt: tt).raw)
                #expect(state.status == ASTRO_SUCCESS)

                func column(_ t: Double) -> [Double] {
                    var raw = AstroTime(tt: t).raw
                    let rot = Astronomy_Rotation_EQJ_ECT(&raw)
                    let vector = astro_vector_t(status: ASTRO_SUCCESS, x: basis[0], y: basis[1], z: basis[2], t: raw)
                    let rotated = Astronomy_RotateVector(rot, vector)
                    return [rotated.x, rotated.y, rotated.z]
                }
                let plus2 = column(tt + 2 * h)
                let plus1 = column(tt + h)
                let minus1 = column(tt - h)
                let minus2 = column(tt - 2 * h)
                var expected = [0.0, 0.0, 0.0]
                for k in 0..<3 {
                    let numerator = -plus2[k] + 8 * plus1[k] - 8 * minus1[k] + minus2[k]
                    expected[k] = numerator / (12 * h)
                }
                let actual = [state.vx, state.vy, state.vz]
                let here = column(tt)
                #expect(here[0].bitPattern == state.x.bitPattern)
                #expect(here[1].bitPattern == state.y.bitPattern)
                #expect(here[2].bitPattern == state.z.bitPattern)
                for k in 0..<3 {
                    worst = max(worst, abs(expected[k] - actual[k]))
                }
            }
        }
        #expect(worst <= 1e-12, "worst \(worst) rad/day")
    }

    // MARK: - 4. Nutation rates

    @Test("Nutation angle rates match differenced psi/eps, values untouched")
    func nutationRates() {
        var worst = 0.0
        for tt in Self.grid(count: 100, from: -40_000, to: 40_000) {
            var time = AstroTime(tt: tt).raw
            var dpsi = 0.0
            var deps = 0.0
            _Astronomy_Iau2000bRates(&time, &dpsi, &deps)

            var check = AstroTime(tt: tt).raw
            _ = Astronomy_Rotation_EQJ_EQD(&check)
            #expect(check.psi.bitPattern == time.psi.bitPattern)
            #expect(check.eps.bitPattern == time.eps.bitPattern)

            func angles(_ t: Double) -> (Double, Double) {
                var raw = AstroTime(tt: t).raw
                _ = Astronomy_Rotation_EQJ_EQD(&raw)
                return (raw.psi, raw.eps)
            }
            let h = Self.narrowStep
            let p2 = angles(tt + 2 * h)
            let p1 = angles(tt + h)
            let m1 = angles(tt - h)
            let m2 = angles(tt - 2 * h)
            let psiRate = (-p2.0 + 8 * p1.0 - 8 * m1.0 + m2.0) / (12 * h)
            let epsRate = (-p2.1 + 8 * p1.1 - 8 * m1.1 + m2.1) / (12 * h)
            let psiError = abs(psiRate - dpsi)
            let epsError = abs(epsRate - deps)
            worst = max(worst, psiError, epsError)
        }
        #expect(worst <= 1e-9, "worst \(worst) arcsec/day")
    }

    // MARK: - 5. Light-time iteration-count switch

    @Test("Mercury rate is smooth across the archived light-time iteration transition")
    func iterationSwitch() throws {
        let center = 19_590.68873
        let step = 1e-4
        var previous: Double? = nil
        var worst = 0.0
        var tt = center - 0.03
        while tt <= center + 0.03 {
            let rate = try CelestialBody.mercury.geocentricEclipticState(at: AstroTime(tt: tt)).longitudeRate
            if let previous {
                worst = max(worst, abs(rate - previous))
            }
            previous = rate
            tt += step
        }
        // Mercury's acceleration stays below 0.2 deg/day^2, so adjacent samples differ by at most 2e-5 from curvature.
        #expect(worst <= 2e-5, "worst adjacent difference \(worst)")

        var second = 0.0
        var t2 = center - 0.03
        while t2 <= center + 0.03 {
            let d = 2e-5
            let a = try CelestialBody.mercury.geocentricEclipticState(at: AstroTime(tt: t2 - d)).longitudeRate
            let b = try CelestialBody.mercury.geocentricEclipticState(at: AstroTime(tt: t2)).longitudeRate
            let c = try CelestialBody.mercury.geocentricEclipticState(at: AstroTime(tt: t2 + d)).longitudeRate
            second = max(second, abs(a - 2 * b + c))
            t2 += 1e-3
        }
        #expect(second <= 1e-9, "worst second difference \(second) deg/day")
    }

    // MARK: - 6. Polynomial seams

    @Test("Heliocentric velocity is continuous across every polynomial segment boundary")
    func polynomialSeams() {
        let widths: [(astro_body_t, Double)] = [
            (BODY_MERCURY, 8), (BODY_VENUS, 32), (BODY_EARTH, 8), (BODY_MARS, 32),
            (BODY_JUPITER, 32), (BODY_SATURN, 16), (BODY_URANUS, 32), (BODY_NEPTUNE, 16),
        ]
        let start = -36_524.5
        let stop = 36_889.5
        for (body, width) in widths {
            var worst = 0.0
            var boundary = start
            while boundary <= stop {
                let below = Astronomy_HelioState(body, AstroTime(tt: boundary.nextDown).raw)
                let above = Astronomy_HelioState(body, AstroTime(tt: boundary.nextUp).raw)
                #expect(below.status == ASTRO_SUCCESS && above.status == ASTRO_SUCCESS)
                let jumpX = abs(below.vx - above.vx)
                let jumpY = abs(below.vy - above.vy)
                let jumpZ = abs(below.vz - above.vz)
                worst = max(worst, jumpX, jumpY, jumpZ)
                boundary += width
            }
            #expect(worst <= 1e-12, "body \(body.rawValue): worst seam velocity jump \(worst) AU/day")
        }
    }

    // MARK: - 8. Stations

    /// Bisects `f` for a sign change on [lo, hi] down to `tolerance` days.
    static func bisect(_ f: (Double) throws -> Double, lo: Double, hi: Double, tolerance: Double) throws -> Double? {
        var lo = lo
        var hi = hi
        var flo = try f(lo)
        let fhi = try f(hi)
        guard flo * fhi <= 0 else { return nil }
        while hi - lo > tolerance {
            let mid = (lo + hi) / 2
            let fmid = try f(mid)
            if flo * fmid <= 0 {
                hi = mid
            } else {
                lo = mid
                flo = fmid
            }
        }
        return (lo + hi) / 2
    }

    @Test("Mercury's 2025-08-11 station from the analytic rate agrees with the differenced position")
    func mercuryStation() throws {
        let center = AstroTime(year: 2_025, month: 8, day: 11, hour: 12, minute: 0, second: 0).terrestrialTime
        let analytic = try Self.bisect(
            { try CelestialBody.mercury.geocentricEclipticState(at: AstroTime(tt: $0)).longitudeRate },
            lo: center - 1, hi: center + 1, tolerance: 1e-7)
        let differenced = try Self.bisect(
            { tt in
                try Self.fivePoint(
                    { t in
                        let lon = try CelestialBody.mercury.geocentricPosition(at: AstroTime(tt: t)).toEcliptic()
                            .longitude
                        return Self.unwrap(lon, near: 180)
                    }, at: tt, step: 0.01)
            },
            lo: center - 1, hi: center + 1, tolerance: 1e-7)
        let a = try #require(analytic)
        let d = try #require(differenced)
        #expect(abs(a - d) * 86_400 < 1, "roots differ by \(abs(a - d) * 86_400) s")
    }

    /// The archived motion investigation's Mars case: the independent station time is
    /// TT -33748.35542866588, and at the model's own root the orbital and frame
    /// contributions to the longitude rate (about ∓3.7e-5 deg/day) cancel.
    @Test("Mars station near TT -33748.355 agrees with the differenced position")
    func marsStation() throws {
        let reference = -33_748.35542866588
        let analytic = try Self.bisect(
            { try CelestialBody.mars.geocentricEclipticState(at: AstroTime(tt: $0)).longitudeRate },
            lo: reference - 0.01, hi: reference + 0.01, tolerance: 1e-8)
        let differenced = try Self.bisect(
            { tt in
                try Self.fivePoint(
                    { t in
                        Self.unwrap(
                            try CelestialBody.mars.geocentricPosition(at: AstroTime(tt: t)).toEcliptic().longitude,
                            near: 180)
                    }, at: tt, step: 0.01)
            },
            lo: reference - 0.01, hi: reference + 0.01, tolerance: 1e-8)
        let a = try #require(analytic)
        let d = try #require(differenced)
        #expect(
            abs(a - reference) * 86_400 < 60, "model root is \(abs(a - reference) * 86_400) s from the independent time"
        )
        #expect(abs(a - d) * 86_400 < 0.01, "analytic and differenced roots differ by \((a - d) * 86_400) s")
    }
}
