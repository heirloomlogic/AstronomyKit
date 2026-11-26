import Foundation

extension Engine.ApparentPlace {
    /// Earth's selected heliocentric trajectory and its analytic acceleration in AU per TT day squared.
    ///
    /// Position and velocity retain the public planet evaluator's bits. Acceleration differentiates the selected DE source, both blends, and the retained trajectory outside them. At a fitted-segment or source-record boundary it is the selected right-hand derivative.
    static func earthHeliocentricKinematics(tt: Double) throws -> Kinematics {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        let state = try Engine.Planet.earth.heliocentricState(at: time)
        let (weight, rate) = Engine.PlanetDE441.weight(tt: tt)
        let acceleration: SIMD3<Double>
        if weight == 1 {
            let clockAcceleration = tdbAcceleration(tt: tt)
            guard
                let sourceAcceleration = Engine.PlanetDE441.earthAcceleration(
                    tt: tt, tdbAcceleration: clockAcceleration)
            else { throw AstronomyError.badTime }
            acceleration = sourceAcceleration
        } else {
            let retainedAcceleration: SIMD3<Double>
            if Engine.PlanetPolynomial.covers(tt),
                let fitted = polynomialAcceleration(Engine.PlanetPolynomial.model(.earth), tt: tt)
            {
                retainedAcceleration = fitted
            } else {
                retainedAcceleration = seriesAcceleration(.earth, tt: tt)
            }
            let legacyAcceleration = Engine.VSOP87B.toEquatorial.apply(to: retainedAcceleration)
            if weight > 0 {
                let clockAcceleration = tdbAcceleration(tt: tt)
                guard
                    let sourceAcceleration = Engine.PlanetDE441.earthAcceleration(
                        tt: tt, tdbAcceleration: clockAcceleration),
                    let source = Engine.PlanetDE441.state(of: .earth, tt: tt, physicalCenter: true)
                else { throw AstronomyError.badTime }
                let retained = Engine.VSOP87B.toEquatorial.apply(
                    to: try Engine.Planet.earth.retainedEclipticState(at: time))
                let legacyPosition = retained.positionVector
                let legacyVelocity = retained.velocityVector
                let accelerationBlend: SIMD3<Double> = weight * (sourceAcceleration - legacyAcceleration)
                let velocityBlend: SIMD3<Double> = (2 * rate) * (source.velocity - legacyVelocity)
                let positionBlend: SIMD3<Double> =
                    Engine.PlanetDE441.weightAcceleration(tt: tt) * (source.position - legacyPosition)
                acceleration = legacyAcceleration + accelerationBlend + velocityBlend + positionBlend
            } else {
                acceleration = legacyAcceleration
            }
        }
        guard acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite else {
            throw AstronomyError.badTime
        }
        return Kinematics(motion: VectorRate(state.positionVector, state.velocityVector), acceleration: acceleration)
    }

    /// Earth's heliocentric motion (position + velocity only, skipping unused second derivatives).
    static func earthHeliocentricMotion(tt: Double) throws -> VectorRate {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        let state = try Engine.Planet.earth.heliocentricState(at: time)
        return VectorRate(state.positionVector, state.velocityVector)
    }

    /// Motion-only DE441 solar trajectory (skips the 787-term `tdbAcceleration` and second-derivative pass).
    static func sunSourceMotion(tt: Double) throws -> VectorRate {
        guard tt.isFinite, tt >= -Engine.acceptedTTDays - 2, tt <= Engine.acceptedTTDays else {
            throw AstronomyError.badTime
        }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let state = Engine.PlutoDE441.sun.evaluate(tdb: tdb) else { throw AstronomyError.badTime }
        let bias = Engine.FrameBias.icrsToEqj
        let motion = VectorRate(bias.apply(to: state.position), bias.apply(to: state.velocity * conversion.rate))
        guard motion.isFinite else { throw AstronomyError.badTime }
        return motion
    }

    /// Earth barycentric motion (position + velocity only) plus the Sun's barycentric motion at `tt`.
    static func earthAndSunBarycentricMotion(tt: Double) throws -> (earth: VectorRate, sun: VectorRate) {
        let earthHelio = try earthHeliocentricMotion(tt: tt)
        let sun = try sunSourceMotion(tt: tt)
        return (earthHelio + sun, sun)
    }

    /// DE441's compiled solar trajectory, transformed from ICRF/TDB to EQJ/TT.
    ///
    /// The cubic source interpolation is C1. Its acceleration is the selected record's derivative and can jump at a record boundary. The accepted TT interval stays inside the compiled source coverage.
    static func sunBarycentricKinematics(tt: Double) throws -> Kinematics {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        return try sunSourceKinematics(tt: tt)
    }

