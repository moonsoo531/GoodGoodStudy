"""Safety checks for the pinned SDK backport, using temporary SDK copies."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tool/apply_flutter_semantics_patch.py"
PATCHES = ROOT / "tool/patches"
METADATA_NAME = "flutter-3.47.7-semantics-orphans.json"


class FlutterSemanticsBackportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata = json.loads((PATCHES / METADATA_NAME).read_text(encoding="utf-8"))
        sdk = os.environ.get("FLUTTER_ROOT")
        executable = shutil.which("flutter")
        if sdk:
            sdk_root = Path(sdk).resolve()
        elif executable:
            sdk_root = Path(executable).resolve().parents[1]
        else:
            raise unittest.SkipTest("Set FLUTTER_ROOT or add flutter to PATH for the optional SDK patch tests")
        framework = sdk_root / cls.metadata["runtime_file"]
        candidates = [framework.with_name(framework.name + ".before-pr-193372"), framework]
        cls.baseline = None
        for candidate in candidates:
            if candidate.is_file():
                content = candidate.read_bytes()
                if hashlib.sha256(content).hexdigest() == cls.metadata["base_sha256"]:
                    cls.baseline = content
                    break
        if cls.baseline is None:
            raise unittest.SkipTest("Pinned Flutter baseline or its reviewed backup is not available")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="flutter-backport-test-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.sdk = root / "sdk"
        self.target = self.sdk / self.metadata["runtime_file"]
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(self.baseline)
        self.version = self.sdk / "bin/cache/flutter.version.json"
        self.version.parent.mkdir(parents=True)
        self.version.write_text(json.dumps(self.metadata["sdk"]), encoding="utf-8")
        self.backup = self.target.with_name(self.target.name + ".before-pr-193372")
        self.tool = root / "tool"
        self.tool.mkdir()
        shutil.copyfile(SCRIPT, self.tool / SCRIPT.name)
        shutil.copytree(PATCHES, self.tool / "patches")

    def run_tool(self, mode, expected):
        result = subprocess.run(
            [sys.executable, str(self.tool / SCRIPT.name), "--sdk", str(self.sdk), mode],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def assert_baseline_untouched(self):
        self.assertEqual(self.target.read_bytes(), self.baseline)
        self.assertFalse(self.backup.exists())

    def test_check_reports_required_patch_without_writing(self):
        self.run_tool("--check", 1)
        self.assert_baseline_untouched()
        self.assertFalse(self.target.with_name(self.target.name + ".pr-193372.tmp").exists())

    def test_apply_creates_reviewed_target_and_backup_and_is_idempotent(self):
        self.run_tool("--apply", 0)
        self.assertEqual(
            hashlib.sha256(self.target.read_bytes()).hexdigest(), self.metadata["target_sha256"]
        )
        self.assertEqual(self.backup.read_bytes(), self.baseline)
        first_mtime = self.target.stat().st_mtime_ns
        backup_mtime = self.backup.stat().st_mtime_ns
        self.run_tool("--check", 0)
        self.run_tool("--apply", 0)
        self.assertEqual(self.target.stat().st_mtime_ns, first_mtime)
        self.assertEqual(self.backup.stat().st_mtime_ns, backup_mtime)

    def test_unknown_source_hash_is_rejected_without_overwrite(self):
        unknown = self.baseline + b"\n// unreviewed modification\n"
        self.target.write_bytes(unknown)
        self.run_tool("--apply", 2)
        self.assertEqual(self.target.read_bytes(), unknown)
        self.assertFalse(self.backup.exists())

    def test_different_sdk_or_engine_version_is_rejected(self):
        for field in self.metadata["sdk"]:
            with self.subTest(field=field):
                version = {**self.metadata["sdk"], field: "unreviewed"}
                self.version.write_text(json.dumps(version), encoding="utf-8")
                self.run_tool("--apply", 2)
                self.assert_baseline_untouched()

    def test_altered_patch_is_rejected_before_applying(self):
        patch = self.tool / "patches" / self.metadata["patch_file"]
        patch.write_bytes(patch.read_bytes() + b"\n# unreviewed change\n")
        self.run_tool("--apply", 2)
        self.assert_baseline_untouched()

    def test_unexpected_target_hash_is_rejected_before_writing(self):
        path = self.tool / "patches" / METADATA_NAME
        metadata = {**self.metadata, "target_sha256": "0" * 64}
        path.write_text(json.dumps(metadata), encoding="utf-8")
        self.run_tool("--apply", 2)
        self.assert_baseline_untouched()

    def test_check_still_checks_patch_integrity_after_application(self):
        self.run_tool("--apply", 0)
        applied = self.target.read_bytes()
        patch = self.tool / "patches" / self.metadata["patch_file"]
        patch.write_bytes(patch.read_bytes() + b"\n# unreviewed change\n")
        self.run_tool("--check", 2)
        self.assertEqual(self.target.read_bytes(), applied)
        self.assertEqual(self.backup.read_bytes(), self.baseline)

    def test_conflicting_backup_is_not_overwritten(self):
        self.backup.write_bytes(b"unrelated backup")
        self.run_tool("--apply", 2)
        self.assertEqual(self.target.read_bytes(), self.baseline)
        self.assertEqual(self.backup.read_bytes(), b"unrelated backup")


if __name__ == "__main__":
    unittest.main()
