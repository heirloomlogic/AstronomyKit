import importlib.util
import json
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
                mock.patch.object(self.builder, "PUBLISHER_SOURCES", {}),
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
                mock.patch.object(self.builder, "PUBLISHER_SOURCES", {}),
                mock.patch.object(
                    self.builder,
                    "HORIZONS_OBSERVER_QUERIES",
                    {"moon-observer": ("301", [2_451_544.5])},
                ),
                mock.patch.object(self.builder, "HORIZONS_VECTOR_QUERIES", {}),
            ):
                with self.assertRaisesRegex(RuntimeError, "response hash"):
                    self.builder.verify_sources()

    def test_refresh_writes_a_publisher_source_by_its_full_url_into_its_directory(self):
        data = b"published constants"
        with tempfile.TemporaryDirectory() as temporary:
            source_dir = Path(temporary)
            download = mock.Mock(return_value=data)
            with (
                mock.patch.object(self.builder, "SOURCE_DIR", source_dir),
                mock.patch.object(self.builder, "UPSTREAM_SOURCES", {}),
                mock.patch.object(
                    self.builder,
                    "PUBLISHER_SOURCES",
                    {"naif/constants.tpc": ("https://example.org/constants.tpc", self.builder.sha256(data))},
                ),
                mock.patch.object(self.builder, "horizons_acquisitions", return_value=[]),
                mock.patch.object(self.builder, "download", download),
            ):
                self.builder.refresh_sources()
            download.assert_called_once_with("https://example.org/constants.tpc")
            self.assertEqual(data, (source_dir / "naif" / "constants.tpc").read_bytes())


class SofaFixedStarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_reference_pins_recipe_and_requires_twice_the_sampled_residual(self):
        references = self.builder.parse_sofa_fixed_stars()
        self.assertEqual(1, len(references))
        reference = references[0]
        self.assertGreaterEqual(
            reference["sampledToleranceArcseconds"],
            2 * reference["sampledMaximumResidualArcseconds"],
        )

    def test_changed_recipe_fails_its_archived_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_dir = root / "Scripts/reference-data/sources"
            (source_dir / "sofa").mkdir(parents=True)
            (root / "Scripts/reference-data").mkdir(parents=True, exist_ok=True)
            source = ROOT / "Scripts/reference-data/sources/sofa/fixed-star-reference.json"
            (source_dir / "sofa/fixed-star-reference.json").write_bytes(source.read_bytes())
            (root / "Scripts/reference-data/sofa-fixed-star-reference.c").write_text("changed recipe\n")
            with (
                mock.patch.object(self.builder, "ROOT", root),
                mock.patch.object(self.builder, "SOURCE_DIR", source_dir),
            ):
                with self.assertRaisesRegex(RuntimeError, "recipe hash"):
                    self.builder.parse_sofa_fixed_stars()

    def test_changed_recipe_output_fails_even_when_recipe_hash_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sofa_dir = root / "Scripts/reference-data/sources/sofa"
            sofa_dir.mkdir(parents=True)
            source = ROOT / "Scripts/reference-data/sources/sofa/fixed-star-reference.json"
            reference = json.loads(source.read_text())
            recipe_source = ROOT / "Scripts/reference-data/sofa-fixed-star-reference.c"
            changed_recipe = recipe_source.read_text().replace(
                'printf("rightAscensionHours %.17g\\n", hours(rc));',
                'printf("rightAscensionHours %.17g\\n", hours(rc) + 1.0);',
            )
            self.assertNotEqual(recipe_source.read_text(), changed_recipe)
            reference["_recipeSHA256"] = self.builder.sha256(changed_recipe.encode())
            (sofa_dir / "fixed-star-reference.json").write_text(self.builder.encoded(reference).decode())
            archive = ROOT / "Scripts/reference-data/sources/sofa/sofa_c-20231011.tar.gz"
            (sofa_dir / archive.name).write_bytes(archive.read_bytes())
            (root / "Scripts/reference-data/sofa-fixed-star-reference.c").write_text(changed_recipe)
            with (
                mock.patch.object(self.builder, "ROOT", root),
                mock.patch.object(self.builder, "SOURCE_DIR", root / "Scripts/reference-data/sources"),
            ):
                with self.assertRaisesRegex(RuntimeError, "recipe output mismatch"):
                    self.builder.parse_sofa_fixed_stars()


class ConstellationFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_published_table_covers_every_name_boundary_and_tie(self):
        fixture = self.builder.parse_constellations()
        names = fixture["names"]
        boundaries = fixture["boundaries"]
        self.assertEqual(88, len(names))
        self.assertEqual(88, len({item["symbol"] for item in names}))
        self.assertEqual("Antlia", next(item["name"] for item in names if item["symbol"] == "Ant"))
        self.assertEqual("Boötes", next(item["name"] for item in names if item["symbol"] == "Boo"))
        self.assertEqual("Chamaeleon", next(item["name"] for item in names if item["symbol"] == "Cha"))
        self.assertEqual("Ophiuchus", next(item["name"] for item in names if item["symbol"] == "Oph"))
        self.assertEqual(357, len(boundaries))
        self.assertEqual({item["symbol"] for item in names}, {item["symbol"] for item in boundaries})
        self.assertEqual(3 * len(boundaries), len(fixture["boundaryTies"]))
        self.assertEqual(len(boundaries), len(fixture["nearBoundaryStars"]))
        self.assertEqual(8, len(fixture["publishedExamples"]))

    def test_generated_swift_table_contains_every_published_row(self):
        fixture = self.builder.parse_constellations()
        generated = self.builder.generate_constellation_swift(fixture)
        self.assertEqual(88, generated.count("Info(symbol:"))
        self.assertEqual(357, generated.count("Boundary(infoIndex:"))


class ApparentRangeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_horizons_apparent_range_is_preserved_in_au(self):
        observations = self.builder.parse_horizons()["observations"]

        self.assertEqual(12, len(observations))
        self.assertTrue(all(observation["apparentRangeAU"] > 0 for observation in observations))
        moon_1900 = next(
            observation
            for observation in observations
            if observation["body"] == "moon" and observation["utc"].startswith("1900-")
        )
        self.assertEqual(0.00246250044096, moon_1900["apparentRangeAU"])


class AngularEventFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()
        cls.fixture = cls.builder.parse_angular_events()

    def test_relative_longitude_rows_are_source_brackets(self):
        rows = self.fixture["relativeLongitudeEvents"]
        self.assertEqual(4, len(rows))
        self.assertEqual(
            {("mars", 0.0), ("mars", 180.0), ("venus", 0.0), ("venus", 180.0)},
            {(row["body"], row["targetRelativeLongitudeDegrees"]) for row in rows},
        )
        for row in rows:
            self.assertLessEqual(row["lowerOffsetDegrees"], 0)
            self.assertGreater(row["upperOffsetDegrees"], 0)
            self.assertLessEqual(row["lowerJulianDateTDB"], row["estimatedJulianDateTDB"])
            self.assertLessEqual(row["estimatedJulianDateTDB"], row["upperJulianDateTDB"])
            self.assertEqual(0.002, row["timeScaleAllowanceSeconds"])
            self.assertAlmostEqual(
                row["timeToleranceSeconds"],
                row["sampleResolutionSeconds"] + row["timeScaleAllowanceSeconds"],
            )

    def test_maximum_elongation_rows_preserve_source_resolution_and_both_sides(self):
        rows = self.fixture["maximumElongationEvents"]
        self.assertEqual(4, len(rows))
        for body in ("mercury", "venus"):
            body_rows = [row for row in rows if row["body"] == body]
            self.assertEqual(2, len(body_rows))
            self.assertEqual({False, True}, {row["trailsSun"] for row in body_rows})
        for row in rows:
            self.assertGreaterEqual(row["sampleResolutionSeconds"], 3600)
            self.assertGreaterEqual(row["timeToleranceSeconds"], row["sampleResolutionSeconds"])
            self.assertGreaterEqual(row["angleToleranceDegrees"], 0.0001)

    def test_maximum_elongation_rows_reject_timestamp_mismatches(self):
        source_name = "mercury-max-2025-03"
        original_horizons_result = self.builder.horizons_result

        def changed_result(mutation):
            def result(name):
                original = original_horizons_result(name)
                if name != source_name:
                    return original
                prefix, remainder = original.split("$$SOE\n", 1)
                table, suffix = remainder.split("$$EOE", 1)
                lines = table.strip().splitlines()
                return f"{prefix}$$SOE\n{'\n'.join(mutation(lines))}\n$$EOE{suffix}"

            return result

        mutations = {
            "shifted": lambda lines: [lines[0].replace("18:00:00.000", "17:00:00.000"), *lines[1:]],
            "duplicate": lambda lines: [lines[0], lines[1].replace("19:00:00.000", "18:00:00.000"), *lines[2:]],
            "reordered": lambda lines: [lines[1], lines[0], *lines[2:]],
        }
        for mismatch, mutation in mutations.items():
            with self.subTest(mismatch=mismatch):
                with mock.patch.object(self.builder, "horizons_result", side_effect=changed_result(mutation)):
                    with self.assertRaisesRegex(RuntimeError, "maximum-elongation timestamp mismatch"):
                        self.builder.parse_angular_events()

    def test_angular_event_queries_keep_the_required_observables(self):
        acquisitions = dict(self.builder.horizons_acquisitions())
        for name in self.builder.RELATIVE_LONGITUDE_VECTOR_QUERIES:
            query = acquisitions[name]
            self.assertEqual("'500@10'", query["CENTER"])
            self.assertEqual("'NONE'", query["VEC_CORR"])
            self.assertEqual("'FRAME'", query["REF_PLANE"])
        for name in self.builder.MAX_ELONGATION_QUERIES:
            query = acquisitions[name]
            self.assertEqual("'500@399'", query["CENTER"])
            self.assertEqual("'23'", query["QUANTITIES"])
            self.assertEqual("'AIRLESS'", query["APPARENT"])


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

        # 2000-01-01 and 21 dates from one end of the domain, JD 2426545.0, to the other, 2476545.0, for each moon.
        domain = {2_451_544.5} | {2_426_545.0 + 2_500.0 * k for k in range(21)}
        self.assertEqual(4 * 22, len(bounded))
        self.assertEqual(domain, {vector["julianDateTDB"] for vector in bounded})
        self.assertEqual({9e-4}, {vector["relativeTolerance"] for vector in bounded})
        # 1900 and 2100, and a day outside each end of the domain.
        self.assertEqual(4 * 4, len(unbounded))
        self.assertEqual(
            {2_415_020.5, 2_426_544.0, 2_476_546.0, 2_488_069.5},
            {vector["julianDateTDB"] for vector in unbounded},
        )


class RiseSetFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_every_pinned_row_is_exported_in_source_order(self):
        rows = self.builder.parse_rise_set()
        groups = {
            (row["body"], row["longitudeDegrees"], row["latitudeDegrees"], row["utc"][:4])
            for row in rows
        }

        self.assertEqual(5_909, len(rows))
        self.assertEqual(list(range(1, 5_910)), [row["sourceLine"] for row in rows])
        self.assertEqual(17, len(groups))
        self.assertEqual({"1750", "2050"}, {min(row["utc"][:4] for row in rows), max(row["utc"][:4] for row in rows)})
        self.assertEqual({70.8}, {row["timeToleranceSeconds"] for row in rows})

    def test_malformed_and_dropped_sequence_rows_are_rejected(self):
        with mock.patch.object(self.builder, "source_text", return_value="Sun 0 0 invalid r\n"):
            with self.assertRaisesRegex(RuntimeError, "line 1"):
                self.builder.parse_rise_set()
        with mock.patch.object(
            self.builder,
            "source_text",
            return_value="Sun 181 0 2022-01-01T06:00Z r\n",
        ):
            with self.assertRaisesRegex(RuntimeError, "coordinates at line 1"):
                self.builder.parse_rise_set()
        with mock.patch.object(
            self.builder,
            "source_text",
            return_value=(
                "Sun 0 0 2022-01-01T06:00Z r\n"
                "Sun 0 0 2022-01-02T06:00Z r\n"
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "alternate"):
                self.builder.parse_rise_set()
        with mock.patch.object(
            self.builder,
            "source_text",
            return_value=(
                "Sun 0 0 2022-01-01T06:00Z r\n"
                "Sun 0 0 2022-01-01T18:00Z s\n"
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "expected 5909"):
                self.builder.parse_rise_set()

    def test_nonchronological_rows_are_rejected(self):
        with mock.patch.object(
            self.builder,
            "source_text",
            return_value=(
                "Sun 0 0 2022-01-02T18:00Z s\n"
                "Sun 0 0 2022-01-01T06:00Z r\n"
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "chronological"):
                self.builder.parse_rise_set()


class SaturnApsisFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_planet_center_tt_semantics_and_directed_roots(self):
        query = self.builder.saturn_apsis_query()
        self.assertEqual("'699'", query["COMMAND"])
        self.assertEqual("'500@10'", query["CENTER"])
        self.assertEqual("'TT'", query["TIME_TYPE"])
        self.assertEqual("'NONE'", query["VEC_CORR"])
        references = self.builder.parse_saturn_apsis_events()
        self.assertEqual(6, len(references))
        self.assertEqual({"saturn"}, {row["body"] for row in references})
        self.assertEqual({1.0}, {row["sourceToleranceSeconds"] for row in references})
        self.assertEqual({60.0}, {row["acceptanceToleranceSeconds"] for row in references})
        self.assertEqual({"pericenter", "apocenter"}, {row["kind"] for row in references})
        source = self.builder.horizons_result("saturn-apsis-precision")
        lines = source.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()
        self.assertEqual([float(line.split(",")[10]) for line in lines[2::5]], [row["sourceRangeRateAUPerDay"] for row in references])

    def test_time_units_and_nonfinite_values_are_rejected(self):
        result = self.builder.horizons_result("saturn-apsis-precision")
        for old, new in [("JDTT", "JDTDB"), ("Output units    : AU-D", "Output units    : KM-S")]:
            with mock.patch.object(self.builder, "horizons_result", return_value=result.replace(old, new)):
                with self.assertRaises(RuntimeError):
                    self.builder.parse_saturn_apsis_events()
        rows = self.builder.data_lines(result)
        fields = rows[0].split(",")
        fields[9] = "nan"
        with mock.patch.object(self.builder, "data_lines", return_value=[",".join(fields), *rows[1:]]):
            with self.assertRaisesRegex(RuntimeError, "finite-value"):
                self.builder.parse_saturn_apsis_events()

    def test_wrong_target_metadata_is_rejected(self):
        result = self.builder.horizons_result("saturn-apsis-precision")
        changed = result.replace("Target body name: Saturn (699)", "Target body name: Saturn Barycenter (6)")
        with mock.patch.object(self.builder, "horizons_result", return_value=changed):
            with self.assertRaisesRegex(RuntimeError, "target, center"):
                self.builder.parse_saturn_apsis_events()


if __name__ == "__main__":
    unittest.main()


class RecordedQueryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder()

    def test_recorded_queries_match_their_responses(self):
        self.builder.verify_recorded_queries()

    def test_a_changed_response_fails_its_recipe_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "body.json").write_bytes(b"response")
            recipe = {"COMMAND": "'899'", "_responseSHA256": self.builder.sha256(b"response")}
            (directory / "body.query.json").write_bytes(self.builder.encoded(recipe))
            self.builder.verify_recorded_queries(directory)
            (directory / "body.json").write_bytes(b"edited response")
            with self.assertRaises(RuntimeError):
                self.builder.verify_recorded_queries(directory)

    def test_a_response_without_a_recipe_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "body.json").write_bytes(b"response")
            with self.assertRaises(RuntimeError):
                self.builder.verify_recorded_queries(directory)
