import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'io_model_fs.dart';
import 'local_model.dart';

/// null when no runtime is available on this platform (e.g. tests, iOS today).
final modelRuntimeProvider = Provider<LocalModelRuntime?>((ref) => null);

final modelFsProvider = Provider<ModelFs>((ref) => IoModelFs());

/// App-specific external storage on Android (reachable by `adb push`, no
/// storage permission needed); documents dir elsewhere.
final modelDirProvider = FutureProvider<String>((ref) async {
  final d = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
      await getApplicationDocumentsDirectory();
  return d.path;
});

class VoiceState {
  const VoiceState({this.voice, this.loadedModel, this.loadTime, this.error, this.busy = false});
  final PersonaVoice? voice;
  final String? loadedModel;
  final Duration? loadTime;
  final String? error;
  final bool busy;
}

/// Opt-in, experimental: wording of the persona only. Scoring never uses it.
class VoiceController extends Notifier<VoiceState> {
  @override
  VoiceState build() => const VoiceState();

  Future<void> enable(ModelSpec spec, String path) async {
    final rt = ref.read(modelRuntimeProvider);
    if (rt == null) {
      state = const VoiceState(error: 'No local model runtime on this device/build.');
      return;
    }
    state = const VoiceState(busy: true);
    try {
      final t = await rt.load(path);
      state = VoiceState(voice: PersonaVoice(rt), loadedModel: spec.name, loadTime: t);
    } catch (e) {
      state = VoiceState(error: 'Could not load ${spec.name}. The app keeps working with scripted replies.');
    }
  }

  Future<void> disable() async {
    await ref.read(modelRuntimeProvider)?.unload();
    state = const VoiceState();
  }
}

final voiceProvider = NotifierProvider<VoiceController, VoiceState>(VoiceController.new);
