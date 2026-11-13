#!/usr/bin/env python3
"""Создаём стенд и симулятор; ошибки стенда запрещают успешный результат прогона."""

import importlib.util
import json
import os
import plistlib
import re
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    original, artifacts = sys.argv[1:3]
    ui = len(sys.argv) > 3 and sys.argv[3] == "test-ui"
    root = Path(__file__).resolve().parent.parent
    selected = []
    if ui and os.environ.get("UI_TEST_MANIFEST"):
        selected = json.loads(Path(os.environ["UI_TEST_MANIFEST"]).read_text())
        available = json.loads((root / "Tests/expected-ui-tests.json").read_text())
        if (not isinstance(selected, list) or not selected
                or any(not isinstance(name, str) or not re.fullmatch(r"CTWebKitUITests/test\w+\(\)", name) for name in selected)
                or len(set(selected)) != len(selected) or not set(selected) <= set(available)):
            raise ValueError("UI_TEST_MANIFEST должен содержать непустой список уникальных UI-тестов из основного манифеста")
        (Path(artifacts) / "selected-tests.json").write_text(json.dumps(selected, indent=2) + "\n")
    resources = root / "Tests/CraftTalkTests/Fixtures/Runtime"
    # Не перезаписываем ресурсы другого запуска; параллельные SPM-прогоны запрещены.
    resources.mkdir()
    simulator = None
    fixture = None
    process = None

    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        with tempfile.TemporaryDirectory(prefix="crafttalk-tls-") as directory:
            spec = importlib.util.spec_from_file_location("https_fixture", root / "scripts/https-fixture.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            fixture = module.Fixture(directory, resources, Path(artifacts) / "server-requests.jsonl")
            if ui:
                config_path = resources / "config.json"
                config = json.loads(config_path.read_text())
                config["uiCase"] = str(uuid.uuid4())
                config_path.write_text(json.dumps(config))
                shutil.copy(resources / "valid.der", resources / "CTCertificate.der")
                info = root / ".build/ci/ui-host.plist"
                info.parent.mkdir(parents=True, exist_ok=True)
                info.write_bytes(plistlib.dumps({
                    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                    "CFBundleName": "CraftTalk UI Host", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
                    "CFBundleShortVersionString": "1.0", "UILaunchScreen": {}, "LSRequiresIPhoneOS": True,
                    "UIFileSharingEnabled": True, "LSSupportsOpeningDocumentsInPlace": True,
                    "CTChatBaseURL": f"https://localhost:{fixture.ports['valid']}/case/{config['uiCase']}",
                    "CTChatNamespace": "channel", "CTSalt": "synthetic-ui-salt",
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                    "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                }))
            devices = json.loads((Path(artifacts) / "simulators.json").read_text())["devices"]
            runtime, device = next((runtime, device) for runtime, devices in devices.items()
                                   for device in devices if device["udid"] == original)
            simulator = run("xcrun", "simctl", "create", "CraftTalk Tests " + str(uuid.uuid4()),
                            device["deviceTypeIdentifier"], runtime, capture_output=True).stdout.strip()
            (Path(artifacts) / "fixture.json").write_text(json.dumps({"simulator": simulator, "runtime": runtime,
                                                                    "ports": fixture.ports, "verifyTime": fixture.verify_time}))
            run("xcrun", "simctl", "boot", simulator)
            run("xcrun", "simctl", "bootstatus", simulator, "-b", timeout=240)
            run("xcrun", "simctl", "keychain", simulator, "add-root-cert", str(Path(directory) / "system-root.pem"))
            print("HTTPS-стенд готов; отдельный симулятор:", simulator, flush=True)
            selection = (["-project", str(root / "Tests/WebKitHost/CraftTalkUIHost.xcodeproj"), "-scheme", "CraftTalkUIHost"] if ui
                         else ["-scheme", "CraftTalk"])
            process = subprocess.Popen([
                "xcodebuild", *selection, "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=" + simulator, "-destination-timeout", "60",
                "-derivedDataPath", str(root / (".build/ci/ui" if ui else ".build/ci/spm")), "-resultBundlePath", str(Path(artifacts) / "tests.xcresult"),
                "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                "-default-test-execution-time-allowance", "180" if ui else "60", "-maximum-test-execution-time-allowance", "240" if ui else "120",
                *(["-enableCodeCoverage", "YES"] if ui else []),
                *["-only-testing:CraftTalkUITests/" + name.removesuffix("()") for name in selected],
                "CODE_SIGNING_ALLOWED=NO", "test"], cwd=root)
            status = process.wait()
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        try:
            if fixture is not None:
                fixture.close()
        finally:
            try:
                if simulator:
                    subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True)
                    run("xcrun", "simctl", "delete", simulator)
            finally:
                shutil.rmtree(resources)

    # close() уже остановил барьеры: поздний callback не может потерять ошибку таймаута.
    if fixture.errors:
        print(f"Ошибка HTTPS-стенда: {len(fixture.errors)} таймаутов release; см. {fixture.error_path}", file=sys.stderr)
        return status or 1
    return status


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
