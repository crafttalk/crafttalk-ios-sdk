#!/usr/bin/env python3
"""Проверяем точный состав и результат XCTest по сохранённым данным xcresulttool."""

import json
from pathlib import Path
import sys


def verify(summary, tree, expected):
    if not expected or len(set(expected)) != len(expected):
        raise ValueError("Манифест тестов пуст или содержит повторы")

    cases = []

    def visit(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                cases.append(node)
            visit(node.get("children", []))

    visit(tree.get("testNodes", []))
    actual = [case.get("nodeIdentifier") for case in cases]
    if len(actual) != len(set(actual)):
        raise ValueError("Один сценарий выполнен несколько раз; повтор не заменяет успешный прогон")
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected), key=str)
    if missing or extra:
        raise ValueError(f"Состав XCTest изменился. Отсутствуют: {missing}; лишние: {extra}")
    failed = [case.get("nodeIdentifier") for case in cases if case.get("result") != "Passed"]
    if failed:
        raise ValueError(f"Не все сценарии прошли: {failed}")
    count = len(expected)
    if (summary.get("totalTestCount") != count or summary.get("passedTests") != count
            or summary.get("failedTests") != 0 or summary.get("skippedTests") != 0
            or summary.get("expectedFailures", 0) != 0):
        raise ValueError(f"Ожидались ровно {count} успешных тестов без ошибок и пропусков")
    print(f"Результат XCTest: passed={count}, failed=0, skipped=0; состав совпадает с манифестом")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 4:
            raise ValueError("Использование: verify-test-results.py summary.json tests.json expected-tests.json")
        verify(*(json.loads(Path(path).read_text()) for path in sys.argv[1:]))
    except (OSError, ValueError, TypeError, KeyError) as error:
        sys.exit(f"Ошибка проверки XCTest: {error}")
