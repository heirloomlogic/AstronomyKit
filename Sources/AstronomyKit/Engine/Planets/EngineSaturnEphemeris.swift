import Foundation

extension Engine {
    /// Saturn's physical center: DE441 Saturn-system barycenter minus Sun, plus SAT441's center offset, on ICRF axes.
    enum SaturnEphemeris {}
}

extension Engine.SaturnEphemeris {
    typealias Table = Engine.DirectChebyshevTable

    /// The 1900–2130 full-weight interval and its 32-day blends deliberately reuse the existing Moon/Pluto window; this is not a new global accuracy range.
    static func weight(tt: Double) -> (weight: Double, rate: Double) { Engine.MoonEphemeris.weight(tt: tt) }

    /// A state in AU and AU per TT day on the retained model’s ecliptic axes. The default includes the physical-center offset; system-mass callers exclude it.
    static func eclipticState(
        at time: Engine.Time, physicalCenter: Bool = true
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        let tt = time.tt
        guard tt.isFinite, weight(tt: tt).weight > 0 else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let b = barycenter.evaluate(tdb: tdb), let s = sun.evaluate(tdb: tdb) else { return nil }
        var c = (position: SIMD3<Double>.zero, velocity: SIMD3<Double>.zero)
        if physicalCenter {
            guard let center = offset.evaluate(tdb: tdb) else { return nil }
            c = center
        }
        let position = (b.position - s.position + c.position) / Engine.kilometersPerAU
        let velocity = (b.velocity - s.velocity + c.velocity) * conversion.rate / Engine.kilometersPerAU
        let p = Engine.FrameBias.icrsToEqj.apply(to: position)
        let v = Engine.FrameBias.icrsToEqj.apply(to: velocity)
        let state = Engine.State<Engine.EQJ>(x: p.x, y: p.y, z: p.z, vx: v.x, vy: v.y, vz: v.z, time: time)
        let ecliptic = Engine.VSOP87B.toEquatorial.inverse.apply(to: state)
        return (SIMD3(ecliptic.x, ecliptic.y, ecliptic.z), SIMD3(ecliptic.vx, ecliptic.vy, ecliptic.vz))
    }
}
