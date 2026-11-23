"""Проверяем по коду возврата, что пропуск или подмена теста не пройдут CI."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify-test-results.py"
EXPECTED = ["ExampleTests/testFirst()", "ExampleTests/testSecond()"]


class VerifyResultsTests(unittest.TestCase):
    def run_checker(self, tests=None, expected=EXPECTED, **summary_changes):
        if tests is None:
            tests = [(name, "Passed") for name in EXPECTED]
        summary = {"totalTestCount": 2, "passedTests": 2, "failedTests": 0,
                   "skippedTests": 0, "expectedFailures": 0}
        summary.update(summary_changes)
        cases = [{"nodeType": "Test Case", "nodeIdentifier": name, "result": result}
                 for name, result in tests]
        tree = {"testNodes": [{"nodeType": "Test Suite", "children": cases}]}
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ("summary.json", "tree.json", "expected.json")]
            for path, data in zip(paths, (summary, tree, expected)):
                path.write_text(json.dumps(data))
            return subprocess.run([sys.executable, str(SCRIPT), *map(str, paths)],
                                  capture_output=True, text=True)

    def test_exact_successful_run_passes(self):
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed=2", result.stdout)

    def test_missing_replaced_and_repeated_cases_fail(self):
        first, second = EXPECTED
        for names in [(first,), (first, "OtherTests/testOther()"), (first, second, first)]:
            with self.subTest(names=names):
                result = self.run_checker(tests=[(name, "Passed") for name in names])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Ошибка проверки XCTest", result.stderr)

    def test_nonpassing_cases_and_summary_fail(self):
        for result_name in ("Failed", "Skipped", "Expected Failure"):
            with self.subTest(result_name=result_name):
                result = self.run_checker(tests=[(EXPECTED[0], "Passed"), (EXPECTED[1], result_name)])
                self.assertNotEqual(result.returncode, 0)
        for field in ("failedTests", "skippedTests", "expectedFailures"):
            with self.subTest(field=field):
                self.assertNotEqual(self.run_checker(**{field: 1}).returncode, 0)
