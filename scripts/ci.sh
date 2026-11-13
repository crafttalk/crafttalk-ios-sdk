#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case "${1:-}" in
    build-spm|test-spm|test-ui|build-example) command_name="$1" ;;
    *) echo "Использование: bash scripts/ci.sh {build-spm|test-spm|test-ui|build-example}" >&2; exit 2 ;;
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
    local simulator_id status manifest
    python3 -m unittest discover -s scripts/tests -v
    manifest=Tests/expected-tests.json
    if [[ "$command_name" == test-ui ]]; then manifest="${UI_TEST_MANIFEST:-Tests/expected-ui-tests.json}"; fi
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
    if python3 scripts/run-network-tests.py "$simulator_id" "$run_dir" "$command_name"; then
        xcrun xcresulttool get test-results summary --path "$run_dir/tests.xcresult" \
            > "$run_dir/test-summary.json"
        xcrun xcresulttool get test-results tests --path "$run_dir/tests.xcresult" \
            > "$run_dir/test-results.json"
        python3 scripts/verify-test-results.py "$run_dir/test-summary.json" \
            "$run_dir/test-results.json" "$manifest"
    else
        status=$?
        if [[ -d "$run_dir/tests.xcresult" ]]; then
            xcrun xcresulttool get test-results summary --path "$run_dir/tests.xcresult" \
                > "$run_dir/test-summary.json" || true
            xcrun xcresulttool get test-results tests --path "$run_dir/tests.xcresult" \
                > "$run_dir/test-results.json" || true
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
        test-spm|test-ui) test_spm ;;
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
