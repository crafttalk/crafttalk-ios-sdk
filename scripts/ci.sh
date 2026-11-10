#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case "${1:-}" in
    build-spm|test-spm|build-example) command_name="$1" ;;
    *) echo "Использование: bash scripts/ci.sh {build-spm|test-spm|build-example}" >&2; exit 2 ;;
esac

artifact_root="${ARTIFACTS_DIR:-$ROOT/artifacts/ci}"
mkdir -p "$artifact_root"
run_dir="$(mktemp -d "$artifact_root/$command_name.XXXXXX")"
run_dir="$(cd "$run_dir" && pwd)"

check_xcode() {
    if ! xcodebuild -version; then
        echo "Нужен полный Xcode. Задайте DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
        return 1
    fi
    if [[ -n "${EXPECTED_XCODE_VERSION:-}" ]]; then
        local actual
        actual="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
        if [[ "$actual" != "$EXPECTED_XCODE_VERSION" ]]; then
            echo "Ожидался Xcode $EXPECTED_XCODE_VERSION, выбран $actual (${DEVELOPER_DIR:-xcode-select})." >&2
            return 1
        fi
    fi
    xcrun swift --version
}

test_spm() {
    local simulator_id status
    xcrun simctl list devices available --json > "$run_dir/simulators.json"
    simulator_id="$(python3 - "$run_dir/simulators.json" "${SIMULATOR_OS:-18.6}" "${SIMULATOR_DEVICE:-iPhone 16}" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    devices = json.load(stream)["devices"]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + sys.argv[2].replace(".", "-")
matches = [device for device in devices.get(runtime, [])
           if device["name"] == sys.argv[3] and device.get("isAvailable", False)]
if not matches:
    sys.exit(f"Нет доступного симулятора {sys.argv[3]} с iOS {sys.argv[2]}. "
             "Установите runtime или задайте SIMULATOR_OS / SIMULATOR_DEVICE явно.")
print(matches[0]["udid"])
PY
)"
    if xcodebuild -scheme CraftTalk -configuration Debug \
        -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 60 \
        -derivedDataPath "$ROOT/.build/ci/spm" \
        -resultBundlePath "$run_dir/tests.xcresult" \
        -parallel-testing-enabled NO -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 \
        CODE_SIGNING_ALLOWED=NO test; then
        xcrun xcresulttool get test-results summary --path "$run_dir/tests.xcresult" \
            > "$run_dir/test-summary.json"
        python3 - "$run_dir/test-summary.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    result = json.load(stream)
passed = result.get("passedTests", 0)
failed = result.get("failedTests", 0)
skipped = result.get("skippedTests", 0)
print(f"Результат XCTest: passed={passed}, failed={failed}, skipped={skipped}")
if passed < 2 or failed != 0 or skipped != 0:
    sys.exit("Ожидались как минимум два выполненных успешных теста без пропусков.")
PY
    else
        status=$?
        if [[ -d "$run_dir/tests.xcresult" ]]; then
            xcrun xcresulttool get test-results summary --path "$run_dir/tests.xcresult" \
                > "$run_dir/test-summary.json" || true
        fi
        return "$status"
    fi
}

main() {
    echo "Диагностика: $run_dir"
    check_xcode
    case "$command_name" in
        build-spm)
            xcodebuild -scheme CraftTalk -configuration Debug \
                -destination 'generic/platform=iOS Simulator' \
                -derivedDataPath "$ROOT/.build/ci/spm" \
                -resultBundlePath "$run_dir/build.xcresult" CODE_SIGNING_ALLOWED=NO build
            ;;
        test-spm) test_spm ;;
        build-example)
            xcodebuild -workspace Example/Chat.xcworkspace -scheme Chat -configuration Debug \
                -destination 'generic/platform=iOS' \
                -derivedDataPath "$ROOT/.build/ci/example" \
                -resultBundlePath "$run_dir/build.xcresult" \
                CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
            ;;
    esac
}

main 2>&1 | tee "$run_dir/output.log"
