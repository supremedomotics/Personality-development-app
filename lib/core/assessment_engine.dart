import 'models.dart';
import 'rubric.dart';
import 'text_analysis.dart';

/// Pure function of (rubric, utterances, options): same input ⇒ same output.
class AssessmentEngine {
  const AssessmentEngine();

  static const int minWords = 12;

  Assessment assess(
    Rubric rubric,
    List<Utterance> utterances, {
    Set<String>? only,
  }) {
    final words = utterances.fold<int>(0, (a, u) => a + wordCount(u.text));
    final ids = only ?? rubric.criteria.map((c) => c.id).toSet();
    final asrValues =
        utterances.where((u) => !u.corrected && u.asrConfidence != null).map((u) => u.asrConfidence!).toList();
    final asrAvg = asrValues.isEmpty
        ? null
        : asrValues.reduce((a, b) => a + b) / asrValues.length;
    final asrFactor = asrAvg == null ? 1.0 : (asrAvg / 0.9).clamp(0.3, 1.0);

    final caveats = <String>[
      'Scores come from rule-based text patterns, not from a model that understands meaning.',
    ];
    if (asrAvg != null && asrAvg < 0.75) {
      caveats.add(
          'Speech recognition confidence was low (${(asrAvg * 100).round()}%). Correct the transcript and re-assess before trusting this score.');
    }

    final insufficient = words < minWords;
    if (insufficient) {
      caveats.add('Too little speech ($words words) to assess reliably.');
    }

    final results = <CriterionResult>[];
    for (final spec in rubric.criteria) {
      if (!ids.contains(spec.id) || insufficient) {
        results.add(CriterionResult(
          id: spec.id,
          label: spec.label,
          score: null,
          confidence: 0,
          evidence: const [],
          comment: insufficient ? 'Not enough evidence.' : 'Not applicable to this attempt.',
        ));
        continue;
      }
      final r = switch (spec.id) {
        'ask' => _ask(spec, utterances),
        'hold' => _hold(spec, utterances),
        'value' => _value(spec, utterances),
        'trade' => _trade(spec, utterances),
        'commit' => _commit(spec, utterances),
        'clarity' => _clarity(spec, utterances),
        _ => throw StateError('No detector for ${spec.id}'),
      };
      results.add(CriterionResult(
        id: r.id,
        label: r.label,
        score: r.score,
        confidence: r.score == null ? 0 : r.confidence * asrFactor,
        evidence: r.evidence,
        comment: r.comment,
      ));
    }

    var wsum = 0.0, ssum = 0.0, csum = 0.0;
    for (final r in results.where((r) => r.assessed)) {
      final w = rubric.spec(r.id).weight;
      wsum += w;
      ssum += w * r.score!;
      csum += w * r.confidence;
    }
    return Assessment(
      rubricId: rubric.id,
      rubricVersion: rubric.version,
      engineVersion: kEngineVersion,
      criteria: results,
      overall: wsum == 0 ? null : (ssum / wsum).round(),
      confidence: wsum == 0 ? 0 : csum / wsum,
      insufficientEvidence: insufficient,
      caveats: caveats,
      wordCount: words,
    );
  }

  // ---- detectors -----------------------------------------------------

  static Evidence _ev(int turn, int s, int e, String text, String note) =>
      Evidence(turn: turn, start: s, end: e, quote: text.substring(s, e), note: note);

  /// Walks sentences in order, returning the events needed by several criteria.
  _Timeline _timeline(List<Utterance> us) {
    final tl = _Timeline();
    for (final u in us) {
      final concessions = findConcessions(u.text);
      for (final s in splitSentences(u.text)) {
        final q = classifyQuestion(s.text);
        if (q != QuestionKind.none) {
          tl.questions.add(_Q(u.turn, s, q, tl.order++));
        }
        for (final c in concessions.where((c) => c.sentence.start == s.start)) {
          tl.concessions.add(_C(u.turn, c, tl.order++));
        }
      }
    }
    return tl;
  }

