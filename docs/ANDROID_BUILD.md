# Getting an installable Android build

## Option A — download from GitHub Actions (no tools needed on your side)
1. Open the repository's **Actions** tab → latest successful **android-build** run on branch `claude/exciting-curie-97xzfn`.
2. Download an artifact (requires being signed in to GitHub):
   - `ceo-forge-text-prototype-apk` — the app itself. **Text-only prototype**: you type replies, scoring is rule-based, no microphone permission, no network permission. Not the offline-AI MVP.
   - `ceo-forge-bench-apk` — the separate **on-device AI benchmark** app (profile build; has microphone and, as a debug-tooling side effect, network permission). Used only to measure the S23 Ultra.
3. Unzip, copy the `.apk` to the phone, allow "install unknown apps" for your file manager, install. These are signed with Flutter's *debug* key: **sideload/testing only**; installing a build with a different key later requires uninstalling first (which deletes local data).
4. Integrity: each artifact's SHA-256 is shown by the API/CI log; compare it with the file you downloaded if you care about tampering.

## Option B — build on your computer
Requirements: Flutter 3.47.7 stable (`flutter --version`), Android Studio or command-line SDK with **NDK r27 or newer** (needed by the llama plugin), JDK 17.
```
git clone https://github.com/supremedomotics/Personality-development-app && cd Personality-development-app
git checkout claude/exciting-curie-97xzfn
flutter pub get
flutter test                       # expect all tests to pass
flutter build apk --release        # app: build/app/outputs/flutter-apk/app-release.apk
cd tools/bench_app && flutter pub get && flutter build apk --profile   # benchmark app
adb install -r <apk>
```
Verify what you built: `aapt dump permissions build/app/outputs/flutter-apk/app-release.apk` and `tools/check_manifest.sh build/app/outputs/flutter-apk/app-release.apk`.

## Why the cloud container cannot build APKs
Its network policy blocks `dl.google.com` (Android SDK), `huggingface.co` (models) and scholarly sites. To allow them, edit the environment's *Network access → Allowed domains* (keep "Allow package managers" ticked): https://code.claude.com/docs/en/cloud-environments#network-access
CI on GitHub's runners is the workaround used instead.
