import Foundation

extension Engine.ApparentPlace {
    /// Second-order analytic differentiation, with independent variable reception TT in days.
    /// UT advances at the same rate: the observation's Delta T is held fixed.
    struct SecondOrder: Sendable {
        var value: Double
        var rate: Double
        var acceleration: Double
        init(_ value: Double, _ rate: Double = 0, _ acceleration: Double = 0) {
            self.value = value
            self.rate = rate
            self.acceleration = acceleration
        }
        static func + (a: Self, b: Self) -> Self {
            Self(a.value + b.value, a.rate + b.rate, a.acceleration + b.acceleration)
        }
        static prefix func - (a: Self) -> Self { Self(-a.value, -a.rate, -a.acceleration) }
        static func - (a: Self, b: Self) -> Self {
            Self(a.value - b.value, a.rate - b.rate, a.acceleration - b.acceleration)
        }
        static func * (a: Self, b: Self) -> Self {
            Self(
                a.value * b.value, a.rate * b.value + a.value * b.rate,
                a.acceleration * b.value + 2 * a.rate * b.rate + a.value * b.acceleration)
        }
        static func * (a: Self, s: Double) -> Self {
            Self(a.value * s, a.rate * s, a.acceleration * s)
        }
        static func * (s: Double, a: Self) -> Self {
            Self(a.value * s, a.rate * s, a.acceleration * s)
        }
        static func / (a: Self, b: Self) -> Self {
            let inv = 1 / b.value
            let inv2 = inv * inv
            return a * Self(inv, -b.rate * inv2, (2 * b.rate * b.rate * inv - b.acceleration) * inv2)
        }
        func sincos() -> (s: Self, c: Self) {
            let sv = Foundation.sin(value)
            let cv = Foundation.cos(value)
            let r2 = rate * rate
            return (
                Self(sv, cv * rate, cv * acceleration - sv * r2),
                Self(cv, -sv * rate, -sv * acceleration - cv * r2)
            )
        }
        func sin() -> Self {
            let sv = Foundation.sin(value)
            let cv = Foundation.cos(value)
            return Self(sv, cv * rate, cv * acceleration - sv * rate * rate)
        }
        func cos() -> Self {
            let sv = Foundation.sin(value)
            let cv = Foundation.cos(value)
            return Self(cv, -sv * rate, -sv * acceleration - cv * rate * rate)
        }
        func sqrt() -> Self {
            let root = Foundation.sqrt(value)
            let first = rate / (2 * root)
            return Self(root, first, (acceleration - 2 * first * first) / (2 * root))
        }
        func atan2(_ x: Self) -> Self {
            let d = x.value * x.value + value * value
            let n = x.value * rate - value * x.rate
            return Self(
                Foundation.atan2(value, x.value), n / d,
                (x.value * acceleration - value * x.acceleration) / d
                    - 2 * (x.value * x.rate + value * rate) * n / (d * d))
        }
        func reduced(_ period: Double) -> Self {
            Self(fmod(value, period), rate, acceleration)
        }
        static func polynomial(_ c: [Double], at t: Self) -> Self {
            var result = Self(0)
            for index in stride(from: c.count - 1, through: 0, by: -1) {
                result = result * t + Self(c[index])
            }
            return result
        }
    }

    private struct Vec3J: Sendable {
        var x: SecondOrder
        var y: SecondOrder
        var z: SecondOrder

        static func dot(_ a: Self, _ b: Self) -> SecondOrder {
            a.x * b.x + a.y * b.y + a.z * b.z
        }
        static func cross(_ a: Self, _ b: Self) -> Self {
            Self(
                x: a.y * b.z - a.z * b.y,
                y: a.z * b.x - a.x * b.z,
                z: a.x * b.y - a.y * b.x)
        }
    }

    private struct NutationSecondOrder: Sendable {
        let longitude: SecondOrder
        let obliquity: SecondOrder
        let complementary: SecondOrder
    }

    private static let nutationSecondOrderCache = Engine.BoundedCache<Engine.ExactKey, NutationSecondOrder>(
        capacity: 32, registry: .shared)

    private static let sinEps0 = sin(Engine.Precession.obliquityAtJ2000 * Engine.radiansPerArcsecond)
    private static let cosEps0 = cos(Engine.Precession.obliquityAtJ2000 * Engine.radiansPerArcsecond)
    private static let luniSolarSmallestFirst: [Engine.Nutation.LuniSolarTerm] = Array(
        Engine.Nutation.luniSolarTerms.reversed())
    private static let planetarySmallestFirst: [Engine.Nutation.PlanetaryTerm] = Array(
        Engine.Nutation.planetaryTerms.reversed())

