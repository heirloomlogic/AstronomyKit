import importlib.util
import json
import math
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

SPEC = importlib.util.spec_from_file_location("sun_pilot", Path(__file__).with_name("sun_pilot.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ComparisonTests(unittest.TestCase):
    def sample(self):
        return dict(status="success", ut=0.0, tt=0.0, x=1.0, y=0.0, z=0.0,
                    gx=1.0, gy=0.0, gz=0.0, ra=0.0, dec=0.0, distance=1.0,
                    altitude=45.0, fallback=True, iterations=3, fallbackEvaluations=3)

    def test_identical_samples_pass(self):
        self.assertEqual(MODULE.differences(self.sample(), self.sample()), [])

    def test_angles_wrap_and_fixed_budgets_remain_strict(self):
        expected = self.sample()
        actual = dict(expected, ra=24.0)
        self.assertEqual(MODULE.differences(expected, actual), [])
        for field, value in [("x", 1.0 + 2e-12), ("altitude", 45 + 2e-8),
                             ("ra", 2e-8 / 15), ("distance", 1 + 2e-12),
                             ("ut", 1e-14), ("iterations", 2), ("fallback", False)]:
            with self.subTest(field=field):
                self.assertTrue(MODULE.differences(expected, dict(expected, **{field: value})))

    def test_nonfinite_and_missing_numbers_fail(self):
        for value in [float("nan"), float("inf"), None]:
            self.assertTrue(MODULE.differences(self.sample(), dict(self.sample(), x=value)))

    def test_error_status_is_exact(self):
        self.assertEqual(MODULE.differences({"status": "bad-time"}, {"status": "bad-time"}), [])
        self.assertTrue(MODULE.differences({"status": "bad-time"}, {"status": "invalid-parameter"}))

    def test_corpus_has_every_earth_seam_and_adjacent_values(self):
        cases = MODULE.corpus()
        seams = [item for item in cases if item["category"] == "seam"]
        self.assertEqual(len(seams), (9177 + 1) * 3 * 2)
        self.assertTrue(any(item["category"] == "delta-t" for item in cases))
        self.assertTrue(any(item["category"] == "invalid" for item in cases))

    def test_rss_stages_cover_controls_initialization_caches_and_workloads(self):
        self.assertEqual(MODULE.RSS_STAGES, (
            "startup", "serialization", "polynomialEarth", "fallbackEarth",
            "polynomialCache", "fallbackCache", "firstAccess", "freshPolynomial",
            "repeatedPolynomial", "freshFallback", "repeatedFallback", "aggregate",
        ))

    @mock.patch.object(MODULE, "measured_process")
    def test_rss_attribution_uses_a_fresh_process_for_every_stage_and_trial(self, measured_process):
        measured_process.side_effect = lambda binary, arguments: {
            "peakResidentBytes": 1024, "stdout": arguments[-1] + "\n",
        }
        receipt = MODULE.rss_attribution(Path("runner"), 2)
        self.assertEqual(list(receipt), list(MODULE.RSS_STAGES))
        self.assertTrue(all(len(samples) == 2 for samples in receipt.values()))
        expected = [mock.call(Path("runner"), ["--rss-stage", stage]) for stage in MODULE.RSS_STAGES for _ in range(2)]
        self.assertEqual(measured_process.call_args_list, expected)

    def test_rss_attribution_rejects_incomplete_or_empty_receipts(self):
        valid = {stage: [{"peakResidentBytes": 1024, "stdout": "0\n"}] for stage in MODULE.RSS_STAGES}
        self.assertIs(MODULE.validate_rss_attribution(valid, 1), valid)
        for receipt in (
            {**valid, "startup": []},
            {**valid, "startup": [{"peakResidentBytes": 0, "stdout": "0\n"}]},
            {**valid, "startup": [{"peakResidentBytes": 1024, "stdout": ""}]},
        ):
            with self.assertRaises(ValueError):
                MODULE.validate_rss_attribution(receipt, 1)

    def test_matched_earth_stages_require_equal_checksums(self):
        candidate = {
            "polynomialEarth": [{"stdout": "0.19756834584757474\n"}],
            "fallbackEarth": [{"stdout": "-1.0334993594907775\n"}],
        }
        oracle = {
            "polynomialEarth": [{"stdout": "0.19759227388022271\n"}],
            "fallbackEarth": [{"stdout": "-1.0334418720675367\n"}],
        }
        with self.assertRaisesRegex(ValueError, "polynomialEarth"):
            MODULE.validate_matched_earth_stages(candidate, oracle, 1)
        self.assertIs(MODULE.validate_matched_earth_stages(oracle, oracle, 1), oracle)

    def aggregate_trial(self):
        checkpoints = [{"checkpoint": "beforeWork", "mappingRSSBytes": {"executable": 100}}]
        workloads = {}
        for mode in MODULE.AGGREGATE_MODES:
            workload = {
                "operations": MODULE.AGGREGATE_OPERATIONS[mode],
                "elapsedNanoseconds": 10,
                "checksum": 1.0,
            }
            workloads[mode] = workload
            checkpoints.append({
                "checkpoint": mode,
                "mappingRSSBytes": {"executable": 100, "heap": 20},
                "workload": workload,
            })
        return {"checkpoints": checkpoints, "externalPeakResidentBytes": 4096, "workloads": workloads}

    def test_aggregate_checkpoint_inventory_freezes_order_and_operation_counts(self):
        self.assertEqual(MODULE.AGGREGATE_MODES, (
            "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback",
        ))
        self.assertEqual(MODULE.AGGREGATE_CHECKPOINTS, ("beforeWork", *MODULE.AGGREGATE_MODES))
        self.assertEqual(MODULE.AGGREGATE_OPERATIONS, {
            "firstAccess": 1,
            "freshPolynomial": 200,
            "repeatedPolynomial": 200,
            "freshFallback": 200,
            "repeatedFallback": 200,
        })
        self.assertEqual(MODULE.AGGREGATE_TRIALS, 5)

    def test_aggregate_checkpoint_validation_rejects_malformed_stale_and_missing_data(self):
        trial = self.aggregate_trial()
        self.assertIs(MODULE.validate_aggregate_checkpoint_trial(trial), trial)
        mutations = []
        missing = json.loads(json.dumps(trial))
        missing["checkpoints"].pop()
        mutations.append(missing)
        duplicate = json.loads(json.dumps(trial))
        duplicate["checkpoints"][2]["checkpoint"] = "firstAccess"
        mutations.append(duplicate)
        stale = json.loads(json.dumps(trial))
        stale["checkpoints"][1]["workload"]["operations"] = 200
        mutations.append(stale)
        malformed = json.loads(json.dumps(trial))
        malformed["checkpoints"][1]["workload"]["checksum"] = math.nan
        mutations.append(malformed)
        failed = json.loads(json.dumps(trial))
        failed["externalPeakResidentBytes"] = 0
        mutations.append(failed)
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                MODULE.validate_aggregate_checkpoint_trial(mutation)

    def test_smaps_classification_and_growth_require_all_five_trials(self):
        smaps = """00400000-00401000 r-xp 00000000 08:01 1 /tmp/runner
Rss:                  4 kB
00600000-00601000 rw-p 00000000 00:00 0 [heap]
Rss:                  8 kB
00700000-00701000 r-xp 00000000 08:01 2 /usr/lib/swift/linux/libswiftCore.so
Rss:                 12 kB
00800000-00801000 r-xp 00000000 08:01 3 /usr/lib/libc.so.6
Rss:                 16 kB
00900000-00901000 rw-p 00000000 00:00 0
Rss:                 20 kB
"""
        self.assertEqual(MODULE.classify_smaps(smaps, Path("/tmp/runner")), {
            "anonymous": 20 * 1024,
            "executable": 4 * 1024,
            "heap": 8 * 1024,
            "sharedLibrary": 16 * 1024,
            "swiftRuntime": 12 * 1024,
        })
        trials = []
        for index in range(5):
            trial = self.aggregate_trial()
            trial["checkpoints"][0]["mappingRSSBytes"] = {"heap": 100 + index}
            trial["checkpoints"][1]["mappingRSSBytes"] = {"heap": 110 + index}
            trials.append(trial)
        summary = MODULE.summarize_aggregate_checkpoints(trials)
        self.assertEqual(summary["reproduciblePositiveGrowth"]["firstAccess"]["heap"]["minimumBytes"], 10)
        trials[-1]["checkpoints"][1]["mappingRSSBytes"]["heap"] = 99
        summary = MODULE.summarize_aggregate_checkpoints(trials)
        self.assertNotIn("heap", summary["reproduciblePositiveGrowth"].get("firstAccess", {}))
        self.assertFalse(summary["removableOwnerEstablished"])

    def test_smaps_classification_rejects_missing_truncated_and_duplicate_rss_rows(self):
        complete = """00400000-00401000 r-xp 00000000 08:01 1 /tmp/runner
Rss:                  4 kB
00600000-00601000 rw-p 00000000 00:00 0 [heap]
Rss:                  8 kB
"""
        malformed = {
            "missing": complete.replace("Rss:                  4 kB\n", ""),
            "truncated": complete + "00700000-00701000 rw-p 00000000 00:00 0\n",
            "duplicate": complete.replace("Rss:                  4 kB\n", "Rss:                  4 kB\nRss:                  4 kB\n"),
        }
        for name, contents in malformed.items():
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "smaps"):
                MODULE.classify_smaps(contents, Path("/tmp/runner"))

    def test_checkpoint_workloads_bind_to_uninstrumented_counts_and_checksums(self):
        trials = [self.aggregate_trial() for _ in range(5)]
        campaign = {"trials": trials}
        runtime = [{"workloads": trial["workloads"]} for trial in trials]
        receipt = MODULE.validate_checkpoint_workloads(campaign, runtime)
        self.assertTrue(receipt["checksumsMatchUninstrumented"])
        changed = json.loads(json.dumps(runtime))
        changed[-1]["workloads"]["freshFallback"]["checksum"] = 2.0
        with self.assertRaisesRegex(ValueError, "freshFallback"):
            MODULE.validate_checkpoint_workloads(campaign, changed)

    def test_timed_line_read_rejects_timeout_and_process_eof(self):
        with subprocess.Popen(
            ["python3", "-c", "import time; time.sleep(1)"],
            stdout=subprocess.PIPE,
        ) as process:
            with self.assertRaisesRegex(TimeoutError, "checkpoint"):
                MODULE.read_process_line(process.stdout.fileno(), 0.01)
        with tempfile.TemporaryFile() as stream:
            with self.assertRaisesRegex(RuntimeError, "closed"):
                MODULE.read_process_line(stream.fileno(), 0.01)

    def test_final_checkpoint_output_requires_immediate_eof(self):
        final = b'{"firstAccess":{}}\n'
        with tempfile.TemporaryFile() as stream:
            stream.write(final)
            stream.seek(0)
            self.assertEqual(MODULE.read_final_checkpoint_output(stream.fileno(), 0.01), {"firstAccess": {}})
        for trailing in (b'{"firstAccess":{}}\n', b"foreign output\n"):
            with self.subTest(trailing=trailing), tempfile.TemporaryFile() as stream:
                stream.write(final + trailing)
                stream.seek(0)
                with self.assertRaisesRegex(ValueError, "trailing"):
                    MODULE.read_final_checkpoint_output(stream.fileno(), 0.01)

    @mock.patch.object(MODULE.os, "killpg")
    def test_process_cleanup_kills_and_reaps_a_running_group(self, killpg):
        process = mock.Mock()
        process.pid = 42
        process.poll.return_value = None
        MODULE.cleanup_process_group(process)
        killpg.assert_called_once()
        process.wait.assert_called_once()


@unittest.skipUnless(os.environ.get("SUN_PILOT_RUNNER"), "requires an actual built Sun runner")
class RunnerOutputTests(unittest.TestCase):
    def run_runner(self, arguments=(), text="", closed_stdout=False):
        return subprocess.run(
            [os.environ["SUN_PILOT_RUNNER"], *arguments], input=text, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            preexec_fn=(lambda: os.close(1)) if closed_stdout else None,
        )

    def test_completed_records_survive_later_malformed_input(self):
        row = "espenak-meeus ut 9000 35 -80 100 0\n"
        clean = self.run_runner(text=row)
        self.assertEqual(clean.returncode, 0)
        self.assertEqual(json.loads(clean.stdout)["status"], "success")
        for count in (1, 10):
            with self.subTest(count=count):
                failed = self.run_runner(text=row * count + "bad\n")
                self.assertNotEqual(failed.returncode, 0)
                self.assertTrue(failed.stderr)
                self.assertEqual(failed.stdout, clean.stdout * count)

    def test_closed_stdout_fails_in_every_measured_output_mode(self):
        modes = [((), "espenak-meeus ut 9000 35 -80 100 0\n"), (("--performance",), "")]
        modes += [(("--rss-stage", stage), "") for stage in MODULE.RSS_STAGES]
        modes.append((("--rss-aggregate-checkpoints",), "continue\n" * len(MODULE.AGGREGATE_CHECKPOINTS)))
        for arguments, text in modes:
            with self.subTest(arguments=arguments):
                result = self.run_runner(arguments, text, closed_stdout=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)

    def test_large_stream_delivers_every_complete_record(self):
        row = "espenak-meeus ut 9000 35 -80 100 0\n"
        clean = self.run_runner(text=row)
        count = 1000
        streamed = self.run_runner(text=row * count)
        self.assertEqual(streamed.returncode, 0)
        self.assertEqual(streamed.stdout, clean.stdout * count)

    def test_aggregate_checkpoint_mode_preserves_sequence_and_rejects_bad_ack(self):
        result = self.run_runner(
            ("--rss-aggregate-checkpoints",),
            "continue\n" * len(MODULE.AGGREGATE_CHECKPOINTS),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([row["checkpoint"] for row in lines[:-1]], list(MODULE.AGGREGATE_CHECKPOINTS))
        self.assertEqual(set(lines[-1]), set(MODULE.AGGREGATE_MODES))
        for mode, row in zip(MODULE.AGGREGATE_MODES, lines[1:-1]):
            self.assertEqual(row["workload"]["operations"], MODULE.AGGREGATE_OPERATIONS[mode])
            self.assertEqual(row["workload"], lines[-1][mode])
        rejected = self.run_runner(("--rss-aggregate-checkpoints",), "stale\n")
        self.assertNotEqual(rejected.returncode, 0)


if __name__ == "__main__":
    unittest.main()
