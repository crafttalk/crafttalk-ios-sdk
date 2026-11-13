# AGENTS.md

## Project Purpose

CraftTalk iOS SDK embeds the chat widget in WKWebView and handles native downloads, previews, and push registration. It is distributed as Swift sources and the `CraftTalk` Swift package.

## Stack

Swift (package tools version 5.8), UIKit, WebKit, Foundation/Security, XCTest. The Example uses CocoaPods with dependencies committed to Git.

## First Steps

Use neighboring code and the relevant docs to resolve conventions. Match the style of the area you change; this codebase includes legacy iOS paths.

## Commands

Run from the repository root. Select a full Xcode installation without changing global settings:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/sync-sdk.py --check  # Проверка копий без изменений
python3 scripts/sync-sdk.py --sync   # Синхронизация из корневого CTChat
bash scripts/ci.sh build-spm        # Сборка SDK для iOS Simulator
bash scripts/ci.sh test-spm         # XCTest на iPhone 16 / iOS 18.6
bash scripts/ci.sh test-ui          # WebKit XCUITest на iPhone 16 / iOS 18.6
bash scripts/ci.sh build-example    # Сборка Example без подписи
```

See [CI and testing](docs/ci-and-testing.md) for simulator overrides, artifacts, and toolchain requirements. Do not use macOS `swift test` for this UIKit SDK.

## Repo Layout

- `CTChat/` — canonical SDK sources; networking, security policy, WebView, previews and helpers.
- `Example/Chat/CTChat/` — mirrored SDK sources compiled into the Example app.
- `Example/Chat.xcworkspace` — Example app and committed Pods; shared scheme `Chat`.
- `Tests/CraftTalkTests/` — Swift package XCTest tests.
- `Tests/WebKitHost/` — isolated app host and WebKit XCUITest scenarios.
- `scripts/` and `.github/workflows/` — shared local/CI commands and GitHub Actions.
- `docs/` — integration constraints and development instructions.

## Key Rules

- **SDK copies** — edit `CTChat/` first, then synchronize and check the mirror. Register new mirrored Swift files in the Example target's Compile Sources. The sync script does not edit the Xcode project or delete extra files.
- **Local changes** — inspect Git status before edits. Preserve unrelated and uncommitted work; never reset or overwrite it to make synchronization pass. The sync command refuses to overwrite modified destinations.
- **Compatibility** — preserve public APIs, the legacy `configure()` path, and existing deployment settings unless the task explicitly changes them. CI's Example build override is not a new SDK minimum or proof of older-iOS support.
- **TLS** — preserve chain, hostname and validity checks in the new security mode. Host-scoped extra roots augment system trust; they do not grant navigation permission. Keep redirect allowlists separate and check every hop. Do not add trust-all handlers or ATS bypasses to make tests pass. Legacy certificate pinning has separate documented semantics.
- **Attachments** — preserve cookies/session state, the chat page and draft. Never probe or replay a one-use download request or replay a POST. Use safe basenames inside isolated temporary directories and clean up owned files after completion, dismissal or failure.
- **Diagnostics** — keep SDK errors sanitized: stage, host, domain and code; no URL paths/query, tokens, visitor data or request bodies.
- **Local files** — do not commit environment-specific secrets, certificates/private keys, logs, DerivedData or test results. Future test certificate fixtures must be explicitly synthetic. Keep cleanup limited to artifacts owned by the current task.
- **Dependencies** — build against committed Pods and `Podfile.lock`. Do not edit Pods by hand or run dependency updates as incidental cleanup.
- **Task scope** — keep changes surgical. Fix related build/behavior failures; report independent problems without broad refactoring or warning cleanup.
- **Comments** — write new source and script comments in Russian; identifiers and technical terms may remain in English. Keep AGENTS.md in English and detailed docs in Russian.

## Detailed Docs

- [Integration](README.md) — consumer setup and current compatibility claims.
- [Security configuration](docs/security-configuration.md) — consult for TLS, redirects, downloads, legacy behavior and initialization constraints.
- [CI and testing](docs/ci-and-testing.md) — consult when changing tests, build scripts, SDK synchronization or workflows.
- [Writing and reviewing tests](docs/testing.md) — consult before adding or reviewing tests; covers independent assertions, async ordering, isolation after failure, and limits of test evidence.

## Self-Improvement

When a task reveals verified, non-obvious reusable knowledge or a stale instruction, update the canonical note instead of duplicating it. Keep notes short; temporary workarounds must state when they can be removed. No mandatory report or new document after every task.

## Validation

| Change type | Run |
| --- | --- |
| Docs only | Check commands, paths and links; no Xcode build required |
| SDK logic | Sync and check copies; SPM build/tests and Example build; `test-ui` for WebKit/lifecycle changes |
| Tests only | `bash scripts/ci.sh test-spm` or `test-ui` for the changed suite; inspect executed test counts |
| Example project/config | `bash scripts/ci.sh build-example`; check copies if touched |
| CI/scripts/package | Relevant shared commands; verify failure exit codes and diagnostic artifacts |

Report what actually ran and any environment limits. See docs/ci-and-testing.md for the current suite and expected test count. Blob bridge coverage does not prove TLS, navigation, downloads, or UI lifecycle coverage. Do not claim a GitHub Actions run based only on local builds.
