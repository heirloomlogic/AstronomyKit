import Foundation

extension Engine.ApparentPlace {
    /// Second-order analytic differentiation, with independent variable reception TT in days.
    /// UT advances at the same rate: the observation's Delta T is held fixed.
    struct SecondOrder {
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
        static func - (a: Self, b: Self) -> Self { a + -b }
        static func * (a: Self, b: Self) -> Self {
            Self(
                a.value * b.value, a.rate * b.value + a.value * b.rate,
                a.acceleration * b.value + 2 * a.rate * b.rate + a.value * b.acceleration)
        }
        static func / (a: Self, b: Self) -> Self {
            a
                * Self(
                    1 / b.value, -b.rate / (b.value * b.value),
                    (2 * b.rate * b.rate / b.value - b.acceleration) / (b.value * b.value))
        }
        func sin() -> Self {
            Self(
                Foundation.sin(value), Foundation.cos(value) * rate,
                Foundation.cos(value) * acceleration - Foundation.sin(value) * rate * rate)
        }
        func cos() -> Self {
            Self(
                Foundation.cos(value), -Foundation.sin(value) * rate,
                -Foundation.sin(value) * acceleration - Foundation.cos(value) * rate * rate)
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
            c.reversed().reduce(Self(0)) { $0 * t + Self($1) }
        }
    }

    private static func dot(_ a: [SecondOrder], _ b: [SecondOrder]) -> SecondOrder {
        zip(a, b).reduce(SecondOrder(0)) { $0 + $1.0 * $1.1 }
    }
    private static func cross(_ a: [SecondOrder], _ b: [SecondOrder]) -> [SecondOrder] {
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    }

    private static func precessionKinematics(tt: Double) -> (axes: [[SecondOrder]], obliquity: SecondOrder) {
        typealias J = SecondOrder
        let t = J(tt / 36525, 1 / 36525)
        func pole(_ polynomial: [[Double]], _ periodic: [[Double]]) -> [J] {
            var x = J(0)
            var y = J(0)
            for term in periodic {
                let angle = J(2 * Double.pi) * t / J(term[0])
                x = x + angle.cos() * J(term[1]) + angle.sin() * J(term[3])
                y = y + angle.cos() * J(term[2]) + angle.sin() * J(term[4])
            }
            x = (x + J.polynomial(polynomial[0], at: t)) * J(Engine.radiansPerArcsecond)
            y = (y + J.polynomial(polynomial[1], at: t)) * J(Engine.radiansPerArcsecond)
            return [x, y, (J(1) - x * x - y * y).sqrt()]
        }
        let z = pole(Engine.Precession.equatorPolynomial, Engine.Precession.equatorPeriodic)
        let local = pole(Engine.Precession.eclipticPolynomial, Engine.Precession.eclipticPeriodic)
        let eps0 = Engine.Precession.obliquityAtJ2000 * Engine.radiansPerArcsecond
        let c = J(cos(eps0))
        let s = J(sin(eps0))
        let e = [local[0], -local[1] * c - local[2] * s, -local[1] * s + local[2] * c]
        let v = cross(z, e)
        let length = dot(v, v).sqrt()
        let x = v.map { $0 / length }
        return ([x, cross(z, x), z], length.atan2(dot(z, e)))
    }

