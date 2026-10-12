import Foundation

extension Engine {
    /// Light propagation and observer transformations on fixed EQJ axes, with rates per TT day.
    enum ApparentPlace {}
}

extension Engine.ApparentPlace {
    /// A scalar and its derivative with respect to reception TT.
    struct ScalarRate {
        var value: Double
        var rate: Double

        init(_ value: Double, _ rate: Double = 0) {
            self.value = value
            self.rate = rate
        }

        static func + (a: Self, b: Self) -> Self { Self(a.value + b.value, a.rate + b.rate) }
        static func - (a: Self, b: Self) -> Self { Self(a.value - b.value, a.rate - b.rate) }
        static func * (a: Self, b: Self) -> Self {
            Self(a.value * b.value, a.rate * b.value + a.value * b.rate)
        }
        static func / (a: Self, b: Self) -> Self {
            Self(a.value / b.value, (a.rate - a.value / b.value * b.rate) / b.value)
        }
    }

    /// A vector and its derivative on the same fixed axes.
    struct VectorRate {
        var value: SIMD3<Double>
        var rate: SIMD3<Double>

        init(_ value: SIMD3<Double>, _ rate: SIMD3<Double> = .zero) {
            self.value = value
            self.rate = rate
        }

        static func + (a: Self, b: Self) -> Self { Self(a.value + b.value, a.rate + b.rate) }
        static func - (a: Self, b: Self) -> Self { Self(a.value - b.value, a.rate - b.rate) }
        static func * (a: Self, b: ScalarRate) -> Self {
            Self(a.value * b.value, a.rate * b.value + a.value * b.rate)
        }
        func dot(_ b: Self) -> ScalarRate {
            ScalarRate((value * b.value).sum(), (rate * b.value + value * b.rate).sum())
        }
        func cross(_ b: Self) -> Self {
            Self(
                Engine.ApparentPlace.cross(value, b.value),
                Engine.ApparentPlace.cross(rate, b.value) + Engine.ApparentPlace.cross(value, b.rate))
        }
        var isFinite: Bool { [value.x, value.y, value.z, rate.x, rate.y, rate.z].allSatisfy(\.isFinite) }

        func normalized() throws -> Self {
            let r = Engine.ApparentPlace.norm(value)
            guard isFinite, r.isFinite, r > 0 else { throw AstronomyError.badVector }
            let p = value / r
            let result = Self(p, (rate - p * (p * rate).sum()) / r)
            guard result.isFinite else { throw AstronomyError.badVector }
            return result
        }
    }

    struct Kinematics {
        let motion: VectorRate
        let acceleration: SIMD3<Double>
    }

    /// ERFA's solar Schwarzschild radius, in AU (`ERFA_SRS`).
    static let solarSchwarzschildRadius = 1.97412574336e-8

    /// ERFA `eraAb`: natural to proper direction, including the solar potential term and exact normalization.
    ///
    /// `beta` is the observer's barycentric velocity per TDB day divided by c; its rate is the derivative of that ratio per TT day. `sunDistance` is the observer-Sun distance in AU. Input directions must have unit length to within 1e-6, allowing the rounded published ERFA examples. Invalid inputs throw `badVector`.
    static func aberration(direction p: VectorRate, beta: VectorRate, sunDistance s: ScalarRate) throws -> VectorRate {
        try checkDirection(p)
        guard beta.isFinite, s.value.isFinite, s.value > 0, s.rate.isFinite else { throw AstronomyError.badVector }
        let b2 = beta.dot(beta)
        guard b2.value < 1 else { throw AstronomyError.badVector }
        let inverseGamma = sqrt(1 - b2.value)
        let bm1 = ScalarRate(inverseGamma, -b2.rate / (2 * inverseGamma))
        let pdv = p.dot(beta)
        let w1 = ScalarRate(1) + pdv / (ScalarRate(1) + bm1)
        let w2 = ScalarRate(solarSchwarzschildRadius) / s
        return try (p * bm1 + beta * w1 + (beta - p * pdv) * w2).normalized()
    }

