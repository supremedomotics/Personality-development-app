import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../core/missions.dart';
import '../core/rubric.dart';
import 'theme.dart';

class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Real-world missions')),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Missions could not be loaded.')),
          data: (d) {
            final open = d.missions.where((m) => m.status == MissionStatus.open).toList().reversed.toList();
            final done = d.missions.where((m) => m.status != MissionStatus.open).toList().reversed.toList();
            if (d.missions.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No missions yet. After you finish a scored session, the app proposes one small action to practise in a real conversation.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('Completion is self-reported. The app cannot verify what happened outside it.',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 12),
              if (open.isNotEmpty) Text('To do', style: Theme.of(context).textTheme.titleLarge),
              for (final m in open) _OpenCard(m: m),
              if (done.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Done or skipped', style: Theme.of(context).textTheme.titleLarge),
                for (final m in done) _DoneTile(m: m),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

String _label(String id) => negotiationRubric.criteria.firstWhere((c) => c.id == id).label;

class _OpenCard extends ConsumerWidget {
  const _OpenCard({required this.m});
  final Mission m;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label(m.criterionId), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(m.text, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: () => _save(context, ref, (c) => c.skip(DateTime.now())),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                  onPressed: () => _complete(context, ref),
                  child: const Text('I did this'),
                ),
              ]),
            ]),
          ),
        ),
      );

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final r = await showDialog<({String outcome, String reflection})>(
        context: context, builder: (_) => const _ReflectDialog());
    if (r == null) return;
    if (!context.mounted) return;
    await _save(context, ref,
        (c) => c.complete(now: DateTime.now(), outcome: r.outcome, reflection: r.reflection));
  }

  Future<void> _save(BuildContext context, WidgetRef ref, void Function(Mission) change) async {
    try {
      await ref.read(appControllerProvider.notifier).updateMission(m.id, change);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save this change. Nothing was changed; try again.')));
      }
    }
  }
}

class _DoneTile extends StatelessWidget {
  const _DoneTile({required this.m});
  final Mission m;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final done = m.status == MissionStatus.done;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(done ? Icons.check_circle_outline : Icons.remove_circle_outline, color: done ? t.ok : t.muted),
      title: Text(m.text),
      subtitle: Text(done
          ? 'What happened: ${m.outcome}${(m.reflection ?? '').isEmpty ? '' : '\nLesson: ${m.reflection}'}'
          : 'Skipped'),
    );
  }
}

/// Owns its controllers so they are disposed only after the route is gone.
class _ReflectDialog extends StatefulWidget {
  const _ReflectDialog();
  @override
  State<_ReflectDialog> createState() => _ReflectDialogState();
}

class _ReflectDialogState extends State<_ReflectDialog> {
  final _outcome = TextEditingController();
  final _lesson = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _outcome.dispose();
    _lesson.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('What happened?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _outcome,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
                labelText: 'What did you do and how did they respond?',
                errorText: _showError ? 'Write at least a few words.' : null),
          ),
          const SizedBox(height: 12),
          TextField(controller: _lesson, maxLines: 2, decoration: const InputDecoration(labelText: 'Lesson (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (_outcome.text.trim().length < 3) {
                setState(() => _showError = true);
                return;
              }
              Navigator.pop(context, (outcome: _outcome.text, reflection: _lesson.text));
            },
            child: const Text('Save'),
          ),
        ],
      );
}
