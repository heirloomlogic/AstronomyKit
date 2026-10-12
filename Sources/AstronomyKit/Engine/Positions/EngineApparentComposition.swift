import Foundation

extension Engine.ApparentPlace {
    /// Selected heliocentric models share the compiled DE441 solar origin on fixed EQJ axes.
    ///
    /// Only internal emission epochs may use the two-day lower padding. The public reception interval is unchanged. Table-backed trajectories check their actual source coverage as well.
    static func bodyMotion(_ body: CelestialBody, tt: Double) throws -> VectorRate {
        guard tt.isFinite, tt >= -Engine.acceptedTTDays - 2, tt <= Engine.acceptedTTDays else {
            throw AstronomyError.badTime
        }
        if body == .solarSystemBarycenter { return VectorRate(.zero) }
        let sun = try sunSourceKinematics(tt: tt).motion
        if body == .sun { return sun }
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        if tt >= -Engine.acceptedTTDays {
            let state = try Engine.Positions.heliocentricState(of: body, at: time)
            return VectorRate(state.positionVector, state.velocityVector) + sun
        }
        if body == .pluto {
            let clock = Engine.TDB.offsetAndRate(tt: tt)
            guard let state = Engine.PlutoDE441.pluto.evaluate(tdb: tt + clock.offsetSeconds / Engine.secondsPerDay)
            else { throw AstronomyError.badTime }
            let bias = Engine.FrameBias.icrsToEqj
            return VectorRate(bias.apply(to: state.position), bias.apply(to: state.velocity * clock.rate))
        }
        if body == .moon || body == .earthMoonBarycenter {
            guard let moon = Engine.MoonDE441.state(tt: tt) else { throw AstronomyError.badTime }
            let scale = body == .moon ? 1 : 1 / (1 + Engine.Moon.earthMoonMassRatio)
            return try bodyMotion(.earth, tt: tt) + VectorRate(moon.position * scale, moon.velocity * scale)
        }
        guard let planet = Engine.Planet(body) else { throw AstronomyError.invalidBody }
        let t = tt / Engine.VSOP87B.daysPerMillennium
        let sphere = Engine.VSOP87B.coordinates(planet, millennia: t)
        let rates = Engine.VSOP87B.derivatives(planet, millennia: t)
        return VectorRate(
            Engine.VSOP87B.toEquatorial.apply(to: Engine.VSOP87B.rectangular(sphere)),
            Engine.VSOP87B.toEquatorial.apply(to: Engine.VSOP87B.velocity(sphere, rates: rates))) + sun
    }

    static func length(_ vector: VectorRate) throws -> ScalarRate {
        let value = norm(vector.value)
        guard value.isFinite, value > 0 else { throw AstronomyError.badVector }
        return ScalarRate(value, (vector.value / value * vector.rate).sum())
    }

    /// Kaplan (1998), section 2: finite-source solar deflection uses the Sun at reception.
    ///
    /// The source's astrometric range is retained after angular corrections. The Sun does not deflect its own image. The ERFA solar limiter bounds the expression inside the solar disk; those occulted rays do not establish observable accuracy.
    static func correctedMotion(
        _ displacement: VectorRate, sunToObserver: VectorRate, beta: VectorRate, solarSource: Bool
    ) throws -> VectorRate {
        let range = try length(displacement)
        let solarDistance = try length(sunToObserver)
        var direction = try displacement.normalized()
        if !solarSource {
            let q = try (displacement + sunToObserver).normalized()
            let e = try sunToObserver.normalized()
            let squared = solarDistance * solarDistance
            let limiter = squared.value > 1 ? ScalarRate(1e-6) / squared : ScalarRate(1e-6)
            direction = try deflection(
                mass: 1, direction: direction, bodyToSource: q, bodyToObserver: e,
                distance: solarDistance, limiter: limiter
            ).normalized()
        }
        return try aberration(direction: direction, beta: beta, sunDistance: solarDistance) * range
    }

    static func solution(
        body: CelestialBody, at time: Engine.Time, observer: Kinematics, aberration: Aberration
    ) throws -> (motion: VectorRate, emissionTT: Double) {
        try Engine.checkAcceptedTime(time)
        let retarded = try retardedState(atTT: time.tt, observer: observer.motion) {
            try bodyMotion(body, tt: $0)
        }
        if aberration == .none { return (retarded.displacement, retarded.emissionTT) }
        let sun = try sunBarycentricKinematics(tt: time.tt)
        let corrected = try correctedMotion(
            retarded.displacement, sunToObserver: observer.motion - sun.motion,
            beta: observerBeta(observer, atTT: time.tt), solarSource: body == .sun)
        return (corrected, retarded.emissionTT)
    }

    static func geocentricMotion(
        body: CelestialBody, at time: Engine.Time, aberration: Aberration
    ) throws -> VectorRate {
        try solution(
            body: body, at: time, observer: earthBarycentricKinematics(tt: time.tt), aberration: aberration
        ).motion
    }
}
