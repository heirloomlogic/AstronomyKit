//
//  EngineNutation.swift
//  AstronomyKit
//
//  IAU 2006/2000A nutation, its shared cache, and Earth's tilt at a TT instant.
//

import Foundation

extension Engine {
    /// The IAU 2000A nutation model (Mathews, Herring and Buffett 2002) with
    /// the IAU 2006 adjustments (Wallace and Capitaine 2006), as SOFA's
    /// `iauNut06a` evaluates it: 678 luni-solar and 687 planetary terms, free
    /// core nutation omitted.
    enum Nutation {}
}

extension Engine.Nutation {
    /// One luni-solar term.
    ///
    /// The argument is `nl·l + nlp·l′ + nf·F + nd·D + nom·Ω`, the Delaunay
    /// arguments. The coefficients are in units of 0.1 microarcsecond, and
    /// the `t` coefficients per Julian century: the term adds
    /// `(ps + pst·t)·sin + pc·cos` to the longitude and
    /// `(ec + ect·t)·cos + es·sin` to the obliquity.
    struct LuniSolarTerm: Sendable {
        let nl, nlp, nf, nd, nom: Double
        let ps, pst, pc: Double
        let ec, ect, es: Double

        init(
            _ nl: Double, _ nlp: Double, _ nf: Double, _ nd: Double, _ nom: Double,
            _ ps: Double, _ pst: Double, _ pc: Double, _ ec: Double, _ ect: Double, _ es: Double
        ) {
            (self.nl, self.nlp, self.nf, self.nd, self.nom) = (nl, nlp, nf, nd, nom)
            (self.ps, self.pst, self.pc) = (ps, pst, pc)
            (self.ec, self.ect, self.es) = (ec, ect, es)
        }
    }

    /// One planetary term.
    ///
    /// The argument combines l, F, D and Ω, the mean longitudes of Mercury
    /// through Neptune, and the general precession in longitude, in that
    /// order. The coefficients are in units of 0.1 microarcsecond: the term
    /// adds `ps·sin + pc·cos` to the longitude and `es·sin + ec·cos` to the
    /// obliquity.
    struct PlanetaryTerm: Sendable {
        let nl, nf, nd, nom: Double
        let nme, nve, nea, nma, nju, nsa, nur, nne, npa: Double
        let ps, pc, es, ec: Double

        init(
            _ nl: Double, _ nf: Double, _ nd: Double, _ nom: Double,
            _ nme: Double, _ nve: Double, _ nea: Double, _ nma: Double, _ nju: Double,
            _ nsa: Double, _ nur: Double, _ nne: Double, _ npa: Double,
            _ ps: Double, _ pc: Double, _ es: Double, _ ec: Double
        ) {
            (self.nl, self.nf, self.nd, self.nom) = (nl, nf, nd, nom)
            (self.nme, self.nve, self.nea, self.nma, self.nju) = (nme, nve, nea, nma, nju)
            (self.nsa, self.nur, self.nne, self.npa) = (nsa, nur, nne, npa)
            (self.ps, self.pc, self.es, self.ec) = (ps, pc, es, ec)
        }
    }

    /// The nutation in longitude (Δψ) and in obliquity (Δε) in degrees, and
    /// their rates in degrees per TT day.
    struct Angles: Equatable, Sendable {
        var longitude: Double
        var obliquity: Double
        var longitudeRate: Double
        var obliquityRate: Double
    }

    /// The Delaunay arguments of the luni-solar series as polynomials in
    /// arcseconds, constant term first, in Julian centuries: l, F and Ω from
    /// the IERS Conventions 2003 (`iauFal03`, `iauFaf03`, `iauFaom03`), and
    /// l′ and D from MHB2000, as `iauNut00a` takes them.
    private static let luniSolarArguments: [[Double]] = [
        [485_868.249_036, 1_717_915_923.217_8, 31.879_2, 0.051_635, -0.000_244_70],
        [1_287_104.793_05, 129_596_581.048_1, -0.553_2, 0.000_136, -0.000_011_49],
        [335_779.526_232, 1_739_527_262.847_8, -12.751_2, -0.001_037, 0.000_004_17],
        [1_072_260.703_69, 1_602_961_601.209_0, -6.370_6, 0.006_593, -0.000_031_69],
        [450_160.398_036, -6_962_890.543_1, 7.472_2, 0.007_702, -0.000_059_39],
    ]

