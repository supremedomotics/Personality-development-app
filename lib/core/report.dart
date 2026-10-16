library;

import 'missions.dart';
import 'planner.dart';
import 'rubric.dart';
import 'session.dart';

/// Reports are pure functions of stored session/mission records: the same
/// records, window and timezone offset always give the same report.
String dayKey(DateTime t, Duration tz) {
  final d = t.toUtc().add(tz);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class DailySessionLine {
  const DailySessionLine({
    required this.sessionId,
    required this.scenarioId,
    required this.targetCriterion,
    required this.overall,
    required this.targetFirst,
    required this.targetRetry,
    required this.corrected,
    required this.endedEarly,
    required this.minutes,
    required this.failed,
  });
  final String sessionId, scenarioId, targetCriterion;
  final int? overall, targetFirst, targetRetry;
  final bool? corrected;
  final bool endedEarly;
  final int minutes;

  /// "Label (score): comment" for criteria under the pass mark.
  final List<String> failed;
}

class DailyReport {
  const DailyReport({required this.day, required this.lines, required this.openMissions});
  final String day;
  final List<DailySessionLine> lines;
  final int openMissions;

  bool get isEmpty => lines.isEmpty;

  String get headline {
    if (lines.isEmpty) return 'No session recorded for this day.';
    final scored = lines.where((l) => l.overall != null).toList();
    if (scored.isEmpty) return 'Session recorded but too little speech to score.';
    final fixed = lines.where((l) => l.corrected == true).length;
    return '${lines.length} session(s). ${fixed > 0 ? 'You corrected the targeted mistake on retry in $fixed.' : 'The targeted mistake was not yet corrected on retry.'}';
  }
}

DailyReport buildDailyReport({
  required List<SessionRecord> sessions,
  required List<Mission> missions,
  required String day,
  Duration tz = Duration.zero,
  Rubric rubric = negotiationRubric,
}) {
  final lines = <DailySessionLine>[];
  for (final s in sessions.where((s) => dayKey(s.startedAt, tz) == day)) {
    final a = s.assessment;
    final tgt = a?.criterion(s.targetCriterion)?.score;
    final rt = s.retry?.retryScore(s.targetCriterion);
    lines.add(DailySessionLine(
      sessionId: s.id,
      scenarioId: s.scenarioId,
      targetCriterion: s.targetCriterion,
      overall: a?.overall,
      targetFirst: tgt,
      targetRetry: rt,
      corrected: (tgt != null && rt != null) ? (rt > tgt && rt >= kPassScore) : null,
      endedEarly: s.endedEarly,
      minutes: s.completedAt == null ? 0 : s.completedAt!.difference(s.startedAt).inMinutes,
      failed: [
        if (a != null)
          for (final c in a.criteria.where((c) => c.assessed && c.score! < kPassScore))
            '${c.label} (${c.score}): ${c.comment}'
      ],
    ));
  }
  return DailyReport(
    day: day,
    lines: lines,
    openMissions: missions.where((m) => m.status == MissionStatus.open).length,
  );
}

enum Direction { improving, regressing, stagnating, stable, insufficient }

class CriterionWeek {
  const CriterionWeek(this.id, this.label, this.scores, this.direction);
  final String id, label;
  final List<int> scores; // chronological, in-window
  final Direction direction;
  double get mean => scores.reduce((a, b) => a + b) / scores.length;
}

class WeeklyReport {
  const WeeklyReport({
    required this.fromDay,
    required this.toDay,
    required this.sessionsCompleted,
    required this.daysPracticed,
    required this.criteria,
    required this.repeatedMistakes,
    required this.best,
    required this.worst,
    required this.retentionChecks,
    required this.retentionHeld,
    required this.priorities,
    required this.missionsCreated,
    required this.missionsDone,
    required this.caveats,
  });
  final String fromDay, toDay;
  final int sessionsCompleted, daysPracticed;
  final List<CriterionWeek> criteria;
  final List<String> repeatedMistakes; // criterion labels
  final String? best, worst; // "scenario (score)"
  final int retentionChecks, retentionHeld;
  final List<String> priorities;
  final int missionsCreated, missionsDone;
  final List<String> caveats;
}

const _trendThreshold = 8.0;
const _minForTrend = 3;

/// 7-day window ending on [endDay] (inclusive). Retention uses full history.
WeeklyReport buildWeeklyReport({
  required List<SessionRecord> sessions,
  required List<Mission> missions,
  required DateTime endDay,
  Duration tz = Duration.zero,
  Rubric rubric = negotiationRubric,
}) {
  final end = DateTime.utc(endDay.year, endDay.month, endDay.day);
  final days = [for (var i = 6; i >= 0; i--) dayKey(end.subtract(Duration(days: i)), Duration.zero)];
  final inWin = sessions
      .where((s) => s.completedAt != null && days.contains(dayKey(s.startedAt, tz)))
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final scored = inWin.where((s) => s.assessment != null && !s.assessment!.insufficientEvidence).toList();

  final crits = <CriterionWeek>[];
  final repeated = <String>[];
  for (final spec in rubric.criteria) {
    final scores = <int>[
      for (final s in scored)
        if (s.assessment!.criterion(spec.id)?.score != null) s.assessment!.criterion(spec.id)!.score!
    ];
    if (scores.isEmpty) continue;
    Direction dir;
    if (scores.length < _minForTrend) {
      dir = Direction.insufficient;
    } else {
      final h = scores.length ~/ 2;
      double m(List<int> l) => l.reduce((a, b) => a + b) / l.length;
      final early = m(scores.sublist(0, h)), late = m(scores.sublist(scores.length - h));
      final d = late - early;
      dir = d >= _trendThreshold
          ? Direction.improving
          : d <= -_trendThreshold
              ? Direction.regressing
              : (m(scores) < kPassScore ? Direction.stagnating : Direction.stable);
    }
    crits.add(CriterionWeek(spec.id, spec.label, scores, dir));
    if (scores.where((x) => x < kPassScore).length >= 2) repeated.add(spec.label);
  }

  String fmt(SessionRecord s) => '${s.scenarioId} (${s.assessment!.overall})';
  final withOverall = scored.where((s) => s.assessment!.overall != null).toList();
  String? best, worst;
  if (withOverall.isNotEmpty) {
    final sorted = [...withOverall]..sort((a, b) {
        final c = b.assessment!.overall!.compareTo(a.assessment!.overall!);
        return c != 0 ? c : a.startedAt.compareTo(b.startedAt);
      });
    best = fmt(sorted.first);
    worst = fmt(sorted.last);
  }

  // Retention: a criterion first passed >=7 days before a later in-window score.
  var checks = 0, held = 0;
  final all = sessions.where((s) => s.assessment != null && !s.assessment!.insufficientEvidence).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final s in scored) {
    for (final c in s.assessment!.criteria.where((c) => c.assessed)) {
      final prior = all.where((p) =>
          p.startedAt.isBefore(s.startedAt.subtract(const Duration(days: 7))) &&
          (p.assessment!.criterion(c.id)?.score ?? -1) >= kPassScore);
      if (prior.isNotEmpty) {
        checks++;
        if (c.score! >= kPassScore) held++;
      }
    }
  }

  // Priorities: repeated mistakes first, then lowest in-window mean (max 3).
  final byMean = [...crits]..sort((a, b) {
      final c = a.mean.compareTo(b.mean);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final priorities = <String>[
    ...repeated,
    for (final c in byMean)
      if (c.mean < kPassScore && !repeated.contains(c.label)) c.label,
  ].take(3).toList();

  final winMissions = missions.where((m) => days.contains(dayKey(m.createdAt, tz))).toList();
  final caveats = <String>[
    if (scored.length < 3) 'Fewer than 3 scored sessions this week: trends are not reliable.',
    if (scored.map((s) => s.rubricVersion).toSet().length > 1)
      'Sessions used different rubric versions; those scores are not directly comparable.',
    'Scores are rule-based pattern matches, not a validated measure of negotiation skill.',
    'Mission completion is self-reported.',
  ];

  return WeeklyReport(
    fromDay: days.first,
    toDay: days.last,
    sessionsCompleted: inWin.length,
    daysPracticed: inWin.map((s) => dayKey(s.startedAt, tz)).toSet().length,
    criteria: crits,
    repeatedMistakes: repeated,
    best: best,
    worst: worst,
    retentionChecks: checks,
    retentionHeld: held,
    priorities: priorities,
    missionsCreated: winMissions.length,
    missionsDone: winMissions.where((m) => m.status == MissionStatus.done).length,
    caveats: caveats,
  );
}
