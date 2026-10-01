"""Checks of bounds.py and of the article's use of bounds.json."""
import json
import re
import unittest
from decimal import Decimal
from fractions import Fraction as F

import bounds

ARTICLE = bounds.ROOT / "Sources/AstronomyKit/Documentation.docc/SolarAltitudeNumerics.md"
RECORDED = json.loads(bounds.TARGET.read_text())["computed"]

# The article writes a value from bounds.json as "`key` = n" (or ≤, ≥) or as "n ... (`key`)".
NUMBER = r"([-+]?\d[\d,]*\.?\d*(?:e[-+]?\d+)?)"
TAGGED = re.compile(r"`(\w+)` [=≤≥] " + NUMBER)
TRAILING = re.compile(NUMBER + r"[^|`\n]{0,16}\(`(\w+)`\)")
# A printed figure may round away from the exact value but never toward it:
# an error bound, rate, or signed step prints at or beyond the recorded
# magnitude, a lower bound at or below the recorded value, and a count exactly.
LOWER = {"radiusAU", "radiusGridAU"}
EXACT = {"segments"}


def flatten(document, prefix=""):
    for key, value in document.items():
        if isinstance(value, dict):
            yield from flatten(value, prefix + key + ".")
        else:
            yield key, value


def quoted_values(text):
    for key, number in TAGGED.findall(text):
        yield key, number
    for number, key in TRAILING.findall(text):
        yield key, number


