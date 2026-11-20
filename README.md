# eSIM Issue62 test build

This repository builds an independent test APK for
[NekokoLPA2 issue #62](https://github.com/iebb/NekokoLPA2/issues/62).
The upstream source is pinned to `6d2145a515557941f10c5ebbf734d01f7d05fb43`.
The production patch and regression tests are versioned here; builds never
download executable changes from a mutable issue comment.

## What the candidate changes

- Preserve explicit OMAPI permission errors while scanning alternative AIDs.
- Recognize both current and legacy permission error codes in Dart.
- Avoid unnecessary recovery and retries after an unambiguous permission denial.
- Keep mixed/null channel failures eligible for recovery, including the native-to-Dart boundary.

This improves failure classification and recovery behavior. It does not grant
ARA-M access, replace profile access rules, or establish that a particular card
will work. Automated tests use simulated OMAPI responses. Physical Samsung,
Xiaomi and removable-eUICC validation must still be performed on a device.

## Build and download

Open this repository's **Actions → Issue62 tests and coexist APK** workflow.
The APK job only starts after the Kotlin and Flutter regression tests pass.
Successful runs publish **issue62-tested-coexist-apk**, containing the APK,
SHA-256 checksum, public signing certificate and build/verification metadata.
Test reports are uploaded separately, including on test failure. APKs are not
published by a failed verification step.

The test job and Android build job use separate runners and bounded timeouts.
Unused preinstalled runner components are removed before building so Android,
Flutter and Rust do not consume the disk needed by tests.

## Install identity

| Field | Value |
| --- | --- |
| App name | `eSIM Issue62 Test 2` |
| Application ID | `io.github.forcemind.nekokolpa.issue62.v2` |
| Version | `2.5.0-issue62.2` / code `2` |
| ABI | ARM64 (`arm64-v8a`) |
| Signing | Independent RSA 3072-bit key, generated for this build only |

The package coexists with the official app and the earlier Issue62 test APK.
It does not register the official app's activation deep links. The private
signing key is never uploaded or committed and is removed at job completion;
later independent runs will have a different signer and will not update an
already-installed APK signed by an earlier run.

Begin device testing with a profile already known to work. A newly signed app
can itself lack authorization, so an error with that baseline profile is not
evidence that the problematic profile has been repaired or further damaged.

## Local reproduction

Use Python 3, Java 17, Kotlin 1.9.25, Flutter 3.47.2, Rust 1.99.1 and Android SDK
36 / build tools 36.0.0 / NDK 28.2.13676358. Run `python3 scripts/prepare_source.py`
in an empty working checkout, then follow the exact test and build steps in
`.github/workflows/issue62.yml`. Source preparation refuses to overwrite an
existing source directory. The original upstream MIT notice is retained in
`LICENSE.upstream`.
