"""Локальный push проверяет отправляемый коммит и блокируется при ошибке тестов."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
ZERO = "0" * 40


class PrePushTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / "source"
        self.repo.mkdir()
        self.scratch = self.base / "scratch"
        self.scratch.mkdir()
        # Синтетические репозитории не используют ключи, hooks и настройки пользователя.
        template = self.base / "empty-template"
        template.mkdir()
        self.env = dict({key: value for key, value in os.environ.items() if not key.startswith("GIT_")},
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TEMPLATE_DIR=str(template),
                        TMPDIR=str(self.scratch),
                        UI_TEST_MANIFEST="must-not-limit-tests.json", CI_HELPER_TESTS_CHECKED="1")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Synthetic hook test")
        self.git("config", "user.email", "hook@example.invalid")
        (self.repo / ".githooks").mkdir()
        shutil.copy2(ROOT / ".githooks/pre-push", self.repo / ".githooks/pre-push")
        (self.repo / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/install-hooks.sh", self.repo / "scripts/install-hooks.sh")
        (self.repo / "scripts/ci.sh").write_text('''#!/bin/bash
set -eu
test -z "${GIT_DIR:-}"
test -z "${UI_TEST_MANIFEST:-}"
if [[ "$1" == test-spm ]]; then test -z "${CI_HELPER_TESTS_CHECKED:-}"; fi
printf '%s\\n' "$1" >> "$ARTIFACTS_DIR/calls.txt"
pwd > "$ARTIFACTS_DIR/source.txt"
cp marker "$ARTIFACTS_DIR/marker.txt"
if [[ "$1" == "${SYNTHETIC_FAIL_SUITE:-}" ]]; then exit 65; fi
''')
        (self.repo / "marker").write_text("committed")
        self.git("add", ".")
        self.git("commit", "-m", "Synthetic fixture")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("config", "core.hooksPath", ".githooks")
        self.remote = self.base / "remote.git"
        self.git("init", "--bare", str(self.remote))

    def git(self, *args, check=True, env=None):
        return subprocess.run(["git", *args], cwd=self.repo, env=env or self.env,
                              text=True, capture_output=True, check=check)

    def artifacts(self):
        return list((self.repo / "artifacts/ci").glob("pre-push.*"))

    def invoke(self, lines, **environment):
        return subprocess.run(["bash", ".githooks/pre-push"], cwd=self.repo,
                              env=dict(self.env, **environment), input=lines,
                              text=True, capture_output=True)

    def test_push_uses_sent_commit_without_touching_head_or_dirty_files(self):
        (self.repo / "marker").write_text("newer HEAD")
        self.git("commit", "-am", "Newer fixture")
        head = self.git("rev-parse", "HEAD").stdout.strip()
        (self.repo / "marker").write_text("uncommitted")
        result = self.git("push", str(self.remote), f"{self.commit}:refs/heads/checked",
                          env=dict(self.env, GIT_DIR=str(self.repo / ".git")), check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "checked").stdout.strip(), self.commit)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), head)
        self.assertEqual((self.repo / "marker").read_text(), "uncommitted")
        [artifact] = self.artifacts()
        self.assertEqual((artifact / "marker.txt").read_text(), "committed")
        self.assertEqual((artifact / "calls.txt").read_text().splitlines(), ["test-spm", "test-ui"])
        self.assertFalse(Path((artifact / "source.txt").read_text().strip()).exists())

    def test_either_suite_failure_blocks_real_push_and_preserves_logs(self):
        for suite in ["test-spm", "test-ui"]:
            with self.subTest(suite=suite):
                result = self.git("push", str(self.remote), f"HEAD:refs/heads/{suite}",
                                  env=dict(self.env, SYNTHETIC_FAIL_SUITE=suite), check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotEqual(self.git("--git-dir", str(self.remote), "show-ref", "--verify",
                                             f"refs/heads/{suite}", check=False).returncode, 0)
        calls = sorted((p / "calls.txt").read_text().splitlines() for p in self.artifacts())
        self.assertEqual(calls, [["test-spm"], ["test-spm", "test-ui"]])
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_failure_exit_code_is_preserved(self):
        result = self.invoke(f"HEAD {self.commit} refs/heads/main {ZERO}\n", SYNTHETIC_FAIL_SUITE="test-spm")
        self.assertEqual(result.returncode, 65, result.stderr)

    def test_multiple_refs_to_one_commit_run_once(self):
        self.git("tag", "-a", "fixture", "-m", "Synthetic tag")
        result = self.git("push", str(self.remote), "main", "fixture", check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        [artifact] = self.artifacts()
        self.assertEqual((artifact / "calls.txt").read_text().splitlines(), ["test-spm", "test-ui"])

    def test_deletion_and_empty_push_do_not_run_tests(self):
        for lines in ["", f"(delete) {ZERO} refs/heads/main {self.commit}\n"]:
            result = self.invoke(lines)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.artifacts(), [])

    def test_installer_does_not_replace_another_hooks_path(self):
        self.git("config", "core.hooksPath", "custom-hooks")
        result = subprocess.run(["bash", "scripts/install-hooks.sh"], cwd=self.repo,
                                env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("config", "core.hooksPath").stdout.strip(), "custom-hooks")
        self.git("config", "--unset", "core.hooksPath")
        result = subprocess.run(["bash", "scripts/install-hooks.sh"], cwd=self.repo,
                                env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("config", "core.hooksPath").stdout.strip(), ".githooks")

    def test_installer_preserves_active_default_hook(self):
        self.git("config", "--unset", "core.hooksPath")
        hook = self.repo / ".git/hooks/pre-commit"
        hook.parent.mkdir(exist_ok=True)
        hook.write_text("#!/bin/sh\nexit 73\n")
        hook.chmod(0o755)
        for install in [False, True]:
            if install:
                result = subprocess.run(["bash", "scripts/install-hooks.sh"], cwd=self.repo,
                                        env=self.env, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
            result = self.git("commit", "--allow-empty", "-m", "Must remain blocked", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.commit)
        self.assertNotEqual(self.git("config", "--get", "core.hooksPath", check=False).returncode, 0)
        self.assertEqual(hook.read_text(), "#!/bin/sh\nexit 73\n")

    def test_installer_accepts_default_samples_and_can_run_twice(self):
        self.git("config", "--unset", "core.hooksPath")
        sample = self.repo / ".git/hooks/pre-commit.sample"
        sample.parent.mkdir(exist_ok=True)
        sample.write_text("#!/bin/sh\nexit 73\n")
        sample.chmod(0o755)
        for _ in range(2):
            result = subprocess.run(["bash", "scripts/install-hooks.sh"], cwd=self.repo,
                                    env=self.env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("config", "core.hooksPath").stdout.strip(), ".githooks")

    def test_fixture_ignores_user_git_configuration_and_templates(self):
        config = self.base / "user.gitconfig"
        config.write_text("[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /usr/bin/false\n")
        template = self.base / "user-template"
        hook = template / "hooks/pre-commit"
        hook.parent.mkdir(parents=True)
        hook.write_text("#!/bin/sh\nexit 73\n")
        hook.chmod(0o755)
        nested = PrePushTests()
        try:
            with patch.dict(os.environ, {
                "GIT_CONFIG_GLOBAL": str(config), "GIT_CONFIG_SYSTEM": str(config),
                "GIT_TEMPLATE_DIR": str(template), "GIT_DIR": str(self.base / "not-a-repository"),
                "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "commit.gpgsign", "GIT_CONFIG_VALUE_0": "true",
            }):
                nested.setUp()
                result = nested.git("push", str(nested.remote), "main", check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((nested.repo / ".git/hooks/pre-commit").exists())
        finally:
            nested.doCleanups()
