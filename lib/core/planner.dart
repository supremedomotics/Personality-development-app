library;

import 'dart:math' as math;

import 'assessment_engine.dart';
import 'models.dart';
import 'rubric.dart';
import 'scenario.dart';

const int kPassScore = 70;
const List<int> kReviewIntervalsDays = [1, 3, 7, 14, 30, 60];

/// Per-criterion learning state, e.g. key "negotiation.ask".
class SkillState {
  SkillState({
    required this.key,
    required this.baseline,
    List<int>? recent,
    this.ewma = 0,
    this.attempts = 0,
    this.passes = 0,
    this.fails = 0,
    this.consecutiveFails = 0,
    this.consecutivePasses = 0,
    this.box = 0,
    this.difficulty = 1,
    this.lastPracticed,
    this.nextReview,
    this.retentionScores = const [],
    Set<String>? passedScenarios,
    this.confidence = 0,
  })  : recent = recent ?? [],
        passedScenarios = passedScenarios ?? {};

  final String key;
  final int baseline;
  final List<int> recent; // last 8 scores, oldest first
  double ewma;
  int attempts, passes, fails, consecutiveFails, consecutivePasses;
  int box; // spaced-repetition box 0..5
  int difficulty; // 1..5
  DateTime? lastPracticed;
  DateTime? nextReview;

  /// Scores achieved on attempts made after the review interval had elapsed.
  List<int> retentionScores;

  /// Distinct scenario ids where the criterion was passed (transfer evidence).
  final Set<String> passedScenarios;
  double confidence;

  bool isDue(DateTime now) => nextReview == null || !nextReview!.isAfter(now);

  /// Trend: mean of last 3 minus mean of previous up-to-3. Null if < 4 points.
  double? get trend {
    if (recent.length < 4) return null;
    final last = recent.sublist(recent.length - 3);
    final prev = recent.sublist(math.max(0, recent.length - 6), recent.length - 3);
    double m(List<int> l) => l.reduce((a, b) => a + b) / l.length;
    return m(last) - m(prev);
  }

  /// "Mastered" is never permanent and needs transfer + delayed retention.
  bool get demonstratesMastery =>
      passes >= 3 &&
      passedScenarios.length >= 2 &&
      retentionScores.any((s) => s >= kPassScore);

  Map<String, Object?> toJson() => {
        'key': key,
        'baseline': baseline,
        'recent': recent,
        'ewma': ewma,
        'attempts': attempts,
        'passes': passes,
        'fails': fails,
        'cf': consecutiveFails,
        'cp': consecutivePasses,
        'box': box,
        'difficulty': difficulty,
        'last': lastPracticed?.toIso8601String(),
        'next': nextReview?.toIso8601String(),
        'ret': retentionScores,
        'ps': passedScenarios.toList()..sort(),
        'conf': confidence,
      };

  factory SkillState.fromJson(Map<String, Object?> j) => SkillState(
        key: j['key']! as String,
        baseline: j['baseline']! as int,
        recent: (j['recent']! as List).cast<int>().toList(),
        ewma: (j['ewma']! as num).toDouble(),
        attempts: j['attempts']! as int,
        passes: j['passes']! as int,
        fails: j['fails']! as int,
        consecutiveFails: j['cf']! as int,
        consecutivePasses: j['cp']! as int,
        box: j['box']! as int,
        difficulty: j['difficulty']! as int,
        lastPracticed:
            j['last'] == null ? null : DateTime.parse(j['last']! as String),
        nextReview:
            j['next'] == null ? null : DateTime.parse(j['next']! as String),
        retentionScores: (j['ret']! as List).cast<int>().toList(),
        passedScenarios: (j['ps']! as List).cast<String>().toSet(),
        confidence: (j['conf']! as num).toDouble(),
      );
}

class SkillBook {
  SkillBook([Map<String, SkillState>? states]) : states = states ?? {};
  final Map<String, SkillState> states;

  /// Records one scored attempt. [now] is injected so behaviour is reproducible.
  void record({
    required String key,
    required int score,
    required double confidence,
    required String scenarioId,
    required DateTime now,
  }) {
    final s = states.putIfAbsent(key, () => SkillState(key: key, baseline: score, ewma: score.toDouble()));
    final wasDue = s.attempts > 0 && s.isDue(now);
    // A "retention" sample is an attempt made after the scheduled delay.
    if (wasDue && s.lastPracticed != null && now.difference(s.lastPracticed!).inHours >= 20) {
      s.retentionScores = [...s.retentionScores, score];
    }
    s.attempts++;
    s.recent.add(score);
    if (s.recent.length > 8) s.recent.removeAt(0);
    s.ewma = s.attempts == 1 ? score.toDouble() : 0.6 * s.ewma + 0.4 * score;
    s.confidence = math.min(1.0, (s.attempts / 5)) * confidence;
    if (score >= kPassScore) {
      s.passes++;
      s.consecutivePasses++;
      s.consecutiveFails = 0;
      s.box = math.min(s.box + 1, kReviewIntervalsDays.length - 1);
      s.passedScenarios.add(scenarioId);
      if (s.consecutivePasses >= 2 && s.difficulty < 5) {
        s.difficulty++;
        s.consecutivePasses = 0;
      }
    } else {
      s.fails++;
      s.consecutiveFails++;
      s.consecutivePasses = 0;
      s.box = 0;
      if (s.consecutiveFails >= 2 && s.difficulty > 1) {
        s.difficulty--;
        s.consecutiveFails = 0;
      }
    }
    s.lastPracticed = now;
    s.nextReview = now.add(Duration(days: kReviewIntervalsDays[s.box]));
  }

