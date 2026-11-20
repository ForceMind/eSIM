#!/usr/bin/env python3
"""Verify the install identity, release mode, ABI, and independent APK signer."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
APK = DIST / "eSIM-Issue62-Test2-arm64-v8a.apk"
SDK = Path(os.environ["ANDROID_HOME"]) / "build-tools/36.0.0"
APP_ID = "io.github.forcemind.nekokolpa.issue62.v2"

assert APK.is_file() and APK.stat().st_size > 1_000_000
signer = subprocess.check_output([str(SDK / "apksigner"), "verify", "--verbose", "--print-certs", str(APK)], text=True)
badging = subprocess.check_output([str(SDK / "aapt"), "dump", "badging", str(APK)], text=True)
(DIST / "signer.txt").write_text(signer)
(DIST / "apk-info.txt").write_text(badging)
assert f"package: name='{APP_ID}'" in badging
assert "versionCode='2'" in badging
assert "versionName='2.5.0-issue62.2'" in badging
assert "application-label:'eSIM Issue62 Test 2'" in badging
assert "launchable-activity: name='ee.nekoko.nlpa2.MainActivity'" in badging
assert "native-code: 'arm64-v8a'" in badging
assert "application-debuggable" not in badging
cert_hash = hashlib.sha256((DIST / "test-certificate.der").read_bytes()).hexdigest()
actual = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]+)", signer)
assert actual and actual.group(1) == cert_hash
upstream_hash = hashlib.sha256((DIST / "upstream-certificate.der").read_bytes()).hexdigest()
assert cert_hash != upstream_hash, "APK must not use upstream's committed community signing key"
digest = hashlib.sha256(APK.read_bytes()).hexdigest()
(DIST / "SHA256SUMS.txt").write_text(f"{digest}  {APK.name}\n")
metadata = json.loads((ROOT / "source/issue62-build-info.json").read_text())
metadata.update({
    "apk_sha256": digest, "apk_size_bytes": APK.stat().st_size,
    "signer_certificate_sha256": cert_hash,
    "build_recipe_commit": os.environ.get("GITHUB_SHA"),
    "workflow_run": os.environ.get("GITHUB_RUN_ID"),
    "automated_tests": "passed (required preceding test job)",
})
(DIST / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(metadata, indent=2))
