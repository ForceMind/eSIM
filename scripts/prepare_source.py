#!/usr/bin/env python3
"""Prepare the pinned upstream source in a disposable directory."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = "https://github.com/iebb/NekokoLPA2.git"
BASELINE = "6d2145a515557941f10c5ebbf734d01f7d05fb43"
APP_ID = "io.github.forcemind.nekokolpa.issue62.v5"
APP_NAME = "9eSIM Test 5"
VERSION = "2.5.0-issue62.5+5"
ANDROID = "{http://schemas.android.com/apk/res/android}"
ET.register_namespace("android", ANDROID[1:-1])


def run(*args: str, cwd: Path) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def replace_exact(text: str, old: str, new: str, count: int = 1) -> str:
    if text.count(old) != count:
        raise RuntimeError(f"Source precondition failed for {old!r}")
    return text.replace(old, new)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "source")
    args = parser.parse_args()
    source = args.source.resolve()
    if source.exists() and any(source.iterdir()):
        raise RuntimeError("Refusing to overwrite a nonempty source directory")
    source.mkdir(parents=True, exist_ok=True)
    run("git", "init", "-q", cwd=source)
    run("git", "remote", "add", "origin", UPSTREAM, cwd=source)
    run("git", "fetch", "--depth=1", "origin", BASELINE, cwd=source)
    run("git", "checkout", "--detach", "FETCH_HEAD", cwd=source)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if head != BASELINE:
        raise RuntimeError("Upstream revision mismatch")

    patch = ROOT / "patches/issue62-v2.patch"
    run("git", "apply", "--check", str(patch), cwd=source)
    run("git", "apply", str(patch), cwd=source)

    diagnostics_patch = ROOT / "patches/issue62-diagnostics.patch"
    run("git", "apply", "--check", str(diagnostics_patch), cwd=source)
    run("git", "apply", str(diagnostics_patch), cwd=source)

    # Add the system STK recovery route after the diagnostic patch.
    overlay = ROOT / "overlays/stk"
    for relative in (
        "android/app/src/main/kotlin/ee/nekoko/nlpa2/StkRecoveryBridge.kt",
        "lib/pages/stk_recovery_page.dart",
    ):
        shutil.copy2(overlay / relative, source / relative)

    activity = source / "android/app/src/main/kotlin/ee/nekoko/nlpa2/MainActivity.kt"
    activity.write_text(replace_exact(
        activity.read_text(),
        "        flutterEngine.plugins.add(AdbBridgePlugin())",
        '        flutterEngine.plugins.add(AdbBridgePlugin())\n'
        '        val stkBridge = StkRecoveryBridge(this)\n'
        '        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger,\n'
        '            "io.github.forcemind/stk_recovery").setMethodCallHandler(stkBridge::handle)',
    ))
    settings_page = source / "lib/pages/settings_page.dart"
    page = replace_exact(settings_page.read_text(), "import 'issue62_diagnostics_page.dart';",
                         "import 'issue62_diagnostics_page.dart';\nimport 'stk_recovery_page.dart';")
    page = replace_exact(page, "children: [_buildIssue62DiagnosticsLink(context, width)],",
                         "children: [_buildIssue62DiagnosticsLink(context, width),\n"
                         "                      _buildStkRecoveryLink(context, width)],")
    page = replace_exact(page, "  Widget _buildIssue62DiagnosticsLink(",
                         """  Widget _buildStkRecoveryLink(BuildContext context, double screenWidth) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return _buildResponsiveTile(
      context,
      screenWidth: screenWidth,
      icon: const Icon(Icons.sim_card_outlined),
      title: zh ? 'SIM 卡工具包（STK）' : 'SIM Toolkit (STK)',
      subtitle: zh ? '通过系统菜单手动切卡' : 'Switch profiles manually in system UI',
      child: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const StkRecoveryPage()),
      ),
    );
  }

  Widget _buildIssue62DiagnosticsLink(""")
    settings_page.write_text(page)
    diagnostics_page = source / "lib/pages/issue62_diagnostics_page.dart"
    diagnostics_page.write_text(diagnostics_page.read_text().replace("Test 4", "Test 5").replace("test4-diagnostics", "test5-diagnostics"))

    gradle = source / "android/app/build.gradle.kts"
    text = replace_exact(gradle.read_text(), 'applicationId = "ee.nekoko.nlpa2.open"',
                         f'applicationId = "{APP_ID}"', 2)
    text = replace_exact(text, 'manifestPlaceholders["appName"] = "NekokoLPA 2 Community"',
                         f'manifestPlaceholders["appName"] = "{APP_NAME}"')
    gradle.write_text(text)

    # Keep the public shared core; make the in-app title identify this lab build.
    # Card compatibility comes from the verified signer set, not this label.
    settings = source / "lib/settings/app_settings.dart"
    settings.write_text(replace_exact(
        settings.read_text(),
        "if (v == 'community') return 'NekokoLPA 2 Community';",
        f"if (v == 'community') return '{APP_NAME}';",
    ))

    manifest = source / "android/app/src/main/AndroidManifest.xml"
    tree = ET.fromstring(manifest.read_text())
    app = tree.find("application")
    if app is None:
        raise RuntimeError("Missing Android application")
    for node in [app, *list(app)]:
        name = node.get(ANDROID + "name", "")
        if name.startswith("."):
            node.set(ANDROID + "name", "ee.nekoko.nlpa2" + name)
    removed = 0
    for activity in app.findall("activity"):
        for intent in list(activity.findall("intent-filter")):
            if any(a.get(ANDROID + "name") == "android.intent.action.VIEW" for a in intent.findall("action")):
                activity.remove(intent)
                removed += 1
    if removed != 2:
        raise RuntimeError(f"Expected two original deep-link filters; found {removed}")
    queries = tree.find("queries")
    if queries is None:
        queries = ET.SubElement(tree, "queries")
    for package in ("com.android.stk", "com.android.stk1", "com.android.stk2"):
        if not any(p.get(ANDROID + "name") == package for p in queries.findall("package")):
            ET.SubElement(queries, "package", {ANDROID + "name": package})
    ET.indent(tree, space="    ")
    manifest.write_text(ET.tostring(tree, encoding="unicode") + "\n")

    pubspec = source / "pubspec.yaml"
    text, count = re.subn(r"^version:\s*\S+", f"version: {VERSION}", pubspec.read_text(), count=1, flags=re.M)
    if count != 1:
        raise RuntimeError("Missing pubspec version")
    pubspec.write_text(text)
    version_name, build_number = VERSION.split("+", 1)
    version_file = source / "lib/version.dart"
    version_text = replace_exact(version_file.read_text(),
                                 "const String kAppVersion = '2.5.0';",
                                 f"const String kAppVersion = '{version_name}';")
    version_text = replace_exact(version_text,
                                 "const String kAppBuildNumber = '606';",
                                 f"const String kAppBuildNumber = '{build_number}';")
    version_file.write_text(version_text)

    tests = source / "test/issue62"
    tests.mkdir(parents=True, exist_ok=True)
    for test in (ROOT / "tests").glob("*_test.dart"):
        shutil.copy2(test, tests / test.name)

    metadata = {
        "upstream_repository": "iebb/NekokoLPA2", "upstream_commit": BASELINE,
        "application_id": APP_ID, "application_name": APP_NAME, "version": VERSION,
        "patch_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
        "diagnostics_patch_sha256": hashlib.sha256(diagnostics_patch.read_bytes()).hexdigest(),
        "stk_recovery": "user-selected public system STK launcher only; no direct CAT or profile writes",
        "diagnostics": "passive native events and read-only snapshots; no ARA-M inspection or card writes",
        "signing_key": "independent ephemeral test key plus official published 9eSIM community key",
        "signing_scheme": "APK v2 with two current signers; not signing lineage",
        "hardware_validation": "not performed",
    }
    (source / "issue62-build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
