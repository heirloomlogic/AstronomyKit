//
//  EngineLunarSeries.swift
//  AstronomyKit
//
//  The lunar series outside the span of the DE440 Moon.
//

import Foundation

extension Engine {
    /// The geocentric Moon from the lunar series of Montenbruck and Pfleger,
    /// Astronomy on the Personal Computer, based on the Improved Lunar
    /// Ephemeris of 1954: long-period and planetary perturbations, 104 solar
    /// terms in longitude, latitude, parallax and the node, and the
    /// latitude's series N.
    ///
    /// The engine uses it outside the DE440 Moon's span; see
    /// ``MoonEphemeris``.
    enum LunarSeries {}
}

extension Engine.LunarSeries {
    /// The Moon's longitude and latitude in radians, on the mean ecliptic and
    /// equinox of date, and its distance in AU, at `t` Julian centuries of TT
    /// from J2000. The longitude is from 0 to 2π.
    ///
    /// A `t` that is not finite gives NaN coordinates.
    static func coordinates(centuries t: Double) -> SIMD3<Double> {
        var series = Series(t: t)
        for term in solarTerms {
            series.add(term)
        }
        series.addSolarN()
        series.addPlanetary()
        let s = series.f + series.ds / arc
        let latitudeSeconds =
            (1.000002708 + 139.978 * series.dgam) * (18_518.511 + 1.189 + series.gam1c) * sin(s) - 6.24 * sin(3 * s)
            + series.n
        return SIMD3(
            twoPi * fraction((series.l0 + series.dlam / arc) / twoPi),
            latitudeSeconds * (Engine.radiansPerDegree / 3600),
            (arc * earthEquatorialRadius) / (0.999953253 * series.sinpi)
        )
    }

    /// Arcseconds per radian.
    static let arc = 3600 * 180 / Double.pi

    private static let twoPi = 2 * Double.pi

    /// Earth's equatorial radius in AU: 6,378.1366 km, IERS Conventions
    /// (2010) Table 1.1, the radius the parallax refers to.
    static let earthEquatorialRadius = 6_378.1366 / Engine.kilometersPerAU

    private static func fraction(_ x: Double) -> Double {
        x - x.rounded(.down)
    }

    /// The sine of `phi` in revolutions.
    private static func sine(_ phi: Double) -> Double {
        sin(twoPi * phi)
    }

    /// One solar term: coefficients in longitude, the node term S, the
    /// latitude factor γ1C and the parallax, all in arcseconds, and the
    /// multiples of l, l′, F and D in its argument.
    struct Term: Sendable {
        let longitude, node, gamma, parallax: Double
        let p, q, r, s: Int

        init(
            _ longitude: Double, _ node: Double, _ gamma: Double, _ parallax: Double,
            _ p: Int, _ q: Int, _ r: Int, _ s: Int
        ) {
            (self.longitude, self.node, self.gamma, self.parallax) = (longitude, node, gamma, parallax)
            (self.p, self.q, self.r, self.s) = (p, q, r, s)
        }
    }

    /// The working state of one evaluation: the mean arguments, the sums,
    /// and cos and sin of each multiple of each argument.
    private struct Series {
        let t: Double
        var dgam = 0.0, dlam = 0.0, n = 0.0, gam1c = 0.0, sinpi = 3_422.7
        var l0 = 0.0, l = 0.0, ls = 0.0, f = 0.0, d = 0.0
        var dl0 = 0.0, dl = 0.0, dls = 0.0, df = 0.0, dd = 0.0, ds = 0.0
        /// Multiple `j` from −6 to 6 of argument `i` from 1 to 4 (l, l′, F,
        /// D) is at `(j + 6) * 4 + i - 1`.
        var co = [Double](repeating: 0, count: 52)
        var si = [Double](repeating: 0, count: 52)

        static func index(_ j: Int, _ i: Int) -> Int { (j + 6) * 4 + i - 1 }

