//
//  EngineNutation.swift
//  AstronomyKit
//
//  IAU 2000B nutation, its shared cache, and Earth's tilt at a TT instant.
//

import Foundation

extension Engine {
    /// The IAU 2000B nutation model (McCarthy and Luzum 2003), as SOFA's
    /// `iauNut00b` evaluates it: 77 luni-solar terms plus fixed offsets in
    /// place of the planetary terms.
    enum Nutation {}
}

extension Engine.Nutation {
    /// One luni-solar term.
    ///
    /// The argument is `nl·l + nlp·l′ + nf·F + nd·D + nom·Ω`, the Delaunay
    /// arguments of Simon et al. (1994). The coefficients are in units of 0.1
    /// microarcsecond, and the `t` coefficients per Julian century: the term
    /// adds `(ps + pst·t)·sin + pc·cos` to the longitude and
    /// `(ec + ect·t)·cos + es·sin` to the obliquity.
    struct Term: Sendable {
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

    /// The nutation in longitude (Δψ) and in obliquity (Δε) in degrees, and
    /// their rates in degrees per TT day.
    struct Angles: Equatable, Sendable {
        var longitude: Double
        var obliquity: Double
        var longitudeRate: Double
        var obliquityRate: Double
    }

    /// The Delaunay arguments l, l′, F, D and Ω of Simon et al. (1994), in
    /// arcseconds at J2000 and per Julian century. IAU 2000B uses only these
    /// linear terms.
    private static let delaunayArguments: [(atJ2000: Double, perCentury: Double)] = [
        (485_868.249_036, 1_717_915_923.217_8),  // mean anomaly of the Moon
        (1_287_104.793_05, 129_596_581.048_1),  // mean anomaly of the Sun
        (335_779.526_232, 1_739_527_262.847_8),  // Moon's mean argument of latitude
        (1_072_260.703_69, 1_602_961_601.209_0),  // mean elongation of the Moon from the Sun
        (450_160.398_036, -6_962_890.543_1),  // mean longitude of the Moon's ascending node
    ]

    /// The rates of ``delaunayArguments`` in radians per Julian century.
    private static let delaunayRates = delaunayArguments.map { $0.perCentury * Engine.radiansPerArcsecond }

    /// Evaluates the series at `t` Julian centuries of TT from J2000.
    ///
    /// The values follow `iauNut00b` term for term, smallest terms first;
    /// the rates are the derivatives of the same expressions.
    static func evaluate(centuries t: Double) -> Angles {
        let angle = delaunayArguments.map {
            fmod($0.atJ2000 + $0.perCentury * t, 1_296_000) * Engine.radiansPerArcsecond
        }
        let rate = delaunayRates

        var dp = 0.0
        var de = 0.0
        var dpRate = 0.0
        var deRate = 0.0
        for term in terms.reversed() {
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

        // 0.1 microarcsecond to degrees, and the fixed planetary offsets of
        // -0.135 and +0.388 milliarcseconds.
        let unit = 1.0e-7 / 3600
        let perDay = unit / 36525
        return Angles(
            longitude: dp * unit - 0.135e-3 / 3600,
            obliquity: de * unit + 0.388e-3 / 3600,
            longitudeRate: dpRate * perDay,
            obliquityRate: deRate * perDay
        )
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
        var nutation: Nutation.Angles

        /// The mean obliquity of the ecliptic, εA, in degrees.
        var meanObliquity: Double

        /// The rate of ``meanObliquity`` in degrees per TT day.
        var meanObliquityRate: Double

        /// The true obliquity, εA + Δε, in degrees.
        var trueObliquity: Double { meanObliquity + nutation.obliquity }

        /// The rate of ``trueObliquity`` in degrees per TT day.
        var trueObliquityRate: Double { meanObliquityRate + nutation.obliquityRate }

        /// The equation of the equinoxes, Δψ·cos εA, in degrees.
        ///
        /// This leaves out the complementary terms of the published definition
        /// (SOFA `iauEect00`), as the C engine does. They stay below 3
        /// milliarcseconds; #170 tracks adding them.
        var equationOfEquinoxes: Double {
            nutation.longitude * cos(meanObliquity * Engine.radiansPerDegree)
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
            nutation: Engine.Nutation.angles(tt: tt, cache: cache),
            meanObliquity: Engine.Precession.meanObliquity(tt: tt),
            meanObliquityRate: Engine.Precession.meanObliquityRate(tt: tt)
        )
    }
}
