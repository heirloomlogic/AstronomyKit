import Foundation

extension Engine.ApparentPlace {
    /// Earth's selected heliocentric trajectory and its analytic acceleration in AU per TT day squared.
    ///
    /// The position and velocity retain the public planet evaluator's bits. Acceleration differentiates that same polynomial or VSOP branch. At a polynomial boundary it is the right-hand branch derivative; no continuity across fitted segments is assumed.
    static func earthHeliocentricKinematics(tt: Double) throws -> Kinematics {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays else { throw AstronomyError.badTime }
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        let state = try Engine.Planet.earth.heliocentricState(at: time)
        let acceleration: SIMD3<Double>
        if Engine.PlanetPolynomial.covers(tt),
            let fitted = polynomialAcceleration(Engine.PlanetPolynomial.model(.earth), tt: tt)
        {
            acceleration = fitted
        } else {
            acceleration = seriesAcceleration(.earth, tt: tt)
        }
        let equatorial = Engine.VSOP87B.toEquatorial.apply(to: acceleration)
        guard [equatorial.x, equatorial.y, equatorial.z].allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
        return Kinematics(motion: VectorRate(state.positionVector, state.velocityVector), acceleration: equatorial)
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
        let table = Engine.PlutoDE441.sun
        guard let state = table.evaluate(tdb: tdb) else { throw AstronomyError.badTime }
        let record = Int(floor((tdb - table.start) / table.days))
        guard (0..<table.recordCount).contains(record) else { throw AstronomyError.badTime }
        let x = 2 * (tdb - table.start - Double(record) * table.days) / table.days - 1
        let acceleration: SIMD3<Double> = table.data.withUnsafeBytes { raw in
            func value(_ offset: Int) -> Double {
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
            }
            let left = record * 48
            let right = left + 48
            var result = SIMD3<Double>()
            for axis in 0..<3 {
                let pl = value(left + axis * 8)
                let pr = value(right + axis * 8)
                let dl = value(left + (axis + 3) * 8) * table.days / 2
                let dr = value(right + (axis + 3) * 8) * table.days / 2
                let c2 = (dr - dl) / 8
                let c3 = (dr + dl - (pr - pl)) / 16
                result[axis] = (4 * c2 + 24 * x * c3) * 4 / (table.days * table.days * Engine.kilometersPerAU)
            }
            return result
        }
        let bias = Engine.FrameBias.icrsToEqj
        let motion = VectorRate(bias.apply(to: state.position), bias.apply(to: state.velocity * conversion.rate))
        let ttAcceleration = bias.apply(
            to: acceleration * (conversion.rate * conversion.rate) + state.velocity * tdbAcceleration(tt: tt))
        guard motion.isFinite, [ttAcceleration.x, ttAcceleration.y, ttAcceleration.z].allSatisfy(\.isFinite) else {
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

    /// The second derivative of the complete spherical VSOP87B series, per Julian millennium squared.
    static func seriesSecondDerivative(_ model: Engine.VSOP87B.Model, millennia t: Double) -> SIMD3<Double> {
        var result = SIMD3<Double>()
        var term = 0
        for coordinate in 0..<3 {
            var total = Engine.VSOP87B.CompensatedSum()
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
                    values.add(a * cos(angle))
                    first.add(-a * c * sin(angle))
                    second.add(-a * c * c * cos(angle))
                    term += 1
                }
                total.add(
                    power * second.value + 2 * Double(alpha) * lower * first.value + Double(alpha * (alpha - 1))
                        * lower2 * values.value)
                (lower2, lower, power) = (lower, power, power * t)
            }
            result[coordinate] = total.value
        }
        return result
    }

    static func seriesAcceleration(_ planet: Engine.Planet, tt: Double) -> SIMD3<Double> {
        let t = tt / Engine.VSOP87B.daysPerMillennium
        let p = Engine.VSOP87B.coordinates(planet, millennia: t)
        let v = Engine.VSOP87B.derivatives(planet, millennia: t)
        let a = seriesSecondDerivative(Engine.VSOP87B.model(planet), millennia: t)
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
                s += term.amplitude * sin(angle)
                d += term.amplitude * term.frequency * cos(angle)
                a -= term.amplitude * term.frequency * term.frequency * sin(angle)
            }
            second = second * t + 2 * first + a
            first = first * t + value + d
            value = value * t + s
        }
        for (amplitude, frequency, phase) in [
            (0.00065e-6, 6069.776754, 4.021194), (0.00033e-6, 213.299095, 5.543132),
            (-0.00196e-6, 6208.294251, 5.696701), (-0.00173e-6, 74.781599, 2.435900),
        ] {
            second -= amplitude * frequency * frequency * sin(frequency * t + phase)
        }
        second += 2 * 0.03638e-6
        return second / (365250 * 365250 * Engine.secondsPerDay)
    }
}
