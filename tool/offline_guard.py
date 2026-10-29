#!/usr/bin/env python3
"""Reviewable static checks for the offline application, not a network monitor."""

import argparse
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tool" / "dependency_baseline.json"
IGNORED_PARTS = {"Pods", ".symlinks", "ephemeral", "build", ".git"}
DENIED_PACKAGE = re.compile(
    r"(?:^|_)(?:firebase|supabase|appwrite|amplify|posthog|sentry|mixpanel|"
    r"amplitude|segment|appsflyer|adjust|admob|ads|advertising|analytics|"
    r"purchases|revenuecat|in_app_purchase|stripe|auth|sign_in|signin|"
    r"auto_updater|ota_update|hot_updater|shorebird|azure_speech|"
    r"ai_sdk|openai|anthropic|google_generative_ai|remote_config)(?:_|$)",
    re.I,
)
DENIED_PLUGIN = re.compile(
    r"posthog|sentry|firebase|supabase|appwrite|analytics|admob|"
    r"googlemobileads|revenuecat|purchases|inapppurchase|stripe|"
    r"google.?sign.?in|sign.?in.?with.?apple|azure.?speech|"
    r"auto.?updater|ota.?update|sparkle|shorebird",
    re.I,
)
DENIED_HOST_SUFFIXES = (
    "enjoy.bot", "enjoy.ai", "posthog.com", "posthog.eu", "sentry.io",
    "api.openai.com", "api.anthropic.com", "api.deepseek.com",
    "api.groq.com", "generativelanguage.googleapis.com",
    "speech.microsoft.com", "speech.azure.com", "cognitiveservices.azure.com",
    "doubleclick.net", "googlesyndication.com", "google-analytics.com",
)
NETWORK_API = re.compile(
    r"\b(?:HttpClient|HttpServer|WebSocket|WebSocketChannel|NetworkImage|"
    r"NetworkAssetBundle|CachedNetworkImage|Dio)\s*[.(]|"
    r"\b(?:Socket|SecureSocket|RawSocket|RawDatagramSocket|InternetAddress)"
    r"\s*\.\s*(?:connect|bind|lookup)|\bImage\s*\.\s*network\s*\(|"
    r"\b(?:URLSession|NSURLConnection|WKWebView|SFSafariViewController)\b|"
    r"\b(?:HttpURLConnection|OkHttpClient)\b"
)
NETWORK_IMPORT = re.compile(
    r"(?:import|export)\s+['\"](?:package:(?:http|dio|web_socket_channel|"
    r"webview_flutter|flutter_inappwebview|url_launcher)/|dart:html)"
)
SERVICE_CONFIG = re.compile(
    r"POSTHOG_API_KEY|POSTHOG_HOST|SENTRY_DSN|SUFeedURL|SUPublicEDKey|"
    r"FirebaseApp|GoogleService-Info|GADApplicationIdentifier|"
    r"enjoy\.bot|ai\.enjoy\.player",
    re.I,
)
URL = re.compile(r"https?://[^\s'\"<>\\)\]}]+", re.I)
NATIVE_SUFFIXES = {
    ".swift", ".m", ".mm", ".h", ".plist", ".entitlements", ".xcconfig",
    ".pbxproj", ".gradle", ".kts", ".kt", ".java", ".xml", ".cmake",
}
SDK_MODULES = {"Cocoa", "Foundation", "FlutterMacOS", "Flutter", "UIKit"}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_entries(path, lock=False):
    entries = {}
    section = None
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        top = re.match(r"^([a-zA-Z_][\w]*):", line)
        if top:
            section = top.group(1)
            current = None
        if section not in ({"packages"} if lock else {"dependencies", "dev_dependencies", "dependency_overrides"}):
            continue
        match = re.match(r"^  ([a-zA-Z_][\w]*):(?:\s+(.*))?$", line)
        if match:
            current = match.group(1)
            entries[current] = {"section": section}
            if match.group(2):
                entries[current]["constraint"] = match.group(2).strip("'\"")
        elif current:
            item = re.match(r"^    (dependency|version|source|sdk|path|git):\s*(.*)$", line)
            if item:
                entries[current][item.group(1)] = item.group(2).strip("'\"")
            digest = re.match(r"^      sha256:\s*(.*)$", line)
            if digest:
                entries[current]["sha256"] = digest.group(1).strip("'\"")
    return entries


