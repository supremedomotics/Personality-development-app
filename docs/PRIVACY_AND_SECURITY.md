# Privacy and security review (v1)

**Scope:** Android build of the current prototype. iOS is not built and no iOS claim is made. This is an engineering review by the author of the code, **not an independent audit, not a penetration test, and not a network-traffic capture.**

## 1. Claim we want to be able to make
"Your recordings, transcripts, scores and notes never leave this device unless you explicitly export or sync them."

## 2. What is verified, and how
| Statement | Evidence | Strength |
|---|---|---|
| The release APK built by CI (commit 64450e7) declares **no INTERNET permission** and no microphone permission; its only permission is the app's own internal `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `aapt dump permissions` on the built APK, printed in the CI log (run 38944688316) | Certain for that commit. Re-checked on every CI build by `tools/check_manifest.sh`, which fails the build on any unexpected permission |
| Without INTERNET, Android denies the app socket access | Android permission model (general knowledge, not re-tested here) | Likely |
| OS cloud backup / device-to-device transfer of app data is disabled (`allowBackup=false`, `dataExtractionRules` excluding all domains) | Source test `test/privacy/privacy_guard_test.dart`; CI asserts `allowBackup` is false in the built APK | Source: certain. Built APK: asserted by CI from this commit on |
| App source has no networking code and no logging/printing | Static source scan in the same test | Weak: it only covers *our* Dart code, not plugins or native code |
| Free-text fields turn off keyboard suggestions, autocorrect and personalised learning | Source test counts the flags on every `TextField` | Source only; the keyboard app may ignore the hint |

## 3. A gap this review found and fixed
Before this review the manifest did not set `allowBackup`, so Android's default (**backup on**) applied: the private SQLite database (transcripts, reflections) was eligible for upload to the user's Google Drive backup and for device-to-device transfer. That contradicted the product principle and would **not** have been caught by checking the INTERNET permission. Fixed in the same commit as this document. Consequence: a new phone does not get progress automatically; restore will come from the app's own explicit encrypted export/sync (planned, not built).

## 4. Leak paths that remain (not solved by the permission)
1. **Keyboard / IME.** Typed replies pass through the user's keyboard app. Gboard-style apps can have cloud features, and *voice typing* may send audio to a server. We can request "no learning/suggestions", but cannot enforce it. Mitigation to offer: use an offline keyboard, disable voice typing for this app; our own on-device speech input (planned) avoids this path.
2. **Screen contents.** The Android recents screenshot and screen recorders can capture sessions. No `FLAG_SECURE` is set (it would also block the user's own screenshots). Candidate: opt-in setting.
3. **Device compromise / adb / root.** Data is stored in the app sandbox as **plaintext SQLite** (no encryption at rest yet). Anyone with root, a forensic image or an unlocked-device `run-as` on a debuggable build can read it. Android file-based encryption protects it only when the phone is locked.
4. **Debug/profile builds.** These declare INTERNET (Flutter adds it for tooling). The benchmark APK is a profile build and also requests the microphone. Only the release APK is covered by the claims above, and only the text prototype (no mic) is "offline by permission".
5. **Dependencies.** Plugins can contain native code. Without INTERNET they cannot reach the network, but the day INTERNET is added (sign-in/sync) this protection disappears. The local-model plugin (`llama_flutter_android`) is an unverified single-maintainer package; its source has not been audited.
6. **Models.** A GGUF file is code-adjacent input parsed by native llama.cpp; a malicious model file is a risk. The app never downloads models and cannot yet verify them (no publisher digests stored), so it never labels a model "verified".
7. **Clipboard.** The benchmark app copies its results (including model replies) to the clipboard by design. The main app does not use the clipboard.
8. **Sideloading.** The CI APK is signed with the Flutter *debug* key; anyone with the file can't tell it from a tampered copy except by the SHA-256 CI prints. Not for distribution.

## 5. Consequences for future features
- **Account sign-in/sync requires INTERNET.** From that commit on, "no INTERNET permission" is no longer a guarantee. The replacement controls must be: sync off by default; only client-side-encrypted blobs leave the device (key never leaves it); a user-visible list of exactly what is synced; no raw audio unless explicitly enabled; and a network-traffic capture (e.g. per-UID packet capture on the S23 Ultra) showing zero traffic while sync is off.
- **Voice** adds the RECORD_AUDIO permission; microphone data must stay in memory/app-private files, be deletable, and never be logged.

## 6. Verification still to do (pending)
- Per-UID network capture on the real device in airplane mode and with Wi-Fi on, over a full session (expect 0 packets from the app).
- Re-check the merged manifest after adding each plugin (the CI step does this automatically).
- Encrypt the database at rest (e.g. SQLCipher) with a key in Android Keystore; threat model for key loss.
- Independent review before any claim beyond "designed to be offline".

## 7. Deletion and export
Implemented in the data layer and tested (`exportAll`, `deleteAll`); **no user-facing screen yet**.
