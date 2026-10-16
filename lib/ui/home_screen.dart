import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../core/planner.dart';
import '../core/rubric.dart';
import '../core/scenario.dart';
import '../core/session.dart';
import 'session_screen.dart';
import 'theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('CEO Forge')),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _LoadError(onRetry: () => ref.invalidate(appControllerProvider)),
          data: (d) => _Body(data: d, now: now),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: context.t.danger, size: 40),
            const SizedBox(height: 12),
            Text('Your training data could not be opened.', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Nothing was changed. Try again; if it persists, export is unavailable until the database opens.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.now});
  final AppData data;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = data.mission(now);
    final t = context.t;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(m.isBaseline ? 'Baseline session' : "Today's mission", style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(m.criterionLabel, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Line(label: 'Success looks like', text: m.successCriterion),
              _Line(label: 'Why it matters', text: m.why),
              _Line(label: 'Why today', text: m.reason),
              _Line(label: 'Time', text: '${m.minutes} minutes. You can end early at any point.'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _start(context, ref, m),
          child: const Text('Start session'),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Offline status',
          child: Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: t.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Training data stays on this device and this release declares no network permission. Voice and on-device AI are not installed yet, so you type your replies.',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Text('Where you stand', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Practised on ${data.daysPracticedLast7(now)} of the last 7 days. Consistency matters; one missed day does not reset anything.', style: theme.textTheme.labelMedium),
        const SizedBox(height: 12),
        _Skills(book: data.book),
        const SizedBox(height: 24),
        if (data.sessions.isNotEmpty) ...[
          Text('Recent sessions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final s in data.sessions.reversed.take(5)) _SessionTile(s: s),
        ],
      ],
    );
  }

  void _start(BuildContext context, WidgetRef ref, DailyMission m) {
    final sc = negotiationScenarios.firstWhere((s) => s.id == m.scenarioId);
    final ctl = SessionController(
      mission: m,
      scenario: sc,
      book: ref.read(appControllerProvider.notifier).bookCopy(),
      clock: ref.read(clockProvider),
      rubric: negotiationRubric,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionScreen(controller: ctl)));
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.text});
  final String label, text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ]),
      );
}

class _Skills extends StatelessWidget {
  const _Skills({required this.book});
  final SkillBook book;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (book.states.isEmpty) {
      return Text('No scores yet. Your first session sets your baseline.', style: Theme.of(context).textTheme.bodyMedium);
    }
    return Column(children: [
      for (final c in negotiationRubric.criteria)
        Builder(builder: (_) {
          final s = book.states['negotiation.${c.id}'];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label: s == null ? '${c.label}: not assessed yet' : '${c.label}: recent average ${s.ewma.round()} out of 100 from ${s.attempts} attempts',
              child: Row(children: [
                Expanded(flex: 4, child: Text(c.label)),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: s == null ? 0 : s.ewma / 100,
                      minHeight: 8,
                      backgroundColor: t.border.withValues(alpha: 0.3),
                      color: t.accent,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    s == null ? 'not yet' : '${s.ewma.round()} · n=${s.attempts}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ),
          );
        }),
      const SizedBox(height: 4),
      Text('n = attempts. Averages from fewer than 5 attempts are low-confidence.', style: Theme.of(context).textTheme.labelMedium),
    ]);
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.s});
  final SessionRecord s;
  @override
  Widget build(BuildContext context) {
    final sc = negotiationScenarios.where((x) => x.id == s.scenarioId);
    final a = s.assessment;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(sc.isEmpty ? s.scenarioId : sc.first.title),
      subtitle: Text('${s.startedAt.toLocal().toString().substring(0, 16)}${s.endedEarly ? ' · ended early' : ''}'),
      trailing: Text(a?.overall == null ? 'not scored' : '${a!.overall}/100'),
    );
  }
}
