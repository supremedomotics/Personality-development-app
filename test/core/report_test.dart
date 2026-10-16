import 'dart:convert';

import 'package:ceo_forge/core/assessment_engine.dart';
import 'package:ceo_forge/core/missions.dart';
import 'package:ceo_forge/core/models.dart';
import 'package:ceo_forge/core/report.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:ceo_forge/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

const good1 = 'What matters most to you here? Help me understand what the other quotes include and how you compare them.';
const good2 = 'The support plan and warranty reduce your risk of rework after handover for years.';
const good3 = 'I will send the revised scope by Friday and you confirm by Monday, agreed.';
const bad1 = 'Okay, I can give you 10 percent off the whole quote right now to close this today.';
const bad2 = 'Fine, I can also take another 5 percent off if that helps you decide on this.';
const bad3 = 'We can see how things go and talk again whenever it suits you in the coming weeks.';

final base = DateTime.utc(2026, 11, 2, 9); // a Monday

SessionRecord rec(String id, DateTime at, List<String> replies,
    {String target = 'ask', String scenario = 'neg.discount.homeowner', String? retryText, int rubricVersion = 1}) {
  final us = [for (var i = 0; i < replies.length; i++) Utterance(turn: i + 1, text: replies[i])];
  final a = const AssessmentEngine().assess(negotiationRubric, us);
  final r = SessionRecord(
    id: id,
    startedAt: at,
    scenarioId: scenario,
    targetCriterion: target,
    isBaseline: false,
    personaLines: ['open', 'p1', 'p2', 'p3'],
    replies: us,
    assessment: a,
    completedAt: at.add(const Duration(minutes: 9)),
    rubricVersion: rubricVersion,
  );
  if (retryText != null) {
    r.retry = RetryRecord(
      turn: 1,
      promptLine: 'open',
      originalText: replies.first,
      originalScore: a.criterion(target)?.score,
      retryText: retryText,
      retryAssessment: const AssessmentEngine().assess(
          negotiationRubric, [Utterance(turn: 1, text: retryText)],
          only: {target}),
    );
  }
  return r;
}