  CriterionResult _ask(CriterionSpec spec, List<Utterance> us) {
    final tl = _timeline(us);
    final text = {for (final u in us) u.turn: u.text};
    final firstConc = tl.concessions.isEmpty ? 1 << 30 : tl.concessions.first.order;
    final cal = tl.questions.where((q) => q.kind == QuestionKind.calibrated).toList();
    if (cal.isNotEmpty) {
      final q = cal.first;
      final early = q.order < firstConc;
      return CriterionResult(
        id: spec.id, label: spec.label,
        score: early ? 100 : 60, confidence: 0.8,
        evidence: [_ev(q.turn, q.s.start, q.s.end, text[q.turn]!, 'Open discovery question')],
        comment: early
            ? 'You asked an open question before moving on price.'
            : 'You asked an open question, but only after you had already moved on price.',
      );
    }
    final why = tl.questions.where((q) => q.kind == QuestionKind.why).toList();
    if (why.isNotEmpty) {
      final q = why.first;
      return CriterionResult(
        id: spec.id, label: spec.label, score: 60, confidence: 0.7,
        evidence: [_ev(q.turn, q.s.start, q.s.end, text[q.turn]!, '"Why" question')],
        comment: '"Why" can sound like a challenge. "What" or "how" questions usually draw out more (this is contested; it depends on tone and context).',
      );
    }
    if (tl.questions.isNotEmpty) {
      final q = tl.questions.first;
      return CriterionResult(
        id: spec.id, label: spec.label, score: 40, confidence: 0.8,
        evidence: [_ev(q.turn, q.s.start, q.s.end, text[q.turn]!, 'Closed question')],
        comment: 'Your question can be answered yes/no, so it uncovers little.',
      );
    }
    return CriterionResult(
      id: spec.id, label: spec.label, score: 0, confidence: 0.8,
      evidence: const [],
      comment: 'No question about the other party\'s needs was detected.',
    );
  }

  CriterionResult _hold(CriterionSpec spec, List<Utterance> us) {
    final tl = _timeline(us);
    final text = {for (final u in us) u.turn: u.text};
    final firstCal = tl.questions
        .where((q) => q.kind == QuestionKind.calibrated)
        .map((q) => q.order)
        .fold<int>(1 << 30, (a, b) => a < b ? a : b);
    if (tl.concessions.isEmpty) {
      return CriterionResult(
        id: spec.id, label: spec.label, score: 100, confidence: 0.8,
        evidence: const [], comment: 'You did not move on price unprompted.');
    }
    // Worst outcome across all concessions determines the score.
    int score = 100;
    _C? worst;
    String comment = '';
    for (final c in tl.concessions) {
      final before = c.order < firstCal;
      final int s;
      final String why;
      if (before && !c.hit.conditional) {
        s = 0;
        why = 'You conceded on price before asking what the client actually needed.';
      } else if (before && c.hit.conditional) {
        s = 70;
        why = 'You tied the concession to a condition, but offered it before discovery.';
      } else if (!c.hit.conditional) {
        s = 60;
        why = 'You conceded after discovery, which is defensible, but without getting anything back.';
      } else {
        s = 100;
        why = 'The concession came after discovery and was conditional.';
      }
      if (s < score || worst == null) {
        score = s;
        worst = c;
        comment = why;
      }
    }
    final w = worst!;
    return CriterionResult(
      id: spec.id, label: spec.label, score: score, confidence: 0.8,
      evidence: [_ev(w.turn, w.hit.hit.start, w.hit.hit.end, text[w.turn]!, 'Concession')],
      comment: comment,
    );
  }

