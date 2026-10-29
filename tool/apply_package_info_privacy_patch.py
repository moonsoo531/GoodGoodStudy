#!/usr/bin/env python3
"""Patch one reviewed SDK resource before Xcode signs this app; never edit a cache."""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
METADATA = Path(__file__).resolve().parent / "patches/package_info_plus-10.2.2-privacy.json"
BUNDLE = "package_info_plus_package_info_plus.bundle"
VERSION = "10.2.2"


class Refused(ValueError):
    pass


def digest(value):
    return hashlib.sha256(value).hexdigest()


def metadata():
    data = json.loads(METADATA.read_text(encoding="utf-8"))
    if data.get("schema") != 1 or data.get("package") != "package_info_plus" or data.get("version") != VERSION:
        raise Refused("The reviewed patch metadata does not match package_info_plus 10.2.2")
    original = data["original_manifest_utf8"].encode("utf-8")
    source = plistlib.loads(original)
    expected_source = {
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyAccessedAPITypes": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyTracking": False,
    }
    if source != expected_source or digest(original) != data["original_manifest_sha256"]:
        raise Refused("The recorded original manifest hash or schema is not the reviewed source")
    patched = copy.deepcopy(source)
    patched["NSPrivacyAccessedAPITypes"] = [{
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
    }]
    result = plistlib.dumps(patched, fmt=plistlib.FMT_XML, sort_keys=True)
    if digest(result) != data["patched_manifest_sha256"]:
        raise Refused("The recorded patched manifest hash does not match the reviewed transformation")
    return data, source, patched, result


def dependency(root, data):
    lock = root / "pubspec.lock"
    text = lock.read_text(encoding="utf-8")
    match = re.search(r"(?m)^  package_info_plus:\n((?:[ ]{4}[^\n]*\n|\n)*)", text)
    if match is None:
        raise Refused("pubspec.lock has no package_info_plus entry")
    block = match.group(1)

    def field(name, indent):
        found = re.search(rf"(?m)^{' ' * indent}{name}:\s*([^\n]+)$", block)
        return found.group(1).strip().strip("\"'") if found else None

    if field("version", 4) != VERSION or field("source", 4) != "hosted":
        raise Refused("Only the reviewed hosted package_info_plus 10.2.2 dependency is supported")
    if field("sha256", 6) != data["pub_archive_sha256"]:
        raise Refused("The locked package archive checksum changed; review the SDK before patching")


def target(environ):
    products = environ.get("BUILT_PRODUCTS_DIR", "")
    target_products = environ.get("TARGET_BUILD_DIR", "")
    contents = environ.get("CONTENTS_FOLDER_PATH", "")
    platform = environ.get("PLATFORM_NAME", "")
    owner = environ.get("PRODUCT_BUNDLE_IDENTIFIER", "")
    relative = PurePosixPath(contents)
    if platform not in {"iphoneos", "iphonesimulator"}:
        raise Refused("This resource patch is only for an iOS device or simulator Xcode build")
    if not products or not Path(products).is_absolute():
        raise Refused("BUILT_PRODUCTS_DIR must name Xcode's absolute products directory")
    if not target_products or not Path(target_products).is_absolute():
        raise Refused("TARGET_BUILD_DIR must name Xcode's absolute target products directory")
    if not contents or relative.is_absolute() or len(relative.parts) != 1 or not contents.endswith(".app"):
        raise Refused("CONTENTS_FOLDER_PATH must be one iOS .app folder, without traversal")
    if not owner:
        raise Refused("PRODUCT_BUNDLE_IDENTIFIER is required to identify the owning app")
    products = Path(products).resolve(strict=True)
    target_products = Path(target_products).resolve(strict=True)
    app = target_products / contents
    if target_products != products:
        # Archive builds install the real app here and expose a build-product
        # alias. Validate that exact shared-root layout rather than following
        # arbitrary app/resource symlinks or writing through the alias.
        archive = products.parent.parent
        configuration = environ.get("CONFIGURATION", "")
        expected_target = archive / "InstallationBuildProductsLocation/Applications"
        if (
            products.parent.name != "BuildProductsPath"
            or archive.parent.name != "ArchiveIntermediates"
            or not configuration
            or products.name != f"{configuration}-{platform}"
            or target_products != expected_target
        ):
            raise Refused("Different build roots must match Xcode's standard shared Archive installation layout")
        alias = products / contents
        if not alias.is_symlink() or alias.resolve(strict=True) != app:
            raise Refused("The Archive build-product alias must resolve exactly to TARGET_BUILD_DIR's app")
    sdk = app / BUNDLE
    manifest = sdk / "PrivacyInfo.xcprivacy"
    for path in (app, app / "Info.plist", sdk, sdk / "Info.plist", manifest):
        if path.is_symlink():
            raise Refused("Refusing a symlink in the reviewed built-resource path")
        if not path.exists():
            raise Refused("The expected built SDK resource is missing; run this phase after resource copying")
        if target_products not in path.resolve().parents:
            raise Refused("The built-resource path escapes Xcode's target products directory")
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    info = plistlib.loads((sdk / "Info.plist").read_bytes())
    if not isinstance(app_info, dict) or not isinstance(info, dict):
        raise Refused("The app and SDK Info.plist must be dictionaries")
    if app_info.get("CFBundleIdentifier") != owner:
        raise Refused("The product identifier does not match the built app's Info.plist")
    if (
        info.get("CFBundleIdentifier") != "package-info-plus-10.2.2.package-info-plus.resources"
        or info.get("CFBundleName") != "package_info_plus_package_info_plus"
        or info.get("CFBundlePackageType") != "BNDL"
    ):
        raise Refused("The built SDK resource identity/version does not match the reviewed 10.2.2 bundle")
    if info.get("CFBundleExecutable") or (sdk / "_CodeSignature").exists():
        raise Refused("Only an unsigned resource-only SDK bundle is supported; do not invalidate a nested code signature")
    if not manifest.is_file():
        raise Refused("The SDK privacy resource is not a regular file")
    return manifest


def apply(root, environ, check=False):
    data, source, patched, result = metadata()
    dependency(root, data)
    path = target(environ)
    current = path.read_bytes()
    parsed = plistlib.loads(current)
    if digest(current) == data["patched_manifest_sha256"] and parsed == patched:
        return "READY: reviewed package_info_plus 10.2.2 SDK privacy resource is already patched"
    if digest(current) != data["original_manifest_sha256"] or parsed != source:
        raise Refused("The SDK manifest is neither the exact reviewed original nor the exact patched file")
    if check:
        raise Refused("The built SDK manifest still needs the reviewed FileTimestamp/C617.1 patch")
    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, name = tempfile.mkstemp(prefix=".PrivacyInfo.", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(result)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        # Resource identity is rechecked after preparation; no other path is writable.
        if target(environ) != path or path.read_bytes() != current:
            raise Refused("The SDK resource changed while preparing the patch")
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()
    return "PATCHED: package_info_plus 10.2.2 SDK resource FileTimestamp/C617.1; sign Runner afterwards"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Project containing the reviewed pubspec.lock")
    parser.add_argument("--check", action="store_true", help="Read-only: require the expected patched resource")
    args = parser.parse_args()
    try:
        print(apply(args.root.resolve(), os.environ, check=args.check))
        return 0
    except (Refused, OSError, ValueError, KeyError, TypeError) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
