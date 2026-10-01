"""Checks of bounds.py and of the article's use of bounds.json."""
import json
import re
import unittest
from fractions import Fraction as F
from pathlib import Path

import bounds

ARTICLE = bounds.ROOT / "Sources/AstronomyKit/Documentation.docc/SolarAltitudeNumerics.md"
RECORDED = json.loads(bounds.TARGET.read_text())["computed"]


def flatten(document, prefix=""):
    for key, value in document.items():
        if isinstance(value, dict):
            yield from flatten(value, prefix + key + ".")
        else:
            yield key, value


class BoundsTests(unittest.TestCase):
    def test_polynomial_derivative_bound_is_exact_for_a_monomial_sum(self):
        # d/dt (3 + 2t - 5t^2) = 2 - 10t; the bound is 2 + 10 * t_max.
        self.assertEqual(bounds.polynomial_derivative_bound([F(3), F(2), F(-5)], F(2)), F(22))

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
        self.assertLess(earth["joinMaxAU"], 1e-12)
        # The largest nutation term (17.2 arcsec, 18.6-year period) alone moves
        # about 2e-6 degrees per day; the series bound must exceed it.
        self.assertGreater(RECORDED["frameRates"]["nutationDegPerDay"], 2e-6)
        # Espenak-Meeus climbs about 2.4 s/yr by 2101; the loose per-piece bound stays under 20.
        self.assertGreater(RECORDED["deltaTSlopeSecondsPerDay"] * 365.2422, 2.36)
        self.assertLess(RECORDED["deltaTSlopeSecondsPerDay"] * 365.2422, 20)

    def test_article_quotes_bounds_json(self):
        # Every "`key` = value" (or ≤, ≥) in the article must match bounds.json
        # to the precision the article prints.
        recorded = dict(flatten(RECORDED))
        quoted = re.findall(r"`(\w+)` [=≤≥] ([-+]?\d[\d,]*\.?\d*(?:e[-+]?\d+)?)", ARTICLE.read_text())
        self.assertGreater(len(quoted), 10)
        for key, text in quoted:
            self.assertIn(key, recorded, key)
            printed = float(text.replace(",", ""))
            self.assertAlmostEqual(printed, recorded[key], delta=abs(printed) * 5e-3, msg=key)


if __name__ == "__main__":
    unittest.main()