void main() {
  group('daily report', () {
    test('empty day says so', () {
      final d = buildDailyReport(sessions: const [], missions: const [], day: '2026-11-02');
      expect(d.isEmpty, isTrue);
      expect(d.headline, contains('No session'));
    });

    test('shows first vs retry and whether the mistake was corrected, with failed criteria', () {
      final s = rec('a', base, [bad1, bad2, bad3],
          target: 'ask',
          retryText: 'What would need to be true for this price to work for you in this project?');
      final d = buildDailyReport(sessions: [s], missions: const [], day: '2026-11-02');
      final l = d.lines.single;
      expect(l.targetFirst, 0);
      expect(l.targetRetry, 100);
      expect(l.corrected, isTrue);
      expect(l.minutes, 9);
      expect(l.failed.any((f) => f.startsWith('Price discipline (0)')), isTrue);
      expect(d.headline, contains('corrected'));
    });

    test('timezone offset moves a late-evening UTC session to the next local day', () {
      final late = rec('late', DateTime.utc(2026, 11, 2, 22), [good1, good2, good3]);
      expect(buildDailyReport(sessions: [late], missions: const [], day: '2026-11-02').lines.length, 1);
      expect(buildDailyReport(sessions: [late], missions: const [], day: '2026-11-03', tz: const Duration(hours: 5, minutes: 30)).lines.length, 1);
      expect(buildDailyReport(sessions: [late], missions: const [], day: '2026-11-02', tz: const Duration(hours: 5, minutes: 30)).lines, isEmpty);
    });

    test('a session with too little speech is reported as unscored, not as zero', () {
      final s = rec('thin', base, ['No.']);
      final d = buildDailyReport(sessions: [s], missions: const [], day: '2026-11-02');
      expect(d.lines.single.overall, isNull);
      expect(d.headline, contains('too little speech'));
    });
  });

  group('weekly report', () {
    final week = DateTime.utc(2026, 11, 8); // Sunday: window Mon 2 .. Sun 8

    test('window is 7 days inclusive; outside sessions are excluded', () {
      final inside = rec('in', base, [good1, good2, good3]);
      final before = rec('out', base.subtract(const Duration(days: 1)), [good1, good2, good3]);
      final after = rec('after', base.add(const Duration(days: 7)), [good1, good2, good3]);
      final w = buildWeeklyReport(sessions: [inside, before, after], missions: const [], endDay: week);
      expect(w.fromDay, '2026-11-02');
      expect(w.toDay, '2026-11-08');
      expect(w.sessionsCompleted, 1);
    });

    test('improving, regressing and insufficient directions are classified', () {
      // ask goes 0,0,100,100 (improving); hold goes 100,100,0,0 (regressing)
      final ss = [
        rec('1', base, [bad1, bad2, bad3]),
        rec('2', base.add(const Duration(days: 1)), [bad1, bad2, bad3]),
        rec('3', base.add(const Duration(days: 2)), [good1, good2, good3]),
        rec('4', base.add(const Duration(days: 3)), [good1, good2, good3]),
      ];
      final w = buildWeeklyReport(sessions: ss, missions: const [], endDay: week);
      Direction dir(String id) => w.criteria.firstWhere((c) => c.id == id).direction;
      expect(dir('ask'), Direction.improving);
      expect(dir('hold'), Direction.improving); // hold also 0,0,100,100 for this data
      final two = buildWeeklyReport(sessions: ss.take(2).toList(), missions: const [], endDay: week);
      expect(two.criteria.every((c) => c.direction == Direction.insufficient), isTrue);
      final rev = buildWeeklyReport(sessions: ss.reversed.toList(), missions: const [], endDay: week);
      expect(rev.criteria.firstWhere((c) => c.id == 'ask').direction, Direction.improving,
          reason: 'input order must not matter (sorted by time)');
      final down = [
        rec('a', base, [good1, good2, good3]),
        rec('b', base.add(const Duration(days: 1)), [good1, good2, good3]),
        rec('c', base.add(const Duration(days: 2)), [bad1, bad2, bad3]),
        rec('d', base.add(const Duration(days: 3)), [bad1, bad2, bad3]),
      ];
      expect(buildWeeklyReport(sessions: down, missions: const [], endDay: week).criteria.firstWhere((c) => c.id == 'ask').direction,
          Direction.regressing);
    });

    test('flat low scores are "stagnating", flat high scores are "stable"', () {
      final low = [for (var i = 0; i < 3; i++) rec('l$i', base.add(Duration(days: i)), [bad1, bad2, bad3])];
      final high = [for (var i = 0; i < 3; i++) rec('h$i', base.add(Duration(days: i)), [good1, good2, good3])];
      expect(buildWeeklyReport(sessions: low, missions: const [], endDay: week).criteria.firstWhere((c) => c.id == 'ask').direction, Direction.stagnating);
      expect(buildWeeklyReport(sessions: high, missions: const [], endDay: week).criteria.firstWhere((c) => c.id == 'ask').direction, Direction.stable);
    });

    test('repeated mistakes need >=2 sub-pass scores and lead the priorities', () {
      final ss = [
        rec('1', base, [bad1, bad2, bad3]),
        rec('2', base.add(const Duration(days: 1)), [bad1, bad2, bad3]),
      ];
      final w = buildWeeklyReport(sessions: ss, missions: const [], endDay: week);
      expect(w.repeatedMistakes, contains('Discovery question'));
      expect(w.priorities.first, anyOf('Discovery question', 'Price discipline', 'Conditional trading', 'Value framing', 'Commitment & next step'));
      expect(w.priorities.length, lessThanOrEqualTo(3));
    });

    test('best and worst sessions are by overall score', () {
      final ss = [
        rec('good', base, [good1, good2, good3], scenario: 'neg.terms.supplier'),
        rec('bad', base.add(const Duration(days: 1)), [bad1, bad2, bad3], scenario: 'neg.scope.architect'),
      ];
      final w = buildWeeklyReport(sessions: ss, missions: const [], endDay: week);
      expect(w.best, startsWith('neg.terms.supplier'));
      expect(w.worst, startsWith('neg.scope.architect'));
    });

    test('retention compares a score with an earlier pass at least 7 days before', () {
      final early = rec('early', base.subtract(const Duration(days: 10)), [good1, good2, good3]);
      final now = rec('now', base.add(const Duration(days: 1)), [bad1, bad2, bad3]); // forgets ask
      final w = buildWeeklyReport(sessions: [early, now], missions: const [], endDay: week);
      expect(w.retentionChecks, greaterThan(0));
      expect(w.retentionHeld, lessThan(w.retentionChecks));
      final noPrior = buildWeeklyReport(sessions: [now], missions: const [], endDay: week);
      expect(noPrior.retentionChecks, 0);
    });

    test('caveats: few sessions, mixed rubric versions, and always the validity disclaimer', () {
      final ss = [
        rec('1', base, [good1, good2, good3]),
        rec('2', base.add(const Duration(days: 1)), [good1, good2, good3], rubricVersion: 2),
      ];
      final w = buildWeeklyReport(sessions: ss, missions: const [], endDay: week);
      expect(w.caveats.any((c) => c.contains('Fewer than 3')), isTrue);
      expect(w.caveats.any((c) => c.contains('rubric versions')), isTrue);
      expect(w.caveats.any((c) => c.contains('not a validated')), isTrue);
    });

    test('empty week: zero sessions, no crashes, no invented trends', () {
      final w = buildWeeklyReport(sessions: const [], missions: const [], endDay: week);
      expect(w.sessionsCompleted, 0);
      expect(w.criteria, isEmpty);
      expect(w.best, isNull);
      expect(w.priorities, isEmpty);
    });

    test('mission counts use creation day; completion is separate', () {
      final m1 = missionFor(sessionId: 'a', criterionId: 'ask', now: base)..complete(now: base.add(const Duration(days: 1)), outcome: 'Asked, learned their deadline.');
      final m2 = missionFor(sessionId: 'b', criterionId: 'hold', now: base);
      final w = buildWeeklyReport(sessions: const [], missions: [m1, m2], endDay: week);
      expect(w.missionsCreated, 2);
      expect(w.missionsDone, 1);
    });

    test('reproducible: same records give identical report fields regardless of input order', () {
      final ss = [for (var i = 0; i < 4; i++) rec('s$i', base.add(Duration(days: i)), i.isEven ? [good1, good2, good3] : [bad1, bad2, bad3])];
      String sig(WeeklyReport w) => jsonEncode([
            w.sessionsCompleted, w.daysPracticed, w.repeatedMistakes, w.best, w.worst, w.priorities,
            [for (final c in w.criteria) [c.id, c.scores, c.direction.name]]
          ]);
      expect(sig(buildWeeklyReport(sessions: ss, missions: const [], endDay: week)),
          sig(buildWeeklyReport(sessions: ss.reversed.toList(), missions: const [], endDay: week)));
    });
  });

  group('missions', () {
    test('created as an if-then plan for the weak criterion', () {
      final m = missionFor(sessionId: 's1', criterionId: 'hold', now: base);
      expect(m.text, startsWith('When '));
      expect(m.text, contains(', I will '));
      expect(m.status, MissionStatus.open);
    });

    test('completion records self-reported outcome and reflection; JSON round-trips', () {
      final m = missionFor(sessionId: 's1', criterionId: 'ask', now: base);
      m.complete(now: base.add(const Duration(days: 2)), outcome: '  Asked what drove the discount.  ', reflection: 'They wanted speed, not price.');
      expect(m.status, MissionStatus.done);
      expect(m.outcome, 'Asked what drove the discount.');
      final back = Mission.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>);
      expect(jsonEncode(back.toJson()), jsonEncode(m.toJson()));
    });

    test('skip is recorded as skipped, not done', () {
      final m = missionFor(sessionId: 's1', criterionId: 'trade', now: base)..skip(base);
      expect(m.status, MissionStatus.skipped);
    });

    test('every rubric criterion has an if-then template', () {
      for (final c in negotiationRubric.criteria) {
        final m = missionFor(sessionId: 's', criterionId: c.id, now: base);
        expect(m.trigger.isNotEmpty && m.action.isNotEmpty, isTrue);
      }
    });
  });
}
