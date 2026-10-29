#!/usr/bin/env python3
"""Check or apply the pinned Flutter PR 193372 framework backport.

Only the one reviewed framework source file is changed. No network requests,
third-party scripts, SDK updates, or engine changes are performed.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


PATCHES = Path(__file__).resolve().parent / "patches"
METADATA = PATCHES / "flutter-3.47.7-semantics-orphans.json"


def sha256(content):
    return hashlib.sha256(content).hexdigest()


def apply_reviewed_patch(original, patch, relative_path):
    """Apply uniquely matched unified hunks in order, entirely in memory."""
    text = patch.decode("utf-8")
    if text.count("diff --git ") != 1:
        raise ValueError("The reviewed patch must affect exactly one file")
    if f"--- a/{relative_path}\n+++ b/{relative_path}\n" not in text:
        raise ValueError("The reviewed patch targets an unexpected file")
    source = original.decode("utf-8").splitlines(keepends=True)
    lines = text.splitlines(keepends=True)
    output = []
    source_cursor = 0
    index = 0
    hunks = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("@@ "):
            index += 1
            continue
        match = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if not match:
            raise ValueError("Invalid reviewed patch hunk header")
        expected_old = int(match.group(2) or "1")
        expected_new = int(match.group(4) or "1")
        old = []
        new = []
        index += 1
        while len(old) < expected_old or len(new) < expected_new:
            if index >= len(lines):
                raise ValueError("Truncated reviewed patch hunk")
            part = lines[index]
            prefix = part[:1]
            if prefix not in {" ", "+", "-"}:
                raise ValueError("Unexpected reviewed patch hunk line")
            if prefix in {" ", "-"}:
                old.append(part[1:])
            if prefix in {" ", "+"}:
                new.append(part[1:])
            if len(old) > expected_old or len(new) > expected_new:
                raise ValueError("Reviewed patch hunk count mismatch")
            index += 1
        candidates = [
            position
            for position in range(source_cursor, len(source) - len(old) + 1)
            if source[position : position + len(old)] == old
        ]
        if len(candidates) != 1:
            raise ValueError("Reviewed patch context is absent or ambiguous")
        position = candidates[0]
        output.extend(source[source_cursor:position])
        output.extend(new)
        source_cursor = position + len(old)
        hunks += 1
    if hunks != 8:
        raise ValueError(f"Expected eight reviewed framework hunks, found {hunks}")
    output.extend(source[source_cursor:])
    return "".join(output).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    metadata = json.loads(METADATA.read_text(encoding="utf-8"))
    sdk = args.sdk.resolve()
    version = json.loads((sdk / "bin/cache/flutter.version.json").read_text(encoding="utf-8"))
    for field, expected in metadata["sdk"].items():
        if version.get(field) != expected:
            raise ValueError(f"SDK {field} mismatch; refusing to apply this pinned backport")
    patch = (PATCHES / metadata["patch_file"]).read_bytes()
    if sha256(patch) != metadata["patch_sha256"]:
        raise ValueError("Reviewed patch SHA-256 mismatch")
    target = sdk / metadata["runtime_file"]
    current = target.read_bytes()
    current_hash = sha256(current)
    if current_hash == metadata["target_sha256"]:
        print(f"PASS: Flutter 3.47.7 PR 193372 framework backport present ({current_hash})")
        return 0
    if current_hash != metadata["base_sha256"]:
        raise ValueError("Framework source differs from both reviewed base and target; refusing to overwrite")
    patched = apply_reviewed_patch(current, patch, metadata["runtime_file"])
    if sha256(patched) != metadata["target_sha256"]:
        raise ValueError("Patched framework target SHA-256 mismatch")
    if args.check:
        print("PATCH REQUIRED: pinned Flutter 3.47.7 has the reviewed unpatched semantics source", file=sys.stderr)
        return 1
    backup = target.with_name(target.name + ".before-pr-193372")
    if backup.exists():
        if sha256(backup.read_bytes()) != metadata["base_sha256"]:
            raise ValueError("Existing framework backup has an unexpected SHA-256")
    else:
        with backup.open("xb") as stream:
            stream.write(current)
            stream.flush()
            os.fsync(stream.fileno())
    temporary = target.with_name(target.name + ".pr-193372.tmp")
    try:
        with temporary.open("xb") as stream:
            stream.write(patched)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(stat.S_IMODE(target.stat().st_mode))
        temporary.replace(target)
    finally:
        if temporary.exists():
            temporary.unlink()
    print(f"APPLIED: official PR 193372 framework backport; engine unchanged ({metadata['target_sha256']})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
