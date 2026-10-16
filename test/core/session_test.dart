import 'dart:convert';

import 'package:ceo_forge/core/planner.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:ceo_forge/core/scenario.dart';
import 'package:ceo_forge/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 2, 9);

SessionController start(SkillBook book, {DateTime? now}) {
  final n = now ?? t0;
  const p = LearningPlanner();
  final m = p.planDay(book: book, now: n, scenarios: negotiationScenarios, rubric: negotiationRubric);
  final sc = negotiationScenarios.firstWhere((s) => s.id == m.scenarioId);
  return SessionController(
      mission: m, scenario: sc, book: book, clock: () => n, rubric: negotiationRubric, id: 's1');
}

const weak1 = 'Okay, I can give you 10 percent off the whole quote right now to close this today.';
const weak2 = 'Fine, I can also take another 5 percent off if that helps you decide on this.';
const weak3 = 'We can see how things go and talk again whenever it suits you in the coming weeks.';

void main() {
  test('full session: weak play, feedback, retry that fixes the mistake, summary, state saved', () {
    final book = SkillBook();
    final c = start(book);
    expect(c.phase, SessionPhase.roleplay);
    c.submitReply(weak1);
    c.submitReply(weak2);
    c.submitReply(weak3);
    expect(c.phase, SessionPhase.feedback);
    final fb = c.feedback!;
    expect(fb.weakened, isNotEmpty);
    expect(fb.strongerExample, isNotEmpty);
    expect(book.states, isEmpty, reason: 'nothing recorded until the session completes');

    c.startRetry();
    final target = c.mission.criterionId;
    expect(c.retryPrompt, isNotEmpty);
    final r = c.submitRetry(
        "I can't discuss price before I understand the scope. What are the other quotes including, and how are you comparing them?");
    expect(c.phase, SessionPhase.summary);
    expect(r.retryAssessment.criteria.where((x) => x.assessed).length, 1);
    expect(c.summary!.finalScore, isNotNull);
    expect(c.summary!.baselineScore, lessThan(c.summary!.finalScore!));
    expect(c.summary!.corrected, isTrue);
    expect(c.summary!.action, isNotEmpty);
    expect(c.summary!.tomorrow, startsWith('Provisional'));
    expect(book.states['negotiation.$target'], isNotNull);
    expect(book.states['negotiation.$target']!.attempts, 1, reason: 'retry must not double count');
    expect(c.record.completedAt, isNotNull);
  });

  test('record is fully reproducible from JSON', () {
    final book = SkillBook();
    final c = start(book);
    c.submitReply(weak1);
    c.submitReply(weak2);
    c.submitReply(weak3);
    c.skipRetry();
    final j = jsonEncode(c.record.toJson());
    final back = SessionRecord.fromJson(jsonDecode(j) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), j);
    // Re-assessing the stored replies reproduces the stored score.
    final a2 = c.engine.assess(negotiationRubric, back.replies);
    expect(a2.overall, back.assessment!.overall);
  });

  test('ending early with nothing said records nothing', () {
    final book = SkillBook();
    final c = start(book);
    c.endEarly();
    expect(c.phase, SessionPhase.summary);
    expect(book.states, isEmpty);
    expect(c.record.endedEarly, isTrue);
  });

  test('ending early after a substantial reply assesses without the commit criterion', () {
    final book = SkillBook();
    final c = start(book);
    c.submitReply('What matters most to you in this project? Help me understand what the other quotes include.');
    c.endEarly();
    expect(c.phase, SessionPhase.feedback);
    expect(c.record.assessment!.criterion('commit')!.assessed, isFalse);
    c.skipRetry();
    expect(c.phase, SessionPhase.summary);
  });

  test('too little speech: no score, nothing recorded', () {
    final book = SkillBook();
    final c = start(book);
    c.submitReply('No.');
    c.endEarly();
    expect(c.phase, SessionPhase.summary);
    expect(c.summary!.improvement, contains('Not enough speech'));
    expect(book.states, isEmpty);
  });

  test('wrong-phase calls fail loudly', () {
    final c = start(SkillBook());
    expect(() => c.startRetry(), throwsStateError);
    expect(() => c.submitRetry('x'), throwsStateError);
    expect(() => c.submitReply('  '), throwsArgumentError);
  });

  test('correcting a mis-transcribed reply re-assesses and does not penalise the ASR error', () {
    final book = SkillBook();
    final c = start(book);
    // ASR heard "discount" where the user said "how much does the discount matter to you?"
    c.submitReply('I can give you 10 percent off the full quote right now for this project today.', asrConfidence: 0.4);
    c.submitReply('What matters most to you in this project and the scope you want covered?', asrConfidence: 0.9);
    c.submitReply('I will send the revised scope by Friday and you confirm by Monday, agreed.', asrConfidence: 0.9);
    final before = c.record.assessment!.criterion('hold')!.score;
    expect(before, 0);
    expect(c.record.assessment!.caveats.any((s) => s.contains('Speech recognition')), isTrue);
    c.correctTranscript(1, 'What would need to be true for this price to work for you? I cannot move before I know.');
    final after = c.record.assessment!.criterion('hold')!.score;
    expect(after, 100);
    expect(c.record.replies.first.corrected, isTrue);
  });

  test('a second day plans from stored results (adaptive)', () {
    final book = SkillBook();
    final c = start(book);
    c.submitReply(weak1);
    c.submitReply(weak2);
    c.submitReply(weak3);
    c.skipRetry();
    final tomorrow = const LearningPlanner().planDay(
        book: book,
        now: t0.add(const Duration(days: 1)),
        scenarios: negotiationScenarios,
        rubric: negotiationRubric,
        lastScenarioId: c.scenario.id);
    expect(tomorrow.isBaseline, isFalse);
    final lowest = book.states.values.map((x) => x.ewma).reduce((a, b) => a < b ? a : b);
    expect(book.states['negotiation.${tomorrow.criterionId}']!.ewma, lessThanOrEqualTo(lowest + 25),
        reason: 'tomorrow should target a weak criterion, not a strong one');
    expect(tomorrow.scenarioId, isNot(c.scenario.id), reason: 'circumstances should change');
  });
}
