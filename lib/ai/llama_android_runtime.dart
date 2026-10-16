import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'local_model.dart';

/// Adapter over the llama.cpp Android plugin. UNTESTED ON DEVICE as of this
/// commit: it type-checks against llama_flutter_android 0.2.6 only.
class LlamaAndroidRuntime implements LocalModelRuntime {
  LlamaController? _c;

  @override
  bool get isLoaded => _c != null;

  @override
  Future<Duration> load(String path, {int threads = 4, int contextSize = 2048, int? gpuLayers}) async {
    await unload();
    final c = LlamaController();
    final sw = Stopwatch()..start();
    await c.loadModel(modelPath: path, threads: threads, contextSize: contextSize, gpuLayers: gpuLayers);
    _c = c;
    return sw.elapsed;
  }

  @override
  Stream<String> chat(List<ChatTurn> turns, {int maxTokens = 80}) {
    final c = _c;
    if (c == null) return Stream.error(StateError('Model not loaded'));
    return c.generateChat(
      messages: [for (final t in turns) ChatMessage(role: t.role, content: t.content)],
      maxTokens: maxTokens,
      temperature: 0.7,
    );
  }

  @override
  Future<void> cancel() async => _c?.stop();

  @override
  Future<void> unload() async {
    final c = _c;
    _c = null;
    if (c != null) await c.dispose();
  }
}
