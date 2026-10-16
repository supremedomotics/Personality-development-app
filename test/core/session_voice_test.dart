import 'dart:convert';

import 'package:ceo_forge/core/planner.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:ceo_forge/core/scenario.dart';
import 'package:ceo_forge/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 2, 9);
const r1 = 'Okay, I can give you 10 percent off the whole quote right now to close this today.';
const r2 = 'Fine, I can also take another 5 percent off if that helps you decide on this.';
const r3 = 'We can see how things go and talk again whenever it suits you in the coming weeks.';

SessionController make() {
  final book = SkillBook();
  final m = const LearningPlanner().planDay(book: book, now: t0, scenarios: negotiationScenarios, rubric: negotiationRubric);
  return SessionController(
      mission: m,
      scenario: negotiationScenarios.firstWhere((s) => s.id == m.scenarioId),
      book: book,
      clock: () => t0,
      rubric: negotiationRubric,
      id: 's');
}

void main() {
  test('reworded lines replace the persona text and are recorded as local-llm; scores are identical', () async {
    final plain = make();
    for (final r in [r1, r2, r3]) {
      plain.submitReply(r);
    }
    final voiced = make();
    for (final r in [r1, r2, r3]) {
      await voiced.submitReplyAsync(r, reword: (line, reply) async => 'REWORDED: $line');
    }
    expect(voiced.record.personaLines[1], startsWith('REWORDED: '));
    expect(voiced.record.personaSources, ['scripted', 'local-llm', 'local-llm', 'local-llm']);
    expect(plain.record.personaSources, ['scripted', 'scripted', 'scripted', 'scripted']);
    // The assessment depends only on the user's words.
    expect(jsonEncode(voiced.record.assessment!.toJson()), jsonEncode(plain.record.assessment!.toJson()));
  });

  test('the reword callback receives the scripted line and the user reply', () async {
    final c = make();
    String? gotLine, gotReply;
    await c.submitReplyAsync(r1, reword: (l, r) async {
      gotLine = l;
      gotReply = r;
      return null;
    });
    expect(gotLine, contains('room in your price'));
    expect(gotReply, r1);
    expect(c.record.personaSources[1], 'scripted', reason: 'null means keep the scripted line');
  });

  test('a throwing or empty reword leaves the scripted line and never breaks the session', () async {
    final c = make();
    final scripted = await c.submitReplyAsync(r1, reword: (l, r) async => throw StateError('native crash'));
    expect(scripted, contains('room in your price'));
    final again = await c.submitReplyAsync(r2, reword: (l, r) async => '   ');
    expect(again, isNotEmpty);
    expect(c.record.personaSources.every((s) => s == 'scripted'), isTrue);
    await c.submitReplyAsync(r3);
    expect(c.phase, SessionPhase.feedback);
  });

  test('persona sources survive JSON; legacy records without the field default to scripted', () async {
    final c = make();
    await c.submitReplyAsync(r1, reword: (l, r) async => 'X');
    final j = c.record.toJson();
    expect(SessionRecord.fromJson(jsonDecode(jsonEncode(j)) as Map<String, Object?>).personaSources, ['scripted', 'local-llm']);
    j.remove('psrc');
    expect(SessionRecord.fromJson(jsonDecode(jsonEncode(j)) as Map<String, Object?>).personaSources, ['scripted', 'scripted']);
  });
}
