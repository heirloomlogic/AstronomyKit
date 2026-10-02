import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_builder():
    path = ROOT / "Scripts/reference-data/build-fixtures.py"
    spec = importlib.util.spec_from_file_location("reference_fixture_builder", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RefreshSourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_failed_horizons_acquisition_preserves_every_existing_pair(self):
        with tempfile.TemporaryDirectory() as temporary:
            source_dir = Path(temporary)
            horizons_dir = source_dir / "horizons"
            horizons_dir.mkdir()
            response_path = horizons_dir / "first.json"
            recipe_path = horizons_dir / "first.query.json"
            response_path.write_bytes(b"original response")
            recipe_path.write_text("original recipe\n")
            with (
                mock.patch.object(self.builder, "SOURCE_DIR", source_dir),
                mock.patch.object(self.builder, "UPSTREAM_SOURCES", {}),
                mock.patch.object(
                    self.builder,
                    "HORIZONS_OBSERVER_QUERIES",
                    {"first": ("301", [2_451_544.5]), "second": ("499", [2_451_544.5])},
                ),
                mock.patch.object(self.builder, "HORIZONS_VECTOR_QUERIES", {}),
                mock.patch.object(
                    self.builder,
                    "download",
                    side_effect=[
                        b'{"result":"$$SOE\\nreplacement record\\n$$EOE"}\n',
                        RuntimeError("second download failed"),
                    ],
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "second download failed"):
                    self.builder.refresh_sources()
            self.assertEqual(b"original response", response_path.read_bytes())
            self.assertEqual("original recipe\n", recipe_path.read_text())

    def test_source_verification_rejects_a_torn_horizons_pair(self):
        with tempfile.TemporaryDirectory() as temporary:
            source_dir = Path(temporary)
            horizons_dir = source_dir / "horizons"
            horizons_dir.mkdir()
            parameters = self.builder.observer_query("301", [2_451_544.5])
            (horizons_dir / "moon-observer.json").write_text(
                '{"result":"$$SOE\\nrecord\\n$$EOE"}\n'
            )
            (horizons_dir / "moon-observer.query.json").write_text(
                self.builder.encoded({**parameters, "_responseSHA256": "0" * 64}).decode()
            )
            with (
                mock.patch.object(self.builder, "SOURCE_DIR", source_dir),
                mock.patch.object(self.builder, "UPSTREAM_SOURCES", {}),
                mock.patch.object(
                    self.builder,
                    "HORIZONS_OBSERVER_QUERIES",
                    {"moon-observer": ("301", [2_451_544.5])},
                ),
                mock.patch.object(self.builder, "HORIZONS_VECTOR_QUERIES", {}),
            ):
                with self.assertRaisesRegex(RuntimeError, "response hash"):
                    self.builder.verify_sources()


class JupiterMoonToleranceDomainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_relative_tolerance_is_limited_to_upstream_comparison_domain(self):
        vectors = [
            vector
            for vector in self.builder.parse_horizons()["vectors"]
            if vector["origin"] == "jupiter"
        ]

        bounded = [vector for vector in vectors if vector["relativeTolerance"] is not None]
        unbounded = [vector for vector in vectors if vector["relativeTolerance"] is None]

        self.assertEqual(4, len(bounded))
        self.assertEqual({2_451_544.5}, {vector["julianDateTDB"] for vector in bounded})
        self.assertEqual({9e-4}, {vector["relativeTolerance"] for vector in bounded})
        self.assertEqual(8, len(unbounded))
        self.assertEqual(
            {2_415_020.5, 2_488_069.5},
            {vector["julianDateTDB"] for vector in unbounded},
        )


class LunarReferenceConventionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_tolerances_and_comparison_scales_come_from_pinned_harness(self):
        conventions = self.builder.lunar_reference_conventions()

        self.assertEqual(90.0, conventions["phaseToleranceSeconds"])
        self.assertEqual("terrestrialTimeDerivedFromUT", conventions["phaseComparisonScale"])
        self.assertEqual(120.0, conventions["eclipseToleranceSeconds"])
        self.assertEqual("universalTime", conventions["eclipseComparisonScale"])
        self.assertEqual("Astronomy_DeltaT_EspenakMeeus", conventions["deltaTModel"])


if __name__ == "__main__":
    unittest.main()
