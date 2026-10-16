library;

import 'missions.dart';
import 'planner.dart';
import 'report.dart';
import 'rubric.dart';
import 'session.dart';

class CriterionMonth {
  const CriterionMonth({
    required this.id,
    required this.label,
    required this.baseline,
    required this.current,
    required this.n,
    required this.direction,
    required this.evidenceSessionIds,
  });
  final String id, label;

  /// First-ever recorded score for this criterion (all history, not just the window).
  final int baseline;

  /// Mean of the last up to 3 in-window scores.
  final double current;
  final int n; // in-window scores
  final Direction direction;

  /// Sessions the conclusion rests on, so each line can be traced.
  final List<String> evidenceSessionIds;
  double get delta => current - baseline;
}

enum DayKind { train, review, reassess }

class PlannedDay {
  const PlannedDay(this.day, this.kind, this.criterionId, this.note);
  final int day; // 1-based
  final DayKind kind;
  final String? criterionId; // null for a full reassessment
  final String note;
}

class MonthlyReport {
  const MonthlyReport({
    required this.fromDay,
    required this.toDay,
    required this.sessionsCompleted,
    required this.daysPracticed,
    required this.windowDays,
    required this.criteria,
    required this.priorities,
    required this.retentionChecks,
    required this.retentionHeld,
    required this.missionsCreated,
    required this.missionsDone,
    required this.plan,
    required this.caveats,
  });
  final String fromDay, toDay;
  final int sessionsCompleted, daysPracticed, windowDays;
  final List<CriterionMonth> criteria;
  final List<String> priorities; // criterion ids, at most 3
  final int retentionChecks, retentionHeld;
  final int missionsCreated, missionsDone;
  final List<PlannedDay> plan;
  final List<String> caveats;
  double get adherence => daysPracticed / windowDays;
}

const kMonthDays = 30;

MonthlyReport buildMonthlyReport({
  required List<SessionRecord> sessions,
  required List<Mission> missions,
  required DateTime endDay,
  Duration tz = Duration.zero,
  Rubric rubric = negotiationRubric,
}) {
  final end = DateTime.utc(endDay.year, endDay.month, endDay.day);
  final days = [for (var i = kMonthDays - 1; i >= 0; i--) dayKey(end.subtract(Duration(days: i)), Duration.zero)];
  bool usable(SessionRecord s) => s.completedAt != null && s.assessment != null && !s.assessment!.insufficientEvidence;
  final all = sessions.where(usable).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final inWin = all.where((s) => days.contains(dayKey(s.startedAt, tz))).toList();

  final crits = <CriterionMonth>[];
  for (final spec in rubric.criteria) {
    final hist = [for (final s in all) if (s.assessment!.criterion(spec.id)?.score != null) s];
    final win = [for (final s in inWin) if (s.assessment!.criterion(spec.id)?.score != null) s];
    if (win.isEmpty) continue;
    final baseline = hist.first.assessment!.criterion(spec.id)!.score!;
    final scores = [for (final s in win) s.assessment!.criterion(spec.id)!.score!];
    final lastN = scores.length > 3 ? scores.sublist(scores.length - 3) : scores;
    final cur = lastN.reduce((a, b) => a + b) / lastN.length;
    Direction dir;
    if (scores.length < 3) {
      dir = Direction.insufficient;
    } else {
      final h = scores.length ~/ 2;
      double m(List<int> l) => l.reduce((a, b) => a + b) / l.length;
      final d = m(scores.sublist(scores.length - h)) - m(scores.sublist(0, h));
      dir = d >= 8 ? Direction.improving : d <= -8 ? Direction.regressing : (m(scores) < kPassScore ? Direction.stagnating : Direction.stable);
    }
    crits.add(CriterionMonth(
      id: spec.id,
      label: spec.label,
      baseline: baseline,
      current: cur,
      n: scores.length,
      direction: dir,
      evidenceSessionIds: [for (final s in win) s.id],
    ));
  }

  // Priorities: at most three; lowest current score first, regressions break ties.
  final ranked = [...crits]..sort((a, b) {
      int rank(CriterionMonth c) => c.direction == Direction.regressing ? 0 : 1;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final c = a.current.compareTo(b.current);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final priorities = [for (final c in ranked) if (c.current < kPassScore || c.direction == Direction.regressing) c.id].take(3).toList();

  // Retention over the window using full history (>= 7 days after an earlier pass).
  var checks = 0, held = 0;
  for (final s in inWin) {
    for (final c in s.assessment!.criteria.where((c) => c.assessed)) {
      final prior = all.any((p) =>
          p.startedAt.isBefore(s.startedAt.subtract(const Duration(days: 7))) &&
          (p.assessment!.criterion(c.id)?.score ?? -1) >= kPassScore);
      if (prior) {
        checks++;
        if (c.score! >= kPassScore) held++;
      }
    }
  }

  final strong = [for (final c in crits) if (!priorities.contains(c.id) && c.current >= kPassScore) c.id];
  final winMissions = missions.where((m) => days.contains(dayKey(m.createdAt, tz))).toList();
  final practiced = inWin.map((s) => dayKey(s.startedAt, tz)).toSet().length;

  final caveats = <String>[
    if (inWin.length < 8) 'Only ${inWin.length} scored session(s) in 30 days: conclusions are tentative.',
    if (inWin.map((s) => s.rubricVersion).toSet().length > 1) 'Rubric versions differ across the month; scores are not directly comparable.',
    'Baseline is the first recorded score, which is one noisy sample.',
    'Scores are rule-based pattern matches, not a validated measure of negotiation skill.',
    'Mission completion is self-reported.',
  ];

  return MonthlyReport(
    fromDay: days.first,
    toDay: days.last,
    sessionsCompleted: inWin.length,
    daysPracticed: practiced,
    windowDays: kMonthDays,
    criteria: crits,
    priorities: priorities,
    retentionChecks: checks,
    retentionHeld: held,
    missionsCreated: winMissions.length,
    missionsDone: winMissions.where((m) => m.status == MissionStatus.done).length,
    plan: planNextMonth(priorities: priorities, strong: strong, rubric: rubric),
    caveats: caveats,
  );
}

/// A 28-day TEMPLATE, not a fixed curriculum: each real day's session is still
/// chosen by [LearningPlanner] from the results available that day.
List<PlannedDay> planNextMonth({
  required List<String> priorities,
  required List<String> strong,
  Rubric rubric = negotiationRubric,
}) {
  final out = <PlannedDay>[];
  final focus = priorities.isEmpty ? [for (final c in rubric.criteria) c.id] : priorities;
  const pattern = [0, 1, 0, 2, 1, 0]; // weights the first priority most
  var t = 0, r = 0;
  for (var d = 1; d <= 28; d++) {
    if (d == 1 || d == 28) {
      out.add(PlannedDay(d, DayKind.reassess, null,
          d == 1 ? 'Baseline reassessment: no hints, all criteria.' : 'End-of-month reassessment: compare with day 1.'));
    } else if (d % 7 == 0 && strong.isNotEmpty) {
      final id = strong[r++ % strong.length];
      out.add(PlannedDay(d, DayKind.review, id, 'Retention check on a skill you passed earlier, in a new scenario.'));
    } else {
      final id = focus[pattern[t++ % pattern.length] % focus.length];
      out.add(PlannedDay(d, DayKind.train, id, 'Targeted practice, one measurable success criterion.'));
    }
  }
  return out;
}
