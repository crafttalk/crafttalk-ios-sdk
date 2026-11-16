#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
current="$(git config --get core.hooksPath || true)"
if [[ -n "$current" && "$current" != .githooks ]]; then
    echo "Уже настроен core.hooksPath=$current; объедините hooks вручную." >&2
    exit 1
fi
if [[ "$current" != .githooks ]]; then
    hooks_dir="$(git rev-parse --git-path hooks)"
    for hook in "$hooks_dir"/*; do
        # Шаблоны Git не исполняются; действующие hooks нельзя молча отключать.
        if [[ -f "$hook" && -x "$hook" && "$hook" != *.sample ]]; then
            echo "Обнаружен существующий hook: $hook; объедините hooks вручную." >&2
            exit 1
        fi
    done
fi
git config --local core.hooksPath .githooks
echo "Подключён .githooks/pre-push для этого клона и его worktrees."