    private static func precessionKinematics(
        tt: Double
    ) -> (x: Vec3J, y: Vec3J, z: Vec3J, obliquity: SecondOrder) {
        typealias J = SecondOrder
        let t = J(tt / 36525, 1 / 36525)
        func pole(_ polynomial: [[Double]], _ periodic: [[Double]]) -> Vec3J {
            var x = J(0)
            var y = J(0)
            let twoPi = 2 * Double.pi
            for term in periodic {
                let freq = twoPi / term[0]
                let angle = t * freq
                let (s, c) = angle.sincos()
                x = x + c * term[1] + s * term[3]
                y = y + c * term[2] + s * term[4]
            }
            x = (x + J.polynomial(polynomial[0], at: t)) * Engine.radiansPerArcsecond
            y = (y + J.polynomial(polynomial[1], at: t)) * Engine.radiansPerArcsecond
            return Vec3J(x: x, y: y, z: (J(1) - x * x - y * y).sqrt())
        }
        let z = pole(Engine.Precession.equatorPolynomial, Engine.Precession.equatorPeriodic)
        let local = pole(Engine.Precession.eclipticPolynomial, Engine.Precession.eclipticPeriodic)
        let e = Vec3J(
            x: local.x,
            y: -local.y * cosEps0 - local.z * sinEps0,
            z: -local.y * sinEps0 + local.z * cosEps0)
        let v = Vec3J.cross(z, e)
        let length = Vec3J.dot(v, v).sqrt()
        let x = Vec3J(x: v.x / length, y: v.y / length, z: v.z / length)
        return (x, Vec3J.cross(z, x), z, length.atan2(Vec3J.dot(z, e)))
    }

    private static func evaluateNutationKinematics(tt: Double) -> NutationSecondOrder {
        typealias J = SecondOrder
        let t = J(tt / 36525, 1 / 36525)
        let arcsec = Engine.radiansPerArcsecond
        let twoPi = 2 * Double.pi
        let ls = Engine.Nutation.luniSolarArguments
        let a0 = J.polynomial(ls[0], at: t).reduced(1_296_000) * arcsec
        let a1 = J.polynomial(ls[1], at: t).reduced(1_296_000) * arcsec
        let a2 = J.polynomial(ls[2], at: t).reduced(1_296_000) * arcsec
        let a3 = J.polynomial(ls[3], at: t).reduced(1_296_000) * arcsec
        let a4 = J.polynomial(ls[4], at: t).reduced(1_296_000) * arcsec

        var dp = J(0)
        var de = J(0)
        for term in luniSolarSmallestFirst {
            let arg = (a0 * term.nl + a1 * term.nlp + a2 * term.nf + a3 * term.nd + a4 * term.nom).reduced(twoPi)
            let (s, c) = arg.sincos()
            dp = dp + (J(term.ps) + t * term.pst) * s + c * term.pc
            de = de + (J(term.ec) + t * term.ect) * c + s * term.es
        }

        let paTable = Engine.Nutation.planetaryArguments
        @inline(__always)
        func pArg(_ index: Int) -> J {
            (J(paTable[index].atJ2000) + t * paTable[index].perCentury).reduced(twoPi)
        }
        let pl = pArg(0)
        let pf = pArg(1)
        let pd = pArg(2)
        let pom = pArg(3)
        let pme = pArg(4)
        let pve = pArg(5)
        let pea = pArg(6)
        let pma = pArg(7)
        let pju = pArg(8)
        let psa = pArg(9)
        let pur = pArg(10)
        let pne = pArg(11)
        let gp = Engine.Nutation.generalPrecession
        let pa = (J(gp.linear) + t * gp.quadratic) * t

        var pp = J(0)
        var pe = J(0)
        for term in planetarySmallestFirst {
            var arg = pl * term.nl + pf * term.nf + pd * term.nd + pom * term.nom
            arg = arg + pme * term.nme + pve * term.nve + pea * term.nea + pma * term.nma
            arg = (arg + pju * term.nju + psa * term.nsa + pur * term.nur + pne * term.nne + pa * term.npa).reduced(
                twoPi)
            let (s, c) = arg.sincos()
            pp = pp + s * term.ps + c * term.pc
            pe = pe + s * term.es + c * term.ec
        }

        let unit = arcsec / 1e7
        let fj2 = t * Engine.Nutation.j2Rate
        let p00 = dp * unit + pp * unit
        let e00 = de * unit + pe * unit
        let longitude = p00 + p00 * (J(Engine.Nutation.longitudeFactor) + fj2)
        let obliquity = e00 + e00 * fj2

        let values = Engine.Nutation.ComplementaryArguments(centuries: t.value)
        let c0 = J(values.l, a0.rate, a0.acceleration)
        let c1 = J(values.lp, a1.rate, a1.acceleration)
        let c2 = J(values.f, a2.rate, a2.acceleration)
        let c3 = J(values.d, a3.rate, a3.acceleration)
        let c4 = J(values.om, a4.rate, a4.acceleration)
        func sum(_ terms: [Engine.Nutation.ComplementaryTerm]) -> J {
            var result = J(0)
            for term in terms.reversed() {
                let arg =
                    c0 * term.l + c1 * term.lp + c2 * term.f + c3 * term.d + c4 * term.om
                    + pve * term.ve + pea * term.e + pa * term.pa
                let (s, c) = arg.sincos()
                result = result + s * term.s + c * term.c
            }
            return result
        }
        let complementary =
            (sum(Engine.Nutation.complementaryConstantTerms)
                + sum(Engine.Nutation.complementaryLinearTerms) * t) * arcsec
        return NutationSecondOrder(longitude: longitude, obliquity: obliquity, complementary: complementary)
    }

