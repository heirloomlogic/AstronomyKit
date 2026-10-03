"""Negative controls for source-bound, cross-platform representation evidence."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).with_name("measure.py")
SPEC = importlib.util.spec_from_file_location("measure", PATH)
MEASURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MEASURE)


def measurements():
    result = {"workloadSHA256": "0" * 64, "strippedExecutableBytes": 100}
    for configuration in ("Release", "Debug"):
        for mode in ("clean", "incremental"):
            result[f"{mode}{configuration}Seconds"] = [1.0] * 3
            result[f"{mode}{configuration}PeakResidentBytes"] = [10] * 3
    for metric in ("firstAccessNanoseconds", "fullSweepNanoseconds", "firstAccessPeakResidentBytes", "fullSweepPeakResidentBytes"):
        result[metric] = [10] * 5
    return result


def baseline():
    return {"environment": {"system": "test", "swift": "version"}, "budgets": {"cleanBuildSeconds": 2.0, "incrementalBuildSeconds": 2.0, "strippedBinaryBytes": 110}}


class MeasurementTests(unittest.TestCase):
    def test_release_build_budget_uses_slowest_trials(self):
        data = measurements()
        data["incrementalReleaseSeconds"] = [1.0, 2.1, 1.0]
        result = MEASURE.compare_representation(baseline(), data, baseline()["environment"])
        self.assertEqual(result["failures"], ["incrementalReleaseSeconds"])

    def test_representation_gate_rejects_oversized_binary(self):
        data = measurements(); data["strippedExecutableBytes"] = 111
        self.assertEqual(MEASURE.compare_representation(baseline(), data, baseline()["environment"])["failures"], ["strippedExecutableBytes"])

    def test_debug_and_representation_runtime_have_no_astronomical_gate(self):
        data = measurements()
        data["cleanDebugSeconds"] = [1000.0] * 3
        data["fullSweepNanoseconds"] = [10**9] * 5
        data["fullSweepPeakResidentBytes"] = [10**9] * 5
        MEASURE.validate_evidence(data)
        self.assertTrue(MEASURE.compare_representation(baseline(), data, baseline()["environment"])["passed"])

    def test_baseline_environment_mismatch_rejects_gate_claim(self):
        with self.assertRaisesRegex(ValueError, "environment"):
            MEASURE.compare_representation(baseline(), measurements(), {"system": "other", "swift": "version"})

    def test_complete_counts_are_required_for_both_configurations(self):
        for configuration in ("Release", "Debug"):
            for mode in ("clean", "incremental"):
                data = measurements(); data[f"{mode}{configuration}Seconds"].pop()
                with self.subTest(configuration=configuration, mode=mode), self.assertRaisesRegex(ValueError, configuration):
                    MEASURE.validate_evidence(data)

    def test_missing_debug_cannot_be_complete_evidence(self):
        data = measurements(); del data["cleanDebugSeconds"]
        with self.assertRaisesRegex(ValueError, "Debug"):
            MEASURE.validate_evidence(data)

    def test_incomplete_runtime_count_rejects_evidence(self):
        data = measurements(); data["fullSweepNanoseconds"].pop()
        with self.assertRaisesRegex(ValueError, "five"):
            MEASURE.validate_evidence(data)

    def test_nonfinite_build_measurement_rejects_evidence(self):
        for value in (float("nan"), float("inf"), -1.0, True):
            data = measurements(); data["cleanReleaseSeconds"][0] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                MEASURE.validate_evidence(data)

    def test_missing_memory_units_cannot_pass_evidence(self):
        data = measurements(); del data["incrementalDebugPeakResidentBytes"]
        with self.assertRaisesRegex(ValueError, "byte"):
            MEASURE.validate_evidence(data)

    def test_invalid_workload_identity_rejects_evidence(self):
        data = measurements(); data["workloadSHA256"] = "bad"
        with self.assertRaisesRegex(ValueError, "workload"):
            MEASURE.validate_evidence(data)

    def test_gnu_time_kib_are_converted_to_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "time.txt"
            path.write_text("Maximum resident set size (kbytes): 12345\n")
            with patch.object(MEASURE.platform, "system", return_value="Linux"):
                self.assertEqual(MEASURE.parse_rss(path), 12345 * 1024)
                self.assertEqual(MEASURE.time_arguments(path)[1], "-v")

    def test_darwin_time_preserves_byte_units(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "time.txt"
            path.write_text("12345  maximum resident set size\n")
            with patch.object(MEASURE.platform, "system", return_value="Darwin"):
                self.assertEqual(MEASURE.parse_rss(path), 12345)
                self.assertEqual(MEASURE.time_arguments(path)[1], "-l")

    def test_missing_rss_record_rejects_measurement(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "time.txt"; path.write_text("elapsed only\n")
            with self.assertRaises(RuntimeError):
                MEASURE.parse_rss(path)

    def test_strip_uses_platform_specific_debug_option(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "runner"; executable.write_bytes(b"binary")
            for system, flag in (("Darwin", "-S"), ("Linux", "--strip-debug")):
                with patch.object(MEASURE.platform, "system", return_value=system), patch.object(MEASURE.subprocess, "run") as run:
                    self.assertEqual(MEASURE.stripped_size(executable), 6)
                    self.assertEqual(run.call_args.args[0][1], flag)

    def test_protocol_inputs_bind_every_copied_production_and_test_file(self):
        inputs = MEASURE.prototype_inputs(MEASURE.ROOT)
        for name in ("Scripts/model-prototype/measure.py", "Scripts/model-prototype/test_measure.py", "Scripts/migration/performance_baseline.py", "Scripts/model-data/swift-prototype-manifest.json", "Sources/CLibAstronomy/generated/polynomial-data.h", "Sources/AstronomyKit/AstronomyKit.swift", "Tests/AstronomyModelPrototypeTests/ModelDataTests.swift", "Tools/Migration/ModelPrototypeRunner/main.swift"):
            self.assertIn(name, inputs)
        self.assertFalse(any("__pycache__" in name for name in inputs))

    def test_source_drift_rejects_measurement_snapshot(self):
        with self.assertRaisesRegex(RuntimeError, "changed"):
            MEASURE.require_unchanged_snapshot({"coefficient": "a"}, {"coefficient": "b"})

    def test_checkpoint_preserves_trial_progress_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            MEASURE.write_checkpoint(path, "debug-clean-2", {"cleanDebugSeconds": [1.0, 2.0]}, "timeout")
            record = json.loads(path.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["measurements"]["cleanDebugSeconds"], [1.0, 2.0])
            self.assertEqual(record["failure"], "timeout")

    def test_checkpoint_empty_failure_is_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"; MEASURE.write_checkpoint(path, "runtime-first", {}, "")
            self.assertEqual(json.loads(path.read_text())["status"], "incomplete")

    def test_runtime_checks_mode_value_checksum_counts_and_rss(self):
        first = [({"mode": "first", "elapsedNanoseconds": 1, "value": MEASURE.EXPECTED_FIRST_VALUE}, 10)] * 5
        sweep = [({"mode": "sweep", "elapsedNanoseconds": 2, "checksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64}, 20)] * 5
        MEASURE.validate_runner_results(first, sweep)
        for field, invalid in (("mode", "sweep"), ("value", 0), ("elapsedNanoseconds", -1)):
            altered = copy.deepcopy(first); altered[0][0][field] = invalid
            with self.subTest(field=field), self.assertRaises(ValueError):
                MEASURE.validate_runner_results(altered, sweep)
        bad = copy.deepcopy(sweep); bad[0][0]["checksum"] = 0
        with self.assertRaisesRegex(ValueError, "checksum"):
            MEASURE.validate_runner_results(first, bad)
        with self.assertRaisesRegex(ValueError, "count"):
            MEASURE.validate_runner_results(first, sweep[:-1])
        with self.assertRaisesRegex(ValueError, "RSS"):
            MEASURE.validate_runner_results([(first[0][0], 0)] * 5, sweep)

    def test_consumer_manifest_rejects_scripts_network_resources_and_plugins(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            (package / "Scripts").mkdir()
            with self.assertRaisesRegex(ValueError, "scripts"):
                MEASURE.packaging_manifest(package)
            (package / "Scripts").rmdir()
            for manifest in ({"dependencies": ["remote"], "targets": []}, {"dependencies": [], "targets": [{"resources": ["data"]}]}, {"dependencies": [], "targets": [{"pluginUsages": ["plugin"]}]}):
                with patch.object(MEASURE, "logged_output", return_value=json.dumps(manifest)), self.assertRaises(ValueError):
                    MEASURE.packaging_manifest(package)

    def test_campaign_rejects_mismatched_environment_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate.json"
            with patch.object(MEASURE, "load_baseline", return_value=baseline()), patch.object(MEASURE, "environment", return_value={"system": "other"}), patch.object(MEASURE, "build_trials") as build:
                with self.assertRaisesRegex(ValueError, "environment"):
                    MEASURE.measure(Path(directory) / "baseline.json", output)
                build.assert_not_called()
            self.assertEqual(json.loads(output.read_text())["status"], "incomplete")

    def test_historical_evidence_cannot_be_overwritten(self):
        with self.assertRaisesRegex(ValueError, "overwrite"):
            MEASURE.measure(MEASURE.BASELINE, MEASURE.OUTPUT)

    def test_incomplete_record_cannot_claim_gate_pass(self):
        with self.assertRaisesRegex(ValueError, "incomplete"):
            MEASURE.validate_record({"schemaVersion": 2, "status": "incomplete"}, baseline(), Path("unused"))

    def test_baseline_validation_rejects_tampered_budgets(self):
        record = json.loads(MEASURE.BASELINE.read_text()); record["budgets"]["strippedBinaryBytes"] += 1
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"; path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, "budgets"):
                MEASURE.load_baseline(path)

    def test_build_trials_exclude_preflight_and_restore_source_timestamp(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            source = package / "Sources/AstronomyModelPrototype/ModelData.swift"
            source.parent.mkdir(parents=True); source.write_text("fixture")
            original = source.stat().st_mtime_ns
            with patch.object(MEASURE, "timed_build", side_effect=[(99.0, 999)] + [(float(index), index * 10) for index in range(1, 7)]) as build, patch.object(MEASURE, "logged_output", return_value=str(package)):
                result, _ = MEASURE.build_trials(package, "debug")
            self.assertEqual(build.call_count, 7)
            self.assertEqual(result["cleanSeconds"], [1.0, 2.0, 3.0])
            self.assertEqual(result["incrementalSeconds"], [4.0, 5.0, 6.0])
            self.assertEqual(source.stat().st_mtime_ns, original)

    def test_persistent_command_logs_reject_output_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate.json"
            logger = MEASURE.CommandLog(Path(directory) / "candidate.json.logs")
            logger.save(["runner", "sweep"], directory, "checksum", "", 0, "10 bytes")
            MEASURE.validate_logs(logger.receipt(), output)
            (logger.directory / "0001-stdout.log").write_text("corrupt")
            with self.assertRaisesRegex(ValueError, "hash"):
                MEASURE.validate_logs(logger.receipt(), output)

    def test_record_receipt_rejects_runner_result_or_packaging_hash_drift(self):
        for field in ("runnerSHA256", "firstAccessResults", "consumerPackaging", "fixedBudgets"):
            original = {"schemaVersion": 2, "status": "passed", field: "original"}
            original["recordSHA256"] = MEASURE.record_digest(original)
            original[field] = "changed"
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "receipt"):
                MEASURE.validate_record(original, baseline(), Path("unused"))

    def test_complete_record_validates_and_missing_logged_debug_build_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate.json"
            baseline_path = Path(directory) / "baseline.json"; baseline_path.write_text(json.dumps(baseline()))
            logger = MEASURE.CommandLog(Path(directory) / "candidate.json.logs")
            data = measurements(); env = {"system": "Darwin", "swift": "version"}
            comparison = baseline(); comparison["environment"] = env
            for configuration in ("release", "debug"):
                for _ in range(7):
                    logger.save(["/usr/bin/time", "-l", "-o", "time.txt", "swift", "build", "-c", configuration], directory, "built", "", 0, "10 maximum resident set size", 1.0)
            first = {"mode": "first", "elapsedNanoseconds": 10, "value": MEASURE.EXPECTED_FIRST_VALUE}
            sweep = {"mode": "sweep", "elapsedNanoseconds": 10, "checksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64}
            for payload in (first, sweep):
                for _ in range(5):
                    logger.save(["/usr/bin/time", "-l", "-o", "time.txt", "runner", payload["mode"]], directory, json.dumps(payload), "", 0, "10 maximum resident set size")
            logger.save(["swift", "build", "-c", "release", "--product", "ModelConsumer"], directory, "built", "", 0)
            inputs = MEASURE.prototype_inputs(MEASURE.ROOT)
            record = {"schemaVersion": 2, "status": "passed", "baseRevision": "0" * 40, "protocol": MEASURE.protocol(), "inputSHA256": inputs,
                      "baselineSHA256": MEASURE.sha256(baseline_path), "historicalBaselineSHA256": MEASURE.sha256(MEASURE.BASELINE),
                      "measurementProtocolSHA256": inputs["Scripts/model-prototype/measure.py"], "workloadSHA256": inputs["Tools/Migration/ModelPrototypeRunner/main.swift"],
                      "runnerSHA256": "0" * 64, "commandLogs": logger.receipt(), "measurements": data, "firstAccessResults": [first] * 5,
                      "fullSweepResults": [sweep] * 5, "environment": env, "fixedBudgets": comparison["budgets"],
                      "evaluation": MEASURE.compare_representation(comparison, data, env),
                      "consumerPackaging": {"completed": True, "wholeModelChecksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64,
                                            "scriptsCopied": False, "runtimeDataFiles": False, "networkDependencies": False, "buildPlugins": False,
                                            "consumerManifestSHA256": MEASURE.hashlib.sha256(MEASURE.CONSUMER_MANIFEST.encode()).hexdigest(),
                                            "consumerSourceSHA256": MEASURE.hashlib.sha256(MEASURE.CONSUMER_SOURCE.encode()).hexdigest(), "evaluatedManifestSHA256": "0" * 64}}
            record["recordSHA256"] = MEASURE.record_digest(record)
            self.assertTrue(MEASURE.validate_record(record, comparison, baseline_path, output)["passed"])
            logger.entries.pop(13)
            MEASURE.write_record(logger.directory / "commands.json", {"entries": logger.entries})
            record["commandLogs"] = logger.receipt(); record["recordSHA256"] = MEASURE.record_digest(record)
            with self.assertRaisesRegex(ValueError, "build count"):
                MEASURE.validate_record(record, comparison, baseline_path, output)

    def test_post_build_runner_failure_finalizes_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate.json"
            baseline_path = Path(directory) / "baseline.json"; baseline_path.write_text("{}")
            builds = {"cleanSeconds": [1.0] * 3, "incrementalSeconds": [1.0] * 3, "cleanPeakResidentBytes": [10] * 3, "incrementalPeakResidentBytes": [10] * 3}
            with patch.object(MEASURE, "load_baseline", return_value=baseline()), patch.object(MEASURE, "environment", return_value=baseline()["environment"]), patch.object(MEASURE, "prototype_inputs", return_value={}), patch.object(MEASURE, "copy_workspace"), patch.object(MEASURE, "packaging_manifest"), patch.object(MEASURE, "build_trials", return_value=(builds, Path("runner"))), patch.object(MEASURE, "timed_runner", side_effect=RuntimeError("runner failed")):
                with self.assertRaisesRegex(RuntimeError, "runner failed"):
                    MEASURE.measure(baseline_path, output)
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["phase"], "runtime-first")
            self.assertEqual(record["failure"], "runner failed")

    def test_cli_failed_gate_returns_nonzero(self):
        with patch.object(MEASURE, "measure", return_value={"evaluation": {"passed": False, "failures": ["strippedExecutableBytes"]}}), patch("sys.argv", [str(PATH), "--measure", "--baseline", "baseline.json", "--output", "candidate.json"]):
            self.assertEqual(MEASURE.main(), 1)


if __name__ == "__main__":
    unittest.main()
