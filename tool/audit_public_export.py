#!/usr/bin/env python3
"""Inspect a clean source export without showing suspected secret values.

This is a local file audit, not a substitute for license review or security
testing. It neither contacts GitHub nor modifies repository visibility.
"""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
TOP_FOLDERS = {"lib", "test", "tool", "ios", "macos", "assets", "licenses", "docs", ".github"}
TOP_FILES = {
    "README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", ".gitignore",
    ".metadata", "analysis_options.yaml", "pubspec.yaml", "pubspec.lock",
    "flutterw", "flutter-local.sh", "CONTRIBUTING.md", "SECURITY.md",
}
PRIVATE_TESTS = {
    "test/quiz/quiz_ruby_render_test.dart",
    "test/quiz/quiz_sample_import_test.dart",
    "test/study/study_page_test.dart",
    "test/study/study_resume_store_test.dart",
    "test/widgets/ruby_layout_regression_test.dart",
}
BLOCKED_PARTS = {
    "build", "dist", ".dart_tool", ".idea", "Pods", "ephemeral",
    ".symlinks", "xcuserdata", ".build", "__pycache__", "validation",
    "Sample", "学习资源包", "测试资源包", "private",
}
BLOCKED_SUFFIXES = {
    ".zip", ".ipa", ".mobileprovision", ".p12", ".p8", ".pem", ".key",
    ".cer", ".crt", ".pdf", ".mp3", ".m4a", ".aac", ".wav", ".caf",
    ".aif", ".aiff", ".mp4", ".mkv", ".mov", ".srt", ".vtt", ".log",
}
GENERATED_FILES = {
    "ios/Flutter/Generated.xcconfig", "ios/Flutter/Flutter.podspec",
    "ios/Flutter/flutter_export_environment.sh",
    "ios/Runner/GeneratedPluginRegistrant.h", "ios/Runner/GeneratedPluginRegistrant.m",
    ".flutter-plugins", ".flutter-plugins-dependencies",
}
PATTERNS = {
    "personal-home-path": re.compile(r"/Users/[A-Za-z0-9._-]+/"),
    "private-host-cache": re.compile(r"/private/var/folders/[A-Za-z0-9]+/"),
    "device-identifier": re.compile(r"\b0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}\b"),
    "github-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "cloud-access-key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "slack-token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{16,}\b"),
    "personal-signing-identity": re.compile(r"Apple Development:\s+[^\r\n]+"),
    "local-resource-reference": re.compile(r"\.\./(?:Sample|学习资源包|测试资源包)/"),
    "local-sdk-reference": re.compile(r"\.\./\.tools/"),
}


def source_files(root):
    # In a Git worktree, inspect files that could actually enter a commit,
    # including already-tracked files even when a later ignore rule hides them.
    if (root / ".git").exists():
        result = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=root, capture_output=True, check=True,
        )
        return [root / name.decode("utf-8") for name in sorted(set(result.stdout.split(b"\0"))) if name]
    return sorted(path for path in root.rglob("*") if ".git" not in path.relative_to(root).parts and (path.is_file() or path.is_symlink()))


def audit(root):
    findings = []
    manifest = []

    def issue(relative, label, line=None):
        item = {"file": relative, "rule": label}
        if line is not None:
            item["line"] = line
        findings.append(item)

    for path in source_files(root):
        relative = path.relative_to(root).as_posix()
        parts = path.relative_to(root).parts
        if len(parts) == 1 and relative.startswith("public-export-") and path.suffix == ".json":
            continue
        if path.is_symlink():
            issue(relative, "symlink-not-exportable")
            continue
        if not path.is_file():
            issue(relative, "missing-source-file")
            continue
        if parts[0] not in TOP_FOLDERS and relative not in TOP_FILES:
            issue(relative, "outside-source-allowlist")
        if any(part in BLOCKED_PARTS or part.endswith((".app", ".dSYM", ".xcarchive")) for part in parts):
            issue(relative, "private-or-generated-directory")
        if path.suffix.lower() in BLOCKED_SUFFIXES or relative in GENERATED_FILES:
            issue(relative, "private-resource-or-generated-file")
        if relative in PRIVATE_TESTS:
            issue(relative, "private-material-test")
        raw = path.read_bytes()
        manifest.append({"path": relative, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
        if len(raw) > 5 * 1024 * 1024:
            issue(relative, "oversized-source-file")
            continue
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".ico", ".icns"}:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            issue(relative, "unexpected-binary-file")
            continue
        for label, pattern in PATTERNS.items():
            for match in pattern.finditer(text):
                issue(relative, label, text.count("\n", 0, match.start()) + 1)
        if path.suffix == ".pbxproj":
            for match in re.finditer(r"DEVELOPMENT_TEAM\s*=\s*([^;]+);", text):
                if match.group(1).strip().strip('"'):
                    issue(relative, "personal-development-team", text.count("\n", 0, match.start()) + 1)
        if path.suffix == ".py":
            try:
                ast.parse(text, filename=relative)
            except SyntaxError as error:
                issue(relative, "python-syntax", error.lineno)
    info = root / "ios/Runner/Info.plist"
    if info.exists() and plistlib.loads(info.read_bytes()).get("IOSAudioValidationEnabled", False):
        issue("ios/Runner/Info.plist", "release-diagnostics-enabled")
    report = {"passed": not findings, "files_checked": len(manifest), "findings": findings}
    return report, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    report, manifest = audit(args.root.resolve())
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.manifest:
        args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
