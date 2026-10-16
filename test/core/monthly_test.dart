import 'package:ceo_forge/core/monthly.dart';
import 'package:ceo_forge/core/report.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_test.dart' show rec, good1, good2, good3, bad1, bad2, bad3;

final end = DateTime.utc(2026, 11, 30);
List<String> good() => [good1, good2, good3];
List<String> bad() => [bad1, bad2, bad3];

void main() {
  test('empty month: no criteria, no priorities, a generic 28-day template, no crashes', () {
    final m = buildMonthlyReport(sessions: const [], missions: const [], endDay: end);
    expect(m.sessionsCompleted, 0);
    expect(m.criteria, isEmpty);
    expect(m.adherence, 0);
    expect(m.plan.length, 28);
    expect(m.caveats.any((c) => c.contains('tentative')), isTrue);
  });

  test('window is 30 days inclusive and baseline comes from ALL history', () {
    final old = rec('old', DateTime.utc(2026, 9, 1, 9), bad()); // before the window: sets baseline
    final s1 = rec('s1', DateTime.utc(2026, 11, 10, 9), good());
    final s2 = rec('s2', DateTime.utc(2026, 11, 20, 9), good());
    final m = buildMonthlyReport(sessions: [old, s1, s2], missions: const [], endDay: end);
    expect(m.fromDay, '2026-11-01');
    expect(m.toDay, '2026-11-30');
    expect(m.sessionsCompleted, 2);
    final ask = m.criteria.firstWhere((c) => c.id == 'ask');
    expect(ask.baseline, 0);
    expect(ask.current, 100);
    expect(ask.delta, 100);
    expect(ask.evidenceSessionIds, ['s1', 's2']);
  });

  test('adherence counts distinct days, not sessions', () {
    final a = rec('a', DateTime.utc(2026, 11, 3, 8), good());
    final b = rec('b', DateTime.utc(2026, 11, 3, 18), good());
    final c = rec('c', DateTime.utc(2026, 11, 4, 8), good());
    final m = buildMonthlyReport(sessions: [a, b, c], missions: const [], endDay: end);
    expect(m.daysPracticed, 2);
    expect(m.adherence, closeTo(2 / 30, 1e-9));
  });

  test('priorities: at most three, only weak or regressing, weakest first', () {
    final ss = [for (var i = 0; i < 4; i++) rec('b$i', DateTime.utc(2026, 11, 2 + i, 9), bad())];
    final m = buildMonthlyReport(sessions: ss, missions: const [], endDay: end);
    expect(m.priorities.length, lessThanOrEqualTo(3));
    expect(m.priorities, isNotEmpty);
    final strongOnly = buildMonthlyReport(
        sessions: [for (var i = 0; i < 4; i++) rec('g$i', DateTime.utc(2026, 11, 2 + i, 9), good())], missions: const [], endDay: end);
    expect(strongOnly.priorities, isEmpty, reason: 'nothing below the pass mark and nothing regressing');
  });

  test('a regressing criterion is prioritised even if its mean is above the pass mark', () {
    // ask: 100,100,100 then 0,0 -> late mean low => regressing
    final ss = [
      rec('1', DateTime.utc(2026, 11, 2, 9), good()),
      rec('2', DateTime.utc(2026, 11, 3, 9), good()),
      rec('3', DateTime.utc(2026, 11, 4, 9), good()),
      rec('4', DateTime.utc(2026, 11, 5, 9), bad()),
      rec('5', DateTime.utc(2026, 11, 6, 9), bad()),
      rec('6', DateTime.utc(2026, 11, 7, 9), bad()),
    ];
    final m = buildMonthlyReport(sessions: ss, missions: const [], endDay: end);
    expect(m.criteria.firstWhere((c) => c.id == 'ask').direction, Direction.regressing);
    expect(m.priorities, contains('ask'));
  });

  test('retention: earlier pass ≥7 days before a later in-window score is checked', () {
    final early = rec('e', DateTime.utc(2026, 11, 2, 9), good());
    final later = rec('l', DateTime.utc(2026, 11, 20, 9), bad());
    final m = buildMonthlyReport(sessions: [early, later], missions: const [], endDay: end);
    expect(m.retentionChecks, greaterThan(0));
    expect(m.retentionHeld, lessThan(m.retentionChecks));
  });

  test('reproducible and independent of input order', () {
    final ss = [for (var i = 0; i < 6; i++) rec('s$i', DateTime.utc(2026, 11, 2 + i * 3, 9), i.isEven ? good() : bad())];
    String sig(MonthlyReport m) => [
          m.sessionsCompleted, m.daysPracticed, m.priorities, m.retentionChecks, m.retentionHeld,
          [for (final c in m.criteria) [c.id, c.baseline, c.current, c.direction.name]],
          [for (final p in m.plan) [p.day, p.kind.name, p.criterionId]],
        ].toString();
    expect(sig(buildMonthlyReport(sessions: ss, missions: const [], endDay: end)),
        sig(buildMonthlyReport(sessions: ss.reversed.toList(), missions: const [], endDay: end)));
  });

  group('next-month plan', () {
    test('28 days; day 1 and 28 are full reassessments; every 7th day is a review when strong skills exist', () {
      final p = planNextMonth(priorities: ['ask', 'hold'], strong: ['value', 'commit']);
      expect(p.length, 28);
      expect(p.first.kind, DayKind.reassess);
      expect(p.first.criterionId, isNull);
      expect(p.last.kind, DayKind.reassess);
      expect([for (final d in p) if (d.kind == DayKind.review) d.day], [7, 14, 21]);
      expect(p.where((d) => d.kind == DayKind.review).map((d) => d.criterionId).toSet(), {'value', 'commit'});
    });

    test('training days only target the chosen priorities and weight the first most', () {
      final p = planNextMonth(priorities: ['ask', 'hold', 'value'], strong: const []);
      final train = p.where((d) => d.kind == DayKind.train).toList();
      expect(train.every((d) => ['ask', 'hold', 'value'].contains(d.criterionId)), isTrue);
      int n(String id) => train.where((d) => d.criterionId == id).length;
      expect(n('ask'), greaterThan(n('hold')));
      expect(n('hold'), greaterThanOrEqualTo(n('value')));
      expect(p.where((d) => d.kind == DayKind.review), isEmpty, reason: 'no strong skills to review');
    });

    test('with no priorities it rotates through all criteria rather than inventing a weakness', () {
      final p = planNextMonth(priorities: const [], strong: const []);
      expect(p.where((d) => d.kind == DayKind.train).map((d) => d.criterionId).toSet().length, greaterThan(1));
    });

    test('a single priority is used for all training days', () {
      final p = planNextMonth(priorities: ['trade'], strong: const []);
      expect(p.where((d) => d.kind == DayKind.train).every((d) => d.criterionId == 'trade'), isTrue);
    });
  });
}
