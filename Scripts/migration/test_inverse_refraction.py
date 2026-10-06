import importlib.util
import tempfile
import unittest
import shutil
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("inverse", Path(__file__).with_name("check_inverse_refraction.py"))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


class InverseRefractionControls(unittest.TestCase):
    def test_exact_frozen_population(self):
        cases = M.selection(M.load(M.PROTOCOL))
        self.assertEqual(312, len(cases))
        self.assertEqual(312, len(set(cases)))

    def test_straddle_population_is_frozen_with_adjacent_doubles(self):
        protocol = M.load(M.STRADDLE_PROTOCOL)
        cases = M.selection(protocol)
        self.assertEqual((324, 324, 9), (len(cases), len(set(cases)), len(M.straddle_neighbors(protocol))))
        protocol["inputs"][1], protocol["inputs"][2] = protocol["inputs"][2], protocol["inputs"][1]
        with self.assertRaisesRegex(ValueError, "adjacent doubles"):
            M.straddle_neighbors(protocol)

    def test_straddle_assessment_requires_adjacent_inverse_and_unchanged_payloads(self):
        protocol = M.load(M.STRADDLE_PROTOCOL)
        cases = M.selection(protocol)
        neighbors = M.straddle_neighbors(protocol)

        def payloads(repaired):
            result = []
            for mode, value, route, model in cases:
                straddle = mode == "normal" and value in neighbors
                if route == "direct":
                    bits = "0" if mode == "none" or (straddle and not repaired) else ("c" + neighbors[value][0][-4:] if straddle else "c" + value[-4:])
                    result.append({"correctionBits": bits, "finite": True})
                else:
                    corrected = mode != "none" and (repaired or not straddle)
                    result.append({"vectorBits": [mode if corrected else "none", value, model], "finite": True, "timePreserved": True})
            return result
        with tempfile.TemporaryDirectory() as name:
            current, pre_repair = Path(name) / "current", Path(name) / "pre-repair"
            for folder, revision in ((current, "repaired"), (pre_repair, protocol["preRepairRevision"])):
                folder.mkdir()
                M.save(folder / "build-receipt.json.gz", {"sourceRevision": revision})
            straddle = cases.index(("normal", protocol["straddles"][0], "direct", "espenakMeeus"))
            vector = cases.index(("normal", protocol["straddles"][0], "horizon", "espenakMeeus"))
            unaffected = cases.index(("jplHorizons", protocol["straddles"][0], "direct", "espenakMeeus"))
            mutations = [(None, None, None), (1, straddle, {"correctionBits": "0", "finite": True}),
                         (1, straddle, {"correctionBits": "c0000", "finite": True}),
                         (1, unaffected, {"correctionBits": "c0001", "finite": True}),
                         (0, straddle, {"correctionBits": "c0002", "finite": True}),
                         (1, vector, {"vectorBits": ["none", protocol["straddles"][0], "espenakMeeus"], "finite": True, "timePreserved": True})]
            for record, index, replacement in mutations:
                records = [payloads(False), payloads(True)]
                if record is not None:
                    records[record][index] = replacement

                def validate(folder, protocol_path):
                    self.assertEqual(M.STRADDLE_PROTOCOL, protocol_path)
                    return records[folder == current]
                with self.subTest(record=record, index=index), patch.object(M, "validate", validate):
                    if record is None:
                        self.assertEqual(288, M.assess_straddle(current, pre_repair, write=False)["unchangedPayloads"])
                    else:
                        with self.assertRaises(ValueError):
                            M.assess_straddle(current, pre_repair, write=False)

    def test_existing_output_rejects_before_execution(self):
        with tempfile.TemporaryDirectory() as name, patch.object(M, "process") as process:
            with self.assertRaises(FileExistsError):
                M.acquire(Path(name), "HEAD")
            process.assert_not_called()

    def test_timeout_is_killed_and_reaped_with_raw_output(self):
        import os
        import sys
        packet = M.process([sys.executable, "-c", "import time; print('entered', flush=True); time.sleep(30)"], 0.25, {"PATH": os.defpath})
        self.assertEqual("timeout-killed-and-reaped", packet["termination"])
        self.assertEqual(-9, packet["exitCode"])
        self.assertTrue(packet["reaped"])
        self.assertEqual("ZW50ZXJlZAo=", packet["stdoutBase64"])

    def test_interrupted_runner_kills_and_reaps_probe(self):
        import os
        import signal
        import subprocess
        import sys
        import time
        for number in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number.name), tempfile.TemporaryDirectory() as name:
                marker = Path(name) / "probe.pid"
                # The probe spins for at most 30 seconds even if every cleanup below fails.
                probe = (f"import os, time\nopen({str(marker)!r} + '.tmp', 'w').write(str(os.getpid()))\nos.replace({str(marker)!r} + '.tmp', {str(marker)!r})\n"
                         "end = time.monotonic() + 30\nwhile time.monotonic() < end: pass")
                runner = ("import importlib.util, os, signal, sys\nsignal.signal(signal.SIGINT, signal.default_int_handler)\n"
                          f"spec = importlib.util.spec_from_file_location('inverse', {spec.origin!r})\nM = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(M)\n"
                          f"M.process([sys.executable, '-c', {probe!r}], 60, {{'PATH': os.defpath}})")
                child = None
                with subprocess.Popen([sys.executable, "-c", runner], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True) as parent:
                    try:
                        deadline = time.monotonic() + 10
                        while not marker.exists():
                            self.assertLess(time.monotonic(), deadline, "probe did not start")
                            time.sleep(0.02)
                        child = int(marker.read_text())
                        os.kill(parent.pid, number)
                        parent.communicate(timeout=10)
                        self.assertNotEqual(0, parent.returncode)
                        with self.assertRaises(ProcessLookupError):
                            os.kill(child, 0)
                    finally:
                        for group in (child, parent.pid):
                            try:
                                if group:
                                    os.killpg(group, signal.SIGKILL)
                            except (ProcessLookupError, PermissionError):
                                pass

    def test_runner_exception_kills_and_reaps_probe(self):
        import os
        import signal
        import subprocess
        import sys
        started = []

        def failing(child, *arguments, **options):
            started.append(child.pid)
            raise RuntimeError("runner failed")
        try:
            with patch.object(subprocess.Popen, "communicate", failing), self.assertRaisesRegex(RuntimeError, "runner failed"):
                M.process([sys.executable, "-c", "import time; time.sleep(30)"], 60, {"PATH": os.defpath})
            with self.assertRaises(ProcessLookupError):
                os.kill(started[0], 0)
        finally:
            for pid in started:
                try:
                    os.killpg(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except (ProcessLookupError, PermissionError, ChildProcessError):
                    pass

    def test_saved_finiteness_cannot_override_bits(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "40c3880000000000", "finite": True,
                  "correctionBits": "7ff8000000000000"}
        with self.assertRaisesRegex(ValueError, "finiteness"):
            M.validate_payload(case, result)

    def test_nonfinite_time_and_changed_input_reject(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "7ff8000000000000", "finite": True, "correctionBits": "0"}
        with self.assertRaisesRegex(ValueError, "time"):
            M.validate_payload(case, result)
        result["ttBits"] = result["utBits"]
        result["inputBits"] = "3ff0000000000000"
        with self.assertRaisesRegex(ValueError, "input double"):
            M.validate_payload(case, result)

    def test_extra_payload_and_bool_type_reject(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "40c3880000000000", "finite": 1, "correctionBits": "0"}
        with self.assertRaisesRegex(ValueError, "population"):
            M.validate_payload(case, result)
        result["finite"] = True
        result["extra"] = 0
        with self.assertRaisesRegex(ValueError, "population"):
            M.validate_payload(case, result)

    def test_actual_process_failure_keeps_output_and_reaps(self):
        import os
        import sys
        packet = M.process([sys.executable, "-c", "import sys; print('partial'); print('failed', file=sys.stderr); sys.exit(3)"], 5, {"PATH": os.defpath})
        self.assertEqual(3, packet["exitCode"])
        self.assertTrue(packet["reaped"])
        self.assertEqual("cGFydGlhbAo=", packet["stdoutBase64"])
        self.assertEqual("ZmFpbGVkCg==", packet["stderrBase64"])

    def test_retained_payload_and_complete_input_mutations_reject(self):
        archive = M.HOME / "Evidence/baseline"
        self.assertTrue(archive.is_dir(), "retained baseline is mandatory")
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name) / "copy"
            shutil.copytree(archive, directory)
            receipt_path = directory / "build-receipt.json.gz"
            original = receipt_path.read_bytes()
            for mutation in ("hash", "missing", "extra"):
                receipt = M.load(receipt_path)
                coefficient = next(path for path in receipt["inputSHA256"] if path.endswith(".inc"))
                if mutation == "hash":
                    receipt["inputSHA256"][coefficient] = "0" * 64
                elif mutation == "missing":
                    receipt["inputSHA256"].pop(coefficient)
                else:
                    receipt["inputSHA256"]["Sources/extra.inc"] = "0" * 64
                M.save(receipt_path, receipt)
                with self.assertRaisesRegex(ValueError, "source/manifest"):
                    M.validate(directory)
                receipt_path.write_bytes(original)
            raw = directory / "raw-processes.json.gz"
            original = raw.read_bytes()
            packets = M.load(raw)
            for mutated in (packets[:-1], packets + [packets[0]], packets[::-1]):
                M.save(raw, mutated)
                with self.assertRaises(ValueError):
                    M.validate(directory)
            raw.write_bytes(original)
            import base64
            import json
            returned = next(index for index, packet in enumerate(packets) if packet["exitCode"] == 0)
            for field, value in (("model", "wrong-model"), ("finite", False), ("inputBits", "0")):
                mutated = M.load(raw)
                packet = mutated[returned]
                lines = base64.b64decode(packet["stdoutBase64"]).decode().splitlines()
                payload = json.loads(lines[1])
                payload[field] = value
                out = ("entered\n" + json.dumps(payload) + "\n").encode()
                packet["stdoutBase64"] = base64.b64encode(out).decode()
                packet["stdoutSHA256"] = M.sha(out)
                M.save(raw, mutated)
                with self.assertRaises(ValueError):
                    M.validate(directory)
                raw.write_bytes(original)

    def test_registered_execution_record_cannot_be_rehashed_or_replaced(self):
        import json
        M.check_archive()
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name) / "copy"
            shutil.copytree(M.EVIDENCE, directory)
            receipt = directory / "current/build-receipt.json.gz"
            shutil.copyfile(directory / "initial-current/build-receipt.json.gz", receipt)
            with self.assertRaisesRegex(ValueError, "execution artifact"):
                M.check_archive(directory)
            manifest_path = directory / "manifest.json"
            manifest = json.loads(manifest_path.read_bytes())
            manifest["filesSHA256"]["current/build-receipt.json.gz"] = M.sha(receipt.read_bytes())
            M.save(manifest_path, manifest)
            with self.assertRaisesRegex(ValueError, "immutable measured"):
                M.check_archive(directory)

    def test_repaired_straddle_record_cannot_be_rehashed_or_replaced(self):
        import json
        self.assertEqual(36, M.check_repair_archive()["repairedStraddleProcesses"])
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name) / "copy"
            shutil.copytree(M.REPAIR_EVIDENCE, directory)
            assessment = directory / "straddle-current/assessment.json"
            shutil.copyfile(directory / "current/assessment.json", assessment)
            with self.assertRaisesRegex(ValueError, "execution artifact"):
                M.check_repair_archive(directory)
            manifest_path = directory / "manifest.json"
            manifest = json.loads(manifest_path.read_bytes())
            manifest["filesSHA256"]["straddle-current/assessment.json"] = M.sha(assessment.read_bytes())
            M.save(manifest_path, manifest)
            with self.assertRaisesRegex(ValueError, "immutable measured"):
                M.check_repair_archive(directory)


if __name__ == "__main__":
    unittest.main()