class BoundsTests(unittest.TestCase):
    def test_polynomial_derivative_bound_is_exact_for_a_monomial_sum(self):
        # d/dt (3 + 2t - 5t^2) = 2 - 10t; the bound is 2 + 10 * t_max.
        self.assertEqual(bounds.polynomial_derivative_bound([F(3), F(2), F(-5)], F(2)), F(22))

    def test_polynomial_range_bound_is_tight_on_a_unit_interval(self):
        # p(u) = 1 - u^2 on [0, 1]: Taylor about 1/2 gives 3/4 + 1/2 + 1/4 = 3/2, at or above max |p| = 1.
        bound = bounds.polynomial_range_bound([F(1), F(0), F(-1)], F(0), F(1))
        self.assertGreaterEqual(bound, 1)
        self.assertLessEqual(bound, F(3, 2))
        # p(u) = u^2 - 80u on [39, 40] has max |p| = 1,600; the sum of magnitudes at u = 40 gives
        # 4,800, the Taylor expansion about 39.5 gives 1,600.5.
        shifted = bounds.polynomial_range_bound([F(0), F(-80), F(1)], F(39), F(40))
        self.assertGreaterEqual(shifted, 1600)
        self.assertLess(shifted, 1601)

    def test_literals_must_still_appear_in_their_function(self):
        self.assertEqual(bounds.literals("era", ["0.7790572732640"]), [F("0.7790572732640")])
        with self.assertRaises(ValueError):
            bounds.literals("era", ["0.7790572732641"])

    def test_header_constants_parse(self):
        self.assertEqual(bounds.header_constant("C_AUDAY"), F("173.1446326846693"))

    def test_recorded_earth_bounds_are_physical(self):
        # bounds.py --check ties bounds.json to the sources; this checks the values make sense.
        earth = RECORDED["earth"]
        self.assertEqual(earth["segments"], 9177)
        # Earth's orbital speed is 29.3 to 30.3 km/s, 0.0169 to 0.0175 AU/day; the
        # coefficient bound must exceed the real maximum and stay near it.
        self.assertGreater(earth["speedAUPerDay"], 0.0175)
        self.assertLess(earth["speedAUPerDay"], 0.02)
        self.assertGreater(earth["radiusAU"], 0.97)
        self.assertLess(earth["radiusAU"], 0.9833)
        self.assertGreater(earth["radiusMaxAU"], 1.0167)
        self.assertLess(earth["radiusMaxAU"], 1.03)
        self.assertLess(earth["joinMaxAU"], 1e-12)
        # The largest nutation term (17.2 arcsec, 18.6-year period) alone moves
        # about 2e-6 degrees per day; the series bound must exceed it.
        self.assertGreater(RECORDED["frameRates"]["nutationDegPerDay"], 2e-6)

    def test_delta_t_bounds_cover_the_years_the_coverage_reaches(self):
        # The coverage starts at engine year 1899.96, inside the 1860 piece, whose slope at
        # 1900 is 1.48 s/yr; Espenak-Meeus climbs about 2.4 s/yr by 2101. The bound must
        # exceed both and stay near them.
        slope_per_year = RECORDED["deltaTSlopeSecondsPerDay"] * 365.24217
        self.assertGreater(slope_per_year, 2.36)
        self.assertLess(slope_per_year, 4)
        # Delta T itself runs from about -3 s to 203 s over the coverage.
        self.assertGreater(RECORDED["deltaTMagnitudeSeconds"], 203)
        self.assertLess(RECORDED["deltaTMagnitudeSeconds"], 300)
        # Positive jumps leave TT gaps the inverse cannot solve; negative ones give two UTs.
        jumps = RECORDED["deltaTJumpSeconds"]
        self.assertEqual(sorted(jumps), ["y1900", "y1920", "y1941", "y1961", "y1986", "y2005", "y2050"])
        for year in ("y1920", "y1941", "y1961", "y1986"):
            self.assertGreater(jumps[year], 0, year)
        for year in ("y1900", "y2005", "y2050"):
            self.assertLess(jumps[year], 0, year)
        self.assertAlmostEqual(jumps["y1920"], 0.01238, places=6)

    def test_inverse_bound_covers_the_engine_tolerance_and_the_sum_rounding(self):
        # Astronomy_TerrestrialTimeWithDeltaT accepts |tt - time.tt| <= max(1e-12, 2 DBL_EPSILON |tt|),
        # and time.tt = fl(ut + fl(DeltaT/86400)) rounds at least once more at u |tt|.
        match = re.search(r"tolerance = fmax\(([-+0-9.eE]+), ([-+0-9.eE]+) \* ([-+0-9.eE]+) \* fabs\(tt\)\);", bounds.ENGINE)
        self.assertIsNotNone(match, "the inverse tolerance expression moved; update bounds.py and this test")
        floor_tt, factor, epsilon = (F(text) for text in match.groups())
        self.assertEqual(float(epsilon), float(bounds.EPSILON))
        tolerance = max(floor_tt, factor * bounds.EPSILON * bounds.STOP)
        self.assertGreaterEqual(RECORDED["ttInverseDays"], float(tolerance + bounds.U * bounds.STOP))

    def test_civil_bound_counts_the_calendar_arithmetic(self):
        # init(year:...) reaches CivilTime.terrestrialTime through Astronomy_MakeTime, whose three
        # additions each round at u |utc| before the conversion's own sum does.
        self.assertGreaterEqual(RECORDED["civilToTTDays"], float(4 * bounds.U * bounds.STOP))
        # Before 1961 a civil date is taken as UT, so the same roundings reach the UT sensitivity.
        self.assertGreaterEqual(RECORDED["civilToUTDegrees"], RECORDED["civilCalendarDays"] * RECORDED["utSensitivityDegPerDay"] * 0.999)

    def test_article_quotes_bounds_json(self):
        # Every value the article takes from bounds.json is written next to its key, prints
        # within one unit of its last digit of the recorded value, and rounds away from it,
        # and every value in bounds.json appears in the article at least once.
        recorded = dict(flatten(RECORDED))
        text = ARTICLE.read_text()
        quoted = list(quoted_values(text))
        self.assertGreater(len(quoted), 30)
        for key, number in quoted:
            self.assertIn(key, recorded, key)
            printed = Decimal(number.replace(",", ""))
            exact = Decimal(repr(recorded[key]))
            unit = Decimal(1).scaleb(printed.as_tuple().exponent)
            self.assertLessEqual(abs(printed - exact), unit, f"{key}: article {printed}, bounds.json {exact}")
            if key in EXACT:
                self.assertEqual(printed, exact, key)
            elif key in LOWER:
                self.assertLessEqual(printed, exact, f"{key} is a lower bound; the article must not round it up")
            else:
                self.assertEqual(printed >= 0, exact >= 0, key)
                self.assertGreaterEqual(abs(printed), abs(exact), f"{key} is an upper bound; the article must not round it toward zero")
        self.assertEqual(sorted(set(recorded) - {key for key, _ in quoted}), [], "values in bounds.json the article does not quote")


if __name__ == "__main__":
    unittest.main()