    /// The linear arguments of the planetary series in radians at J2000 and
    /// per Julian century: l, F, D, Ω and Neptune from MHB2000, and Mercury
    /// through Uranus from the IERS Conventions 2003 (`iauFame03` through
    /// `iauFaur03`), as `iauNut00a` takes them. The general precession is
    /// ``generalPrecession``.
    private static let planetaryArguments: [(atJ2000: Double, perCentury: Double)] = [
        (2.355_555_98, 8_328.691_426_955_4),  // l
        (1.627_905_234, 8_433.466_158_131),  // F
        (5.198_466_741, 7_771.377_146_812_1),  // D
        (2.182_439_20, -33.757_045),  // Ω
        (4.402_608_842, 2_608.790_314_157_4),  // Mercury
        (3.176_146_697, 1_021.328_554_621_1),  // Venus
        (1.753_470_314, 628.307_584_999_1),  // Earth
        (6.203_480_913, 334.061_242_670_0),  // Mars
        (0.599_546_497, 52.969_096_264_1),  // Jupiter
        (0.874_016_757, 21.329_910_496_0),  // Saturn
        (5.481_293_872, 7.478_159_856_7),  // Uranus
        (5.321_159_000, 3.812_777_400_0),  // Neptune
    ]

    /// The rates of ``planetaryArguments`` in radians per Julian century.
    private static let planetaryRates = planetaryArguments.map(\.perCentury)

    /// The general precession in longitude, `iauFapa03`: (`linear` +
    /// `quadratic`·t)·t radians, t in Julian centuries.
    private static let generalPrecession = (linear: 0.024_381_750, quadratic: 0.000_005_386_91)

    /// Evaluates the series at `t` Julian centuries of TT from J2000.
    ///
    /// The values follow `iauNut06a` and `iauNut00a` term for term, each
    /// series summed smallest terms first; the rates are the derivatives of
    /// the same expressions.
    static func evaluate(centuries t: Double) -> Angles {
        // Luni-solar arguments in radians, and their rates per century.
        let angle = luniSolarArguments.map { c in
            fmod(c[0] + t * (c[1] + t * (c[2] + t * (c[3] + t * c[4]))), 1_296_000) * Engine.radiansPerArcsecond
        }
        let rate = luniSolarArguments.map { c in
            (c[1] + t * (2 * c[2] + t * (3 * c[3] + t * 4 * c[4]))) * Engine.radiansPerArcsecond
        }

        var dp = 0.0
        var de = 0.0
        var dpRate = 0.0
        var deRate = 0.0
        for term in luniSolarTerms.reversed() {
            let argument = fmod(
                term.nl * angle[0] + term.nlp * angle[1] + term.nf * angle[2] + term.nd * angle[3]
                    + term.nom * angle[4],
                2 * Double.pi
            )
            let argumentRate =
                term.nl * rate[0] + term.nlp * rate[1] + term.nf * rate[2] + term.nd * rate[3] + term.nom * rate[4]
            let s = sin(argument)
            let c = cos(argument)
            let p = term.ps + term.pst * t
            let e = term.ec + term.ect * t
            dp += p * s + term.pc * c
            de += e * c + term.es * s
            dpRate += term.pst * s + (p * c - term.pc * s) * argumentRate
            deRate += term.ect * c + (term.es * c - e * s) * argumentRate
        }

        // Planetary arguments: the linear ones, then the general precession.
        let planetary = planetaryArguments.map { fmod($0.atJ2000 + $0.perCentury * t, 2 * Double.pi) }
        let pa = (generalPrecession.linear + generalPrecession.quadratic * t) * t
        let paRate = generalPrecession.linear + 2 * generalPrecession.quadratic * t

        var pp = 0.0
        var pe = 0.0
        var ppRate = 0.0
        var peRate = 0.0
        for term in planetaryTerms.reversed() {
            let argument = fmod(combination(term, planetary, pa), 2 * Double.pi)
            let argumentRate = combination(term, planetaryRates, paRate)
            let s = sin(argument)
            let c = cos(argument)
            pp += term.ps * s + term.pc * c
            pe += term.es * s + term.ec * c
            ppRate += (term.ps * c - term.pc * s) * argumentRate
            peRate += (term.es * c - term.ec * s) * argumentRate
        }

        // 0.1 microarcsecond to radians, IAU 2000A as the sum of the two
        // series, then the IAU 2006 adjustments of `iauNut06a`.
        let unit = Engine.radiansPerArcsecond / 1e7
        let dpsi00 = dp * unit + pp * unit
        let deps00 = de * unit + pe * unit
        let dpsi00Rate = dpRate * unit + ppRate * unit
        let deps00Rate = deRate * unit + peRate * unit
        let fj2 = j2Rate * t
        let dpsi = dpsi00 + dpsi00 * (longitudeFactor + fj2)
        let deps = deps00 + deps00 * fj2
        let dpsiRate = dpsi00Rate + dpsi00Rate * (longitudeFactor + fj2) + dpsi00 * j2Rate
        let depsRate = deps00Rate + deps00Rate * fj2 + deps00 * j2Rate

        let perDay = Engine.degreesPerRadian / 36525
        return Angles(
            longitude: dpsi * Engine.degreesPerRadian,
            obliquity: deps * Engine.degreesPerRadian,
            longitudeRate: dpsiRate * perDay,
            obliquityRate: depsRate * perDay
        )
    }

