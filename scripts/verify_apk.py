#!/usr/bin/env python3
"""Verify install identity and the independent + 9eSIM community signer set."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
APK = DIST / "eSIM-Issue62-Test3-9eSIM-arm64-v8a.apk"
SDK = Path(os.environ["ANDROID_HOME"]) / "build-tools/36.0.0"
APP_ID = "io.github.forcemind.nekokolpa.issue62.v3"
ESIM9_SHA1 = "d1c0f48b370e74d4ea4770ed4c3cd70a3198d31f"

assert APK.is_file() and APK.stat().st_size > 1_000_000
signer = subprocess.check_output([str(SDK / "apksigner"), "verify", "--verbose", "--print-certs", str(APK)], text=True)
badging = subprocess.check_output([str(SDK / "aapt"), "dump", "badging", str(APK)], text=True)
(DIST / "signer.txt").write_text(signer)
(DIST / "apk-info.txt").write_text(badging)
assert f"package: name='{APP_ID}'" in badging
assert "versionCode='3'" in badging
assert "versionName='2.5.0-issue62.3'" in badging
assert "application-label:'9eSIM Test 3'" in badging
assert "launchable-activity: name='ee.nekoko.nlpa2.MainActivity'" in badging
assert "native-code: 'arm64-v8a'" in badging
assert "application-debuggable" not in badging
cert_hash = hashlib.sha256((DIST / "test-certificate.der").read_bytes()).hexdigest()
esim9_bytes = (DIST / "9esim-certificate.der").read_bytes()
esim9_hash = hashlib.sha256(esim9_bytes).hexdigest()
assert hashlib.sha1(esim9_bytes).hexdigest() == ESIM9_SHA1
actual = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)", signer)
assert len(actual) == 2 and set(actual) == {cert_hash, esim9_hash}
assert cert_hash != esim9_hash
assert "Verified using v2 scheme (APK Signature Scheme v2): true" in signer
assert "Verified using v3 scheme (APK Signature Scheme v3): false" in signer
signing_provenance = json.loads((DIST / "signing-provenance.json").read_text())
digest = hashlib.sha256(APK.read_bytes()).hexdigest()
(DIST / "SHA256SUMS.txt").write_text(f"{digest}  {APK.name}\n")
metadata = json.loads((ROOT / "source/issue62-build-info.json").read_text())
metadata.update({
    "apk_sha256": digest, "apk_size_bytes": APK.stat().st_size,
    "signer_certificate_sha256": {"independent_test": cert_hash, "9esim_community": esim9_hash},
    "9esim_community_certificate_sha1": ESIM9_SHA1,
    "signer_count": 2,
    "signing_provenance": signing_provenance,
    "build_recipe_commit": os.environ.get("GITHUB_SHA"),
    "workflow_run": os.environ.get("GITHUB_RUN_ID"),
    "automated_tests": "passed (required preceding test job)",
})
(DIST / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(metadata, indent=2))