def native_files(root):
    for platform in ("macos", "ios", "android", "windows", "linux"):
        folder = root / platform
        if not folder.exists():
            continue
        for path in folder.rglob("*"):
            if not path.is_file() or any(part in IGNORED_PARTS or part.endswith("Tests") for part in path.relative_to(root).parts):
                continue
            if path.suffix in NATIVE_SUFFIXES or path.name in {"Podfile", "Podfile.lock", "CMakeLists.txt"}:
                yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--accept-baseline", action="store_true", help="After manual review, record the current dependency inventory")
    args = parser.parse_args()
    root = args.root.resolve()
    baseline = root / "tool" / BASELINE.name
    violations = []
    notices = []
    scanned = []
    endpoints = []

    def issue(path, message, line=None):
        relative = str(path.relative_to(root))
        violations.append({"file": relative, "line": line, "message": message})

    pubspec = root / "pubspec.yaml"
    lock = root / "pubspec.lock"
    declared = package_entries(pubspec) if pubspec.exists() else {}
    packages = package_entries(lock, lock=True) if lock.exists() else {}
    for path in (pubspec, lock):
        if not path.exists():
            issue(path, "Missing dependency file; resolve and review dependencies before claiming a pass")
    for name in sorted(set(declared) | set(packages)):
        if DENIED_PACKAGE.search(name):
            issue(lock if name in packages else pubspec, f"Forbidden service dependency: {name}")
    for name, values in packages.items():
        if values.get("source") not in {"hosted", "sdk"}:
            issue(lock, f"Unreviewed dependency source for {name}: {values.get('source')}")
    for name, values in declared.items():
        if "git" in values or "path" in values:
            issue(pubspec, f"Local/git dependency requires a separate source audit: {name}")
    for name, values in declared.items():
        if name not in packages:
            issue(lock, f"Declared package absent from lock: {name}")
        if values["section"] == "dependencies" and values.get("constraint", "").startswith("^"):
            notices.append(f"{name} uses a range; the reviewed lock still fixes the resolved version")

    plugin_metadata = root / ".flutter-plugins-dependencies"
    plugins = {}
    if plugin_metadata.exists():
        try:
            metadata = json.loads(plugin_metadata.read_text(encoding="utf-8"))
            plugins = {platform: sorted(plugin["name"] for plugin in rows) for platform, rows in metadata.get("plugins", {}).items()}
            for platform, names in plugins.items():
                for name in names:
                    if name not in packages:
                        issue(plugin_metadata, f"Generated plugin absent from reviewed lock: {name}")
                    if DENIED_PACKAGE.search(name) or DENIED_PLUGIN.search(name):
                        issue(plugin_metadata, f"Forbidden generated plugin for {platform}: {name}")
        except (KeyError, TypeError, json.JSONDecodeError) as error:
            issue(plugin_metadata, f"Cannot parse plugin metadata: {error}")
    else:
        issue(plugin_metadata, "Plugin metadata missing; run flutter pub get")

    dart_files = list((root / "lib").rglob("*.dart"))
    registry = {}
    for path in sorted(set(dart_files + list(native_files(root)))):
        content = path.read_text(encoding="utf-8", errors="replace")
        scanned.append(str(path.relative_to(root)))
        if "GeneratedPluginRegistrant" in path.name or "generated_plugin_registrant" in path.name:
            imports = re.findall(r"^import\s+(\w+)", content, flags=re.M)
            imports += re.findall(r"#import\s+<([^/>]+)/", content)
            registry[str(path.relative_to(root))] = sorted(set(imports) - SDK_MODULES)
            for name in registry[str(path.relative_to(root))]:
                if DENIED_PLUGIN.search(name) or DENIED_PACKAGE.search(name):
                    issue(path, f"Forbidden native plugin import: {name}")
        for number, line in enumerate(content.splitlines(), 1):
            if NETWORK_API.search(line) or NETWORK_IMPORT.search(line):
                issue(path, "Network API or remote-content import in runtime code", number)
            if SERVICE_CONFIG.search(line):
                issue(path, "Official-service identity, telemetry or updater configuration", number)
            if path.name == "Podfile.lock" and DENIED_PLUGIN.search(line):
                issue(path, "Forbidden service component in native dependency lock", number)
            for match in URL.finditer(line):
                endpoint = match.group(0)
                host = (urlsplit(endpoint).hostname or "").lower()
                endpoints.append({"file": str(path.relative_to(root)), "line": number, "host": host})
                if any(host == suffix or host.endswith("." + suffix) for suffix in DENIED_HOST_SUFFIXES):
                    issue(path, f"Forbidden service endpoint: {host}", number)
        if path.suffix == ".entitlements":
            try:
                entitlements = plistlib.loads(path.read_bytes())
                if entitlements.get("com.apple.security.network.client"):
                    issue(path, "Outgoing-network entitlement is enabled")
                if path.name == "Release.entitlements":
                    if entitlements.get("com.apple.security.network.server"):
                        issue(path, "Release must not enable incoming-network entitlement")
                    if not entitlements.get("com.apple.security.app-sandbox"):
                        issue(path, "Release sandbox must be enabled")
            except (plistlib.InvalidFileException, ValueError) as error:
                issue(path, f"Cannot parse entitlements: {error}")

    required = [root / "macos/Flutter/GeneratedPluginRegistrant.swift", root / "macos/Runner/Release.entitlements"]
    for path in required:
        if not path.exists():
            issue(path, "Required macOS generated/release configuration missing")
    if not dart_files:
        issue(root / "lib", "No runtime Dart files found")
    native_locks = {}
    swift_manifests = {}
    for platform in ("macos", "ios"):
        for filename in ("Podfile.lock", "Package.resolved"):
            for path in (root / platform).rglob(filename):
                if not any(part in IGNORED_PARTS for part in path.relative_to(root).parts):
                    native_locks[str(path.relative_to(root))] = sha256(path)
        manifest = root / platform / "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
        if manifest.exists():
            swift_manifests[str(manifest.relative_to(root))] = sha256(manifest)
            for number, line in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
                if DENIED_PLUGIN.search(line):
                    issue(manifest, "Forbidden service component in generated Swift package", number)
                if re.search(r"\.package\s*\([^\n]*\burl\s*:", line):
                    issue(manifest, "Generated Swift package adds a remote native dependency; review its pinned source separately", number)
    inventory = {"declared_dependencies": declared, "packages": packages, "plugins": plugins, "registrant_imports": registry, "native_dependency_lock_sha256": native_locks, "generated_swift_manifest_sha256": swift_manifests}
    inventory["pubspec_lock_sha256"] = sha256(lock) if lock.exists() else None
    if args.accept_baseline:
        if violations:
            notices.append("Baseline was not changed because hard checks failed")
        else:
            baseline.write_text(json.dumps(inventory, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            notices.append("Dependency baseline recorded; this is a review action, not evidence of runtime network behavior")
    elif not baseline.exists():
        issue(baseline, "No reviewed dependency baseline; inspect inventory then explicitly use --accept-baseline")
    else:
        try:
            recorded = json.loads(baseline.read_text(encoding="utf-8"))
            if inventory != recorded:
                issue(baseline, "Dependency lock or native-plugin inventory changed; manually review the diff before recording a new baseline")
        except json.JSONDecodeError as error:
            issue(baseline, f"Cannot parse dependency baseline: {error}")
    report = {
        "scope": "static source/configuration/dependency audit; no runtime network capture",
        "passed": not violations,
        "inventory": inventory,
        "files_scanned": scanned,
        "runtime_url_hosts_for_review": endpoints,
        "violations": violations,
        "notices": notices,
        "limitations": [
            "Does not inspect dependency implementation or native binaries for all network code",
            "media_kit/libmpv supports network protocols; callers must accept local files only",
            "Generated registrants and lock entries show inclusion, not all possible runtime behavior",
            "Documents, licenses, tests, tool scripts and build-time download URLs are deliberately outside runtime-source scanning",
            "Use a Release build and the separate runtime-network procedure before making a no-network claim",
        ],
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{'PASS' if report['passed'] else 'FAIL'}: {len(packages)} locked packages, {len(scanned)} runtime/config files, {sum(map(len, plugins.values()))} platform plugin entries")
    for violation in violations:
        location = violation["file"] + (f":{violation['line']}" if violation["line"] else "")
        print(f"  {location}: {violation['message']}")
    if args.report:
        print(f"Report: {args.report}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