    /// The multipliers of `term` applied to the twelve linear planetary
    /// arguments `a` and the general precession `pa`, summed in the order
    /// `iauNut00a` sums them.
    private static func combination(_ term: PlanetaryTerm, _ a: [Double], _ pa: Double) -> Double {
        var sum = term.nl * a[0]
        sum += term.nf * a[1]
        sum += term.nd * a[2]
        sum += term.nom * a[3]
        sum += term.nme * a[4]
        sum += term.nve * a[5]
        sum += term.nea * a[6]
        sum += term.nma * a[7]
        sum += term.nju * a[8]
        sum += term.nsa * a[9]
        sum += term.nur * a[10]
        sum += term.nne * a[11]
        return sum + term.npa * pa
    }

    /// The nutation shared by every engine caller: 32 entries keyed by the
    /// exact Julian centuries the series reads.
    static let cache = Engine.BoundedCache<Engine.ExactKey, Angles>(capacity: 32, registry: .shared)

    /// The nutation angles and rates at `tt` days of TT from J2000.
    ///
    /// Values and rates come from one evaluation, so a caller that needs
    /// only the angles warms the entry a rate caller reads. A `tt` whose
    /// centuries are not finite has no key: the series runs and nothing is
    /// stored.
    static func angles(
        tt: Double,
        cache: Engine.BoundedCache<Engine.ExactKey, Angles> = Engine.Nutation.cache
    ) -> Angles {
        let t = tt / 36525
        guard let key = Engine.ExactKey(t) else { return evaluate(centuries: t) }
        return cache.value(for: key) { evaluate(centuries: t) }
    }
}

// MARK: - Earth's tilt

extension Engine {
    /// The orientation of Earth's equator at one TT instant: nutation and
    /// the IAU 2006 mean obliquity, with their rates.
    struct EarthTilt: Sendable {
        /// The instant, in days of TT from J2000. Only
        /// ``equationOfEquinoxes`` reads it.
        var tt: Double

        var nutation: Nutation.Angles

        /// The mean obliquity of the ecliptic, εA, in degrees.
        var meanObliquity: Double

        /// The rate of ``meanObliquity`` in degrees per TT day.
        var meanObliquityRate: Double

        /// The true obliquity, εA + Δε, in degrees.
        var trueObliquity: Double { meanObliquity + nutation.obliquity }

        /// The rate of ``trueObliquity`` in degrees per TT day.
        var trueObliquityRate: Double { meanObliquityRate + nutation.obliquityRate }

        /// The equation of the equinoxes in degrees: Δψ·cos εA plus the
        /// complementary terms of IAU 1994 Resolution C7 (SOFA `iauEe00`).
        ///
        /// The complementary series is evaluated at each access, not stored
        /// with the cached nutation, so the rotations that never read this
        /// property do not pay for it.
        var equationOfEquinoxes: Double {
            let complementary = Nutation.complementaryEquationOfEquinoxes(centuries: tt / 36525)
            return nutation.longitude * cos(meanObliquity * Engine.radiansPerDegree)
                + complementary * Engine.degreesPerRadian
        }

