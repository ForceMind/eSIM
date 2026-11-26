# 9eSIM Issue62 diagnostic test build

Independent compatibility and diagnostic builds for [NekokoLPA2 issue #62](https://github.com/iebb/NekokoLPA2/issues/62). This is not an official 9eSIM release. All build work belongs in **ForceMind/eSIM**. The shared LPA source remains pinned to `6d2145a515557941f10c5ebbf734d01f7d05fb43`.

## Test 5: SIM Toolkit recovery entry

Test 5 retains Test 4 diagnostics and adds **Settings → 9eSIM diagnostics → SIM Toolkit (STK)**. It lists enabled, exported launcher activities in known system STK packages (`com.android.stk`, `com.android.stk1`, `com.android.stk2`) and launches only the user-selected entry. It offers system network settings as a separate manual fallback. It never sends CAT commands, changes access rules, or claims a launch request means a profile was switched. Samsung STK may remain unresponsive. Hardware validation is required. The independent package is `io.github.forcemind.nekokolpa.issue62.v5`, version `2.5.0-issue62.5` / code 5. Successful builds publish `issue62-test5-stk-apk` containing `eSIM-Issue62-Test5-STK-arm64-v8a.apk`.

## Test 4: capture evidence before and after a profile switch

The user confirmed that Test 3 lists profiles while a working profile is enabled, then reports access denied after enabling the affected RedPocket profile. This establishes a profile-dependent access failure in that test. It does **not** establish which ARA-M rule applies, that a rule was overwritten, or that a card firmware defect has been proven.

Test 4 retains the tested 9eSIM community signing identity and adds a dedicated **read-only diagnostic report**. It does not claim to fix the remaining profile-switching failure.

### Install identity

| Field | Value |
| --- | --- |
| Launcher and in-app name | `9eSIM Test 4` |
| Application ID | `io.github.forcemind.nekokolpa.issue62.v4` |
| Version | `2.5.0-issue62.4` / code `4` |
| ABI | ARM64 (`arm64-v8a`) |
| Signers | Independent test + published 9eSIM community identity |

The original app and Test 3 can stay installed. Each test build has its own app data and diagnostic snapshots.

### 操作步骤

1. 安装并打开 **9eSIM Test 4**。如果当前已出现访问被拒绝，可以直接进入 **设置 → 9eSIM 诊断**，采集当前状态并保存报告；不要求先恢复或反复切卡。
2. 要做对照时，在能够正常读取卡片列表的状态下，进入诊断页，点击 **记录切换前**。
3. 返回主界面执行原本要测试的切换。错误出现后回到诊断页，点击 **记录切换后**。
4. 点击 **保存诊断文件**，选择保存位置，将生成的 `9esim-test4-diagnostics-*.json` 发回当前排查对话。也可以使用 **复制脱敏报告**。
5. 如果必须重开 App，之前保存的快照仍可读取。报告由用户手动导出，不会自动上传。

### What the report contains

- Each attempted management AID, its success / null / exception outcome, retry phase, exception class and redacted message / cause chain.
- Native method result codes, session errors, SIM refresh events, profile-switch markers, cleanup/safety-guard failures and selected error status words.
- Cached OMAPI reader/session/channel state and the app's current signing certificate fingerprints.
- Android version and device manufacturer/model, plus per-logical-slot subscription mapping and the platform's carrier-privilege result where available.
- User-labelled before/after/current snapshots and bounded event history, including dropped-event counts.

Carrier privileges and OMAPI AID authorization are **separate checks**. `not_confirmed` means the Android carrier-privilege API returned false; it is not proof of a specific card-rule denial. `unavailable` means a value could not be read. Logical slots are not asserted to match physical slots or OMAPI reader names. Signing history is not described as card rules. No ARA-M contents are read by this diagnostic feature.

The dedicated report excludes APDU payloads, ATR, SELECT responses, ICCID, EID, IMSI, IMEI, phone numbers, activation codes and profile names. Exception text is redacted before persistence. It deliberately does not export the existing raw application log. Native events and snapshots are stored privately on the device with size limits; the report records unavailable or failed storage states rather than inventing data.

Opening, capturing, exporting or clearing diagnostics does not open a card session, probe an AID, transmit an APDU, reset the card, or change a profile. Diagnostics remain callable when the existing OMAPI safety guard has blocked further card operations. Actual user-initiated profile operations keep the upstream safety behavior.

## Patches and regression checks

`patches/issue62-v2.patch` retains the prior error-classification changes:

- Preserve explicit permission errors while scanning alternative AIDs.
- Recognize current and legacy permission codes in Dart.
- Avoid cleanup/retry after an unambiguous permission denial.
- Preserve bounded recovery for mixed/null failures across the native-to-Dart boundary.

`patches/issue62-diagnostics.patch` adds the structured recorder, native snapshot API, report UI and accurate Chinese/English access-denial guidance. It is applied after the v2 patch. Both patch digests are recorded in the build manifest.

The workflow runs Kotlin tests against the actual channel-opening implementation, focused diagnostic/privacy tests, Dart analysis, and the complete Flutter suite. The APK job starts only when tests pass. A failed package or signature verification prevents APK publication. Unit tests and CI do not replace Samsung/Xiaomi/physical-card validation.

## Signing provenance

Test 2 used only a newly generated signing key. Test 3 corrected this and the user verified baseline card access. Test 4 retains **two current APK v2 signers**:

1. A newly generated independent test identity.
2. The **public 9eSIM community identity** published in the [official NekokoLPA multisign recipe](https://github.com/iebb/NekokoLPA/blob/517f88f9391099c8744a2f04df30c8d4a9cdd3d9/variants/multisign/signing.sh). Only its public 9eSIM signer section is used.

The public certificate's SHA-1 is `D1C0F48B370E74D4EA4770ED4C3CD70A3198D31F`, also listed on the [upstream download page](https://lpa.nekoko.ee/en/download). Source commit, key-file digest, recipe digest and certificate fingerprint are pinned. The signing recipe is parsed as data, never executed. Separate secret-protected signers are not accessed.

Both signatures are applied in one `apksigner` invocation. Verification requires exactly those two certificates and a valid v2 signature. This is not certificate rotation. Private keys are temporary, are not committed or uploaded, and are removed when signing exits. A new build run changes the independent signer, so it cannot update an earlier APK with the same application ID in place.

## Build and download

Open **Actions → Issue62 tests and coexist APK**. Historical Test 4 runs publish **issue62-test4-diagnostics-apk**, containing:

- `eSIM-Issue62-Test4-Diagnostics-arm64-v8a.apk`
- SHA-256, package inspection and signature verification records
- Both public certificates and pinned signing provenance

Test reports and build diagnostics are separate artifacts. Tests and APK builds use separate runners, bounded timeouts and disk cleanup.

Python 3, Java 17, Kotlin 1.9.25, Flutter 3.47.2, Rust 1.99.1, Android SDK 36, build tools 36.0.0 and NDK 28.2.13676358 are pinned. Run `python3 scripts/prepare_source.py` and follow `.github/workflows/issue62.yml`. Preparation refuses to overwrite a nonempty source directory.

The NekokoLPA2 MIT notice is retained in `LICENSE.upstream`; the signing source notice is in `LICENSE.signing-upstream`. Use of the published community identity does not imply endorsement by NekokoLPA or 9eSIM.
