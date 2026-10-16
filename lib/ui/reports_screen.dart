import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../core/monthly.dart';
import '../core/report.dart';
import '../core/rubric.dart';
import '../core/scenario.dart';
import 'theme.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    final now = ref.watch(clockProvider)();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(tabs: [Tab(text: 'Today'), Tab(text: 'This week'), Tab(text: 'This month')]),
        ),
        body: SafeArea(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Center(child: Text('Reports could not be loaded.')),
            data: (d) {
              final tz = now.timeZoneOffset;
              final daily = buildDailyReport(
                  sessions: d.sessions, missions: d.missions, day: dayKey(now, tz), tz: tz);
              final weekly = buildWeeklyReport(
                  sessions: d.sessions, missions: d.missions, endDay: now.toUtc().add(tz), tz: tz);
              final monthly = buildMonthlyReport(
                  sessions: d.sessions, missions: d.missions, endDay: now.toUtc().add(tz), tz: tz);
              return TabBarView(children: [_Daily(r: daily), _Weekly(r: weekly), _Monthly(r: monthly)]);
            },
          ),
        ),
      ),
    );
  }
}

String _scenarioTitle(String id) {
  final m = negotiationScenarios.where((s) => s.id == id);
  return m.isEmpty ? id : m.first.title;
}

class _Daily extends StatelessWidget {
  const _Daily({required this.r});
  final DailyReport r;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(r.day, style: theme.textTheme.labelMedium),
      Text(r.headline, style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      if (r.isEmpty)
        const Text('Finish a session to see its report here. Reports are built only from saved sessions.'),
      for (final l in r.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_scenarioTitle(l.scenarioId), style: theme.textTheme.titleMedium),
                Text('${l.minutes} min${l.endedEarly ? ' · ended early' : ''}', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(l.overall == null ? 'Not scored (too little speech).' : 'Overall ${l.overall}/100 across the criteria that applied.'),
                if (l.targetFirst != null)
                  Text('Target criterion: ${l.targetFirst}${l.targetRetry == null ? '' : ' → ${l.targetRetry} on retry'}'),
                for (final f in l.failed) Text('• $f', style: theme.textTheme.bodyMedium),
              ]),
            ),
          ),
        ),
      if (r.openMissions > 0) Text('${r.openMissions} real-world mission(s) still open.'),
    ]);
  }
}

class _Weekly extends StatelessWidget {
  const _Weekly({required this.r});
  final WeeklyReport r;

  static const _dir = {
    Direction.improving: ('Improving', Icons.trending_up),
    Direction.regressing: ('Regressing', Icons.trending_down),
    Direction.stagnating: ('Stagnating below pass mark', Icons.trending_flat),
    Direction.stable: ('Stable', Icons.check),
    Direction.insufficient: ('Not enough data (needs 3+)', Icons.hourglass_empty),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return ListView(key: const Key('weekly-list'), padding: const EdgeInsets.all(16), children: [
      Text('${r.fromDay} to ${r.toDay}', style: theme.textTheme.labelMedium),
      Text('${r.sessionsCompleted} session(s) on ${r.daysPracticed} day(s)', style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      if (r.criteria.isEmpty) const Text('No scored sessions this week yet.'),
      for (final c in r.criteria)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_dir[c.direction]!.$2, color: t.muted),
          title: Text(c.label),
          subtitle: Text('${_dir[c.direction]!.$1} · scores ${c.scores.join(', ')}'),
        ),
      if (r.repeatedMistakes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Repeated mistakes', style: theme.textTheme.titleMedium),
        for (final m in r.repeatedMistakes) Text('• $m'),
      ],
      if (r.best != null) ...[
        const SizedBox(height: 12),
        Text('Best: ${r.best}'),
        Text('Weakest: ${r.worst}'),
      ],
      const SizedBox(height: 12),
      Text(
        r.retentionChecks == 0
            ? 'Retention: no criterion was re-tested 7+ days after a pass yet.'
            : 'Retention: ${r.retentionHeld} of ${r.retentionChecks} earlier passes held after 7+ days.',
      ),
      Text('Missions: ${r.missionsDone} of ${r.missionsCreated} created this week done (self-reported).'),
      if (r.priorities.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Suggested priorities', style: theme.textTheme.titleMedium),
        for (final p in r.priorities) Text('• $p'),
      ],
      const SizedBox(height: 16),
      for (final c in r.caveats) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(c, style: theme.textTheme.labelMedium)),
    ]);
  }
}

class _Monthly extends StatelessWidget {
  const _Monthly({required this.r});
  final MonthlyReport r;

  static const _dirText = {
    Direction.improving: 'improving',
    Direction.regressing: 'regressing',
    Direction.stagnating: 'stagnating below pass mark',
    Direction.stable: 'stable',
    Direction.insufficient: 'not enough data (needs 3+)',
  };

  String _label(String id) => negotiationRubric.criteria.firstWhere((c) => c.id == id).label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(key: const Key('monthly-list'), padding: const EdgeInsets.all(16), children: [
      Text('${r.fromDay} to ${r.toDay}', style: theme.textTheme.labelMedium),
      Text('${r.sessionsCompleted} session(s) on ${r.daysPracticed} of ${r.windowDays} days', style: theme.textTheme.titleLarge),
      Text('Adherence ${(r.adherence * 100).round()}%. Practice volume is not the same as skill: judge by the scores below.', style: theme.textTheme.labelMedium),
      const SizedBox(height: 12),
      if (r.criteria.isEmpty) const Text('No scored sessions this month yet.'),
      for (final c in r.criteria)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.label),
          subtitle: Text(
              'First score ${c.baseline} → recent ${c.current.round()} (${c.delta >= 0 ? '+' : ''}${c.delta.round()}), ${_dirText[c.direction]}, n=${c.n}\nBased on sessions: ${c.evidenceSessionIds.length}'),
        ),
      const SizedBox(height: 8),
      Text(r.retentionChecks == 0
          ? 'Retention: no earlier pass was re-tested 7+ days later yet.'
          : 'Retention: ${r.retentionHeld} of ${r.retentionChecks} earlier passes held after 7+ days.'),
      Text('Missions: ${r.missionsDone} of ${r.missionsCreated} done (self-reported).'),
      const SizedBox(height: 12),
      Text('Next month: focus on', style: theme.textTheme.titleMedium),
      if (r.priorities.isEmpty) const Text('No weak or regressing skill found: rotate through all, and reassess on day 1.'),
      for (final p in r.priorities) Text('• ${_label(p)}'),
      const SizedBox(height: 12),
      Text('28-day template', style: theme.textTheme.titleMedium),
      Text('A guide, not a fixed curriculum. Each day the app still picks your session from your latest results.', style: theme.textTheme.labelMedium),
      for (final d in r.plan.take(14))
        Text('Day ${d.day}: ${d.kind == DayKind.reassess ? 'Reassessment' : '${d.kind == DayKind.review ? 'Review' : 'Train'}: ${_label(d.criterionId!)}'}'),
      ExpansionTile(
        title: const Text('Days 15 to 28'),
        tilePadding: EdgeInsets.zero,
        children: [
          for (final d in r.plan.skip(14))
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Day ${d.day}: ${d.kind == DayKind.reassess ? 'Reassessment' : '${d.kind == DayKind.review ? 'Review' : 'Train'}: ${_label(d.criterionId!)}'}'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      for (final c in r.caveats) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(c, style: theme.textTheme.labelMedium)),
    ]);
  }
}
