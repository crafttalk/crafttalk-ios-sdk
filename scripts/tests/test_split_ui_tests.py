"""Все UI-сценарии попадают ровно в одну часть, неверные входы запрещены."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


root = Path(__file__).resolve().parents[2]
script = root / "scripts/split-ui-tests.py"
spec = importlib.util.spec_from_file_location("split_ui_tests", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SplitUITests(unittest.TestCase):
    def test_real_manifest_is_covered_exactly_once(self):
        expected = json.loads((root / "Tests/expected-ui-tests.json").read_text())
        shards = module.split_tests(expected, 4)
        self.assertEqual(len(shards), 4)
        self.assertTrue(all(shards))
        self.assertCountEqual([name for shard in shards for name in shard], expected)
        for index, shard in enumerate(shards):
            for other in shards[index + 1:]:
                self.assertFalse(set(shard) & set(other))
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)

    def test_compatibility_manifest_is_a_unique_subset(self):
        expected = json.loads((root / "Tests/expected-ui-tests.json").read_text())
        compatibility = json.loads((root / "Tests/ui-compatibility-tests.json").read_text())
        self.assertEqual(module.split_tests(compatibility, 1), [compatibility])
        self.assertLess(set(compatibility), set(expected))

    def test_invalid_manifests_and_counts_are_rejected(self):
        valid = ["CTWebKitUITests/testOne()", "CTWebKitUITests/testTwo()"]
        for invalid in [[], {}, [42], ["Other/testOne()"], [valid[0], valid[0]]]:
            with self.subTest(manifest=invalid), self.assertRaises(ValueError):
                module.split_tests(invalid, 1)
        for count in [0, -1, 3]:
            with self.subTest(count=count), self.assertRaises(ValueError):
                module.split_tests(valid, count)

    def test_cli_writes_all_shards_and_rejects_invalid_count_without_output(self):
        with tempfile.TemporaryDirectory(prefix="crafttalk-ui-shards-") as directory:
            output = Path(directory) / "shards"
            result = subprocess.run([sys.executable, str(script), "--count", "4", "--output-dir", str(output)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted(output.glob("*.json"))
            self.assertEqual([path.name for path in files], [f"shard-{index}.json" for index in range(1, 5)])
            expected = json.loads((root / "Tests/expected-ui-tests.json").read_text())
            self.assertCountEqual([name for path in files for name in json.loads(path.read_text())], expected)
            invalid_output = Path(directory) / "invalid"
            result = subprocess.run([sys.executable, str(script), "--count", "0", "--output-dir", str(invalid_output)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Ошибка разделения", result.stderr)
            self.assertFalse(invalid_output.exists())


if __name__ == "__main__":
    unittest.main()
