"""Ошибка дочерней команды не теряется; диагностические этапы сохраняются."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "ci_stage.py"
spec = importlib.util.spec_from_file_location("ci_stage", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StageTests(unittest.TestCase):
    def test_ci_log_stays_open_during_interrupt_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy(SCRIPT.parent / "ci.sh", root / "scripts/ci.sh")
            binary = root / "bin"
            binary.mkdir()
            compiler = binary / "xcodebuild"
            compiler.write_text(f"#!{sys.executable}\n" + '''
import signal, sys, time
from pathlib import Path
if "-version" in sys.argv:
    print("Xcode synthetic")
    sys.exit(0)
def interrupted(signum, frame):
    raise KeyboardInterrupt
signal.signal(signal.SIGINT, interrupted)
Path("ready").touch()
try:
    time.sleep(60)
except KeyboardInterrupt:
    sys.exit(130)
finally:
    time.sleep(0.1)
    print("CLEANUP_COMPLETED", flush=True)
    Path("cleaned").touch()
''')
            compiler.chmod(0o755)
            xcrun = binary / "xcrun"
            xcrun.write_text("#!/bin/sh\nexit 0\n")
            xcrun.chmod(0o755)
            environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                               ARTIFACTS_DIR=str(root / "artifacts"))
            environment.pop("EXPECTED_XCODE_VERSION", None)
            process = subprocess.Popen(["bash", "scripts/ci.sh", "build-spm"], cwd=root,
                                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True, text=True)
            try:
                deadline = time.monotonic() + 10
                while not (root / "ready").exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue((root / "ready").exists(), "Синтетическая сборка не запустилась")
                os.killpg(process.pid, signal.SIGINT)
                stdout, stderr = process.communicate(timeout=10)
                self.assertNotEqual(process.returncode, 0)
                self.assertTrue((root / "cleaned").exists(), stdout + stderr)
                [log] = (root / "artifacts").glob("build-spm.*/output.log")
                self.assertIn("CLEANUP_COMPLETED", log.read_text())
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()

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
