"""Ошибка дочерней команды не теряется; диагностические этапы сохраняются."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "ci_stage.py"
spec = importlib.util.spec_from_file_location("ci_stage", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StageTests(unittest.TestCase):
    def test_command_failure_preserves_exit_code_and_previous_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, code in [("prepare", 0), ("build", 65)]:
                result = subprocess.run([sys.executable, str(SCRIPT), directory, name,
                                         sys.executable, "-c", f"raise SystemExit({code})"], capture_output=True)
                self.assertEqual(result.returncode, code)
            records = json.loads((Path(directory) / "timings.json").read_text())
            self.assertEqual([(r["stage"], r["status"], r["exitCode"]) for r in records],
                             [("prepare", "passed", 0), ("build", "failed", 65)])
            self.assertTrue(all(r["durationSeconds"] >= 0 for r in records))

    def test_interruption_is_recorded_and_propagated(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(KeyboardInterrupt):
                with module.Stage(directory, "tests"):
                    running = json.loads((Path(directory) / "timings.json").read_text())
                    self.assertEqual(running[0]["status"], "running")
                    raise KeyboardInterrupt
            record = json.loads((Path(directory) / "timings.json").read_text())[0]
            self.assertEqual(record["status"], "failed")
            self.assertEqual(record["error"], "KeyboardInterrupt")
            self.assertEqual(record["exitCode"], 130)
