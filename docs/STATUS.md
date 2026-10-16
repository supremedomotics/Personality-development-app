# CEO Forge — Status (living document)

Last updated: end of work session 1. Only items with a stated verification are claimed as working.

## Toolchain (verified)
- Flutter 3.47.7 stable / Dart 3.13.5 installed at `/opt/flutter` (Linux container).
- `flutter doctor`: Flutter ✓, Network ✓. **Android SDK ✗, Chrome ✗, Linux desktop toolchain ✗** (not needed for tests; Android SDK needed to build the APK).
- No Android/iOS device or emulator is reachable from this environment → nothing has been run on the Galaxy S23 Ultra.

## Implemented and tested (automated, in this container)
| Capability | Verification |
|---|---|
| Versioned negotiation rubric (6 criteria, weights sum to 1) | unit tests |
| Deterministic assessment engine with evidence spans, confidence, "insufficient evidence", ASR-confidence caveats, transcript-correction re-assessment | 17 unit tests |
| Persona role-play engine reacting to concession / open question / brochure talk / rambling; 3 scenarios | unit + widget tests |
| Spaced-review planner (boxes 1/3/7/14/30/60 d), difficulty, trend, mastery needing transfer + delayed retention, daily mission with stated reason | 13 unit tests |
| Session lifecycle: roleplay → feedback → retry (targeted criterion only, not double counted) → summary; early end; wrong-phase errors | 8 unit tests |
| Local persistence (Drift/SQLite): atomic save, idempotent, rollback, export, delete-all | 7 tests (real SQLite) |
| UI: Home/mission, live text session, feedback with evidence, transcript correction, retry, summary, save-failure + retry | 5 widget tests |
Total: 55 tests passing, `dart analyze` clean.

## Offline-AI benchmark status
- Harness `tools/bench_app` written; Dart code **type-checks against the real `llama_flutter_android` 0.2.6 and `sherpa_onnx` 1.13.8 APIs**; WER logic unit-tested (4 tests).
- **No benchmark has been run.** No APK has been built (no Android SDK here; `dl.google.com` and `huggingface.co` are blocked by this environment's network policy). No model has been downloaded, loaded or verified. No latency/RAM/WER/thermal number exists.
- Model licenses: sherpa-onnx Apache-2.0 and llama_flutter_android MIT verified from project pages; Qwen3 Apache-2.0 only from secondary sources (UNVERIFIED).
- See `docs/OFFLINE_AI_ARCHITECTURE.md`, `docs/BENCHMARK_PROTOCOL.md`.

## NOT implemented yet (do not assume)
- Voice input/output, VAD, local ASR, TTS, local LLM, translation, pronunciation, acoustic measures.
- Speaking/presentation/other modules (only negotiation has scenarios + rubric).
- Reports (daily/weekly/monthly), missions screen, models screen, settings/privacy screen, research screen.
- Google/Apple sign-in, sync, encryption at rest (database is plaintext SQLite in app documents dir).
- Android/iOS builds (no Android SDK here; no iOS build possible on Linux).
- Any benchmark on the S23 Ultra.

## Known limitations / design debt
- Scoring is lexical pattern matching. It cannot judge meaning, relevance, tone or truth; every score screen says so. Calibration against human raters has NOT been done.
- `trade` is only assessed if the user concedes; a user who never concedes never gets a `trade` baseline, so the planner can keep proposing it. Needs a planner rule.
- Only 3 negotiation scenarios; persona replies are rule-based, not generative.
- Questions without a "?" (e.g. unpunctuated ASR output) are under-detected.
- Fonts: system serif/sans placeholders (no bundled font files yet).
- Dark theme `border` token is low contrast (see DESIGN_SYSTEM.md).
- Offline claim: release manifest declares no INTERNET permission (checked by reading `android/app/src/{main,debug,profile}/AndroidManifest.xml`; debug/profile do declare it). Not yet checked on the merged manifest of a built APK, and not network-traffic tested.