        /// The nutation matrix N = R1(−εA − Δε)·R3(−Δψ)·R1(εA), from the mean
        /// equator and equinox of date to the true ones (SOFA `iauNumat`).
        var nutationRotation: Rotation<EQM, EQD> {
            let t = Terms(self)
            // Element (i, j) of N is rot[j][i], so `xy` is row y, column x of N.
            let xx = t.cpsi
            let yx = -t.spsi * t.cobm
            let zx = -t.spsi * t.sobm
            let xy = t.spsi * t.cobt
            let yy = t.cpsi * t.cobm * t.cobt + t.sobm * t.sobt
            let zy = t.cpsi * t.sobm * t.cobt - t.cobm * t.sobt
            let xz = t.spsi * t.sobt
            let yz = t.cpsi * t.cobm * t.sobt - t.sobm * t.cobt
            let zz = t.cpsi * t.sobm * t.sobt + t.cobm * t.cobt
            return Rotation(rot: ((xx, xy, xz), (yx, yy, yz), (zx, zy, zz)))
        }

        /// The derivative of ``nutationRotation`` per TT day, element by
        /// element.
        var nutationRate: RotationRate<EQM, EQD> {
            let t = Terms(self)
            let psiRate = nutation.longitudeRate * Engine.radiansPerDegree
            let meanRate = meanObliquityRate * Engine.radiansPerDegree
            let trueRate = trueObliquityRate * Engine.radiansPerDegree
            let dcpsi = -t.spsi * psiRate
            let dspsi = t.cpsi * psiRate
            let dcobm = -t.sobm * meanRate
            let dsobm = t.cobm * meanRate
            let dcobt = -t.sobt * trueRate
            let dsobt = t.cobt * trueRate
            // The product rule on each element of ``nutationRotation``.
            let xx = dcpsi
            let yx = -(dspsi * t.cobm + t.spsi * dcobm)
            let zx = -(dspsi * t.sobm + t.spsi * dsobm)
            let xy = dspsi * t.cobt + t.spsi * dcobt
            let yy =
                dcpsi * t.cobm * t.cobt + t.cpsi * dcobm * t.cobt + t.cpsi * t.cobm * dcobt + dsobm * t.sobt
                + t.sobm * dsobt
            let zy =
                dcpsi * t.sobm * t.cobt + t.cpsi * dsobm * t.cobt + t.cpsi * t.sobm * dcobt - dcobm * t.sobt
                - t.cobm * dsobt
            let xz = dspsi * t.sobt + t.spsi * dsobt
            let yz =
                dcpsi * t.cobm * t.sobt + t.cpsi * dcobm * t.sobt + t.cpsi * t.cobm * dsobt - dsobm * t.cobt
                - t.sobm * dcobt
            let zz =
                dcpsi * t.sobm * t.sobt + t.cpsi * dsobm * t.sobt + t.cpsi * t.sobm * dsobt + dcobm * t.cobt
                + t.cobm * dcobt
            return RotationRate(rot: ((xx, xy, xz), (yx, yy, yz), (zx, zy, zz)))
        }

        /// Sines and cosines of Δψ, εA and εA + Δε.
        private struct Terms {
            let cpsi, spsi, cobm, sobm, cobt, sobt: Double

            init(_ tilt: EarthTilt) {
                let psi = tilt.nutation.longitude * Engine.radiansPerDegree
                let mean = tilt.meanObliquity * Engine.radiansPerDegree
                let trueObliquity = tilt.trueObliquity * Engine.radiansPerDegree
                (cpsi, spsi) = (cos(psi), sin(psi))
                (cobm, sobm) = (cos(mean), sin(mean))
                (cobt, sobt) = (cos(trueObliquity), sin(trueObliquity))
            }
        }
    }
}

extension Engine.EarthTilt {
    /// The tilt at `tt` days of TT from J2000, with nutation read through
    /// `cache`.
    init(
        tt: Double,
        cache: Engine.BoundedCache<Engine.ExactKey, Engine.Nutation.Angles> = Engine.Nutation.cache
    ) {
        self.init(
            tt: tt,
            nutation: Engine.Nutation.angles(tt: tt, cache: cache),
            meanObliquity: Engine.Precession.meanObliquity(tt: tt),
            meanObliquityRate: Engine.Precession.meanObliquityRate(tt: tt)
        )
    }
}
