import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("history", Path(__file__).with_name("replay_historical_research.py"))
H = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(H)


class HistoricalResearchTests(unittest.TestCase):
    def test_exact_reviewed_population(self):
        self.assertEqual(set(H.SUITES), {"callback", "constellation", "seasonal"})
        self.assertEqual(H.SUITES["callback"][0], "a06ce8653f7de3aed64bb4ce0509b1d10bc683ab")
        self.assertEqual(H.SUITES["constellation"][0], "97fc275f6fd455ed73063a6961698569783dddb8")
        self.assertEqual(H.SUITES["seasonal"][0], "2d54fd251a36e94f14324daed6d0937fc250d364")

    def test_detects_replaced_source_extra_source_tool_and_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "Sources").mkdir()
            source = root / "Sources/solver.c"
            source.write_text("historical solver")
            tool = root / "check.py"
            tool.write_text("historical checker")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "historical"], cwd=root, check=True)
            revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            original = H.authenticate(root, revision)
            for path in (source, tool):
                data = path.read_bytes()
                path.write_text("replacement")
                with self.assertRaisesRegex(ValueError, "tracked file"):
                    H.authenticate(root, revision)
                path.write_bytes(data)
            extra = root / "Sources/extra.c"
            extra.write_text("extra")
            with self.assertRaisesRegex(ValueError, "population"):
                H.authenticate(root, revision)
            extra.unlink()
            with self.assertRaisesRegex(ValueError, "revision"):
                H.authenticate(root, "0" * 40)
            self.assertEqual(H.authenticate(root, revision), original)
