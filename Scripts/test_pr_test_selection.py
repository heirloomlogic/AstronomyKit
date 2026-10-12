"""Regression controls for the PR selector: never turn a renamed suite into a green no-op."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("run-pr-tests.py")


class SelectionTests(unittest.TestCase):
    def load(self):
        self.assertTrue(SCRIPT.exists(), "the focused PR runner must exist")
        spec = importlib.util.spec_from_file_location("pr_tests", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_every_selected_suite_must_exist(self):
        runner = self.load()
        inventory = [f"{suite}/example()" for suite in runner.SUITES]
        self.assertEqual(runner.select_tests(inventory), inventory)
        for omitted in inventory:
            with self.subTest(omitted=omitted), self.assertRaises(ValueError):
                runner.select_tests([test for test in inventory if test != omitted])

    def test_other_modules_and_prefix_siblings_cannot_satisfy_a_selector(self):
        runner = self.load()
        for suite in runner.SUITES:
            inventory = [f"{other}/example()" for other in runner.SUITES if other != suite]
            inventory += [f"OtherTests.{suite.split('.', 1)[1]}/example()", f"{suite}Extra/example()"]
            with self.subTest(suite=suite), self.assertRaises(ValueError):
                runner.select_tests(inventory)

    def test_filter_matches_exactly_the_validated_selection(self):
        import re
        runner = self.load()
        selected = [f"{suite}/example()" for suite in runner.SUITES]
        excluded = ["AstronomyKitTests.AuditValidationTests/riseSet(stream:)", "OtherTests.NativeSafetyTests/replay()"]
        inventory = selected + excluded
        pattern = runner.filter_pattern()
        self.assertEqual([item for item in inventory if re.search(pattern, item)], runner.select_tests(inventory))


if __name__ == "__main__":
    unittest.main()