    /// Private emission evaluator, limited to two TT days of padding before the public interval.
    static func sunSourceKinematics(tt: Double) throws -> Kinematics {
        guard tt.isFinite, tt >= -Engine.acceptedTTDays - 2, tt <= Engine.acceptedTTDays else {
            throw AstronomyError.badTime
        }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let (position, velocity, acceleration) = Engine.PlutoDE441.sun.evaluateWithAcceleration(tdb: tdb) else {
            throw AstronomyError.badTime
        }
        let bias = Engine.FrameBias.icrsToEqj
        let motion = VectorRate(bias.apply(to: position), bias.apply(to: velocity * conversion.rate))
        let ttAcceleration = bias.apply(
            to: acceleration * (conversion.rate * conversion.rate) + velocity * tdbAcceleration(tt: tt))
        guard motion.isFinite, ttAcceleration.x.isFinite, ttAcceleration.y.isFinite, ttAcceleration.z.isFinite else {
            throw AstronomyError.badTime
        }
        return Kinematics(motion: motion, acceleration: ttAcceleration)
    }

    /// The Earth trajectory composed with the same compiled Sun origin used by the apparent-place model.
    static func earthBarycentricKinematics(tt: Double) throws -> Kinematics {
        let earth = try earthHeliocentricKinematics(tt: tt)
        let sun = try sunBarycentricKinematics(tt: tt)
        return Kinematics(motion: earth.motion + sun.motion, acceleration: earth.acceleration + sun.acceleration)
    }

    /// Earth and Sun barycentric kinematics together, avoiding a duplicate Sun evaluation.
    static func earthAndSunBarycentricKinematics(tt: Double) throws -> (earth: Kinematics, sun: Kinematics) {
        let earth = try earthHeliocentricKinematics(tt: tt)
        let sun = try sunBarycentricKinematics(tt: tt)
        return (
            Kinematics(motion: earth.motion + sun.motion, acceleration: earth.acceleration + sun.acceleration),
            sun
        )
    }

    /// Converts a trajectory differentiated per TT day to barycentric velocity/c and its reception-TT derivative.
    static func observerBeta(_ kinematics: Kinematics, atTT tt: Double) throws -> VectorRate {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        let rate = Engine.TDB.rate(tt: tt)
        guard let beta = subluminalBeta(velocityTT: kinematics.motion.rate, tdbRate: rate) else {
            throw AstronomyError.badVector
        }
        let velocity = kinematics.motion.rate / rate
        let acceleration = (kinematics.acceleration - velocity * tdbAcceleration(tt: tt)) / rate
        let result = VectorRate(beta, acceleration / Engine.speedOfLightAUPerDay)
        guard result.isFinite else { throw AstronomyError.badVector }
        return result
    }

    /// Position-only observer beta (rate zeroed; skips `tdbAcceleration` when callers only read `.value`).
    static func observerBetaValue(_ motion: VectorRate, atTT tt: Double) throws -> VectorRate {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        let rate = Engine.TDB.rate(tt: tt)
        guard let beta = subluminalBeta(velocityTT: motion.rate, tdbRate: rate) else {
            throw AstronomyError.badVector
        }
        return VectorRate(beta)
    }

    static func polynomialAcceleration(_ model: Engine.PlanetPolynomial.Model, tt: Double) -> SIMD3<Double>? {
        guard let segment = model.segment(containing: tt), model.included[segment] else { return nil }
        let half = model.width / 2
        let x = (tt - model.start(ofSegment: segment)) / half - 1
        var result = SIMD3<Double>()
        for axis in 0..<3 {
            let first = (segment * 3 + axis) * (model.degree + 1)
            var (b1, b2, d1, d2, a1, a2) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            for k in stride(from: model.degree, through: 1, by: -1) {
                let b = 2 * x * b1 - b2 + model.coefficients[first + k]
                let d = 2 * b1 + 2 * x * d1 - d2
                let a = 4 * d1 + 2 * x * a1 - a2
                (b2, b1) = (b1, b)
                (d2, d1) = (d1, d)
                (a2, a1) = (a1, a)
            }
            result[axis] = (2 * d1 + x * a1 - a2) / (half * half)
        }
        return result
    }