  Map<String, Object?> toJson() =>
      {for (final e in states.entries) e.key: e.value.toJson()};

  factory SkillBook.fromJson(Map<String, Object?> j) => SkillBook({
        for (final e in j.entries)
          e.key: SkillState.fromJson((e.value! as Map).cast<String, Object?>())
      });
}

class DailyMission {
  const DailyMission({
    required this.skill,
    required this.criterionId,
    required this.criterionLabel,
    required this.scenarioId,
    required this.successCriterion,
    required this.weakness,
    required this.why,
    required this.minutes,
    required this.isBaseline,
    required this.reason,
  });

  final String skill;
  final String criterionId;
  final String criterionLabel;
  final String scenarioId;
  final String successCriterion;
  final String weakness;
  final String why;
  final int minutes;
  final bool isBaseline;

  /// Why the planner chose this (transparent, shown to the user).
  final String reason;
}

const _successText = {
  'ask': 'Ask one open "what" or "how" question before you mention any price movement.',
  'hold': 'Make no price concession until you have asked what is driving the request.',
  'value': 'Use at least two outcome or risk terms to justify the price.',
  'trade': 'If you give anything, attach a condition ("if we...").',
  'commit': 'End with a specific next step and a time.',
  'clarity': 'Keep every reply under 90 words with no filler or hedges.',
};

class LearningPlanner {
  const LearningPlanner();

  /// Deterministic: same book + same date + same history ⇒ same mission.
  DailyMission planDay({
    required SkillBook book,
    required DateTime now,
    required List<Scenario> scenarios,
    required Rubric rubric,
    String? lastScenarioId,
  }) {
    final hasHistory = book.states.isNotEmpty;
    // Order criteria by priority; never-practised criteria come first (baseline).
    final scored = <(CriterionSpec, double, String)>[];
    for (final spec in rubric.criteria) {
      final key = '${rubric.id}.${spec.id}';
      final s = book.states[key];
      double p;
      String why;
      if (s == null) {
        p = 150 + spec.weight * 10;
        why = hasHistory
            ? 'Not yet assessed: establishing a baseline.'
            : 'First session: establishing your baseline.';
      } else {
        final gap = 100 - s.ewma;
        p = gap * 0.5 + s.consecutiveFails * 10 + spec.weight * 10;
        why = 'Recent average ${s.ewma.round()}/100';
        if (s.consecutiveFails > 0) why += ', missed ${s.consecutiveFails} in a row';
        if (s.isDue(now)) {
          p += 40;
          why += ', due for spaced review';
        }
        why += '.';
      }
      scored.add((spec, p, why));
    }
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.id.compareTo(b.$1.id);
    });
    final top = scored.first;
    final spec = top.$1;
    final state = book.states['${rubric.id}.${spec.id}'];
    final difficulty = state?.difficulty ?? 1;

    // Pick a scenario that trains the criterion, matches difficulty, and differs
    // from the last one (varied practice supports transfer).
    final trainsIt = scenarios.where((s) => s.targets.contains(spec.id)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final fitsLevel = trainsIt.where((s) => s.minDifficulty <= difficulty).toList();
    // Prefer: right difficulty and not the last scenario; then any scenario that
    // trains the criterion but differs from the last (variation beats gating);
    // only then repeat.
    var cand = fitsLevel.where((s) => s.id != lastScenarioId).toList();
    if (cand.isEmpty) cand = trainsIt.where((s) => s.id != lastScenarioId).toList();
    if (cand.isEmpty) cand = fitsLevel.isEmpty ? trainsIt : fitsLevel;
    if (cand.isEmpty) cand = [...scenarios]..sort((a, b) => a.id.compareTo(b.id));
    // Rotate by attempts so a repeated weakness meets new circumstances.
    final scenario = cand[(state?.attempts ?? 0) % cand.length];

    return DailyMission(
      skill: rubric.id,
      criterionId: spec.id,
      criterionLabel: spec.label,
      scenarioId: scenario.id,
      successCriterion: _successText[spec.id] ?? spec.what,
      weakness: spec.label,
      why: scenario.whyItMatters,
      minutes: 10,
      isBaseline: state == null,
      reason: top.$3,
    );
  }

  /// Applies a completed session's final assessment to the skill book.
  void applyAssessment({
    required SkillBook book,
    required Assessment assessment,
    required String scenarioId,
    required DateTime now,
  }) {
    for (final c in assessment.criteria.where((c) => c.assessed)) {
      book.record(
        key: '${assessment.rubricId}.${c.id}',
        score: c.score!,
        confidence: c.confidence,
        scenarioId: scenarioId,
        now: now,
      );
    }
  }
}

/// Convenience for tests and the app: assess + apply.
Assessment assessAndRecord({
  required SkillBook book,
  required List<Utterance> utterances,
  required String scenarioId,
  required DateTime now,
  Set<String>? only,
}) {
  final a = const AssessmentEngine().assess(negotiationRubric, utterances, only: only);
  if (!a.insufficientEvidence) {
    const LearningPlanner().applyAssessment(
        book: book, assessment: a, scenarioId: scenarioId, now: now);
  }
  return a;
}
