"""Controls for the issue-248 binary64 planet-source generator."""
import importlib.util
from pathlib import Path
import struct
import unittest


PATH = Path(__file__).with_name("generate-planet-de441.py")
SPEC = importlib.util.spec_from_file_location("planet_de441", PATH)
planet = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(planet)


class PlanetDE441GeneratorTests(unittest.TestCase):
    def test_inventory_preserves_authorized_sources_and_centers(self):
        self.assertEqual(planet.COMPONENTS["uranusBarycenter"].source, "ura184_part-3")
        self.assertEqual((planet.COMPONENTS["uranusBarycenter"].target, planet.COMPONENTS["uranusBarycenter"].center), (7, 0))
        self.assertEqual(planet.COMPONENTS["sun"].source, "de441")
        self.assertEqual((planet.COMPONENTS["uranusOffset"].target, planet.COMPONENTS["uranusOffset"].center), (799, 7))
        self.assertEqual((planet.COMPONENTS["earthOffset"].target, planet.COMPONENTS["earthOffset"].center), (399, 3))
        self.assertNotIn("Sources/CLibAstronomy", " ".join(planet.source_bindings()))

    def test_binary64_payload_rejects_wrong_shape_and_nonfinite_values(self):
        good = struct.pack("<9d", *range(9))
        planet.validate_payload(good, record_count=1, coefficient_count=3)
        for bad in (b"", good[:-1], struct.pack("<9d", *([0] * 8 + [float("inf")]))):
            with self.assertRaises(ValueError):
                planet.validate_payload(bad, record_count=1, coefficient_count=3)

    def test_record_recurrence_and_derivative(self):
        axes = ((1.0, 2.0, 3.0), (4.0, 5.0, 6.0), (7.0, 8.0, 9.0))
        position, velocity = planet.evaluate(axes, -1.0, 4.0)
        self.assertEqual(position, (2.0, 5.0, 8.0))
        self.assertEqual(velocity, (-5.0, -9.5, -14.0))

    def test_generated_paths_are_owned_and_complete(self):
        expected = {f"PlanetDE441{name[0].upper()}{name[1:]}Data.swift" for name in planet.COMPONENTS if name != "sun"}
        self.assertEqual(planet.output_names(), expected)
        self.assertTrue(all("Generated/DE441" in str(path) for path in planet.output_paths()))


if __name__ == "__main__":
    unittest.main()
