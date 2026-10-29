import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


GUARD = Path(__file__).with_name("offline_guard.py")


class OfflineGuardTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="offline-player-guard-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ("tool", "docs", "lib", "macos/Flutter", "macos/Runner"):
            (self.root / folder).mkdir(parents=True)
        (self.root / "pubspec.yaml").write_text("name: probe\ndependencies:\n  flutter:\n    sdk: flutter\n  media_kit: 1.2.6\n", encoding="utf-8")
        (self.root / "pubspec.lock").write_text("packages:\n  flutter:\n    dependency: 'direct main'\n    description: flutter\n    source: sdk\n    version: '0.0.0'\n  media_kit:\n    dependency: 'direct main'\n    description:\n      name: media_kit\n      sha256: abc123\n      url: 'https://pub.dev'\n    source: hosted\n    version: '1.2.6'\nsdks:\n  dart: '>=3.0.0'\n", encoding="utf-8")
        (self.root / ".flutter-plugins-dependencies").write_text(json.dumps({"plugins": {"macos": [{"name": "media_kit"}]}}), encoding="utf-8")
        (self.root / "lib/main.dart").write_text("void main() {}\n", encoding="utf-8")
        (self.root / "macos/Flutter/GeneratedPluginRegistrant.swift").write_text("import FlutterMacOS\nimport media_kit_video\n", encoding="utf-8")
        (self.root / "macos/Runner/Release.entitlements").write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    def run_guard(self, accept=False):
        report = self.root / "report.json"
        command = [sys.executable, str(GUARD), "--root", str(self.root), "--report", str(report)]
        if accept:
            command.append("--accept-baseline")
        result = subprocess.run(command, check=False, capture_output=True, text=True)
        return result, json.loads(report.read_text(encoding="utf-8"))

    def test_license_and_build_registry_urls_are_exempt(self):
        (self.root / "docs/LICENSE").write_text("https://enjoy.bot https://fsf.org", encoding="utf-8")
        ios = self.root / "ios/Runner"
        ios.mkdir(parents=True)
        (ios / "AudioBridge.swift").write_text('import AVFoundation\nimport MediaPlayer\nlet player = AVPlayer(url: URL(fileURLWithPath: "/local/test.mp3"))\n', encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(report["passed"])
        result, _ = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_forbidden_transitive_dependency_blocks_baseline_recording(self):
        lock = self.root / "pubspec.lock"
        lock.write_text(lock.read_text(encoding="utf-8").replace("sdks:", "  posthog_flutter:\n    dependency: transitive\n    source: hosted\n    version: '1.0.0'\nsdks:"), encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("posthog_flutter" in item["message"] for item in report["violations"]))
        self.assertFalse((self.root / "tool/dependency_baseline.json").exists())

    def test_native_plugin_and_service_config_are_blocked(self):
        (self.root / "macos/Flutter/GeneratedPluginRegistrant.swift").write_text("import FlutterMacOS\nimport auto_updater_macos\n", encoding="utf-8")
        (self.root / "macos/Runner/Info.plist").write_bytes(plistlib.dumps({"SUFeedURL": "https://dl.enjoy.bot/appcast.xml"}))
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("native plugin" in item["message"] for item in report["violations"]))
        self.assertTrue(any("endpoint" in item["message"] for item in report["violations"]))

    def test_network_api_and_official_domain_are_blocked(self):
        (self.root / "lib/main.dart").write_text("import 'dart:io';\nfinal x = HttpClient();\nfinal uri = 'https://worker.enjoy.bot';\n", encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("Network API" in item["message"] for item in report["violations"]))
        self.assertTrue(any("endpoint" in item["message"] for item in report["violations"]))

    def test_unknown_dependency_or_version_change_requires_review(self):
        result, _ = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 0)
        lock = self.root / "pubspec.lock"
        lock.write_text(lock.read_text(encoding="utf-8").replace("1.2.6", "1.2.7"), encoding="utf-8")
        result, report = self.run_guard()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("inventory changed" in item["message"] for item in report["violations"]))

    def test_release_network_entitlement_is_blocked(self):
        (self.root / "macos/Runner/Release.entitlements").write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True}))
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("Outgoing-network" in item["message"] for item in report["violations"]))

    def test_stale_or_unlocked_generated_plugin_is_blocked(self):
        (self.root / ".flutter-plugins-dependencies").write_text(json.dumps({"plugins": {"macos": [{"name": "unknown_plugin"}]}}), encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("plugin absent" in item["message"] for item in report["violations"]))

    def test_native_dependency_lock_is_also_checked(self):
        (self.root / "macos/Podfile.lock").write_text("PODS:\n  - PostHog (3.0)\n", encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("native dependency lock" in item["message"] for item in report["violations"]))
        (self.root / "macos/Podfile.lock").unlink()
        manifest = self.root / "macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('.package(url: "https://example.com/native-kit", from: "1.0.0")\n', encoding="utf-8")
        result, report = self.run_guard(accept=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("remote native dependency" in item["message"] for item in report["violations"]))


if __name__ == "__main__":
    unittest.main()
