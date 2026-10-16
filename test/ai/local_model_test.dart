import 'dart:async';

import 'package:ceo_forge/ai/local_model.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRuntime implements LocalModelRuntime {
  FakeRuntime({this.loaded = true, this.chunks = const [], this.hang = false, this.error});
  bool loaded;
  List<String> chunks;
  bool hang;
  Object? error;
  int cancels = 0;
  List<ChatTurn>? seen;

  @override
  bool get isLoaded => loaded;
  @override
  Future<Duration> load(String path, {int threads = 4, int contextSize = 2048, int? gpuLayers}) async {
    loaded = true;
    return const Duration(milliseconds: 5);
  }

  @override
  Stream<String> chat(List<ChatTurn> turns, {int maxTokens = 80}) async* {
    seen = turns;
    if (error != null) throw error!;
    for (final c in chunks) {
      yield c;
    }
    if (hang) await Completer<void>().future; // never completes
  }

  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> unload() async => loaded = false;
}

Future<VoiceResult> run(FakeRuntime r, {Duration? timeout, String idea = 'The other quotes include a two-year support plan for less money.', String user = 'Okay, five percent.'}) =>
    PersonaVoice(r, timeout: timeout ?? const Duration(milliseconds: 200)).rephrase(
        personaName: 'Mr. Hale', setting: 'You are negotiating.', intendedLine: idea, lastUserReply: user);

void main() {
  test('good output is used and flagged as model-generated', () async {
    final r = FakeRuntime(chunks: ['Honestly, ', 'the others ', 'give me two years of support for less.']);
    final v = await run(r);
    expect(v.fromModel, isTrue);
    expect(v.text, 'Honestly, the others give me two years of support for less.');
    expect(r.seen!.first.content, contains('Idea: The other quotes'));
    expect(r.seen!.first.content, contains('Do not add numbers'));
  });

  test('model not loaded → scripted line, no crash', () async {
    final v = await run(FakeRuntime(loaded: false));
    expect(v.fromModel, isFalse);
    expect(v.fallbackReason, 'model not loaded');
    expect(v.text, startsWith('The other quotes'));
  });

  test('hang → timeout, cancel called, scripted line returned', () async {
    final r = FakeRuntime(chunks: ['partial'], hang: true);
    final v = await run(r, timeout: const Duration(milliseconds: 50));
    expect(v.fromModel, isFalse);
    expect(v.fallbackReason, contains('timed out'));
    expect(r.cancels, 1);
  });

  test('runtime error → fallback and cancel', () async {
    final r = FakeRuntime(error: StateError('native crash'));
    final v = await run(r);
    expect(v.fromModel, isFalse);
    expect(v.fallbackReason, 'model error');
    expect(r.cancels, 1);
  });

  test('thinking blocks are stripped, including an unterminated one', () async {
    expect((await run(FakeRuntime(chunks: ['<think>plan the reply</think>Fine, tell me more.']))).text, 'Fine, tell me more.');
    final v = await run(FakeRuntime(chunks: ['<think>still thinking and never closes']));
    expect(v.fromModel, isFalse);
    expect(v.fallbackReason, 'empty output');
  });

  test('invented numbers are rejected; numbers from the idea or the user are allowed', () async {
    final bad = await run(FakeRuntime(chunks: ['I can offer you 12 percent off.']));
    expect(bad.fromModel, isFalse);
    expect(bad.fallbackReason, 'invented a number');
    final ok = await run(FakeRuntime(chunks: ['Two years? And you said 5 percent, which is not enough.']),
        idea: 'Support for 2 years is included elsewhere.', user: 'I can do 5 percent.');
    // "Two" is a word (allowed); "5" appears in the user reply; "2" is not in the output.
    expect(ok.fromModel, isTrue);
  });

  test('breaking character or rambling is rejected', () async {
    expect((await run(FakeRuntime(chunks: ['As an AI language model I cannot negotiate.']))).fallbackReason, 'broke character');
    expect((await run(FakeRuntime(chunks: [List.filled(100, 'word').join(' ')]))).fallbackReason, 'output too long');
  });

  group('model files', () {
    const spec = ModelSpec(id: 'x', name: 'X', fileName: 'x.gguf', licenseNote: 'n');
    const withHash = ModelSpec(id: 'y', name: 'Y', fileName: 'y.gguf', licenseNote: 'n', sha256: 'ABCDEF');
    final fs = _Fs({'/m/x.gguf': 100, '/m/y.gguf': 100, '/m/empty.gguf': 0}, 'abcdef');

    test('missing / empty file is missing', () async {
      const mgr = ModelManager(_NoFs());
      expect((await mgr.quickCheck(spec, '/none')).state, ModelState.missing);
      expect((await ModelManager(fs).quickCheck(const ModelSpec(id: 'e', name: 'E', fileName: 'empty.gguf', licenseNote: ''), '/m')).state, ModelState.missing);
    });

    test('present without a publisher digest can NEVER be verified', () async {
      final s = await ModelManager(fs).verify(spec, '/m');
      expect(s.state, ModelState.presentUnverified);
      expect(fs.hashCalls, 0, reason: 'no point hashing without a reference');
    });

    test('digest match (case-insensitive) → verified; mismatch → corrupt', () async {
      expect((await ModelManager(fs).verify(withHash, '/m')).state, ModelState.verified);
      expect((await ModelManager(_Fs({'/m/y.gguf': 100}, 'deadbeef')).verify(withHash, '/m')).state, ModelState.corrupt);
    });

    test('quickCheck never says verified', () async {
      expect((await ModelManager(fs).quickCheck(withHash, '/m')).state, ModelState.presentUnverified);
    });

    test('shipped candidate list has no digests, so nothing can show as verified yet', () {
      expect(candidateModels.every((m) => m.sha256 == null), isTrue);
      expect(candidateModels.every((m) => m.licenseNote.contains('not yet read')), isTrue);
    });
  });
}

class _NoFs implements ModelFs {
  const _NoFs();
  @override
  Future<int?> sizeOf(String path) async => null;
  @override
  Future<String> sha256Of(String path) async => throw StateError('unused');
}

class _Fs implements ModelFs {
  _Fs(this.sizes, this.hash);
  final Map<String, int> sizes;
  final String hash;
  int hashCalls = 0;
  @override
  Future<int?> sizeOf(String path) async => sizes[path];
  @override
  Future<String> sha256Of(String path) async {
    hashCalls++;
    return hash;
  }
}