        init(t: Double) {
            self.t = t
            longPeriodic()
            let t2 = t * t
            l0 = twoPi * fraction(0.60643382 + 1_336.85522467 * t - 0.00000313 * t2) + dl0 / arc
            l = twoPi * fraction(0.37489701 + 1_325.55240982 * t + 0.00002565 * t2) + dl / arc
            ls = twoPi * fraction(0.99312619 + 99.99735956 * t - 0.00000044 * t2) + dls / arc
            f = twoPi * fraction(0.25909118 + 1_342.22782980 * t - 0.00000892 * t2) + df / arc
            d = twoPi * fraction(0.82736186 + 1_236.85308708 * t - 0.00000397 * t2) + dd / arc
            for i in 1...4 {
                let argument: Double
                let maximum: Int
                let factor: Double
                switch i {
                case 1: (argument, maximum, factor) = (l, 4, 1.000002208)
                case 2: (argument, maximum, factor) = (ls, 3, 0.997504612 - 0.002495388 * t)
                case 3: (argument, maximum, factor) = (f, 4, 1.000002708 + 139.978 * dgam)
                default: (argument, maximum, factor) = (d, 6, 1.0)
                }
                co[Self.index(0, i)] = 1
                co[Self.index(1, i)] = cos(argument) * factor
                si[Self.index(0, i)] = 0
                si[Self.index(1, i)] = sin(argument) * factor
                for j in 2...maximum {
                    (co[Self.index(j, i)], si[Self.index(j, i)]) = Self.addThe(
                        co[Self.index(j - 1, i)], si[Self.index(j - 1, i)],
                        co[Self.index(1, i)], si[Self.index(1, i)])
                }
                for j in 1...maximum {
                    co[Self.index(-j, i)] = co[Self.index(j, i)]
                    si[Self.index(-j, i)] = -si[Self.index(j, i)]
                }
            }
        }

        /// The long-period perturbations, in arcseconds.
        private mutating func longPeriodic() {
            let s1 = sine(0.19833 + 0.05611 * t)
            let s2 = sine(0.27869 + 0.04508 * t)
            let s3 = sine(0.16827 - 0.36903 * t)
            let s4 = sine(0.34734 - 5.37261 * t)
            let s5 = sine(0.10498 - 5.37899 * t)
            let s6 = sine(0.42681 - 0.41855 * t)
            let s7 = sine(0.14943 - 5.37511 * t)
            dl0 = 0.84 * s1 + 0.31 * s2 + 14.27 * s3 + 7.26 * s4 + 0.28 * s5 + 0.24 * s6
            dl = 2.94 * s1 + 0.31 * s2 + 14.27 * s3 + 9.34 * s4 + 1.12 * s5 + 0.83 * s6
            dls = -6.40 * s1 - 1.89 * s6
            df = 0.21 * s1 + 0.31 * s2 + 14.27 * s3 - 88.70 * s4 - 15.30 * s5 + 0.24 * s6 - 1.86 * s7
            dd = dl0 - dls
            dgam =
                -3332e-9 * sine(0.59734 - 5.37261 * t) - 539e-9 * sine(0.35498 - 5.37899 * t)
                - 64e-9 * sine(0.39943 - 5.37511 * t)
        }

        /// cos and sin of the sum of two angles from cos and sin of each.
        static func addThe(_ c1: Double, _ s1: Double, _ c2: Double, _ s2: Double) -> (Double, Double) {
            (c1 * c2 - s1 * s2, s1 * c2 + c1 * s2)
        }

        /// cos and sin of p·l + q·l′ + r·F + s·D.
        func term(_ p: Int, _ q: Int, _ r: Int, _ s: Int) -> (x: Double, y: Double) {
            var (x, y) = (1.0, 0.0)
            for (k, multiple) in [p, q, r, s].enumerated() where multiple != 0 {
                (x, y) = Self.addThe(x, y, co[Self.index(multiple, k + 1)], si[Self.index(multiple, k + 1)])
            }
            return (x, y)
        }

        mutating func add(_ solar: Term) {
            let (x, y) = term(solar.p, solar.q, solar.r, solar.s)
            dlam += solar.longitude * y
            ds += solar.node * y
            gam1c += solar.gamma * x
            sinpi += solar.parallax * x
        }

        /// The solar series N of the latitude.
        mutating func addSolarN() {
            n = 0
            for (coefficient, p, q, r, s) in solarN {
                n += coefficient * term(p, q, r, s).y
            }
        }