    /// ERFA `eraLd` for a finite-distance source. The output retains ERFA's unnormalized convention.
    ///
    /// `p` points from observer to source, `q` from deflector to source, and `e` from deflector to observer. Mass is in solar masses and distance in AU. Below the positive limiter the denominator is clamped; at equality the returned rate uses the limiter branch. The two-sided derivative need not exist at that boundary.
    static func deflection(
        mass: Double, direction p: VectorRate, bodyToSource q: VectorRate, bodyToObserver e: VectorRate,
        distance: ScalarRate, limiter: ScalarRate
    ) throws -> VectorRate {
        try checkDirection(p)
        try checkDirection(q)
        try checkDirection(e)
        guard mass.isFinite, mass >= 0,
            distance.value.isFinite, distance.value > 0, distance.rate.isFinite,
            limiter.value.isFinite, limiter.value > 0, limiter.rate.isFinite
        else { throw AstronomyError.badVector }
        let denominator = q.dot(q + e)
        let limited = denominator.value > limiter.value ? denominator : limiter
        let scale = ScalarRate(mass * solarSchwarzschildRadius) / distance / limited
        let result = p + p.cross(e.cross(q)) * scale
        guard result.isFinite else { throw AstronomyError.badVector }
        return result
    }

    struct RetardedState {
        let emissionTT: Double
        let emissionRate: Double
        let lightTimeDays: Double
        let displacement: VectorRate
        let iterations: Int
    }

    /// Solves barycentric geometric light time in elapsed TDB, parameterized by TT, holding the observer at reception.
    ///
    /// The target evaluator must return position in AU and its derivative per TT day, on the same fixed axes and origin as the observer. It owns source-coverage checks at every requested emission epoch. This solver admits a delay of at most one day, velocities strictly subluminal per TDB day at their respective reception/emission epochs, and a supported reception TT. It returns the derivative of the implicit TDB light-time equation with respect to reception TT, independent of iteration count. The emitted TT must repeat after an iteration, or the TT delay must change by at most four ULP. It does not add Shapiro delay.
    static func retardedState(
        atTT tt: Double, observer: VectorRate, target: (Double) throws -> VectorRate
    ) throws -> RetardedState {
        guard tt.isFinite, abs(tt) <= Engine.acceptedTTDays, observer.isFinite,
            norm(observer.value).isFinite
        else { throw AstronomyError.badTime }
        let c = Engine.speedOfLightAUPerDay
        let observedClock = Engine.TDB.offsetAndRate(tt: tt)
        guard let observerBeta = subluminalBeta(velocityTT: observer.rate, tdbRate: observedClock.rate) else {
            throw AstronomyError.badTime
        }
        var delay = 0.0
        for iteration in 1...20 {
            let emission = tt - delay
            let source = try target(emission)
            let emittedClock = Engine.TDB.offsetAndRate(tt: emission)
            guard source.isFinite,
                let sourceBeta = subluminalBeta(velocityTT: source.rate, tdbRate: emittedClock.rate)
            else {
                throw AstronomyError.badTime
            }
            let p = source.value - observer.value
            let distance = norm(p)
            guard distance.isFinite, distance > 0 else { throw AstronomyError.badVector }
            let lightTime = distance / c
            let nextDelay =
                lightTime - (observedClock.offsetSeconds - emittedClock.offsetSeconds) / Engine.secondsPerDay
            guard lightTime <= 1, nextDelay >= 0 else { throw AstronomyError.badTime }
            if abs(nextDelay - delay) <= 4 * nextDelay.ulp || tt - nextDelay == emission {
                let n = p / distance
                let emissionRate =
                    (observedClock.rate / emittedClock.rate)
                    * ((1 + (n * observerBeta).sum()) / (1 + (n * sourceBeta).sum()))
                let displacement = VectorRate(p, source.rate * emissionRate - observer.rate)
                guard displacement.isFinite, emissionRate.isFinite, emissionRate > 0 else {
                    throw AstronomyError.badTime
                }
                return RetardedState(
                    emissionTT: emission, emissionRate: emissionRate, lightTimeDays: lightTime,
                    displacement: displacement, iterations: iteration)
            }
            delay = nextDelay
        }
        throw AstronomyError.noConvergence
    }

    static func norm(_ p: SIMD3<Double>) -> Double { hypot(hypot(p.x, p.y), p.z) }

    /// Converts a per-TT velocity to a strictly subluminal TDB velocity/c at that velocity's epoch.
    static func subluminalBeta(velocityTT: SIMD3<Double>, tdbRate: Double) -> SIMD3<Double>? {
        guard tdbRate.isFinite, tdbRate > 0 else { return nil }
        let beta = velocityTT / tdbRate / Engine.speedOfLightAUPerDay
        guard norm(beta) < 1 else { return nil }
        return beta
    }

    private static func checkDirection(_ p: VectorRate) throws {
        guard p.isFinite, abs((p.value * p.value).sum() - 1) <= 1e-6 else { throw AstronomyError.badVector }
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
