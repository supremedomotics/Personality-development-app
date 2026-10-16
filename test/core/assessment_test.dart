import 'dart:convert';

import 'package:ceo_forge/core/assessment_engine.dart';
import 'package:ceo_forge/core/models.dart';
import 'package:ceo_forge/core/rubric.dart';
import 'package:flutter_test/flutter_test.dart';

Assessment run(List<String> replies, {Set<String>? only, double? asr, bool corrected = false}) =>
    const AssessmentEngine().assess(
      negotiationRubric,
      [
        for (var i = 0; i < replies.length; i++)
          Utterance(turn: i + 1, text: replies[i], asrConfidence: asr, corrected: corrected)
      ],
      only: only,
    );

int? score(Assessment a, String id) => a.criterion(id)!.score;

void main() {
  test('premature unconditional discount scores 0 on hold and cites the phrase', () {
    final a = run(['Okay, I can give you 10 percent off the whole quote right now to close this.']);
    expect(score(a, 'hold'), 0);
    expect(a.criterion('hold')!.evidence.single.quote.toLowerCase(), contains('10 percent'));
    expect(score(a, 'ask'), 0);
    expect(score(a, 'trade'), 0);
  });

  test('refusal of a discount is not counted as a concession', () {
    final a = run(["I can't offer a discount before I understand the scope. What are the other quotes including, and how are you comparing them?"]);
    expect(score(a, 'hold'), 100);
    expect(a.criterion('trade')!.assessed, isFalse);
    expect(score(a, 'ask'), 100);
  });

  test('conditional concession after discovery is rewarded', () {
    final a = run([
      'What matters most to you in this project? Help me understand the scope you are comparing.',
      'If you confirm the lighting scope and a 40 percent deposit today, I can look at 5 percent off.'
    ]);
    expect(score(a, 'ask'), 100);
    expect(score(a, 'hold'), 100);
    expect(score(a, 'trade'), 100);
  });

  test('concession before discovery but conditional = 70 not 0 (reasonable alternative)', () {
    final a = run(['If you sign this week and agree the deposit, I can do 5 percent off. What scope are you comparing against?']);
    expect(score(a, 'hold'), 70);
  });

  test('unconditional concession AFTER discovery = 60', () {
    final a = run([
      'How are you comparing the quotes and what matters most to you here?',
      'Alright, I will take 5 percent off the price for you on this one.'
    ]);
    expect(score(a, 'hold'), 60);
    expect(score(a, 'trade'), 0);
  });

  test('question after conceding earns only 60 on ask', () {
    final a = run(['I can give you 8 percent off. What else would you like to know about the scope?']);
    expect(score(a, 'ask'), 60);
  });

  test('closed and why questions are distinguished', () {
    final closed = run(['Is the budget the main problem for you with this proposal and the quote?']);
    expect(score(closed, 'ask'), 40);
    final why = run(['Why do you want fifteen percent off on this quote for the villa project?']);
    expect(score(why, 'ask'), 60);
  });

  test('statement beginning with "what" is not a question', () {
    final a = run(['What matters is the commissioning quality we deliver, and that is why the price is higher than the others.']);
    expect(score(a, 'ask'), 0);
  });

  test('value framing counts distinct terms, not repeats', () {
    expect(score(run(['The value is high. The value is real. The value matters a lot for any home owner like you.']), 'value'), 50);
    expect(score(run(['The support plan and warranty reduce your risk of rework after handover for years.']), 'value'), 100);
  });

  test('clarity penalises fillers, hedges and length with evidence', () {
    final a = run(['Um, I think maybe we could, you know, basically look at the price, I just wanted to say sort of that it is fine.']);
    expect(score(a, 'clarity'), lessThan(60));
    expect(a.criterion('clarity')!.evidence.length, greaterThanOrEqualTo(5));
    final long = run([List.filled(160, 'word').join(' ')]);
    expect(score(long, 'clarity'), lessThan(60));
  });

  test('commit looks only at the final reply', () {
    final a = run([
      'What matters most to you here? Help me understand the scope you want covered in the project.',
      'I will send the revised scope by Thursday and you confirm on Monday, agreed for both sides.'
    ]);
    expect(score(a, 'commit'), 100);
    final b = run([
      'I will send the scope by Thursday, which should work for the review you asked about.',
      'We can see how things go and talk again whenever it suits you in the coming weeks.'
    ]);
    expect(score(b, 'commit'), 0);
  });

  test('insufficient evidence yields no overall score', () {
    final a = run(['Maybe.']);
    expect(a.insufficientEvidence, isTrue);
    expect(a.overall, isNull);
    expect(a.criteria.every((c) => !c.assessed), isTrue);
  });

  test('"only" restricts which criteria are assessed (retry scope)', () {
    final a = run(['What would need to be true for this price to work for you in this project?'], only: {'ask'});
    expect(score(a, 'ask'), 100);
    expect(a.criterion('hold')!.assessed, isFalse);
    expect(a.overall, 100);
  });

  test('low ASR confidence lowers confidence and adds a caveat; correction restores it', () {
    const txt = 'What would need to be true for this price to work for you in this project?';
    final low = run([txt], asr: 0.5);
    final fixed = run([txt], asr: 0.5, corrected: true);
    expect(low.confidence, lessThan(fixed.confidence));
    expect(low.caveats.any((c) => c.contains('Speech recognition confidence')), isTrue);
    expect(fixed.caveats.any((c) => c.contains('Speech recognition confidence')), isFalse);
    expect(score(low, 'ask'), score(fixed, 'ask')); // score unchanged, only confidence
  });

  test('reproducible: identical input gives byte-identical JSON; round-trips', () {
    final r = ['Help me understand what is driving this. If you confirm scope I can look at 5 percent off.'];
    final a = run(r), b = run(r);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    final back = Assessment.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), jsonEncode(a.toJson()));
    expect(a.comparableWith(back), isTrue);
  });

  test('score changes with rubric version are flagged as not comparable', () {
    final a = run(['What would need to be true for this price to work for you in this project?']);
    final other = Assessment(
        rubricId: a.rubricId, rubricVersion: a.rubricVersion + 1, engineVersion: a.engineVersion,
        criteria: a.criteria, overall: a.overall, confidence: a.confidence,
        insufficientEvidence: false, caveats: const [], wordCount: a.wordCount);
    expect(a.comparableWith(other), isFalse);
  });

  test('rubric weights sum to 1', () {
    expect(negotiationRubric.criteria.fold<double>(0, (a, c) => a + c.weight), closeTo(1.0, 1e-9));
  });
}