    private static func nutationKinematics(
        tt: Double
    ) -> (longitude: SecondOrder, obliquity: SecondOrder, complementary: SecondOrder) {
        typealias J = SecondOrder
        let t = J(tt / 36525, 1 / 36525)
        let arcsec = J(Engine.radiansPerArcsecond)
        let args = Engine.Nutation.luniSolarArguments.map {
            J.polynomial($0, at: t).reduced(1_296_000) * arcsec
        }
        var dp = J(0)
        var de = J(0)
        for term in Engine.Nutation.luniSolarTerms.reversed() {
            let a = dot([term.nl, term.nlp, term.nf, term.nd, term.nom].map { J($0) }, args).reduced(2 * Double.pi)
            dp = dp + (J(term.ps) + J(term.pst) * t) * a.sin() + J(term.pc) * a.cos()
            de = de + (J(term.ec) + J(term.ect) * t) * a.cos() + J(term.es) * a.sin()
        }
        let planetary = Engine.Nutation.planetaryArguments.map {
            (J($0.atJ2000) + J($0.perCentury) * t).reduced(2 * Double.pi)
        }
        let gp = Engine.Nutation.generalPrecession
        let pa = (J(gp.linear) + J(gp.quadratic) * t) * t
        var pp = J(0)
        var pe = J(0)
        for term in Engine.Nutation.planetaryTerms.reversed() {
            let coefficients = [
                term.nl, term.nf, term.nd, term.nom, term.nme, term.nve, term.nea, term.nma,
                term.nju, term.nsa, term.nur, term.nne, term.npa,
            ].map { J($0) }
            let a = dot(coefficients, planetary + [pa]).reduced(2 * Double.pi)
            pp = pp + J(term.ps) * a.sin() + J(term.pc) * a.cos()
            pe = pe + J(term.es) * a.sin() + J(term.ec) * a.cos()
        }
        let unit = J(Engine.radiansPerArcsecond / 1e7)
        let fj2 = J(Engine.Nutation.j2Rate) * t
        let p00 = dp * unit + pp * unit
        let e00 = de * unit + pe * unit
        let longitude = p00 + p00 * (J(Engine.Nutation.longitudeFactor) + fj2)
        let obliquity = e00 + e00 * fj2
        // IERS complementary arguments differ from the nutation arguments only in two constants.
        let values = Engine.Nutation.ComplementaryArguments(centuries: t.value)
        let constants = [values.l, values.lp, values.f, values.d, values.om]
        let delaunay = zip(args, constants).map { J($1, $0.rate, $0.acceleration) }
        let complementaryArgs = delaunay + [planetary[5], planetary[6], pa]
        func sum(_ terms: [Engine.Nutation.ComplementaryTerm]) -> J {
            var result = J(0)
            for term in terms.reversed() {
                let coefficients = [term.l, term.lp, term.f, term.d, term.om, term.ve, term.e, term.pa].map { J($0) }
                let a = dot(coefficients, complementaryArgs)
                result = result + J(term.s) * a.sin() + J(term.c) * a.cos()
            }
            return result
        }
        let complementary =
            (sum(Engine.Nutation.complementaryConstantTerms)
                + sum(Engine.Nutation.complementaryLinearTerms) * t) * arcsec
        return (longitude, obliquity, complementary)
    }

    /// Differentiates the actual ellipsoid/GAST/precession/nutation path, including frame motion.
    /// The public observer-vector bits are retained; rates are analytic per TT day with Delta T fixed.
    static func siteKinematics(_ observer: Observer, at time: Engine.Time) throws -> Kinematics {
        try Engine.checkAcceptedTime(time)
        typealias J = SecondOrder
        let precession = precessionKinematics(tt: time.tt)
        let nutation = nutationKinematics(tt: time.tt)
        let em = precession.obliquity
        let et = em + nutation.obliquity
        let cp = nutation.longitude.cos()
        let sp = nutation.longitude.sin()
        let cm = em.cos()
        let sm = em.sin()
        let ct = et.cos()
        let st = et.sin()
        let n = [
            [cp, -sp * cm, -sp * sm],
            [sp * ct, cp * cm * ct + sm * st, cp * sm * ct - cm * st],
            [sp * st, cp * cm * st - sm * ct, cp * sm * st + cm * ct],
        ]
        let t = J(time.tt / 36525, 1 / 36525)
        let siderealPolynomial = J.polynomial(
            [0.014506, 4612.156534, 1.3915817, -0.00000044, -0.000029956, -0.0000000368], at: t)
        let era = J(0, 2 * Double.pi * (1 + 0.00273781191135448))
        var angle =
            era + siderealPolynomial * J(Engine.radiansPerArcsecond)
            + nutation.longitude * em.cos() + nutation.complementary
        angle.value =
            (15 * Engine.EarthRotation.apparentSiderealTime(time) + observer.longitude) * Engine.radiansPerDegree
        let latitude = observer.latitude * Engine.radiansPerDegree
        let f = Engine.Observers.polarRatio
        let c = 1 / hypot(cos(latitude), sin(latitude) * f)
        let radius = Engine.Observers.equatorialRadiusKilometers
        let height = observer.height / 1000
        let xy = J((radius * c + height) * cos(latitude) / Engine.kilometersPerAU)
        let z = J((radius * c * f * f + height) * sin(latitude) / Engine.kilometersPerAU)
        let ofDate = [xy * angle.cos(), xy * angle.sin(), z]
        let mean = (0..<3).map { column in dot(n.map { $0[column] }, ofDate) }
        let eqj = (0..<3).map { column in dot(precession.axes.map { $0[column] }, mean) }
        let exact = Engine.Observers.vector(observer, at: time)
        let motion = VectorRate(SIMD3(exact.x, exact.y, exact.z), SIMD3(eqj[0].rate, eqj[1].rate, eqj[2].rate))
        let acceleration = SIMD3(eqj[0].acceleration, eqj[1].acceleration, eqj[2].acceleration)
        guard motion.isFinite, [acceleration.x, acceleration.y, acceleration.z].allSatisfy(\.isFinite) else {
            throw AstronomyError.badVector
        }
        return Kinematics(motion: motion, acceleration: acceleration)
    }
}