        /// The planetary perturbations in longitude.
        mutating func addPlanetary() {
            var sum = 0.82 * sine(0.7736 - 62.5512 * t)
            sum += 0.31 * sine(0.0466 - 125.1025 * t)
            sum += 0.35 * sine(0.5785 - 25.1042 * t)
            sum += 0.66 * sine(0.4591 + 1_335.8075 * t)
            sum += 0.64 * sine(0.3130 - 91.5680 * t)
            sum += 1.14 * sine(0.1480 + 1_331.2898 * t)
            sum += 0.21 * sine(0.5918 + 1_056.5859 * t)
            sum += 0.44 * sine(0.5784 + 1_322.8595 * t)
            sum += 0.24 * sine(0.2275 - 5.7374 * t)
            sum += 0.28 * sine(0.2965 + 2.6929 * t)
            sum += 0.33 * sine(0.3132 + 6.3368 * t)
            dlam += sum
        }
    }

    /// The terms of N: the coefficient in arcseconds and the multiples of
    /// l, l′, F and D.
    private static let solarN: [(Double, Int, Int, Int, Int)] = [
        (-526.069, 0, 0, 1, -2),
        (-3.352, 0, 0, 1, -4),
        (44.297, 1, 0, 1, -2),
        (-6.000, 1, 0, 1, -4),
        (20.599, -1, 0, 1, 0),
        (-30.598, -1, 0, 1, -2),
        (-24.649, -2, 0, 1, 0),
        (-2.000, -2, 0, 1, -2),
        (-22.571, 0, 1, 1, -2),
        (10.985, 0, -1, 1, -2),
    ]

