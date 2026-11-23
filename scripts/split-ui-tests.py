#!/usr/bin/env python3
"""Разбиваем полный UI-манифест на непересекающиеся части для отдельных runners."""

import argparse
import json
from pathlib import Path
import re
import sys


def split_tests(tests, count):
    if (not isinstance(tests, list) or not tests
            or any(not isinstance(name, str) or not re.fullmatch(r"CTWebKitUITests/test\w+\(\)", name) for name in tests)
            or len(set(tests)) != len(tests)):
        raise ValueError("Ожидался непустой UI-манифест с уникальными идентификаторами тестов")
    if count < 1 or count > len(tests):
        raise ValueError("Число частей должно быть от 1 до числа тестов")
    # Чередование распределяет соседние сценарии по разным runners.
    return [tests[index::count] for index in range(count)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().parents[1] / "Tests/expected-ui-tests.json")
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    shards = split_tests(json.loads(args.manifest.read_text()), args.count)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index, tests in enumerate(shards, 1):
        path = args.output_dir / f"shard-{index}.json"
        path.write_text(json.dumps(tests, indent=2) + "\n")
        print(f"UI-часть {index}/{args.count}: {len(tests)} тестов; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        sys.exit(f"Ошибка разделения UI-тестов: {error}")
