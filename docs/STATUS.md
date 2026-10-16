# CEO Forge — Status (living document)

Nothing is listed as working unless the verification is stated. "Tests" = automated, run in CI and in the dev container.

## Build and test
- Flutter 3.47.7 / Dart 3.13.5. `dart analyze` clean. **112 tests passing locally**.
- GitHub Actions (`android-build`) runs analyze + tests and builds two APKs on every push. Run 1 (commit 64450e7) built both APKs successfully; run 2 failed in `sdkmanager` during SDK setup (environment, not code; not root-caused); run 3 succeeded; later runs are in progress. See `docs/ANDROID_BUILD.md`.
- No build has been installed or run on any phone. **Nothing has been seen running on the S23 Ultra.**

## IMPLEMENTED (verified by tests unless noted)
- Negotiation rubric v1 (6 criteria, weights sum to 1), deterministic assessment engine with evidence spans, confidence, "insufficient evidence", ASR-confidence caveats, transcript correction + re-assessment.
- Rule-based persona engine (3 scenarios) that reacts to concessions, open questions, brochure talk, rambling.
- Spaced-review planner, difficulty adjustment, trend, transfer-aware "mastery", daily mission with stated reason. **Conditional-criterion (trade) loop fixed**: mission now asks for one conditional concession; an inapplicability counter backs the planner off with deepening penalty.
- Session lifecycle (roleplay → feedback → retry → summary, early end, save-failure handling); retry not double counted.
- Local persistence (SQLite/Drift): atomic save of session + skill book + missions, export, delete-all (data layer only).
- Real-world missions as if-then plans, self-reported completion with reflection; atomic persistence; failed saves leave state unchanged.
- Daily and weekly reports as pure functions of stored records (trend direction, repeated mistakes, best/worst, retention after 7+ days, priorities, caveats).
- UI: Today, Reports, Missions, Models tabs; live text session; feedback with quoted evidence; transcript correction; retry; summary.
- Local-model integration **behind interfaces** (`LocalModelRuntime`, `PersonaVoice`, `ModelManager`): the model can only re-word the persona's line; output validated (timeout+cancel, no invented numbers, think-blocks stripped, character-break rejected) with scripted fallback; scores provably unaffected (tested). Models screen never says "verified" without a publisher digest (none stored).
- Privacy hardening: OS backup/device-transfer disabled (found enabled-by-default), IME suggestions/learning off on text fields, manifest guard tests, CI manifest assertion. See `docs/PRIVACY_AND_SECURITY.md`.
- Docs: DESIGN_SYSTEM, RESEARCH_EVIDENCE (16 sources, verification levels), OFFLINE_AI_ARCHITECTURE, BENCHMARK_PROTOCOL, PRIVACY_AND_SECURITY, ANDROID_BUILD.

## BUILT BUT NOT VALIDATED ON A DEVICE
- `llama_flutter_android` adapter and the Models screen load path (type-checks only).
- Benchmark app `tools/bench_app` (builds in CI; never run). **No latency, memory, ASR-accuracy or thermal number exists.**

## PENDING (not built)
- Voice: microphone capture, VAD, local ASR (sherpa-onnx), TTS, acoustic measures, pronunciation.
- Speaking and presentation modules (scenarios + rubrics); only negotiation exists.
- Monthly report and next-month plan generator; baseline reassessment sessions; delayed-retention scheduling UI.
- Settings/Privacy screen incl. user-facing export/delete; research/methodology screen.
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
