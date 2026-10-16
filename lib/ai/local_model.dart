library;

import 'dart:async';

/// Boundary between the deterministic coaching core and any on-device LLM.
/// Nothing in lib/core imports this: scoring never depends on a model.
class ChatTurn {
  const ChatTurn(this.role, this.content);
  final String role; // system | user | assistant
  final String content;
}

abstract class LocalModelRuntime {
  bool get isLoaded;

  /// Loads a GGUF file and returns the measured wall-clock load time.
  Future<Duration> load(String path, {int threads = 4, int contextSize = 2048, int? gpuLayers});

  /// Streams generated text chunks. Must stop promptly after [cancel].
  Stream<String> chat(List<ChatTurn> turns, {int maxTokens = 80});

  Future<void> cancel();
  Future<void> unload();
}

class VoiceResult {
  const VoiceResult.model(this.text, this.elapsed)
      : fromModel = true,
        fallbackReason = null;
  const VoiceResult.fallback(this.text, this.fallbackReason, this.elapsed) : fromModel = false;
  final String text;
  final bool fromModel;
  final String? fallbackReason;
  final Duration elapsed;
}

final _thinkRe = RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false);
final _openThinkRe = RegExp(r'<think>.*', dotAll: true, caseSensitive: false);
final _numRe = RegExp(r'\d+(?:[.,]\d+)?');
const _banned = [
  'as an ai',
  'language model',
  "i'm an ai",
  'i am an ai',
  'i cannot assist',
  "i can't assist",
];

/// Lets a local model re-word the persona's scripted line. The model never
/// decides what the persona means: [intendedLine] (chosen by deterministic
/// rules) is the content; unsafe or slow output falls back to it unchanged.
class PersonaVoice {
  PersonaVoice(this.runtime, {this.timeout = const Duration(seconds: 25), this.maxChars = 320});
  final LocalModelRuntime runtime;
  final Duration timeout;
  final int maxChars;

  Future<VoiceResult> rephrase({
    required String personaName,
    required String setting,
    required String intendedLine,
    required String lastUserReply,
  }) async {
    final sw = Stopwatch()..start();
    VoiceResult fb(String why) => VoiceResult.fallback(intendedLine, why, sw.elapsed);
    if (!runtime.isLoaded) return fb('model not loaded');

    final turns = [
      ChatTurn(
          'system',
          'You are $personaName in a business negotiation role-play. $setting '
              'Say the following idea in your own words, in character, in at most 2 sentences. '
              'Do not add numbers, offers, facts or stage directions. /no_think\n'
              'Idea: $intendedLine'),
      ChatTurn('user', lastUserReply),
    ];

    final buf = StringBuffer();
    try {
      await runtime.chat(turns, maxTokens: 80).forEach(buf.write).timeout(timeout);
    } on TimeoutException {
      await runtime.cancel();
      return fb('timed out after ${timeout.inSeconds}s');
    } catch (e) {
      await runtime.cancel();
      return fb('model error');
    }

    var out = buf.toString().replaceAll(_thinkRe, '').replaceAll(_openThinkRe, '').trim();
    if (out.isEmpty) return fb('empty output');
    if (out.length > maxChars) return fb('output too long');
    final low = out.toLowerCase();
    if (_banned.any(low.contains)) return fb('broke character');
    // Reject invented numbers: every figure must appear in the idea or the user's reply.
    final allowed = {..._numRe.allMatches(intendedLine).map((m) => m.group(0)), ..._numRe.allMatches(lastUserReply).map((m) => m.group(0))};
    if (_numRe.allMatches(out).any((m) => !allowed.contains(m.group(0)))) return fb('invented a number');
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return VoiceResult.model(out, sw.elapsed);
  }
}

// ---- model files ------------------------------------------------------------

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.fileName,
    required this.licenseNote,
    this.sha256,
  });
  final String id, name, fileName;

  /// Where the license claim came from and how far it is verified.
  final String licenseNote;

  /// Lower-case hex digest from the publisher, when known. Null = cannot verify.
  final String? sha256;
}

enum ModelState { missing, presentUnverified, verified, corrupt }

class ModelStatus {
  const ModelStatus(this.spec, this.state, {this.path, this.sizeBytes});
  final ModelSpec spec;
  final ModelState state;
  final String? path;
  final int? sizeBytes;
}

abstract class ModelFs {
  Future<int?> sizeOf(String path); // null if the file does not exist
  Future<String> sha256Of(String path);
}

class ModelManager {
  const ModelManager(this.fs);
  final ModelFs fs;

  /// Cheap check (no hashing): presence only. Never reports "verified".
  Future<ModelStatus> quickCheck(ModelSpec s, String dir) async {
    final path = '$dir/${s.fileName}';
    final size = await fs.sizeOf(path);
    if (size == null || size == 0) return ModelStatus(s, ModelState.missing);
    return ModelStatus(s, ModelState.presentUnverified, path: path, sizeBytes: size);
  }

  /// Full check: hashes the file. "verified" requires a publisher digest to match.
  Future<ModelStatus> verify(ModelSpec s, String dir) async {
    final q = await quickCheck(s, dir);
    if (q.state == ModelState.missing || s.sha256 == null) return q;
    final h = await fs.sha256Of(q.path!);
    return ModelStatus(s, h.toLowerCase() == s.sha256!.toLowerCase() ? ModelState.verified : ModelState.corrupt,
        path: q.path, sizeBytes: q.sizeBytes);
  }
}

/// Candidate models (UNEVALUATED). No digests are recorded because the primary
/// model pages were not reachable when this list was written, so nothing here
/// can ever show as "verified" until a publisher digest is added.
const candidateModels = [
  ModelSpec(
    id: 'qwen3-1.7b-q4km',
    name: 'Qwen3 1.7B (Q4_K_M)',
    fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    licenseNote: 'Apache-2.0 per secondary sources only; primary model card not yet read.',
  ),
  ModelSpec(
    id: 'qwen3-4b-q4km',
    name: 'Qwen3 4B (Q4_K_M)',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    licenseNote: 'Apache-2.0 per secondary sources only; primary model card not yet read.',
  ),
];
