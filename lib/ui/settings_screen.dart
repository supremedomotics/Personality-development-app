import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../app_state.dart';
import 'models_screen.dart';
import 'theme.dart';

/// Writes an export file and returns its path. Overridable in tests.
final exportWriterProvider = Provider<Future<String> Function(Map<String, Object?> data)>((ref) {
  return (data) async {
    final dir = await ref.read(modelDirProvider.future);
    final f = File('$dir/ceo_forge_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return f.path;
  };
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await ref.read(repositoryProvider).exportAll();
      final path = await ref.read(exportWriterProvider)(data);
      _message = 'Exported to $path\nThis file is NOT encrypted. Anyone who can read it can read your transcripts and notes. Move it somewhere safe and delete it when done.';
    } catch (e) {
      _message = 'Export failed. Nothing was changed.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all training data?'),
        content: const Text('This permanently erases every session, transcript, score, mission and reflection on this device. It cannot be undone. Exported files are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: ctx.t.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete everything')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).deleteEverything();
      _message = 'All training data was deleted from this device.';
    } catch (e) {
      _message = 'Deletion failed. Your data is unchanged.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(appControllerProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings and privacy')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('What this app does with your data', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const _Bullet('Your sessions, scores and notes are stored only on this device.'),
          const _Bullet('Release builds declare no network permission (checked automatically when the app is built). This is a design check, not an independent audit.'),
          const _Bullet('Android cloud backup and device-to-device transfer of app data are switched off.'),
          const _Bullet('Not covered: your keyboard app (especially voice typing) and screen capture can see what you type. The database is not encrypted yet.'),
          const _Bullet('No account, sync or voice recording exists in this build.'),
          const SizedBox(height: 20),
          Text('Your data', style: theme.textTheme.titleLarge),
          if (data != null)
            Text('${data.sessions.length} session(s), ${data.missions.length} mission(s) stored.', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export my data (JSON file)'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _delete,
            icon: Icon(Icons.delete_outline, color: context.t.danger),
            label: Text('Delete all my data', style: TextStyle(color: context.t.danger)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(_message!)),
          const SizedBox(height: 20),
          Text('Experimental', style: theme.textTheme.titleLarge),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.memory_outlined),
            title: const Text('On-device models'),
            subtitle: const Text('Optional local language model for role-play wording. Not validated yet.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen())),
          ),
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ]),
      );
}
