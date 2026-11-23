"""Проверяем отказ сборки/тестов без Xcode и реального симулятора."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class NetworkRunnerTests(unittest.TestCase):
    def check_failure(self, action, code):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            source = Path(__file__).resolve().parents[1]
            for name in ["run-network-tests.py", "ci_stage.py"]:
                shutil.copy(source / name, scripts / name)
            (scripts / "https-fixture.py").write_text('''
class Fixture:
    ports = {}
    verify_time = 0
    errors = []
    def __init__(self, *args): pass
    def close(self): print("FIXTURE_CLOSED", flush=True)
''')
            resources = root / "Tests/CraftTalkTests/Fixtures"
            resources.mkdir(parents=True)
            artifacts = root / "artifacts"
            artifacts.mkdir()
            (artifacts / "simulators.json").write_text(json.dumps({"devices": {
                "synthetic-runtime": [{"udid": "original", "deviceTypeIdentifier": "synthetic-phone"}]
            }}))
            binary = root / "bin"
            binary.mkdir()
            for name in ["xcrun", "xcodebuild"]:
                executable = binary / name
                executable.write_text(f"#!{sys.executable}\n" + '''
import os, sys
from pathlib import Path
with open(os.environ["CALLS"], "a") as stream:
    stream.write(Path(sys.argv[0]).name + " " + " ".join(sys.argv[1:]) + "\\n")
if sys.argv[1:3] == ["simctl", "create"]:
    print("owned-simulator")
if sys.argv[-1] == os.environ["FAIL_ACTION"]:
    sys.exit(int(os.environ["FAIL_CODE"]))
''')
                executable.chmod(0o755)
            calls = root / "calls.log"
            result = subprocess.run([sys.executable, str(scripts / "run-network-tests.py"), "original", str(artifacts)],
                                    env={**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
                                         "CALLS": str(calls), "FAIL_ACTION": action, "FAIL_CODE": str(code)},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertIn("FIXTURE_CLOSED", result.stdout)
            self.assertFalse((resources / "Runtime").exists())
            commands = calls.read_text()
            self.assertIn("simctl shutdown owned-simulator", commands)
            self.assertIn("simctl delete owned-simulator", commands)
            self.assertEqual("test-without-building" in commands, action == "test-without-building")
            records = json.loads((artifacts / "timings.json").read_text())
            failure = next(record for record in records if record["stage"] == action)
            self.assertEqual((failure["status"], failure["exitCode"]), ("failed", code))

    def test_build_failure_does_not_run_tests_and_cleans_owned_resources(self):
        self.check_failure("build-for-testing", 65)

    def test_test_failure_is_preserved_after_cleanup(self):
        self.check_failure("test-without-building", 66)
