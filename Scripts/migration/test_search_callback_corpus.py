"""Focused controls for finite, authenticated callback transcripts."""

import copy
import importlib.util
import math
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "search_corpus", Path(__file__).with_name("search_callback_corpus.py")
)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class Controls(unittest.TestCase):
    def test_packets(self):
        for value in [0.0, -0.0, 1e300, -1e-300, float("inf"), float("-inf")]:
            self.assertEqual(m.packet(m.number(m.packet(value))), m.packet(value))
        self.assertTrue(math.isnan(m.number("nan")))
        for payload in [
            "f64:7ff0000000000000",
            "f64:7ff8000000000000",
            "f64:000",
            "1",
            1,
            None,
        ]:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                m.number(payload)

    def test_frozen_cases(self):
        self.assertEqual(len(m.protocol()["cases"]), 51)
        self.assertEqual(
            sum(c["operation"] == "root" for c in m.protocol()["cases"]), 32
        )
        self.assertEqual(m.fixture(m.protocol()["cases"][0], 0.375, 1), 0)

    def test_build_receipt_semantics(self):
        receipt = m.expected_receipt_fields()
        receipt["environment"] = {
            k: "test" for k in ("os", "architecture", "cCompiler", "swiftCompiler")
        }
        receipt["binarySHA256"] = {k: "a" * 64 for k in ("c", "swift")}
        m.validate_receipt(receipt)
        for path, value in [
            ("flags", ["-ffast-math"]),
            ("oracleRevision", "false"),
            ("adapterSHA256", "0" * 64),
            ("manifestSHA256", "0" * 64),
            ("sourceFilesSHA256", {}),
            ("oracleFilesSHA256", {}),
            ("swiftAddedCFlags", []),
        ]:
            bad = copy.deepcopy(receipt)
            bad[path] = value
            with self.subTest(path=path), self.assertRaises(ValueError):
                m.validate_receipt(bad)
        bad = copy.deepcopy(receipt)
        bad.pop("flags")
        with self.assertRaises(ValueError):
            m.validate_receipt(bad)

    def test_tool_population(self):
        expected = m.tool_map()
        m.validate_tools(expected)
        for change in [
            {},
            {**expected, "extra": "a"},
            {k: v for k, v in expected.items() if k != m.TOOLS[0]},
        ]:
            with self.assertRaises(ValueError):
                m.validate_tools(change)

    def sample_run(self):
        case = m.protocol()["cases"][0]

        def time(ut):
            return {
                "ut": m.packet(ut),
                "tt": m.packet(ut),
                "model": "espenak-meeus",
                "expectedCapturedTT": m.packet(ut),
            }

        events = [
            {
                "event": "begin",
                "initialModel": "espenak-meeus",
                "start": time(20000),
                "end": time(20001),
            }
        ]
        for visit, ut in enumerate([20000, 20001, 20000.375], 1):
            events.append(
                {
                    "event": "callback",
                    "visit": visit,
                    "time": time(ut),
                    "defaultBefore": "espenak-meeus" if visit % 2 else "jpl-horizons",
                    "defaultAfter": "jpl-horizons" if visit % 2 else "espenak-meeus",
                    "result": {"kind": "scalar", "value": m.packet(ut - 20000 - 0.375)},
                }
            )
        events.append(
            {
                "event": "terminal",
                "outcome": "value",
                "rawStatus": 0,
                "visits": 3,
                "firstErrorVisit": 0,
                "time": time(20000.375),
            }
        )
        import json

        stdout = "".join(json.dumps(e) + "\n" for e in events)
        return (
            case,
            {
                "stdout": stdout,
                "stderr": "",
                "stdoutSHA256": m.sha(stdout.encode()),
                "stderrSHA256": m.sha(b""),
                "exitCode": 0,
                "termination": "algorithm",
            },
            events,
        )

    def test_rehashed_trace_semantics(self):
        import json

        case, run, events = self.sample_run()
        m.validate_run(run, case, "espenak-meeus", "c")
        for change in ["time", "result", "order", "missing", "status", "nonfinite"]:
            bad = copy.deepcopy(events)
            if change == "time":
                bad[2]["time"]["model"] = "jpl-horizons"
            if change == "result":
                bad[2]["result"]["value"] = m.packet(3600)
            if change == "order":
                bad[1], bad[2] = bad[2], bad[1]
            if change == "missing":
                bad.pop(1)
            if change == "status":
                bad[-1]["rawStatus"] = 6
            if change == "nonfinite":
                bad[2]["time"]["tt"] = "f64:7ff8000000000000"
            altered = copy.deepcopy(run)
            altered["stdout"] = "".join(json.dumps(e) + "\n" for e in bad)
            altered["stdoutSHA256"] = m.sha(altered["stdout"].encode())
            with self.subTest(change=change), self.assertRaises(ValueError):
                m.validate_run(altered, case, "espenak-meeus", "c")

    def test_separate_assessment_population(self):
        import json

        case, run, events = self.sample_run()
        swapped = copy.deepcopy(run)
        swapped["stdout"] = (
            run["stdout"]
            .replace("espenak-meeus", "TEMP")
            .replace("jpl-horizons", "espenak-meeus")
            .replace("TEMP", "jpl-horizons")
        )
        swapped["stdoutSHA256"] = m.sha(swapped["stdout"].encode())
        runs = {
            "espenak-meeus": {"c": [{"id": case["id"], **run}], "swift": []},
            "jpl-horizons": {"c": [{"id": case["id"], **swapped}], "swift": []},
        }
        for model in runs:
            public = copy.deepcopy(runs[model]["c"][0])
            parsed = [json.loads(line) for line in public["stdout"].splitlines()]
            parsed[-1]["rawStatus"] = "value"
            public["stdout"] = "".join(json.dumps(e) + "\n" for e in parsed)
            public["stdoutSHA256"] = m.sha(public["stdout"].encode())
            runs[model]["swift"] = [public]
        result = m.assessment(runs, [case])
        self.assertEqual(result["caseCount"], 1)
        self.assertEqual(result["processes"], 4)
        self.assertEqual(result["differences"], [])

    def test_current_original_archive_semantics(self):
        runs, receipt, derived = m.load_archive()
        self.assertEqual(derived["processes"], 204)
        self.assertEqual(derived["differences"], [])

    def test_timeout_retains_partial(self):
        import sys

        result = m.run_command(
            [
                sys.executable,
                "-u",
                "-c",
                "import time; print('partial',flush=True); time.sleep(2)",
            ],
            0.05,
        )
        self.assertEqual(result["termination"], "research-timeout")
        self.assertEqual(result["stdout"], "partial\n")

    def test_population_mutations(self):
        ids = [c["id"] for c in m.protocol()["cases"]]
        m.require_population(ids, ids)
        for bad in [[], ids[:-1], ids + [ids[0]], ids[::-1]]:
            with self.assertRaises(ValueError):
                m.require_population(bad, ids)


if __name__ == "__main__":
    unittest.main()
