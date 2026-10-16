# On-device benchmark protocol (Galaxy S23 Ultra)

App: `tools/bench_app` (separate Flutter app, Android only, minSdk 26). It records stopwatch timings, `/proc/self/status` VmRSS, battery %, and plugin-reported GPU info. It does not estimate temperature.

## Build (on your computer; this cloud container cannot build APKs)
```
cd tools/bench_app
flutter pub get
flutter build apk --profile      # avoids R8 minification issues with the native plugins
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```
Requires Flutter SDK + Android SDK/NDK r27 (plugin requirement) on your machine.

## Get models onto the phone (no in-app downloads)
Download on a computer, then:
```
adb push Qwen3-1.7B-Q4_K_M.gguf /sdcard/Android/data/com.supremedomotics.ceo_forge_bench/files/
adb shell mkdir -p /sdcard/Android/data/com.supremedomotics.ceo_forge_bench/files/whisper
adb push <sherpa-onnx whisper files: *-encoder*.onnx *-decoder*.onnx *-tokens.txt> .../files/whisper/
```
Test at least: one ~1.7B and one ~4B Q4 GGUF; Whisper tiny/base/small (sherpa-onnx int8 exports). Record each file's source URL and license from its primary model card.

## Procedure
1. Charge to >80 %, close other apps, phone at normal room temperature, **airplane mode on** (this is the offline test).
2. Run LLM benchmark (12 sustained turns) for each model; vary threads (4 vs 6) and GPU layers (0 vs recommended).
3. Type a 20–30 word reference sentence, tap *Record 15 s*, read it aloud at normal pace in a quiet room, then once with background noise; run ASR benchmark each time.
4. Tap *Save + copy results JSON* and send me the JSON, plus: phone RAM variant, whether the phone felt hot, and how long each run took.

## What the numbers mean / limits
- `ttftMs`, `totalMs`: wall clock per generation. `streamedChunks` are plugin stream events, approximately tokens (unverified 1:1).
- Falling `chunksPerSecDecode` across the 12 runs suggests throttling; confirm by feel/temperature app. Not a thermal measurement.
- `realTimeFactor` < 1 means ASR is faster than real time. `wer` is only as valid as your reference text and reading accuracy; ≥3 recordings are needed before drawing conclusions.
- WAV parsing assumes a 44-byte header from the `record` plugin — **unverified**; if transcripts are garbage, suspect this first.
- Battery % granularity is 1 %; short runs will show 0 change.
