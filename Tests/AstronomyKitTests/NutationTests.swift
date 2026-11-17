import CLibAstronomy
import Testing

/// The nutation series in `astronomy.c` against the published IAU 2000B series.
///
/// `iau2000b` sums the 77 terms by the angle addition formulas, without a cosine and a
/// sine for each term. These references come from the series evaluated the published
/// way, so they catch a wrong coefficient, a wrong multiple, and a wrong combination.
@Suite("Nutation")
struct NutationTests {
    struct Reference: Sendable, CustomTestStringConvertible {
        /// Terrestrial Time in days since J2000.
        let terrestrialTime: Double
        /// Nutation in longitude, in arcseconds.
        let psi: Double
        /// Nutation in obliquity, in arcseconds.
        let eps: Double

        var testDescription: String { "TT \(terrestrialTime)" }
    }

    /// The published routine's sum, each term with its own cosine and sine, in extended
    /// precision: year 0, 1900, 2000, 2006, 2027, 2100 and 4000.
    static let references = [
        Reference(terrestrialTime: -730_500.0, psi: 15.767680236038, eps: 2.392963012768),
        Reference(terrestrialTime: -36_525.0, psi: 17.345963950414, eps: -2.293000934275),
        Reference(terrestrialTime: 0.0, psi: -13.931663888970, eps: -5.769417077293),
        Reference(terrestrialTime: 2_191.5, psi: -1.986856531999, eps: 8.380945639410),
        Reference(terrestrialTime: 9_862.5, psi: 10.562086360068, eps: 6.797848128578),
        Reference(terrestrialTime: 36_525.0, psi: 3.272757918700, eps: 8.584860083110),
        Reference(terrestrialTime: 730_500.0, psi: 11.481678208991, eps: 6.814786236511),
    ]

    /// Nutation in longitude and in obliquity, in arcseconds.
    ///
    /// The sidereal time needs the nutation, and leaves it in the time it was given.
    static func nutation(terrestrialTime: Double) -> (psi: Double, eps: Double) {
        var time = Astronomy_TerrestrialTime(terrestrialTime)
        _ = Astronomy_SiderealTime(&time)
        return (time.psi, time.eps)
    }

    @Test("Matches the series summed term by term", arguments: references)
    func termByTerm(reference: Reference) {
        let (psi, eps) = Self.nutation(terrestrialTime: reference.terrestrialTime)
        // The two ways of summing differ by under 4e-10 arcseconds over 4000 years.
        #expect(abs(psi - reference.psi) < 2e-9, "longitude is \(psi - reference.psi) arcseconds out")
        #expect(abs(eps - reference.eps) < 2e-9, "obliquity is \(eps - reference.eps) arcseconds out")
    }

    @Test("Matches the SOFA test value")
    func sofaTestValue() {
        // SOFA's own test of its routine, nut00b(2400000.5, 53736.0): radians, to 1e-13.
        let (psi, eps) = Self.nutation(terrestrialTime: 2_400_000.5 + 53_736.0 - 2_451_545.0)
        let radiansPerArcsecond = Double.pi / 648_000
        #expect(abs(psi * radiansPerArcsecond - -0.9632552291148362783e-5) < 1e-13)
        #expect(abs(eps * radiansPerArcsecond - 0.4063197106621159367e-4) < 1e-13)
    }

    @Test("Stays finite at the largest finite time")
    func extremeTime() {
        // The five angles are reduced by whole turns before their cosines and sines are
        // taken, so a time far outside the ephemeris range gives a meaningless but
        // finite nutation, as upstream's routine did.
        let (psi, eps) = Self.nutation(terrestrialTime: 1e300)
        #expect(psi.isFinite)
        #expect(eps.isFinite)
    }
}
