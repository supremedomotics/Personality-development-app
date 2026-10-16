# Offline AI architecture — feasibility status (v0)

**Nothing here has been measured on a device yet.** This container cannot reach `huggingface.co` or `dl.google.com`, has no Android SDK, and has no phone attached. Every performance figure is therefore *unknown* until `docs/BENCHMARK_PROTOCOL.md` is run on the Galaxy S23 Ultra.

## Principle
Deterministic core (`lib/core`: scoring, planning, spaced review, persona rules) owns state, scores and task completion. A local LLM, when installed, may only *add* natural-language role-play and phrasing. If no model is installed the app already works (rule-based persona, text input). This is implemented today.

## Candidate components
| Role | Candidate | License (how verified) | Status |
|---|---|---|---|
| Speech recognition + VAD + TTS runtime | sherpa-onnx (`sherpa_onnx` pub package) | Apache-2.0 — read on the project's GitHub page; lists Android + Flutter, Whisper/Zipformer/Paraformer/Moonshine ASR, Silero VAD, Piper/Kokoro TTS | Dart API type-checked in `tools/bench_app`; **not run on device** |
| LLM runtime (Android) | `llama_flutter_android` 0.2.6 (llama.cpp wrapper) | MIT — read on pub.dev. **Unverified publisher**, ~3.9k downloads, README says *Android only* though tags list iOS | Dart API type-checked; **not run on device**; iOS needs a different path |
| LLM weights | Qwen3-1.7B and Qwen3-4B, Q4 GGUF | Apache-2.0 per *secondary* aggregator pages only. **Primary model card could not be fetched** (host blocked) → treat as UNVERIFIED until the Hugging Face card is read | not downloaded |
| Other LLM options to evaluate | Llama 3.2 1B/3B, Gemma, Phi family, SmolLM2 | licenses **not yet checked** (custom/community licenses carry commercial conditions) | not evaluated |

## Known risks (not measured)
- Qwen3 defaults to a "thinking" mode; it must be disabled for acceptable latency in a coaching loop.
- `llama_flutter_android` is a young single-maintainer plugin; iOS support is unconfirmed. A fallback is binding llama.cpp directly via FFI.
- 4B-class models may not sustain a 10-minute session within thermal limits; the benchmark's 12-turn sustained run is designed to show throughput decay (a throttling *indicator*, not a temperature reading).
- Apps with R8/ProGuard need extra keep rules for the llama plugin (plugin README).

## S23 Ultra RAM
Galaxy S23 Ultra ships in 8 GB and 12 GB variants (from general knowledge, not verified here). **Please confirm yours** (Settings → Battery and device care → Memory); the benchmark app also records `physicalRamSize`.

## Selection rule (to apply once data exists)
Pick the smallest model whose median time-to-first-token and sustained tokens/s on the S23 Ultra allow a natural conversation (target: first token < ~2 s, throughput that does not collapse over 12 turns), whose role-play stays in character in manual review of the saved replies, and whose license is verified commercial-compatible from the primary source.
