# CEO Forge — Status (living document)

Nothing is listed as working unless the verification is stated. "Tests" = automated, run in CI and in the dev container.

## Build and test
- Flutter 3.47.7 / Dart 3.13.5. `dart analyze` clean. **128 tests passing locally**.
- GitHub Actions (`android-build`) runs analyze + tests and builds two APKs on every push. History: runs 1, 3, 4 succeeded; run 2 failed in `sdkmanager` (environment, not root-caused); **runs 5-9 failed** because the main app's minSdk (24) was below the llama plugin's 26 (my mistake, found in the log); **run 10 (commit 01fb7f2) succeeded: analysis, tests and both APK builds**, and its merged-manifest check passed (only the app's internal permission; allowBackup false). See `docs/ANDROID_BUILD.md`.
- minSdk is now 26 (Android 8.0+).
- No build has been installed or run on any phone. **Nothing has been seen running on the S23 Ultra.**

## IMPLEMENTED (verified by tests unless noted)
- Negotiation rubric v1 (6 criteria, weights sum to 1), deterministic assessment engine with evidence spans, confidence, "insufficient evidence", ASR-confidence caveats, transcript correction + re-assessment.
- Rule-based persona engine (3 scenarios) that reacts to concessions, open questions, brochure talk, rambling.
- Spaced-review planner, difficulty adjustment, trend, transfer-aware "mastery", daily mission with stated reason. **Conditional-criterion (trade) loop fixed**: mission now asks for one conditional concession; an inapplicability counter backs the planner off with deepening penalty.
- Session lifecycle (roleplay → feedback → retry → summary, early end, save-failure handling); retry not double counted.
- Local persistence (SQLite/Drift): atomic save of session + skill book + missions, export, delete-all.
- Real-world missions as if-then plans, self-reported completion with reflection; atomic persistence; failed saves leave state unchanged.
- Daily, weekly and monthly reports as pure functions of stored records (trend direction, repeated mistakes, best/worst, retention after 7+ days, per-criterion first-score vs recent with the sessions behind each line, priorities capped at three, adherence, caveats). Next-month plan is a 28-day TEMPLATE (reassessment on days 1 and 28, weekly retention reviews, weighted practice on the top priorities); the real daily session is still chosen by the planner.
- Settings and privacy screen: plain statements of what is/is not protected, export to JSON (plaintext, warned), confirmed delete-all; On-device models lives under Settings. UI: Today, Reports, Missions, Settings tabs; live text session; feedback with quoted evidence; transcript correction; retry; summary.
- Local-model integration **behind interfaces** (`LocalModelRuntime`, `PersonaVoice`, `ModelManager`): the model can only re-word the persona's line; output validated (timeout+cancel, no invented numbers, think-blocks stripped, character-break rejected) with scripted fallback; scores provably unaffected (tested). Models screen never says "verified" without a publisher digest (none stored).
- Privacy hardening: OS backup/device-transfer disabled (found enabled-by-default), IME suggestions/learning off on text fields, manifest guard tests, CI manifest assertion. See `docs/PRIVACY_AND_SECURITY.md`.
- Docs: DESIGN_SYSTEM, RESEARCH_EVIDENCE (16 sources, verification levels), OFFLINE_AI_ARCHITECTURE, BENCHMARK_PROTOCOL, PRIVACY_AND_SECURITY, ANDROID_BUILD.

## BUILT BUT NOT VALIDATED ON A DEVICE
- `llama_flutter_android` adapter and the Models screen load path (type-checks only).
- Benchmark app `tools/bench_app` (builds in CI; never run). **No latency, memory, ASR-accuracy or thermal number exists.**

## PENDING (not built)
- Voice: microphone capture, VAD, local ASR (sherpa-onnx), TTS, acoustic measures, pronunciation.
- Speaking and presentation modules (scenarios + rubrics); only negotiation exists.
- Baseline-reassessment *session type* (the plan schedules it, but the app has no hint-free assessment mode yet); per-skill progress charts; delayed-retention scheduling UI.
- Research/methodology screen; privacy details beyond the Settings summary.
- Encryption at rest; account sign-in (Google/Apple); sync; conflict resolution.
- Onboarding, goals, device-capability detection, language packs, translation.
- Calibration of the rubric against human raters (none done; scores are heuristic).
- iOS build.

## BLOCKED / needs input
- **Model choice and all performance claims**: need the benchmark JSON from the S23 Ultra (and its RAM variant).
- **Model license verification and digests**: Hugging Face is unreachable from the container; someone with access must read the primary model cards and record SHA-256 digests.
- **Primary-source reading of papers**: scholarly sites unreachable; research doc is abstract-level only.
- **Android SDK in the dev container**: `dl.google.com` blocked; CI is the workaround.

## Known limitations
- Scoring is lexical pattern matching: cannot judge meaning, relevance, tone or truth. Unvalidated.
- Only 3 negotiation scenarios; persona replies are rule-based unless a local model re-words them.
- Questions without a "?" are under-detected.
- Fonts are system placeholders; dark-theme border contrast is low.
- Database is plaintext at rest.
