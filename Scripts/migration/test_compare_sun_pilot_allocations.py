"""Controls for the bounded paired allocation comparison."""
import copy
import importlib.util
import gzip
import hashlib
import json
import tarfile
import tempfile
import math
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("allocations", Path(__file__).with_name("compare_sun_pilot_allocations.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def report(rss, revision="2376ee3df52f141f6394cb442243feb7cdbd6b86"):
    workloads = {mode: {"operations": count, "checksum": float(index), "elapsedNanoseconds": 1}
                 for index, (mode, count) in enumerate(MODULE.OPERATIONS.items())}
    configuration = {"comparison": {"passed": True, "count": 67240, "failures": [], "fallbackSamples": 8},
                     "perturbationDetected": True, "perturbationFailures": [1],
                     "runtime": [{"peakResidentBytes": value, "workloads": copy.deepcopy(workloads)} for value in rss]}
    return {"candidateRevision": revision, "status": "complete-evidence", "diagnostic": False, "candidateDirty": False,
            "numericalPassed": True, "environment": {"system": "Linux", "swift": "fixture"},
            "sourceSHA256": {"Sources/generated.swift": "bits"}, "protocolSHA256": "protocol",
            "aggregateRSSProtocolSHA256": "aggregate", "oracle": {"sha256": "oracle"},
            "effectivePackage": {"manifestSHA256": "manifest", "evaluatedManifestSHA256": "graph"},
            "fixedBudgetObservations": {"baselineSHA256": "budget", "budgets": {"peakResidentBytes": 11182080}},
            "configurations": {name: copy.deepcopy(configuration) for name in ("debug", "release")}}


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.baseline = report([12500000] * 5)
        self.candidate = report([12000000] * 5, "58caa65c292794ac138f5d3928100a9fe3479afd")

    def test_separated_trials_support_retention_without_passing_ceiling(self):
        result = MODULE.validate_reports(self.baseline, self.candidate)
        self.assertTrue(result["rssRetentionConditionPassed"])
        self.assertFalse(result["candidateWithinOriginalCeiling"])

    def test_only_isolated_manifest_root_paths_are_normalized(self):
        for record, root in ((self.baseline, "/tmp/first"), (self.candidate, "/tmp/second")):
            record["effectivePackage"]["evaluatedManifest"] = {"packageKind": {"root": [root]}, "targets": []}
            record["effectivePackage"]["evaluatedManifestSHA256"] = root
        self.assertTrue(MODULE.validate_reports(self.baseline, self.candidate)["rssRetentionConditionPassed"])
        self.candidate["effectivePackage"]["evaluatedManifest"]["targets"] = ["changed"]
        with self.assertRaises(ValueError):
            MODULE.validate_reports(self.baseline, self.candidate)

    def test_overlap_is_retained_as_a_negative_observation(self):
        self.candidate["configurations"]["release"]["runtime"][4]["peakResidentBytes"] = 12500000
        self.assertFalse(MODULE.validate_reports(self.baseline, self.candidate)["rssRetentionConditionPassed"])

    def test_changed_workloads_and_nonfinite_values_are_rejected(self):
        for field, value in (("operations", 199), ("checksum", 1.25), ("checksum", math.nan)):
            with self.subTest(field=field, value=value):
                candidate = copy.deepcopy(self.candidate)
                candidate["configurations"]["release"]["runtime"][0]["workloads"]["freshFallback"][field] = value
                with self.assertRaises(ValueError):
                    MODULE.validate_reports(self.baseline, candidate)

    def test_baseline_must_be_the_protocol_frozen_revision(self):
        for revision in (None, "", "58caa65c292794ac138f5d3928100a9fe3479afd"):
            with self.subTest(revision=revision):
                baseline = copy.deepcopy(self.baseline)
                baseline["candidateRevision"] = revision
                with self.assertRaises(ValueError):
                    MODULE.validate_reports(baseline, self.candidate)

    def test_missing_trials_failed_controls_and_drift_are_rejected(self):
        mutations = [lambda r: r["configurations"]["release"]["runtime"].pop(),
                     lambda r: r["configurations"]["debug"].update(perturbationDetected=False),
                     lambda r: r["sourceSHA256"].update({"Sources/generated.swift": "changed"}),
                     lambda r: r["environment"].update(swift="different"),
                     lambda r: r.update(candidateDirty=True),
                     lambda r: r.update(diagnostic=True),
                     lambda r: r["fixedBudgetObservations"]["budgets"].update(peakResidentBytes=99999999)]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(self.candidate)
                mutation(candidate)
                with self.assertRaises(ValueError):
                    MODULE.validate_reports(self.baseline, candidate)


class RawBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        evidence = Path(__file__).resolve().parents[2] / "Documentation/Migration/SunPilotAllocationEvidence"
        cls.files = ("inputs.json.gz", "oracle.jsonl.gz", "debug.jsonl.gz", "release.jsonl.gz",
                     "debug-perturbed.jsonl.gz", "release-perturbed.jsonl.gz")
        cls.reports = {}
        cls.raw = {}
        for label in ("baseline", "candidate"):
            cls.reports[label] = json.loads((evidence / f"linux-{label}-report.json").read_text())
            with tarfile.open(evidence / f"linux-{label}.tar.gz") as archive:
                cls.raw[label] = {name: archive.extractfile(name).read() for name in cls.files}

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directories = []
        for label in ("baseline", "candidate"):
            directory = Path(self.temporary.name) / label
            directory.mkdir()
            (directory / "report.json").write_text(json.dumps(self.reports[label]))
            for name, contents in self.raw[label].items():
                (directory / name).write_bytes(contents)
            self.directories.append(directory)

    def test_intact_archives_validate_and_bind_both_reports(self):
        result = MODULE.compare_directories(*self.directories)
        self.assertEqual(result["status"], "complete-paired-evidence")
        self.assertTrue(result["rssRetentionConditionPassed"])
        self.assertEqual(result["reports"]["baseline"]["revision"], "2376ee3df52f141f6394cb442243feb7cdbd6b86")

    def test_matching_replaced_streams_cannot_reuse_stale_reports(self):
        for name in self.files:
            for payload in (b"", b"not-json\n"):
                with self.subTest(name=name, payload=payload):
                    for directory in self.directories:
                        (directory / name).write_bytes(gzip.compress(payload))
                    with self.assertRaises(ValueError):
                        MODULE.compare_directories(*self.directories)
                    for label, directory in zip(("baseline", "candidate"), self.directories):
                        (directory / name).write_bytes(self.raw[label][name])

    def test_missing_artifact_hash_is_rejected_for_each_report(self):
        for label, directory in zip(("baseline", "candidate"), self.directories):
            for name in self.files:
                with self.subTest(label=label, name=name):
                    receipt = copy.deepcopy(self.reports[label])
                    del receipt["artifactSHA256"][name]
                    (directory / "report.json").write_text(json.dumps(receipt))
                    with self.assertRaises(ValueError):
                        MODULE.compare_directories(*self.directories)
                    (directory / "report.json").write_text(json.dumps(self.reports[label]))

    def test_hash_bound_empty_malformed_and_incomplete_streams_are_rejected(self):
        for name in self.files:
            for payload in (b"", b"not-json\n", b"[]" if name == "inputs.json.gz" else b"{}\n"):
                with self.subTest(name=name, payload=payload):
                    contents = gzip.compress(payload)
                    for label, directory in zip(("baseline", "candidate"), self.directories):
                        (directory / name).write_bytes(contents)
                        receipt = copy.deepcopy(self.reports[label])
                        receipt["artifactSHA256"][name] = hashlib.sha256(contents).hexdigest()
                        (directory / "report.json").write_text(json.dumps(receipt))
                    with self.assertRaises(ValueError):
                        MODULE.compare_directories(*self.directories)
                    for label, directory in zip(("baseline", "candidate"), self.directories):
                        (directory / name).write_bytes(self.raw[label][name])
                        (directory / "report.json").write_text(json.dumps(self.reports[label]))

    def test_candidate_directory_cannot_be_used_as_the_baseline(self):
        with self.assertRaises(ValueError):
            MODULE.compare_directories(self.directories[1], self.directories[1])


if __name__ == "__main__":
    unittest.main()