    /// The solar terms in the order the series adds them.
    static let solarTerms: [Term] = [
        Term(13.9020, 14.0600, -0.0010, 0.2607, 0, 0, 0, 4),
        Term(0.4030, -4.0100, 0.3940, 0.0023, 0, 0, 0, 3),
        Term(2_369.9120, 2_373.3600, 0.6010, 28.2333, 0, 0, 0, 2),
        Term(-125.1540, -112.7900, -0.7250, -0.9781, 0, 0, 0, 1),
        Term(1.9790, 6.9800, -0.4450, 0.0433, 1, 0, 0, 4),
        Term(191.9530, 192.7200, 0.0290, 3.0861, 1, 0, 0, 2),
        Term(-8.4660, -13.5100, 0.4550, -0.1093, 1, 0, 0, 1),
        Term(22_639.5000, 22_609.0700, 0.0790, 186.5398, 1, 0, 0, 0),
        Term(18.6090, 3.5900, -0.0940, 0.0118, 1, 0, 0, -1),
        Term(-4_586.4650, -4_578.1300, -0.0770, 34.3117, 1, 0, 0, -2),
        Term(3.2150, 5.4400, 0.1920, -0.0386, 1, 0, 0, -3),
        Term(-38.4280, -38.6400, 0.0010, 0.6008, 1, 0, 0, -4),
        Term(-0.3930, -1.4300, -0.0920, 0.0086, 1, 0, 0, -6),
        Term(-0.2890, -1.5900, 0.1230, -0.0053, 0, 1, 0, 4),
        Term(-24.4200, -25.1000, 0.0400, -0.3000, 0, 1, 0, 2),
        Term(18.0230, 17.9300, 0.0070, 0.1494, 0, 1, 0, 1),
        Term(-668.1460, -126.9800, -1.3020, -0.3997, 0, 1, 0, 0),
        Term(0.5600, 0.3200, -0.0010, -0.0037, 0, 1, 0, -1),
        Term(-165.1450, -165.0600, 0.0540, 1.9178, 0, 1, 0, -2),
        Term(-1.8770, -6.4600, -0.4160, 0.0339, 0, 1, 0, -4),
        Term(0.2130, 1.0200, -0.0740, 0.0054, 2, 0, 0, 4),
        Term(14.3870, 14.7800, -0.0170, 0.2833, 2, 0, 0, 2),
        Term(-0.5860, -1.2000, 0.0540, -0.0100, 2, 0, 0, 1),
        Term(769.0160, 767.9600, 0.1070, 10.1657, 2, 0, 0, 0),
        Term(1.7500, 2.0100, -0.0180, 0.0155, 2, 0, 0, -1),
        Term(-211.6560, -152.5300, 5.6790, -0.3039, 2, 0, 0, -2),
        Term(1.2250, 0.9100, -0.0300, -0.0088, 2, 0, 0, -3),
        Term(-30.7730, -34.0700, -0.3080, 0.3722, 2, 0, 0, -4),
        Term(-0.5700, -1.4000, -0.0740, 0.0109, 2, 0, 0, -6),
        Term(-2.9210, -11.7500, 0.7870, -0.0484, 1, 1, 0, 2),
        Term(1.2670, 1.5200, -0.0220, 0.0164, 1, 1, 0, 1),
        Term(-109.6730, -115.1800, 0.4610, -0.9490, 1, 1, 0, 0),
        Term(-205.9620, -182.3600, 2.0560, 1.4437, 1, 1, 0, -2),
        Term(0.2330, 0.3600, 0.0120, -0.0025, 1, 1, 0, -3),
        Term(-4.3910, -9.6600, -0.4710, 0.0673, 1, 1, 0, -4),
        Term(0.2830, 1.5300, -0.1110, 0.0060, 1, -1, 0, 4),
        Term(14.5770, 31.7000, -1.5400, 0.2302, 1, -1, 0, 2),
        Term(147.6870, 138.7600, 0.6790, 1.1528, 1, -1, 0, 0),
        Term(-1.0890, 0.5500, 0.0210, 0.0000, 1, -1, 0, -1),
        Term(28.4750, 23.5900, -0.4430, -0.2257, 1, -1, 0, -2),
        Term(-0.2760, -0.3800, -0.0060, -0.0036, 1, -1, 0, -3),
        Term(0.6360, 2.2700, 0.1460, -0.0102, 1, -1, 0, -4),
        Term(-0.1890, -1.6800, 0.1310, -0.0028, 0, 2, 0, 2),
        Term(-7.4860, -0.6600, -0.0370, -0.0086, 0, 2, 0, 0),
        Term(-8.0960, -16.3500, -0.7400, 0.0918, 0, 2, 0, -2),
        Term(-5.7410, -0.0400, 0.0000, -0.0009, 0, 0, 2, 2),
        Term(0.2550, 0.0000, 0.0000, 0.0000, 0, 0, 2, 1),
        Term(-411.6080, -0.2000, 0.0000, -0.0124, 0, 0, 2, 0),
        Term(0.5840, 0.8400, 0.0000, 0.0071, 0, 0, 2, -1),
        Term(-55.1730, -52.1400, 0.0000, -0.1052, 0, 0, 2, -2),
        Term(0.2540, 0.2500, 0.0000, -0.0017, 0, 0, 2, -3),
        Term(0.0250, -1.6700, 0.0000, 0.0031, 0, 0, 2, -4),
        Term(1.0600, 2.9600, -0.1660, 0.0243, 3, 0, 0, 2),
        Term(36.1240, 50.6400, -1.3000, 0.6215, 3, 0, 0, 0),
        Term(-13.1930, -16.4000, 0.2580, -0.1187, 3, 0, 0, -2),
        Term(-1.1870, -0.7400, 0.0420, 0.0074, 3, 0, 0, -4),
        Term(-0.2930, -0.3100, -0.0020, 0.0046, 3, 0, 0, -6),
        Term(-0.2900, -1.4500, 0.1160, -0.0051, 2, 1, 0, 2),
        Term(-7.6490, -10.5600, 0.2590, -0.1038, 2, 1, 0, 0),
        Term(-8.6270, -7.5900, 0.0780, -0.0192, 2, 1, 0, -2),
        Term(-2.7400, -2.5400, 0.0220, 0.0324, 2, 1, 0, -4),
        Term(1.1810, 3.3200, -0.2120, 0.0213, 2, -1, 0, 2),
        Term(9.7030, 11.6700, -0.1510, 0.1268, 2, -1, 0, 0),
        Term(-0.3520, -0.3700, 0.0010, -0.0028, 2, -1, 0, -1),
        Term(-2.4940, -1.1700, -0.0030, -0.0017, 2, -1, 0, -2),
        Term(0.3600, 0.2000, -0.0120, -0.0043, 2, -1, 0, -4),
        Term(-1.1670, -1.2500, 0.0080, -0.0106, 1, 2, 0, 0),
        Term(-7.4120, -6.1200, 0.1170, 0.0484, 1, 2, 0, -2),
        Term(-0.3110, -0.6500, -0.0320, 0.0044, 1, 2, 0, -4),
        Term(0.7570, 1.8200, -0.1050, 0.0112, 1, -2, 0, 2),
        Term(2.5800, 2.3200, 0.0270, 0.0196, 1, -2, 0, 0),
        Term(2.5330, 2.4000, -0.0140, -0.0212, 1, -2, 0, -2),
        Term(-0.3440, -0.5700, -0.0250, 0.0036, 0, 3, 0, -2),
        Term(-0.9920, -0.0200, 0.0000, 0.0000, 1, 0, 2, 2),
        Term(-45.0990, -0.0200, 0.0000, -0.0010, 1, 0, 2, 0),
        Term(-0.1790, -9.5200, 0.0000, -0.0833, 1, 0, 2, -2),
        Term(-0.3010, -0.3300, 0.0000, 0.0014, 1, 0, 2, -4),
        Term(-6.3820, -3.3700, 0.0000, -0.0481, 1, 0, -2, 2),
        Term(39.5280, 85.1300, 0.0000, -0.7136, 1, 0, -2, 0),
        Term(9.3660, 0.7100, 0.0000, -0.0112, 1, 0, -2, -2),
        Term(0.2020, 0.0200, 0.0000, 0.0000, 1, 0, -2, -4),
        Term(0.4150, 0.1000, 0.0000, 0.0013, 0, 1, 2, 0),
        Term(-2.1520, -2.2600, 0.0000, -0.0066, 0, 1, 2, -2),
        Term(-1.4400, -1.3000, 0.0000, 0.0014, 0, 1, -2, 2),
        Term(0.3840, -0.0400, 0.0000, 0.0000, 0, 1, -2, -2),
        Term(1.9380, 3.6000, -0.1450, 0.0401, 4, 0, 0, 0),
        Term(-0.9520, -1.5800, 0.0520, -0.0130, 4, 0, 0, -2),
        Term(-0.5510, -0.9400, 0.0320, -0.0097, 3, 1, 0, 0),
        Term(-0.4820, -0.5700, 0.0050, -0.0045, 3, 1, 0, -2),
        Term(0.6810, 0.9600, -0.0260, 0.0115, 3, -1, 0, 0),
        Term(-0.2970, -0.2700, 0.0020, -0.0009, 2, 2, 0, -2),
        Term(0.2540, 0.2100, -0.0030, 0.0000, 2, -2, 0, -2),
        Term(-0.2500, -0.2200, 0.0040, 0.0014, 1, 3, 0, -2),
        Term(-3.9960, 0.0000, 0.0000, 0.0004, 2, 0, 2, 0),
        Term(0.5570, -0.7500, 0.0000, -0.0090, 2, 0, 2, -2),
        Term(-0.4590, -0.3800, 0.0000, -0.0053, 2, 0, -2, 2),
        Term(-1.2980, 0.7400, 0.0000, 0.0004, 2, 0, -2, 0),
        Term(0.5380, 1.1400, 0.0000, -0.0141, 2, 0, -2, -2),
        Term(0.2630, 0.0200, 0.0000, 0.0000, 1, 1, 2, 0),
        Term(0.4260, 0.0700, 0.0000, -0.0006, 1, 1, -2, -2),
        Term(-0.3040, 0.0300, 0.0000, 0.0003, 1, -1, 2, 0),
        Term(-0.3720, -0.1900, 0.0000, -0.0027, 1, -1, -2, 2),
        Term(0.4180, 0.0000, 0.0000, 0.0000, 0, 0, 4, 0),
        Term(-0.3300, -0.0400, 0.0000, 0.0000, 3, 0, 2, 0),
    ]
}