    /// Evaluates the complete spherical VSOP87B series position, first derivative, and second derivative in a single pass.
    private static func seriesOrder012(
        _ model: Engine.VSOP87B.Model, millennia t: Double
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>) {
        var pos = SIMD3<Double>()
        var vel = SIMD3<Double>()
        var acc = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var totalPos = Engine.VSOP87B.CompensatedSum()
            var totalVel = 0.0
            var totalAcc = Engine.VSOP87B.CompensatedSum()
            var (power, lower, lower2) = (1.0, 0.0, 0.0)
            for (alpha, count) in model.termCounts[coordinate].enumerated() {
                var values = Engine.VSOP87B.CompensatedSum()
                var first = Engine.VSOP87B.CompensatedSum()
                var second = Engine.VSOP87B.CompensatedSum()
                for _ in 0..<count {
                    let a = model.terms[3 * term]
                    let b = model.terms[3 * term + 1]
                    let c = model.terms[3 * term + 2]
                    let angle = b + t * c
                    let cosA = cos(angle)
                    let sinA = sin(angle)
                    let aCos = a * cosA
                    values.add(aCos)
                    first.add(-a * c * sinA)
                    second.add(-aCos * c * c)
                    term += 1
                }
                let v0 = values.value
                let v1 = first.value
                let v2 = second.value
                var posInc = power * v0
                if coordinate == 0 { posInc = posInc.truncatingRemainder(dividingBy: 2 * .pi) }
                totalPos.add(posInc)
                totalVel += Double(alpha) * lower * v0 + power * v1
                totalAcc.add(
                    power * v2 + 2 * Double(alpha) * lower * v1 + Double(alpha * (alpha - 1)) * lower2 * v0)
                (lower2, lower, power) = (lower, power, power * t)
            }
            pos[coordinate] = totalPos.value
            vel[coordinate] = totalVel
            acc[coordinate] = totalAcc.value
        }
        return (pos, vel, acc)
    }

    /// The second derivative of the complete spherical VSOP87B series, per Julian millennium squared.
    static func seriesSecondDerivative(_ model: Engine.VSOP87B.Model, millennia t: Double) -> SIMD3<Double> {
        seriesOrder012(model, millennia: t).acceleration
    }

    static func seriesAcceleration(_ planet: Engine.Planet, tt: Double) -> SIMD3<Double> {
        let t = tt / Engine.VSOP87B.daysPerMillennium
        let (p, v, a) = seriesOrder012(Engine.VSOP87B.model(planet), millennia: t)
        let (sl, cl, sb, cb) = (sin(p.x), cos(p.x), sin(p.y), cos(p.y))
        let r = p.z * cb
        let dr = v.z * cb - p.z * sb * v.y
        let ddr = a.z * cb - 2 * v.z * sb * v.y - p.z * cb * v.y * v.y - p.z * sb * a.y
        let result = SIMD3(
            ddr * cl - 2 * dr * sl * v.x - r * cl * v.x * v.x - r * sl * a.x,
            ddr * sl + 2 * dr * cl * v.x - r * sl * v.x * v.x + r * cl * a.x,
            a.z * sb + 2 * v.z * cb * v.y - p.z * sb * v.y * v.y + p.z * cb * a.y)
        return result / (Engine.VSOP87B.daysPerMillennium * Engine.VSOP87B.daysPerMillennium)
    }

    private static let tdbJPLTerms: [(amplitude: Double, frequency: Double, phase: Double)] = [
        (0.00065e-6, 6069.776754, 4.021194),
        (0.00033e-6, 213.299095, 5.543132),
        (-0.00196e-6, 6208.294251, 5.696701),
        (-0.00173e-6, 74.781599, 2.435900),
    ]

    /// Analytic derivative of `Engine.TDB.rate`, per TT day, using the same Fairhead and JPL terms.
    static func tdbAcceleration(tt: Double) -> Double {
        let t = tt / 365250
        var value = 0.0
        var first = 0.0
        var second = 0.0
        for group in Engine.TDB.terms.reversed() {
            var (s, d, a) = (0.0, 0.0, 0.0)
            for term in group.reversed() {
                let angle = term.frequency * t + term.phase
                let sinA = sin(angle)
                let cosA = cos(angle)
                let ampSin = term.amplitude * sinA
                s += ampSin
                d += term.amplitude * term.frequency * cosA
                a -= ampSin * term.frequency * term.frequency
            }
            second = second * t + 2 * first + a
            first = first * t + value + d
            value = value * t + s
        }
        for term in tdbJPLTerms {
            second -= term.amplitude * term.frequency * term.frequency * sin(term.frequency * t + term.phase)
        }
        second += 2 * 0.03638e-6
        return second / (365250 * 365250 * Engine.secondsPerDay)
    }
}