    private static func nutationKinematics(tt: Double) -> NutationSecondOrder {
        guard let key = Engine.ExactKey(tt) else { return evaluateNutationKinematics(tt: tt) }
        return nutationSecondOrderCache.value(for: key) { evaluateNutationKinematics(tt: tt) }
    }

    /// Fast first-order topocentric observer position and velocity on EQJ axes (reuses cached nutation and single-pass precession).
    /// Used by position-only callers (`equatorial`, `horizontal`, `EngineStar`) where acceleration does not enter the result.
    static func siteMotion(_ observer: Observer, at time: Engine.Time) throws -> VectorRate {
        try Engine.checkAcceptedTime(time)
        let latitude = observer.latitude * Engine.radiansPerDegree
        let f = Engine.Observers.polarRatio
        let sinLat = sin(latitude)
        let cosLat = cos(latitude)
        let c = 1 / hypot(cosLat, sinLat * f)
        let radius = Engine.Observers.equatorialRadiusKilometers
        let height = observer.height / 1000
        let xy = (radius * c + height) * cosLat / Engine.kilometersPerAU
        let z = (radius * c * f * f + height) * sinLat / Engine.kilometersPerAU
        if xy == 0 && z == 0 {
            return VectorRate(.zero)
        }
        let precession = Engine.Precession.frame(tt: time.tt)
        let tilt = Engine.EarthTilt(tt: time.tt, precession: precession)

        let t = time.tt / 36525
        let dt = 1.0 / 36525.0
        let siderealPoly =
            0.014_506
            + ((((-0.000_000_036_8 * t - 0.000_029_956) * t - 0.000_000_44) * t + 1.391_581_7) * t + 4_612.156_534) * t
        let siderealPolyRate =
            ((((-5 * 0.000_000_036_8 * t - 4 * 0.000_029_956) * t - 3 * 0.000_000_44) * t + 2 * 1.391_581_7) * t
                + 4_612.156_534) * (Engine.radiansPerArcsecond * dt)
        let gastDegrees =
            tilt.equationOfEquinoxes + siderealPoly / 3600 + Engine.EarthRotation.angle(ut: time.ut)
        let gastHours = Engine.normalized(fmod(gastDegrees, 360) / 15, period: 24)
        let angle = (15 * gastHours + observer.longitude) * Engine.radiansPerDegree

        // First-order complementary terms rate (34 terms, avoids full 1,365-term second-order nutation).
        func polyRate(_ c: [Double]) -> Double {
            var r = 0.0
            for i in stride(from: c.count - 1, through: 1, by: -1) { r = r * t + Double(i) * c[i] }
            return r * Engine.radiansPerArcsecond * dt
        }
        let values = Engine.Nutation.ComplementaryArguments(centuries: t)
        let lRate = polyRate(Engine.Nutation.luniSolarArguments[0])
        let lpRate = polyRate(Engine.Nutation.luniSolarArguments[1])
        let fRate = polyRate(Engine.Nutation.luniSolarArguments[2])
        let dRate = polyRate(Engine.Nutation.luniSolarArguments[3])
        let omRate = polyRate(Engine.Nutation.luniSolarArguments[4])
        let veBase = Engine.Nutation.planetaryArguments[5]
        let eaBase = Engine.Nutation.planetaryArguments[6]
        let pveVal = fmod(veBase.atJ2000 + veBase.perCentury * t, 2 * Double.pi)
        let pveRate = veBase.perCentury * dt
        let peaVal = fmod(eaBase.atJ2000 + eaBase.perCentury * t, 2 * Double.pi)
        let peaRate = eaBase.perCentury * dt
        let gp = Engine.Nutation.generalPrecession
        let paVal = (gp.linear + gp.quadratic * t) * t
        let paRate = (gp.linear + 2 * gp.quadratic * t) * dt
        func compSum(_ terms: [Engine.Nutation.ComplementaryTerm]) -> (value: Double, rate: Double) {
            var v = 0.0
            var r = 0.0
            for term in terms.reversed() {
                let arg =
                    values.l * term.l + values.lp * term.lp + values.f * term.f + values.d * term.d
                    + values.om * term.om + pveVal * term.ve + peaVal * term.e + paVal * term.pa
                let argRate =
                    lRate * term.l + lpRate * term.lp + fRate * term.f + dRate * term.d
                    + omRate * term.om + pveRate * term.ve + peaRate * term.e + paRate * term.pa
                let s = sin(arg)
                let c = cos(arg)
                v += s * term.s + c * term.c
                r += (c * term.s - s * term.c) * argRate
            }
            return (v, r)
        }
        let comp0 = compSum(Engine.Nutation.complementaryConstantTerms)
        let comp1 = compSum(Engine.Nutation.complementaryLinearTerms)
        let compRate = (comp0.rate + comp1.rate * t + comp1.value * dt) * Engine.radiansPerArcsecond

        let psi = ScalarRate(tilt.nutation.longitude * Engine.radiansPerDegree, tilt.nutation.longitudeRate * Engine.radiansPerDegree)
        let em = ScalarRate(tilt.meanObliquity * Engine.radiansPerDegree, tilt.meanObliquityRate * Engine.radiansPerDegree)
        let et = ScalarRate(tilt.trueObliquity * Engine.radiansPerDegree, tilt.trueObliquityRate * Engine.radiansPerDegree)
        @inline(__always)
        func srSinCos(_ a: ScalarRate) -> (s: ScalarRate, c: ScalarRate) {
            let sv = sin(a.value)
            let cv = cos(a.value)
            return (ScalarRate(sv, cv * a.rate), ScalarRate(cv, -sv * a.rate))
        }
        let (sp, cp) = srSinCos(psi)
        let (sm, cm) = srSinCos(em)
        let (st, ct) = srSinCos(et)
        let n00 = cp
        let n01 = ScalarRate(-sp.value, -sp.rate) * cm
        let n02 = ScalarRate(-sp.value, -sp.rate) * sm
        let n10 = sp * ct
        let n11 = cp * cm * ct + sm * st
        let n12 = cp * sm * ct - cm * st
        let n20 = sp * st
        let n21 = cp * cm * st - sm * ct
        let n22 = cp * sm * st + cm * ct

        let angleRate =
            2 * Double.pi * (1 + 0.002_737_811_911_354_48) + siderealPolyRate
            + psi.rate * cm.value + psi.value * cm.rate + compRate
        let (sinA, cosA) = srSinCos(ScalarRate(angle, angleRate))
        let ofDate0 = ScalarRate(cosA.value * xy, cosA.rate * xy)
        let ofDate1 = ScalarRate(sinA.value * xy, sinA.rate * xy)
        let ofDate2 = ScalarRate(z, 0)

        let mean0 = n00 * ofDate0 + n10 * ofDate1 + n20 * ofDate2
        let mean1 = n01 * ofDate0 + n11 * ofDate1 + n21 * ofDate2
        let mean2 = n02 * ofDate0 + n12 * ofDate1 + n22 * ofDate2

        let pr = precession.rotation.rot
        let dp = precession.rate.rot
        let eqj0 = ScalarRate(pr.0.0, dp.0.0) * mean0 + ScalarRate(pr.0.1, dp.0.1) * mean1 + ScalarRate(pr.0.2, dp.0.2) * mean2
        let eqj1 = ScalarRate(pr.1.0, dp.1.0) * mean0 + ScalarRate(pr.1.1, dp.1.1) * mean1 + ScalarRate(pr.1.2, dp.1.2) * mean2
        let eqj2 = ScalarRate(pr.2.0, dp.2.0) * mean0 + ScalarRate(pr.2.1, dp.2.1) * mean1 + ScalarRate(pr.2.2, dp.2.2) * mean2

        let motion = VectorRate(
            SIMD3(eqj0.value, eqj1.value, eqj2.value),
            SIMD3(eqj0.rate, eqj1.rate, eqj2.rate))
        guard motion.isFinite else { throw AstronomyError.badVector }
        return motion
    }

