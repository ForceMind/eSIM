# 9eSIM Issue62 test build

Independent compatibility builds for [NekokoLPA2 issue #62](https://github.com/iebb/NekokoLPA2/issues/62). This is not an official 9eSIM release. The shared LPA source is pinned to `6d2145a515557941f10c5ebbf734d01f7d05fb43`; the patch and regression tests are versioned here.

## Test 3 corrects the signing setup

Test 2 used only a newly generated signing key. Compilation and unit tests did not establish that this identity could access a card which accepts the original app. It cannot evaluate a profile-specific failure when access already fails at baseline.

Test 3 retains its own application ID and applies **two current APK v2 signers**:

1. A newly generated independent test identity.
2. The **public 9eSIM community identity** published in the [official NekokoLPA multisign recipe](https://github.com/iebb/NekokoLPA/blob/517f88f9391099c8744a2f04df30c8d4a9cdd3d9/variants/multisign/signing.sh). Only its public 9eSIM signer section is used.

The public certificate's SHA-1 is `D1C0F48B370E74D4EA4770ED4C3CD70A3198D31F`, also listed for 9eSIM-signed builds on the [upstream download page](https://lpa.nekoko.ee/en/download). The build pins the source commit, key-file digest, recipe digest and certificate fingerprint. It follows the published recipe without executing its shell script or accessing the separate secret-protected signers.

Both identities are applied in one `apksigner` invocation. Verification requires exactly these two certificates and a valid v2 signature. This is not certificate rotation and does not replace the official app.

**Physical-device validation is still required.** A card may bind a certificate to a package name, and Android/card implementations differ. A matching certificate is not proof that every card or enabled profile will accept this separate package. The build does not modify card rules, profiles, IMEI or phone security settings.

## Candidate code changes

- Preserve explicit permission errors while scanning alternative AIDs.
- Recognize current and legacy permission codes in Dart.
- Avoid cleanup/retry after an unambiguous permission denial.
- Preserve bounded recovery for mixed/null failures across the native-to-Dart boundary.

The app uses the shared public LPA/OMAPI implementation. Test 3 has an explicit in-app test title; changing the brand label is not what grants card access.

## Build and download

Open **Actions → Issue62 tests and coexist APK**. The APK job starts only after Kotlin tests, Dart analysis and the complete Flutter suite pass. Successful runs publish **issue62-test3-9esim-coexist-apk**, containing:

- `eSIM-Issue62-Test3-9eSIM-arm64-v8a.apk`
- SHA-256, package inspection and signature verification records
- Both public certificates and pinned signing provenance

Test reports and diagnostics are separate artifacts. A failed signature/package check prevents APK upload. Tests and Android builds use separate runners, disk cleanup and bounded timeouts.

## Install identity

| Field | Value |
| --- | --- |
| Launcher and in-app name | `9eSIM Test 3` |
| Application ID | `io.github.forcemind.nekokolpa.issue62.v3` |
| Version | `2.5.0-issue62.3` / code `3` |
| ABI | ARM64 (`arm64-v8a`) |
| Signers | Independent test + published 9eSIM community identity |

The official app and earlier test packages can stay installed. The test does not claim the official activation deep links. First check whether it lists profiles in the **same phone/card/profile state** where the original app works. Only after that succeeds should it evaluate the original profile-switching problem.

The independent key is ephemeral and never committed or uploaded. Key files stay in a private temporary directory and are removed when signing exits. A later independent run changes the signer set and cannot update an APK from an earlier run in place.

## Reproduction and notices

Python 3, Java 17, Kotlin 1.9.25, Flutter 3.47.2, Rust 1.99.1, Android SDK 36, build tools 36.0.0 and NDK 28.2.13676358 are pinned in the workflow. Run `python3 scripts/prepare_source.py` and follow `.github/workflows/issue62.yml`. Preparation refuses to overwrite a nonempty source directory.

The NekokoLPA2 MIT notice is retained in `LICENSE.upstream`; the signing source notice is in `LICENSE.signing-upstream`. Use of a published community identity does not imply endorsement by NekokoLPA or 9eSIM.
