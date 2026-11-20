#!/usr/bin/env python3
"""Add the reviewed public 9eSIM signer and a fresh independent test signer.

Only the intentionally public 9eSIM community key is fetched. The original
multi-signer shell recipe is parsed as data, never executed. Vendor-private
keys and CI secrets mentioned by that recipe are neither fetched nor used.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
import urllib.request

SOURCE_REPOSITORY = "iebb/NekokoLPA"
SOURCE_COMMIT = "517f88f9391099c8744a2f04df30c8d4a9cdd3d9"
PUBLIC_KEY_PATH = "signer/keys/9esim.jks"
PUBLIC_RECIPE_PATH = "variants/multisign/signing.sh"
PUBLIC_KEY_SHA256 = "44745c415cd0abb1ca98987f04a9e123f41001d0681b5f57db1c8f0ff86bc1e5"
PUBLIC_RECIPE_SHA256 = "2c6c6be2f898d5fa0f9136f92bf7535503e9dd13643562429291bbd517327ae8"
EXPECTED_9ESIM_SHA1 = "d1c0f48b370e74d4ea4770ed4c3cd70a3198d31f"
EXPECTED_9ESIM_SHA256 = "6966004ad0161165335f9204f8f5a52df49fe068c9545c0c589c23221af8d3a4"


class SigningError(RuntimeError):
    pass


def fetch_pinned(path: str, digest: str) -> bytes:
    url = f"https://raw.githubusercontent.com/{SOURCE_REPOSITORY}/{SOURCE_COMMIT}/{path}"
    request = urllib.request.Request(url, headers={"User-Agent": "Issue62-public-signing-recipe"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(65537)
    if len(data) > 65536 or hashlib.sha256(data).hexdigest() != digest:
        raise SigningError(f"Pinned source checksum mismatch: {path}")
    return data


def public_password(recipe: bytes) -> str:
    # shlex only tokenizes the reviewed recipe. It does not evaluate variables,
    # run substitutions, source the script, or access any other referenced key.
    tokens = shlex.split(recipe.decode("utf-8").replace("\\\n", " "))
    matches = [i for i, token in enumerate(tokens[:-1])
               if token == "--ks" and tokens[i + 1] == PUBLIC_KEY_PATH]
    if len(matches) != 1:
        raise SigningError("Expected exactly one public 9eSIM signer in the pinned recipe")
    start = matches[0] + 2
    end = tokens.index("--next-signer", start) if "--next-signer" in tokens[start:] else len(tokens)
    section = tokens[start:end]
    if section.count("--ks-pass") != 1:
        raise SigningError("Missing explicit public 9eSIM password in the pinned recipe")
    value = section[section.index("--ks-pass") + 1]
    if not value.startswith("pass:") or len(value) == 5:
        raise SigningError("The selected 9eSIM recipe does not contain a public literal password")
    return value[5:]


def run_checked(args: list[str], *, env: dict[str, str], stage: str,
                redactions: tuple[str, ...], timeout: int = 120) -> str:
    result = subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        diagnostic = result.stderr or result.stdout
        for value in redactions:
            diagnostic = diagnostic.replace(value, "<redacted>")
        raise SigningError(f"{stage} failed (exit {result.returncode}): {diagnostic[:1800]}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apksigner", type=Path, required=True)
    args = parser.parse_args()
    source, output, apksigner = args.input.resolve(), args.output.resolve(), args.apksigner.resolve()
    if not source.is_file() or not apksigner.is_file():
        raise SigningError("Input APK and apksigner must be existing files")
    if source == output:
        raise SigningError("Input and output APKs must be different paths")
    if output.exists():
        raise SigningError("Refusing to overwrite an existing signed APK")
    output.parent.mkdir(parents=True, exist_ok=True)

    key_bytes = fetch_pinned(PUBLIC_KEY_PATH, PUBLIC_KEY_SHA256)
    public_pass = public_password(fetch_pinned(PUBLIC_RECIPE_PATH, PUBLIC_RECIPE_SHA256))
    test_pass = secrets.token_urlsafe(32)
    env = os.environ.copy()
    env["ISSUE62_PUBLIC_9ESIM_STORE_PASS"] = public_pass
    env["ISSUE62_EPHEMERAL_TEST_STORE_PASS"] = test_pass
    redactions = (public_pass, test_pass)

    # Both keystores are private temporary files and removed even on failure.
    # The independent key is never present in the checked-out source tree.
    with tempfile.TemporaryDirectory(prefix="issue62-signing-") as temp:
        private = Path(temp)
        public_key = private / "9esim-community.jks"
        test_key = private / "independent-test.jks"
        public_key.write_bytes(key_bytes)
        public_key.chmod(0o600)
        public_listing = run_checked([
            "keytool", "-list", "-rfc", "-keystore", str(public_key),
            "-storepass:env", "ISSUE62_PUBLIC_9ESIM_STORE_PASS",
        ], env=env, stage="Read public 9eSIM certificate", redactions=redactions)
        certificates = re.findall(
            r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----",
            public_listing, flags=re.S)
        if len(certificates) != 1:
            raise SigningError("Expected exactly one certificate in the public 9eSIM keystore")
        public_cert = base64.b64decode(re.sub(r"\s+", "", certificates[0]), validate=True)
        if hashlib.sha1(public_cert).hexdigest() != EXPECTED_9ESIM_SHA1 or \
                hashlib.sha256(public_cert).hexdigest() != EXPECTED_9ESIM_SHA256:
            raise SigningError("Public 9eSIM certificate does not match the reviewed identity")

        run_checked([
            "keytool", "-genkeypair", "-noprompt", "-storetype", "JKS",
            "-keystore", str(test_key), "-alias", "issue62-test3",
            "-keyalg", "RSA", "-keysize", "3072", "-sigalg", "SHA256withRSA",
            "-validity", "3650", "-storepass:env", "ISSUE62_EPHEMERAL_TEST_STORE_PASS",
            "-keypass:env", "ISSUE62_EPHEMERAL_TEST_STORE_PASS",
            "-dname", "CN=eSIM Issue62 Test 3, OU=Independent test signer, O=ForceMind",
        ], env=env, stage="Generate independent test key", redactions=redactions)
        test_key.chmod(0o600)
        test_certificate = private / "test-certificate.der"
        run_checked([
            "keytool", "-exportcert", "-keystore", str(test_key),
            "-alias", "issue62-test3", "-storepass:env", "ISSUE62_EPHEMERAL_TEST_STORE_PASS",
            "-file", str(test_certificate),
        ], env=env, stage="Export independent public certificate", redactions=redactions)
        test_cert = test_certificate.read_bytes()
        test_sha256 = hashlib.sha256(test_cert).hexdigest()
        if test_sha256 == EXPECTED_9ESIM_SHA256:
            raise SigningError("Independent signer must differ from the public 9eSIM signer")

        staged_apk = private / "dual-signed.apk"
        run_checked([
            str(apksigner), "sign", "--v1-signing-enabled", "false",
            "--v2-signing-enabled", "true", "--v3-signing-enabled", "false",
            "--v4-signing-enabled", "false", "--out", str(staged_apk),
            "--ks", str(public_key), "--ks-pass", "env:ISSUE62_PUBLIC_9ESIM_STORE_PASS",
            "--key-pass", "env:ISSUE62_PUBLIC_9ESIM_STORE_PASS",
            "--next-signer", "--ks", str(test_key), "--ks-key-alias", "issue62-test3",
            "--ks-pass", "env:ISSUE62_EPHEMERAL_TEST_STORE_PASS",
            "--key-pass", "env:ISSUE62_EPHEMERAL_TEST_STORE_PASS", str(source),
        ], env=env, stage="Dual-sign APK", redactions=redactions)
        verification = run_checked([
            str(apksigner), "verify", "--verbose", "--print-certs", str(staged_apk),
        ], env=env, stage="Verify dual-signed APK", redactions=redactions)
        fingerprints = re.findall(
            r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$",
            verification, flags=re.M)
        fingerprints = [fingerprint.lower() for fingerprint in fingerprints]
        if len(fingerprints) != 2 or set(fingerprints) != {EXPECTED_9ESIM_SHA256, test_sha256}:
            raise SigningError("Verified APK signer set differs from the two expected certificates")
        if "Verified using v2 scheme (APK Signature Scheme v2): true" not in verification:
            raise SigningError("APK Signature Scheme v2 verification did not pass")

        # Only a fully verified APK and public records leave the private directory.
        output.write_bytes(staged_apk.read_bytes())
        (output.parent / "test-certificate.der").write_bytes(test_cert)
        (output.parent / "9esim-certificate.der").write_bytes(public_cert)
        metadata = {
            "source_repository": SOURCE_REPOSITORY,
            "source_commit": SOURCE_COMMIT,
            "public_key_path": PUBLIC_KEY_PATH,
            "public_key_file_sha256": PUBLIC_KEY_SHA256,
            "public_recipe_path": PUBLIC_RECIPE_PATH,
            "public_recipe_sha256": PUBLIC_RECIPE_SHA256,
            "expected_9esim_certificate_sha1": EXPECTED_9ESIM_SHA1,
            "certificate_sha256": {"9esim": EXPECTED_9ESIM_SHA256, "test": test_sha256},
            "signer_count": 2,
            "apk_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "private_keys_retained": False,
            "hardware_access_validation": "not performed",
        }
        (output.parent / "signing-provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (SigningError, subprocess.TimeoutExpired, OSError, ValueError) as error:
        # subprocess arguments contain environment variable names, never passwords.
        print(f"Signing failed: {error}", file=sys.stderr)
        raise SystemExit(1)
