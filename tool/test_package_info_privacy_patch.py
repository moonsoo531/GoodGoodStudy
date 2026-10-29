import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("apply_package_info_privacy_patch.py")
METADATA = json.loads((SCRIPT.parent / "patches/package_info_plus-10.2.2-privacy.json").read_text())


class PackageInfoPrivacyPatchTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ggs-sdk-privacy-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.products = self.root / "products"
        self.app = self.products / "Runner.app"
        self.sdk = self.app / "package_info_plus_package_info_plus.bundle"
        self.sdk.mkdir(parents=True)
        self.target = self.sdk / "PrivacyInfo.xcprivacy"
        self.original = METADATA["original_manifest_utf8"].encode()
        self.target.write_bytes(self.original)
        (self.app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "dev.example.synthetic"}))
        self.bundle_info = self.sdk / "Info.plist"
        self.bundle_info.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "package-info-plus-10.2.2.package-info-plus.resources",
            "CFBundleName": "package_info_plus_package_info_plus",
            "CFBundlePackageType": "BNDL",
        }))
        (self.root / "pubspec.lock").write_text(
            'packages:\n  package_info_plus:\n    dependency: transitive\n'
            '    description:\n      name: package_info_plus\n'
            f'      sha256: "{METADATA["pub_archive_sha256"]}"\n'
            '      url: "https://pub.dev"\n    source: hosted\n    version: "10.2.2"\n'
            '  unrelated_package:\n    source: hosted\n    version: "1.0.0"\n'
        )
        self.environment = {
            **os.environ,
            "BUILT_PRODUCTS_DIR": str(self.products),
            "TARGET_BUILD_DIR": str(self.products),
            "CONTENTS_FOLDER_PATH": "Runner.app",
            "PLATFORM_NAME": "iphoneos",
            "PRODUCT_BUNDLE_IDENTIFIER": "dev.example.synthetic",
        }

    def archive_layout(self):
        archive = self.root / "ArchiveIntermediates/Runner"
        products = archive / "BuildProductsPath/Release-iphoneos"
        installation = archive / "InstallationBuildProductsLocation/Applications"
        products.mkdir(parents=True)
        installation.mkdir(parents=True)
        actual_app = installation / "Runner.app"
        self.app.rename(actual_app)
        alias = products / "Runner.app"
        alias.symlink_to(os.path.relpath(actual_app, products), target_is_directory=True)
        self.app = actual_app
        self.sdk = actual_app / "package_info_plus_package_info_plus.bundle"
        self.target = self.sdk / "PrivacyInfo.xcprivacy"
        self.bundle_info = self.sdk / "Info.plist"
        self.environment.update({
            "BUILT_PRODUCTS_DIR": str(products),
            "TARGET_BUILD_DIR": str(installation),
            "CONFIGURATION": "Release",
        })
        return alias, installation

    def run_patch(self, check=False, environment=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)] + (["--check"] if check else []),
            env=environment or self.environment, capture_output=True, text=True, check=False,
        )

    def test_patch_changes_only_sdk_manifest_and_preserves_original_declarations(self):
        app_manifest = self.app / "PrivacyInfo.xcprivacy"
        app_manifest.write_text("app-owned manifest must remain untouched")
        source_copy = self.root / "synthetic-read-only-sdk-source.xcprivacy"
        source_copy.write_bytes(self.original)
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        result = self.run_patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        patched = plistlib.loads(self.target.read_bytes())
        self.assertEqual(patched["NSPrivacyAccessedAPITypes"], [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        }])
        for key, value in plistlib.loads(self.original).items():
            if key != "NSPrivacyAccessedAPITypes":
                self.assertEqual(patched[key], value)
        self.assertEqual(hashlib.sha256(self.target.read_bytes()).hexdigest(), METADATA["patched_manifest_sha256"])
        changed = [p for p, raw in before.items() if p.read_bytes() != raw]
        self.assertEqual(changed, [self.target])
        self.assertEqual(set(before), {p for p in self.root.rglob("*") if p.is_file()})

    def test_repeated_apply_is_idempotent_and_check_mode_never_patches(self):
        result = self.run_patch(check=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), self.original)
        self.assertEqual(self.run_patch().returncode, 0)
        before = self.target.stat().st_mtime_ns
        self.assertEqual(self.run_patch().returncode, 0)
        self.assertEqual(self.run_patch(check=True).returncode, 0)
        self.assertEqual(self.target.stat().st_mtime_ns, before)

    def test_unknown_original_schema_or_content_is_refused_without_rewriting(self):
        changed = plistlib.loads(self.original)
        changed["NSPrivacyTracking"] = True
        raw = plistlib.dumps(changed)
        self.target.write_bytes(raw)
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("neither the exact reviewed original", result.stderr)
        self.assertEqual(self.target.read_bytes(), raw)

    def test_wrong_dependency_version_or_archive_checksum_is_refused(self):
        lock = self.root / "pubspec.lock"
        original = lock.read_text()
        for changed in [original.replace('version: "10.2.2"', 'version: "10.2.3"'), original.replace(METADATA["pub_archive_sha256"], "0" * 64)]:
            with self.subTest(lock=changed):
                lock.write_text(changed)
                result = self.run_patch()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_wrong_built_sdk_identity_is_refused(self):
        info = plistlib.loads(self.bundle_info.read_bytes())
        info["CFBundleIdentifier"] = "package-info-plus-10.2.3.package-info-plus.resources"
        self.bundle_info.write_bytes(plistlib.dumps(info))
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity/version", result.stderr)
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_symlink_target_cannot_change_an_external_manifest(self):
        external = self.root / "external.xcprivacy"
        external.write_bytes(self.original)
        self.target.unlink()
        self.target.symlink_to(external)
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertEqual(external.read_bytes(), self.original)

    def test_executable_or_independently_signed_sdk_bundle_is_refused(self):
        original = self.bundle_info.read_bytes()
        for executable in [True, False]:
            with self.subTest(executable=executable):
                info = plistlib.loads(original)
                if executable:
                    info["CFBundleExecutable"] = "unexpected-code"
                else:
                    (self.sdk / "_CodeSignature").mkdir()
                self.bundle_info.write_bytes(plistlib.dumps(info))
                result = self.run_patch()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("resource-only", result.stderr)
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_invalid_build_path_or_platform_is_refused(self):
        for key, value in [("CONTENTS_FOLDER_PATH", "../Other.app"), ("CONTENTS_FOLDER_PATH", str(self.app)), ("PLATFORM_NAME", "macosx"), ("PRODUCT_BUNDLE_IDENTIFIER", "dev.example.other")]:
            with self.subTest(key=key, value=value):
                result = self.run_patch(environment={**self.environment, key: value})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_missing_expected_bundle_does_not_search_or_patch_lookalikes(self):
        self.target.unlink()
        lookalike = self.app / "lookalike.bundle"
        lookalike.mkdir()
        another = lookalike / "PrivacyInfo.xcprivacy"
        another.write_bytes(self.original)
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing", result.stderr)
        self.assertEqual(another.read_bytes(), self.original)

    def test_standard_archive_alias_patches_only_the_real_installed_resource(self):
        alias, installation = self.archive_layout()
        result = self.run_patch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(alias.is_symlink())
        self.assertEqual(alias.resolve(), installation / "Runner.app")
        self.assertEqual(hashlib.sha256(self.target.read_bytes()).hexdigest(), METADATA["patched_manifest_sha256"])
        self.assertEqual(self.run_patch(check=True).returncode, 0)

    def test_archive_alias_and_target_cannot_escape_the_shared_archive_root(self):
        alias, _ = self.archive_layout()
        outside = self.root / "untrusted/Applications"
        outside.mkdir(parents=True)
        self.app.rename(outside / "Runner.app")
        alias.unlink()
        alias.symlink_to(outside / "Runner.app", target_is_directory=True)
        external_manifest = outside / "Runner.app/package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy"
        result = self.run_patch(environment={**self.environment, "TARGET_BUILD_DIR": str(outside)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shared Archive installation layout", result.stderr)
        self.assertEqual(external_manifest.read_bytes(), self.original)

    def test_archive_alias_must_match_the_target_and_sdk_symlinks_remain_forbidden(self):
        alias, _ = self.archive_layout()
        alias.unlink()
        other = self.root / "other.app"
        other.mkdir()
        alias.symlink_to(other, target_is_directory=True)
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("resolve exactly", result.stderr)
        self.assertEqual(self.target.read_bytes(), self.original)
        alias.unlink()
        alias.symlink_to(self.app, target_is_directory=True)
        external = self.root / "external.xcprivacy"
        external.write_bytes(self.original)
        self.target.unlink()
        self.target.symlink_to(external)
        result = self.run_patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertEqual(external.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