  CriterionResult _value(CriterionSpec spec, List<Utterance> us) {
    final ev = <Evidence>[];
    final seen = <String>{};
    for (final u in us) {
      for (final h in findValueTerms(u.text)) {
        if (seen.add(h.text.toLowerCase())) {
          ev.add(_ev(u.turn, h.start, h.end, u.text, 'Value language'));
        }
      }
    }
    final n = ev.length;
    final score = n == 0 ? 0 : (n == 1 ? 50 : 100);
    return CriterionResult(
      id: spec.id, label: spec.label, score: score, confidence: 0.6, evidence: ev,
      comment: n == 0
          ? 'No outcome, risk or value language was detected.'
          : n == 1
              ? 'One value term found. Connect it to a consequence for this client.'
              : 'You framed the price with several value terms. (Relevance to this client is not judged automatically.)',
    );
  }

  CriterionResult _trade(CriterionSpec spec, List<Utterance> us) {
    final tl = _timeline(us);
    if (tl.concessions.isEmpty) {
      return CriterionResult(
        id: spec.id, label: spec.label, score: null, confidence: 0,
        evidence: const [], comment: 'No concession made, so trading does not apply.');
    }
    final text = {for (final u in us) u.turn: u.text};
    final cond = tl.concessions.where((c) => c.hit.conditional).length;
    final total = tl.concessions.length;
    final score = cond == total ? 100 : (cond == 0 ? 0 : 50);
    final first = tl.concessions.firstWhere((c) => cond == 0 || cond == total ? true : !c.hit.conditional);
    return CriterionResult(
      id: spec.id, label: spec.label, score: score, confidence: 0.75,
      evidence: [_ev(first.turn, first.hit.hit.start, first.hit.hit.end, text[first.turn]!, 'Concession')],
      comment: score == 100
          ? 'Each concession was tied to a condition.'
          : score == 0
              ? 'You gave without asking for anything in return.'
              : 'Some concessions were given without a condition.',
    );
  }

  CriterionResult _commit(CriterionSpec spec, List<Utterance> us) {
    final last = us.reduce((a, b) => a.turn >= b.turn ? a : b);
    final hits = findCommitments(last.text);
    if (hits.isEmpty) {
      return CriterionResult(
        id: spec.id, label: spec.label, score: 0, confidence: 0.6,
        evidence: const [], comment: 'The final reply had no concrete next step or time.');
    }
    final h = hits.first;
    return CriterionResult(
      id: spec.id, label: spec.label, score: 100, confidence: 0.6,
      evidence: [_ev(last.turn, h.start, h.end, last.text, 'Next step')],
      comment: 'You closed with a concrete next step.',
    );
  }

  CriterionResult _clarity(CriterionSpec spec, List<Utterance> us) {
    final ev = <Evidence>[];
    var fill = 0, hedge = 0, words = 0;
    for (final u in us) {
      words += wordCount(u.text);
      for (final h in findFillers(u.text)) {
        fill++;
        ev.add(_ev(u.turn, h.start, h.end, u.text, 'Filler'));
      }
      for (final h in findHedges(u.text)) {
        hedge++;
        ev.add(_ev(u.turn, h.start, h.end, u.text, 'Hedge'));
      }
    }
    final avg = words / us.length;
    final overlong = avg > 90 ? (avg - 90) * 0.8 : 0.0;
    final score = (100 - overlong - fill * 8 - hedge * 5).round().clamp(0, 100);
    final parts = <String>[
      if (overlong > 0) 'average reply ${avg.round()} words (aim for under 90)',
      if (fill > 0) '$fill filler${fill == 1 ? '' : 's'}',
      if (hedge > 0) '$hedge hedge${hedge == 1 ? '' : 's'}',
    ];
    return CriterionResult(
      id: spec.id, label: spec.label, score: score, confidence: 0.7, evidence: ev,
      comment: parts.isEmpty ? 'Concise and direct.' : 'Detected: ${parts.join(', ')}.',
    );
  }
}

class _Q {
  _Q(this.turn, this.s, this.kind, this.order);
  final int turn;
  final Sentence s;
  final QuestionKind kind;
  final int order;
}

class _C {
  _C(this.turn, this.hit, this.order);
  final int turn;
  final ConcessionHit hit;
  final int order;
}

class _Timeline {
  final questions = <_Q>[];
  final concessions = <_C>[];
  int order = 0;
}
