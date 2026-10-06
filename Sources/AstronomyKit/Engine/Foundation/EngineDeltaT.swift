//
//  EngineDeltaT.swift
//  AstronomyKit
//
//  The two Delta T models: Espenak-Meeus and the JPL Horizons approximation.
//

extension Engine {
    /// Delta T, the difference TT − UT in seconds, under each ``DeltaTModel``.
    enum DeltaT {
        /// Days per tropical year, used to turn UT days into the decimal year
        /// the Espenak-Meeus polynomials take.
        static let daysPerTropicalYear = 365.24217

        /// TT − UT in seconds at modeled UT1 `ut` days since J2000.
        static func seconds(ut: Double, model: DeltaTModel) -> Double {
            switch model {
            case .espenakMeeus: espenakMeeus(ut: ut)
            case .jplHorizons: jplHorizons(ut: ut)
            }
        }

        /// The piecewise polynomials of Espenak and Meeus, "Five Millennium
        /// Canon of Solar Eclipses" (NASA/TP-2006-214141), as published at
        /// https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html.
        ///
        /// The decimal year is `2000 + (ut - 14) / daysPerTropicalYear`, so
        /// year 2000.0 falls on 2000-01-15 12:00 UT. NASA defines the year of
        /// a month as `year + (month - 0.5) / 12`, which puts 2000.0 at the
        /// start of January; see `NATIVE_ENGINE.md`. Each piece covers its
        /// years from the lower bound up to, not including, the next.
        static func espenakMeeus(ut: Double) -> Double {
            let y = 2000 + (ut - 14) / daysPerTropicalYear

            if y < -500 {
                let u = (y - 1820) / 100
                return -20 + (32 * u * u)
            }
            if y < 500 {
                let u = y / 100
                let p = Powers(u)
                return 10583.6 - 1014.41 * u + 33.78311 * p.u2 - 5.952053 * p.u3 - 0.1798452 * p.u4 + 0.022174192 * p.u5
                    + 0.0090316521 * p.u6
            }
            if y < 1600 {
                let u = (y - 1000) / 100
                let p = Powers(u)
                return 1574.2 - 556.01 * u + 71.23472 * p.u2 + 0.319781 * p.u3 - 0.8503463 * p.u4 - 0.005050998 * p.u5
                    + 0.0083572073 * p.u6
            }
            if y < 1700 {
                let u = y - 1600
                let p = Powers(u)
                return 120 - 0.9808 * u - 0.01532 * p.u2 + p.u3 / 7129.0
            }
            if y < 1800 {
                let u = y - 1700
                let p = Powers(u)
                return 8.83 + 0.1603 * u - 0.0059285 * p.u2 + 0.00013336 * p.u3 - p.u4 / 1_174_000
            }
            if y < 1860 {
                let u = y - 1800
                let p = Powers(u)
                return 13.72 - 0.332447 * u + 0.0068612 * p.u2 + 0.0041116 * p.u3 - 0.00037436 * p.u4
                    + 0.0000121272 * p.u5 - 0.0000001699 * p.u6 + 0.000000000875 * p.u7
            }
            if y < 1900 {
                let u = y - 1860
                let p = Powers(u)
                return 7.62 + 0.5737 * u - 0.251754 * p.u2 + 0.01680668 * p.u3 - 0.0004473624 * p.u4 + p.u5 / 233_174
            }
            if y < 1920 {
                let u = y - 1900
                let p = Powers(u)
                return -2.79 + 1.494119 * u - 0.0598939 * p.u2 + 0.0061966 * p.u3 - 0.000197 * p.u4
            }
            if y < 1941 {
                let u = y - 1920
                let p = Powers(u)
                return 21.20 + 0.84493 * u - 0.076100 * p.u2 + 0.0020936 * p.u3
            }
            if y < 1961 {
                let u = y - 1950
                let p = Powers(u)
                return 29.07 + 0.407 * u - p.u2 / 233 + p.u3 / 2547
            }
            if y < 1986 {
                let u = y - 1975
                let p = Powers(u)
                return 45.45 + 1.067 * u - p.u2 / 260 - p.u3 / 718
            }
            if y < 2005 {
                let u = y - 2000
                let p = Powers(u)
                return 63.86 + 0.3345 * u - 0.060374 * p.u2 + 0.0017275 * p.u3 + 0.000651814 * p.u4
                    + 0.00002373599 * p.u5
            }
            if y < 2050 {
                let u = y - 2000
                return 62.92 + 0.32217 * u + 0.005589 * u * u
            }
            if y < 2150 {
                let u = (y - 1820) / 100
                return -20 + 32 * u * u - 0.5628 * (2150 - y)
            }
            // After 2150, and for a NaN year, which fails every comparison.
            let u = (y - 1820) / 100
            return -20 + (32 * u * u)
        }

        /// Powers of `u`, each built from lower powers as `astronomy.c` builds them.
        private struct Powers {
            let u2: Double
            let u3: Double
            let u4: Double
            let u5: Double
            let u6: Double
            let u7: Double

            init(_ u: Double) {
                u2 = u * u
                u3 = u * u2
                u4 = u2 * u2
                u5 = u2 * u3
                u6 = u3 * u3
                u7 = u3 * u4
            }
        }

        /// The library's approximation of the Delta T that JPL Horizons used:
        /// Espenak-Meeus with UT held at 17 tropical years after J2000, so
        /// Delta T stops growing after early 2017.
        ///
        /// It is not a published model, and it is not the civil UTC
        /// leap-second table.
        static func jplHorizons(ut: Double) -> Double {
            let limit = 17.0 * daysPerTropicalYear
            return espenakMeeus(ut: ut > limit ? limit : ut)
        }
    }
}
