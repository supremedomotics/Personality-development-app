import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../ai/local_model.dart';
import 'theme.dart';

class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});
  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  final Map<String, ModelStatus> _status = {};
  final Map<String, String> _note = {};
  bool _scanned = false;

  Future<void> _scan(String dir) async {
    final mgr = ModelManager(ref.read(modelFsProvider));
    for (final s in candidateModels) {
      _status[s.id] = await mgr.quickCheck(s, dir);
    }
    if (mounted) setState(() => _scanned = true);
  }

  Future<void> _hash(ModelSpec s, String dir) async {
    setState(() => _note[s.id] = 'Hashing… large files take a minute or more.');
    try {
      final st = await ModelManager(ref.read(modelFsProvider)).verify(s, dir);
      final fs = ref.read(modelFsProvider);
      final h = st.path == null ? null : await fs.sha256Of(st.path!);
      setState(() => _note[s.id] = switch (st.state) {
            ModelState.verified => 'Digest matches the publisher value.',
            ModelState.corrupt => 'Digest does NOT match: the file is damaged or the wrong file.',
            _ => 'SHA-256: $h\nNo publisher digest is stored, so this cannot be called verified. Compare it with the value on the model page.',
          });
    } catch (e) {
      setState(() => _note[s.id] = 'Could not read the file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(modelDirProvider);
    final voice = ref.watch(voiceProvider);
    final runtime = ref.watch(modelRuntimeProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('On-device models')),
      body: SafeArea(
        child: dir.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Storage location unavailable.')),
          data: (d) {
            if (!_scanned) _scan(d);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                'Experimental. A local model may re-word the role-play partner\'s lines. It never affects scores, plans or reports, and the app works without it. Nothing is downloaded automatically.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SelectableText('Copy a .gguf file to: $d', style: theme.textTheme.labelMedium),
              if (runtime == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('This build has no local-model runtime, so models cannot be loaded here.',
                      style: TextStyle(color: context.t.danger)),
                ),
              const SizedBox(height: 16),
              for (final s in candidateModels) _Card(
                spec: s,
                status: _status[s.id],
                note: _note[s.id],
                loaded: voice.loadedModel == s.name,
                canLoad: runtime != null && !voice.busy,
                onHash: () => _hash(s, d),
                onLoad: () => ref.read(voiceProvider.notifier).enable(s, '$d/${s.fileName}'),
                onUnload: () => ref.read(voiceProvider.notifier).disable(),
              ),
              if (voice.busy) const LinearProgressIndicator(),
              if (voice.error != null) Text(voice.error!, style: TextStyle(color: context.t.danger)),
              if (voice.loadTime != null)
                Text('Loaded in ${voice.loadTime!.inMilliseconds} ms. This is a load time only, not a quality or speed test.',
                    style: theme.textTheme.labelMedium),
            ]);
          },
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.spec, required this.status, required this.note, required this.loaded, required this.canLoad, required this.onHash, required this.onLoad, required this.onUnload});
  final ModelSpec spec;
  final ModelStatus? status;
  final String? note;
  final bool loaded, canLoad;
  final VoidCallback onHash, onLoad, onUnload;

  static const _label = {
    ModelState.missing: 'Not installed',
    ModelState.presentUnverified: 'File present, integrity not verified',
    ModelState.verified: 'Verified',
    ModelState.corrupt: 'Damaged or wrong file',
  };

  @override
  Widget build(BuildContext context) {
    final st = status?.state ?? ModelState.missing;
    final theme = Theme.of(context);
    final present = st == ModelState.presentUnverified || st == ModelState.verified;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.name, style: theme.textTheme.titleMedium),
            Text(spec.fileName, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text('${_label[st]}${status?.sizeBytes == null ? '' : ' · ${(status!.sizeBytes! / (1024 * 1024)).round()} MB'}'),
            Text('License: ${spec.licenseNote}', style: theme.textTheme.labelMedium),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(note!)),
            if (present) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: onHash, child: const Text('Compute SHA-256')),
                if (!loaded) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(140, 48)), onPressed: canLoad ? onLoad : null, child: const Text('Load for role-play')),
                if (loaded) OutlinedButton(onPressed: onUnload, child: const Text('Unload')),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
