import Foundation
import Testing

@testable import AstronomyKit

@Suite("Apparent-place foundations")
struct EngineApparentPlaceTests {
    typealias Model = Engine.ApparentPlace
    typealias VectorRate = Model.VectorRate

    @Test("Published ERFA aberration example")
    func publishedAberration() throws {
        let p = SIMD3(-0.76321968546737951, -0.60869453983060384, -0.21676408580639883)
        let beta = SIMD3(2.1044018893653786e-5, -8.9108923304429319e-5, -3.8633714797716569e-5)
        let result = try Model.aberration(
            direction: VectorRate(p), beta: VectorRate(beta), sunDistance: .init(0.99980921395708788))
        let expected = SIMD3(-0.7631631094219556269, -0.6087553082505590832, -0.2167926269368471279)
        #expect(maximum(result.value - expected) < 1e-12)
        #expect(result.rate == .zero)
    }

    @Test("Published ERFA finite-source deflection example")
    func publishedDeflection() throws {
        let p = VectorRate(SIMD3(-0.763276255, -0.608633767, -0.216735543))
        let e = VectorRate(SIMD3(0.76700421, 0.605629598, 0.211937094))
        let result = try Model.deflection(
            mass: 0.00028574, direction: p, bodyToSource: p, bodyToObserver: e,
            distance: .init(8.91276983), limiter: .init(3e-10))
        #expect(
            maximum(result.value - SIMD3(-0.7632762548968159627, -0.6086337670823762701, -0.2167355431320546947))
                < 1e-12)
        #expect(result.rate == .zero)
    }

    @Test("Linear radial light time and its implicit derivative")
    func radialLightTime() throws {
        let c = Engine.speedOfLightAUPerDay
        let vo = 0.01
        let vt = 0.02
        let time = 100.0
        let result = try Model.retardedState(
            atTT: time, observer: VectorRate(SIMD3(vo * time, 0, 0), SIMD3(vo, 0, 0))
        ) { tt in
            VectorRate(SIMD3(10 + vt * tt, 0, 0), SIMD3(vt, 0, 0))
        }
        var expectedEmission = (time - (10 - vo * time) / c) / (1 + vt / c)
        for _ in 0..<5 {
            let correction =
                (Engine.TDB.offsetSeconds(tt: time) - Engine.TDB.offsetSeconds(tt: expectedEmission))
                / Engine.secondsPerDay
            expectedEmission = (time - (10 - vo * time) / c + correction) / (1 + vt / c)
        }
        let expectedRate = (Engine.TDB.rate(tt: time) + vo / c) / (Engine.TDB.rate(tt: expectedEmission) + vt / c)
        #expect(abs(result.emissionTT - expectedEmission) < 3e-14)
        #expect(abs(result.emissionRate - expectedRate) < 3e-16)
        #expect(abs(result.displacement.rate.x - (vt * expectedRate - vo)) < 1e-17)
        #expect(abs(result.lightTimeDays - result.displacement.value.x / c) < 1e-12)
    }

    @Test("Earth kinematics preserve the selected public position and velocity")
    func earthKinematics() throws {
        for tt in [-Engine.acceptedTTDays, -100000.0, -36525, 0, 36525, 100000, Engine.acceptedTTDays] {
            let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
            let expected = try Engine.Planet.earth.heliocentricState(at: time)
            let result = try Model.earthHeliocentricKinematics(tt: tt)
            #expect(result.motion.value == expected.positionVector)
            #expect(result.motion.rate == expected.velocityVector)
            #expect(result.acceleration.x.isFinite)
        }
    }

    @Test("Compiled ERFA values and independent high-precision directional rates")
    func independentRates() throws {
        for row in PublishedApparentPlace.aberration {
            let actual = try Model.aberration(
                direction: VectorRate(row.p, row.dp), beta: VectorRate(row.beta, row.dbeta),
                sunDistance: .init(row.distance, row.distanceRate))
            #expect(maximum(actual.value - row.expected) < 2e-15)
            #expect(maximum(actual.rate - row.expectedRate) < 2e-16)
        }
        for row in PublishedApparentPlace.deflection {
            let actual = try Model.deflection(
                mass: row.mass, direction: VectorRate(row.p, row.dp), bodyToSource: VectorRate(row.q, row.dq),
                bodyToObserver: VectorRate(row.e, row.de), distance: .init(row.distance, row.distanceRate),
                limiter: .init(row.limiter, row.limiterRate))
            #expect(maximum(actual.value - row.expected) < 2e-15)
            #expect(maximum(actual.rate - row.expectedRate) < 2e-16)
        }
    }

    @Test("Kinematics differentiate the selected trajectory away from its seams")
    func analyticAccelerations() throws {
        for tt in [-1460999.0, -100000.25, -35000.25, -1.25, 0.25, 35000.25, 100000.25, 1460999.0] {
            for evaluator in [
                Model.earthHeliocentricKinematics, Model.sunBarycentricKinematics, Model.earthBarycentricKinematics,
            ] {
                let h = 0.02
                let before2 = try evaluator(tt - 2 * h).motion.rate
                let before = try evaluator(tt - h).motion.rate
                let after = try evaluator(tt + h).motion.rate
                let after2 = try evaluator(tt + 2 * h).motion.rate
                let difference = (before2 - 8 * before + 8 * after - after2) / (12 * h)
                let analytic = try evaluator(tt).acceleration
                #expect(maximum(analytic - difference) < 2e-11)
            }
        }
    }

    @Test("Non-radial accelerated trajectories differentiate the retarded solution")
    func retardedDerivative() throws {
        func state(_ tt: Double) throws -> Model.RetardedState {
            let observer = VectorRate(SIMD3(cos(tt), sin(tt), 0), SIMD3(-sin(tt), cos(tt), 0))
            return try Model.retardedState(atTT: tt, observer: observer) { t in
                VectorRate(SIMD3(3 + t * t / 100, t / 10, 1), SIMD3(t / 50, 0.1, 0))
            }
        }
        let tt = 0.37
        let h = 1e-4
        let analytic = try state(tt)
        let before2 = try state(tt - 2 * h).displacement.value
        let before = try state(tt - h).displacement.value
        let after = try state(tt + h).displacement.value
        let after2 = try state(tt + 2 * h).displacement.value
        #expect(maximum(analytic.displacement.rate - (before2 - 8 * before + 8 * after - after2) / (12 * h)) < 1e-11)
        #expect(analytic.emissionTT <= tt)
        #expect(analytic.iterations <= 8)
    }

    @Test("Invalid effects and reception domains fail closed")
    func invalidInputs() throws {
        let unit = VectorRate(SIMD3(1, 0, 0))
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.badVector) {
                try Model.aberration(direction: unit, beta: VectorRate(SIMD3(bad, 0, 0)), sunDistance: .init(1))
            }
            #expect(throws: AstronomyError.badTime) { try Model.earthHeliocentricKinematics(tt: bad) }
            #expect(throws: AstronomyError.badTime) { try Model.sunBarycentricKinematics(tt: bad) }
        }
        #expect(throws: AstronomyError.badVector) {
            try Model.aberration(direction: unit, beta: VectorRate(SIMD3(1, 0, 0)), sunDistance: .init(1))
        }
        #expect(throws: AstronomyError.badVector) {
            try Model.deflection(
                mass: 1, direction: unit, bodyToSource: unit, bodyToObserver: unit,
                distance: .init(1), limiter: .init(0))
        }
        for tt in [(-Engine.acceptedTTDays).nextDown, Engine.acceptedTTDays.nextUp, .nan, .infinity] {
            #expect(throws: AstronomyError.badTime) {
                try Model.retardedState(atTT: tt, observer: VectorRate(.zero)) { _ in unit }
            }
        }
        #expect(throws: AstronomyError.badTime) {
            try Model.retardedState(atTT: 0, observer: VectorRate(.zero)) { _ in VectorRate(SIMD3(200, 0, 0)) }
        }
        #expect(throws: AstronomyError.badVector) {
            try Model.retardedState(atTT: 0, observer: VectorRate(.zero)) { _ in VectorRate(.zero) }
        }
        #expect(throws: AstronomyError.badTime) {
            try Model.retardedState(atTT: 0, observer: VectorRate(.zero)) { tt in
                guard tt >= 0 else { throw AstronomyError.badTime }
                return unit
            }
        }
    }

    @Test("Acceleration recurrences match independently differentiated polynomial and harmonic examples")
    func derivativeRecurrences() throws {
        let width = Engine.PlanetPolynomial.stop - Engine.PlanetPolynomial.start
        let polynomial = Engine.PlanetPolynomial.Model(
            degree: 3, width: width, excludedSegments: [], coefficients: [1, 2, 3, 4, -2, 5, 7, -11, 13, 17, 19, 23])
        for tt in [
            Engine.PlanetPolynomial.start, Engine.PlanetPolynomial.start + width * 0.25,
            Engine.PlanetPolynomial.start + width * 0.75, Engine.PlanetPolynomial.stop.nextDown,
        ] {
            let x = 2 * (tt - Engine.PlanetPolynomial.start) / width - 1
            let actual = try #require(Model.polynomialAcceleration(polynomial, tt: tt))
            let expected = SIMD3(12 + 96 * x, 28 - 264 * x, 76 + 552 * x) * (4 / (width * width))
            #expect(maximum(actual - expected) < 1e-22)
        }
        #expect(Model.polynomialAcceleration(polynomial, tt: Engine.PlanetPolynomial.start.nextDown) == nil)
        #expect(Model.polynomialAcceleration(polynomial, tt: Engine.PlanetPolynomial.stop) == nil)
        let harmonic = Engine.VSOP87B.Model(
            termCounts: [[1, 1, 1], [1, 1, 1], [1, 1, 1]],
            terms: Array(repeating: [2.0, 0.3, 7, 3, 0.5, 11, 5, 0.7, 13], count: 3).flatMap { $0 })
        for t in [-4.0, 0, 4] {
            let expected =
                -98 * cos(0.3 + 7 * t) - 66 * sin(0.5 + 11 * t)
                - 363 * t * cos(0.5 + 11 * t) + 10 * cos(0.7 + 13 * t)
                - 260 * t * sin(0.7 + 13 * t) - 845 * t * t * cos(0.7 + 13 * t)
            #expect(maximum(Model.seriesSecondDerivative(harmonic, millennia: t) - SIMD3(repeating: expected)) < 4e-12)
        }
    }

    @Test("Source domain endpoints and adjacent representable values")
    func sourceEndpoints() throws {
        for evaluator in [
            Model.earthHeliocentricKinematics, Model.sunBarycentricKinematics, Model.earthBarycentricKinematics,
        ] {
            for tt in [
                -Engine.acceptedTTDays, (-Engine.acceptedTTDays).nextUp, Engine.acceptedTTDays.nextDown,
                Engine.acceptedTTDays,
            ] {
                let state = try evaluator(tt)
                #expect(state.motion.isFinite)
                #expect([state.acceleration.x, state.acceleration.y, state.acceleration.z].allSatisfy { $0.isFinite })
            }
            for tt in [(-Engine.acceptedTTDays).nextDown, Engine.acceptedTTDays.nextUp] {
                #expect(throws: AstronomyError.badTime) { try evaluator(tt) }
            }
        }
        let model = Engine.PlanetPolynomial.model(.earth)
        for k in [0, 1, model.segmentCount / 2, model.segmentCount - 1] {
            let boundary = model.start(ofSegment: k)
            for tt in [boundary.nextDown, boundary, boundary.nextUp] {
                let actual = try Model.earthHeliocentricKinematics(tt: tt)
                let expected = try Engine.Planet.earth.heliocentricState(
                    at: Engine.Time(ut: tt, tt: tt, deltaTModel: .jplHorizons))
                #expect(actual.motion.value == expected.positionVector)
                #expect(actual.motion.rate == expected.velocityVector)
            }
        }
    }

    @Test("Limiter equality returns its documented branch derivative")
    func limiterEquality() throws {
        let p = VectorRate(SIMD3(1, 0, 0), SIMD3(0, 0.01, 0))
        let q = VectorRate(SIMD3(0, 1, 0), SIMD3(0.01, 0, 0))
        let e = VectorRate(SIMD3(0, 0, 1), SIMD3(0, 0.02, 0))
        let exact = try Model.deflection(
            mass: 1, direction: p, bodyToSource: q, bodyToObserver: e,
            distance: .init(1), limiter: .init(1, 0.3))
        let inside = try Model.deflection(
            mass: 1, direction: p, bodyToSource: q, bodyToObserver: e,
            distance: .init(1), limiter: .init(1.000000001, 0.3))
        #expect(maximum(exact.rate - inside.rate) < 1e-16)
    }

    @Test("TDB second derivative matches its rate on both sides of J2000")
    func tdbSecondDerivative() {
        for tt in [-1461000.0, -100000, 0, 100000, 1_461_000] {
            let h = 0.25
            let difference =
                (Engine.TDB.rate(tt: tt - 2 * h) - 8 * Engine.TDB.rate(tt: tt - h)
                    + 8 * Engine.TDB.rate(tt: tt + h) - Engine.TDB.rate(tt: tt + 2 * h)) / (12 * h)
            #expect(abs(Model.tdbAcceleration(tt: tt) - difference) < 2e-15)
        }
    }

    @Test("Independent 80-digit TDB light-time roots distinguish the TT-only equation")
    func independentTDBRoots() throws {
        for row in PublishedApparentPlace.retarded {
            let actual = try Model.retardedState(atTT: row.tt, observer: VectorRate(.zero, SIMD3(0.01, 0, 0))) { tt in
                VectorRate(SIMD3(10 + 0.02 * (tt - row.tt), 0, 0), SIMD3(0.02, 0, 0))
            }
            #expect(abs(actual.emissionTT - row.emission) <= max(2 * row.emission.ulp, 2e-16))
            #expect(abs(actual.emissionRate - row.emissionRate) < 4e-16)
            #expect(abs(actual.displacement.rate.x - row.displacementRate) < 1e-17)
            #expect(abs(actual.lightTimeDays - row.delay) < 5e-14)
            if abs(row.tt) <= 1000 {
                #expect(abs(actual.emissionTT - row.ttOnlyEmission) > 3 * row.emission.ulp)
            }
        }
    }

    @Test("Aberration velocity converts TT derivatives to TDB coordinate velocity")
    func observerVelocityScale() throws {
        let tt = 0.0
        let earth = try Model.earthBarycentricKinematics(tt: tt)
        let beta = try Model.observerBeta(earth, atTT: tt)
        let unconverted = earth.motion.rate / Engine.speedOfLightAUPerDay
        #expect(maximum(beta.value - unconverted) > 1e-14)
        let h = 0.01
        let before = try Model.observerBeta(Model.earthBarycentricKinematics(tt: tt - h), atTT: tt - h).value
        let after = try Model.observerBeta(Model.earthBarycentricKinematics(tt: tt + h), atTT: tt + h).value
        #expect(maximum(beta.rate - (after - before) / (2 * h)) < 2e-14)
    }

    @Test("Discontinuous target iteration reports nonconvergence")
    func noConvergence() {
        #expect(throws: AstronomyError.noConvergence) {
            try Model.retardedState(atTT: 0, observer: VectorRate(.zero)) { tt in
                VectorRate(SIMD3(tt < -0.005 ? 0.5 : 1, 0, 0))
            }
        }
    }

    @Test("Subluminal admission uses TDB velocity at each corresponding epoch")
    func tdbSpeedDomain() throws {
        let c = Engine.speedOfLightAUPerDay
        let rejectedTT = 180.0
        let rejectedSpeed = c * (1 - 1e-10)
        #expect(rejectedSpeed / Engine.TDB.rate(tt: rejectedTT) > c)
        for sign in [-1.0, 1] {
            let observer = VectorRate(.zero, SIMD3(sign * rejectedSpeed, 0, 0))
            #expect(throws: AstronomyError.badVector) {
                try Model.observerBeta(.init(motion: observer, acceleration: .zero), atTT: rejectedTT)
            }
            #expect(throws: AstronomyError.badTime) {
                try Model.retardedState(atTT: rejectedTT, observer: observer) { _ in VectorRate(SIMD3(10, 0, 0)) }
            }
            #expect(throws: AstronomyError.badTime) {
                try Model.retardedState(atTT: rejectedTT, observer: VectorRate(.zero)) { tt in
                    VectorRate(
                        SIMD3(10 + sign * rejectedSpeed * (tt - rejectedTT), 0, 0), SIMD3(sign * rejectedSpeed, 0, 0))
                }
            }
        }
        let acceptedTT = 0.0
        let acceptedSpeed = c * (1 + 1e-10)
        #expect(acceptedSpeed > c)
        #expect(acceptedSpeed / Engine.TDB.rate(tt: acceptedTT) < c)
        for sign in [-1.0, 1] {
            let observer = VectorRate(.zero, SIMD3(sign * acceptedSpeed, 0, 0))
            let beta = try Model.observerBeta(.init(motion: observer, acceleration: .zero), atTT: acceptedTT)
            #expect(Model.norm(beta.value) < 1)
            let result = try Model.retardedState(atTT: acceptedTT, observer: observer) { _ in
                VectorRate(SIMD3(10, 0, 0))
            }
            #expect(result.emissionRate > 0)
        }
        // A near-c transverse source is admitted, but its fixed-point iteration does not converge within 20 steps.
        #expect(throws: AstronomyError.noConvergence) {
            try Model.retardedState(atTT: acceptedTT, observer: VectorRate(.zero)) { tt in
                VectorRate(SIMD3(10, acceptedSpeed * tt, 0), SIMD3(0, acceptedSpeed, 0))
            }
        }
    }

    @Test("Target speed is validated at the retarded epoch and rejects nonfinite and luminal values")
    func emittedSpeedDomain() {
        let c = Engine.speedOfLightAUPerDay
        for tt in [0.0, 180] {
            for factor in [1.0, 1.000000001, Double.infinity, Double.nan] {
                #expect(throws: AstronomyError.badTime) {
                    try Model.retardedState(atTT: tt, observer: VectorRate(.zero)) { emission in
                        let speed = emission == tt ? 0 : c * Engine.TDB.rate(tt: emission) * factor
                        return VectorRate(SIMD3(10, 0, 0), SIMD3(speed, 0, 0))
                    }
                }
            }
        }
    }

    func maximum(_ v: SIMD3<Double>) -> Double { max(abs(v.x), abs(v.y), abs(v.z)) }
}
