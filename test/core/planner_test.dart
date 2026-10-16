import 'dart:convert';

import 'package:ceo_forge/core/models.dart';
import 'package:ceo_forge/core/planner.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:ceo_forge/core/scenario.dart';
import 'package:flutter_test/flutter_test.dart';

final d0 = DateTime.utc(2026, 11, 2, 9);

void rec(SkillBook b, String id, int score, DateTime t, {String sc = 'neg.discount.homeowner'}) =>
    b.record(key: 'negotiation.$id', score: score, confidence: 0.8, scenarioId: sc, now: t);

DailyMission plan(SkillBook b, DateTime now, {String? last}) => const LearningPlanner().planDay(
    book: b, now: now, scenarios: negotiationScenarios, rubric: negotiationRubric, lastScenarioId: last);

void main() {
  test('first day is a baseline, one primary objective, 10 minutes', () {
    final m = plan(SkillBook(), d0);
    expect(m.isBaseline, isTrue);
    expect(m.minutes, 10);
    expect(m.successCriterion, isNotEmpty);
  });

  test('planning is deterministic', () {
    final b = SkillBook();
    for (final id in ['ask', 'hold', 'value', 'trade', 'commit', 'clarity']) {
      rec(b, id, 50, d0);
    }
    final a = plan(b, d0.add(const Duration(days: 2)));
    final c = plan(b, d0.add(const Duration(days: 2)));
    expect(a.criterionId, c.criterionId);
    expect(a.scenarioId, c.scenarioId);
  });

  test('targets the weakest criterion and explains why', () {
    final b = SkillBook();
    for (final id in ['hold', 'value', 'trade', 'commit', 'clarity']) {
      rec(b, id, 90, d0);
    }
    rec(b, 'ask', 20, d0);
    final m = plan(b, d0.add(const Duration(days: 1)));
    expect(m.criterionId, 'ask');
    expect(m.isBaseline, isFalse);
    expect(m.reason, contains('20'));
  });

  test('repeated failure raises priority over a slightly lower average', () {
    final b = SkillBook();
    for (final id in ['ask', 'hold', 'value', 'trade', 'commit', 'clarity']) {
      rec(b, id, 60, d0);
    }
    rec(b, 'value', 60, d0.add(const Duration(days: 1)));
    rec(b, 'value', 60, d0.add(const Duration(days: 2)));
    final m = plan(b, d0.add(const Duration(days: 3)));
    expect(m.criterionId, 'value'); // consecutive fails add priority
  });

  test('varied scenario: avoids the last scenario for repeated weakness', () {
    final b = SkillBook();
    for (final id in ['ask', 'hold', 'value', 'trade', 'commit', 'clarity']) {
      rec(b, id, 40, d0);
    }
    final m = plan(b, d0.add(const Duration(days: 1)), last: 'neg.discount.homeowner');
    expect(m.scenarioId, isNot('neg.discount.homeowner'));
  });

  test('spaced review: pass advances box and interval; fail resets to 1 day', () {
    final b = SkillBook();
    rec(b, 'ask', 80, d0);
    var s = b.states['negotiation.ask']!;
    expect(s.box, 1);
    expect(s.nextReview, d0.add(const Duration(days: 3)));
    rec(b, 'ask', 80, d0.add(const Duration(days: 3)));
    expect(s.box, 2);
    expect(s.nextReview, d0.add(const Duration(days: 3 + 7)));
    rec(b, 'ask', 30, d0.add(const Duration(days: 10)));
    s = b.states['negotiation.ask']!;
    expect(s.box, 0);
    expect(s.nextReview, d0.add(const Duration(days: 11)));
  });

  test('due items get priority; undue strong items do not', () {
    final b = SkillBook();
    for (final id in ['ask', 'hold', 'value', 'trade', 'commit']) {
      rec(b, id, 85, d0);
    }
    rec(b, 'clarity', 85, d0);
    final soon = plan(b, d0.add(const Duration(hours: 2)));
    final later = plan(b, d0.add(const Duration(days: 4)));
    expect(later.reason, contains('due'));
    expect(soon.reason, isNot(contains('due')));
  });

  test('a single success never marks mastery; needs repeats, transfer and delayed retention', () {
    final b = SkillBook();
    rec(b, 'ask', 95, d0);
    final s = b.states['negotiation.ask']!;
    expect(s.demonstratesMastery, isFalse);
    rec(b, 'ask', 95, d0.add(const Duration(days: 3)), sc: 'neg.terms.supplier');
    rec(b, 'ask', 95, d0.add(const Duration(days: 10)), sc: 'neg.scope.architect');
    expect(s.passes, 3);
    expect(s.passedScenarios.length, 3);
    expect(s.retentionScores, isNotEmpty); // attempts after the delay were retention samples
    expect(s.demonstratesMastery, isTrue);
  });

  test('same-day repeats are not counted as retention', () {
    final b = SkillBook();
    rec(b, 'ask', 90, d0);
    rec(b, 'ask', 90, d0.add(const Duration(hours: 1)));
    expect(b.states['negotiation.ask']!.retentionScores, isEmpty);
  });

  test('difficulty rises after two passes and falls after two fails', () {
    final b = SkillBook();
    rec(b, 'hold', 90, d0);
    rec(b, 'hold', 90, d0.add(const Duration(days: 1)));
    expect(b.states['negotiation.hold']!.difficulty, 2);
    rec(b, 'hold', 20, d0.add(const Duration(days: 2)));
    rec(b, 'hold', 20, d0.add(const Duration(days: 3)));
    expect(b.states['negotiation.hold']!.difficulty, 1);
  });

  test('trend needs enough data, then reflects direction', () {
    final b = SkillBook();
    for (var i = 0; i < 3; i++) {
      rec(b, 'value', 40, d0.add(Duration(days: i)));
    }
    expect(b.states['negotiation.value']!.trend, isNull);
    for (var i = 3; i < 6; i++) {
      rec(b, 'value', 80, d0.add(Duration(days: i)));
    }
    expect(b.states['negotiation.value']!.trend, 40);
  });

  test('skill book survives JSON round trip', () {
    final b = SkillBook();
    rec(b, 'ask', 80, d0);
    rec(b, 'hold', 30, d0);
    final back = SkillBook.fromJson(jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), jsonEncode(b.toJson()));
  });

  test('insufficient evidence is not recorded into the skill book', () {
    final b = SkillBook();
    final a = assessAndRecord(
        book: b, utterances: const [Utterance(turn: 1, text: 'No.')], scenarioId: 's', now: d0);
    expect(a.insufficientEvidence, isTrue);
    expect(b.states, isEmpty);
  });

  group('persona reacts to what the user actually said', () {
    ScenarioRun start() => ScenarioRun(negotiationScenarios.first);
    Utterance u(int t, String s) => Utterance(turn: t, text: s);

    test('premature concession escalates pressure', () {
      final r = start();
      final line = r.reply(u(1, 'Okay, I can give you 10 percent off to close the deal today for you.'));
      expect(line.text, contains('fifteen'));
      expect(line.text, contains('room in your price'));
    });

    test('open question reveals the real interest', () {
      final r = start();
      final line = r.reply(u(1, 'Help me understand what the other quotes include and what matters most to you?'));
      expect(line.text, contains('architect'));
    });

    test('brochure talk without a question is rebuffed', () {
      final r = start();
      final line = r.reply(u(1, 'Our system has great reliability, warranty and support for every home we do.'));
      expect(line.text, contains('brochure'));
    });

    test('run ends after three replies; closer depends on commitment', () {
      final r = start();
      r.reply(u(1, 'What matters most to you about this project and the scope you want covered?'));
      r.reply(u(2, 'The support plan and warranty reduce your risk of rework after handover for years.'));
      final last = r.reply(u(3, 'I will send the revised scope by Friday and you confirm by Monday.'));
      expect(r.finished, isTrue);
      expect(last.text, contains('Friday'));
      final v = start();
      v.reply(u(1, 'What matters most to you about this project and the scope you want covered?'));
      v.reply(u(2, 'The support plan and warranty reduce your risk of rework after handover.'));
      expect(v.reply(u(3, 'We can see how things go and talk again whenever it suits you.')).text, contains('think about it'));
    });

    test('model answers exist for every criterion in every scenario', () {
      for (final s in negotiationScenarios) {
        for (final c in negotiationRubric.criteria) {
          expect(s.strongerExamples[c.id], isNotNull, reason: '${s.id}/${c.id}');
        }
      }
    });
  });
}