    /// Differentiates the actual ellipsoid/GAST/precession/nutation path, including frame motion.
    /// The public observer-vector bits are retained; rates are analytic per TT day with Delta T fixed.
    static func siteKinematics(_ observer: Observer, at time: Engine.Time) throws -> Kinematics {
        try Engine.checkAcceptedTime(time)
        let latitude = observer.latitude * Engine.radiansPerDegree
        let f = Engine.Observers.polarRatio
        let sinLat = sin(latitude)
        let cosLat = cos(latitude)
        let c = 1 / hypot(cosLat, sinLat * f)
        let radius = Engine.Observers.equatorialRadiusKilometers
        let height = observer.height / 1000
        let xyValue = (radius * c + height) * cosLat / Engine.kilometersPerAU
        let zValue = (radius * c * f * f + height) * sinLat / Engine.kilometersPerAU
        if xyValue == 0 && zValue == 0 {
            return Kinematics(motion: VectorRate(.zero), acceleration: .zero)
        }
        typealias J = SecondOrder
        let precession = precessionKinematics(tt: time.tt)
        let nutation = nutationKinematics(tt: time.tt)
        let em = precession.obliquity
        let et = em + nutation.obliquity
        let (sp, cp) = nutation.longitude.sincos()
        let (sm, cm) = em.sincos()
        let (st, ct) = et.sincos()
        let n00 = cp
        let n01 = -sp * cm
        let n02 = -sp * sm
        let n10 = sp * ct
        let n11 = cp * cm * ct + sm * st
        let n12 = cp * sm * ct - cm * st
        let n20 = sp * st
        let n21 = cp * cm * st - sm * ct
        let n22 = cp * sm * st + cm * ct

        let t = J(time.tt / 36525, 1 / 36525)
        let siderealPolynomial = J.polynomial(
            [0.014506, 4612.156534, 1.3915817, -0.00000044, -0.000029956, -0.0000000368], at: t)
        let era = J(0, 2 * Double.pi * (1 + 0.00273781191135448))
        var angle =
            era + siderealPolynomial * Engine.radiansPerArcsecond
            + nutation.longitude * cm + nutation.complementary
        angle.value =
            (15 * Engine.EarthRotation.apparentSiderealTime(time) + observer.longitude) * Engine.radiansPerDegree

        let (sinA, cosA) = angle.sincos()
        let ofDate0 = cosA * xyValue
        let ofDate1 = sinA * xyValue
        let ofDate2 = J(zValue)

        let mean0 = n00 * ofDate0 + n10 * ofDate1 + n20 * ofDate2
        let mean1 = n01 * ofDate0 + n11 * ofDate1 + n21 * ofDate2
        let mean2 = n02 * ofDate0 + n12 * ofDate1 + n22 * ofDate2

        let eqj0 = precession.x.x * mean0 + precession.y.x * mean1 + precession.z.x * mean2
        let eqj1 = precession.x.y * mean0 + precession.y.y * mean1 + precession.z.y * mean2
        let eqj2 = precession.x.z * mean0 + precession.y.z * mean1 + precession.z.z * mean2

        let motion = VectorRate(
            SIMD3(eqj0.value, eqj1.value, eqj2.value),
            SIMD3(eqj0.rate, eqj1.rate, eqj2.rate))
        let acceleration = SIMD3(eqj0.acceleration, eqj1.acceleration, eqj2.acceleration)
        guard motion.isFinite, acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite else {
            throw AstronomyError.badVector
        }
        return Kinematics(motion: motion, acceleration: acceleration)
    }
}
