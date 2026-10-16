library;

import 'assessment_engine.dart';
import 'models.dart';
import 'planner.dart';
import 'rubric.dart';
import 'scenario.dart';

enum SessionPhase { briefing, roleplay, feedback, retry, summary }

class RetryRecord {
  const RetryRecord({
    required this.turn,
    required this.promptLine,
    required this.originalText,
    required this.originalScore,
    required this.retryText,
    required this.retryAssessment,
  });

  final int turn;
  final String promptLine;
  final String originalText;
  final int? originalScore;
  final String retryText;
  final Assessment retryAssessment;

  int? retryScore(String criterion) => retryAssessment.criterion(criterion)?.score;

  Map<String, Object?> toJson() => {
        'turn': turn,
        'prompt': promptLine,
        'orig': originalText,
        'origScore': originalScore,
        'retry': retryText,
        'retryAssessment': retryAssessment.toJson(),
      };

  factory RetryRecord.fromJson(Map<String, Object?> j) => RetryRecord(
        turn: j['turn']! as int,
        promptLine: j['prompt']! as String,
        originalText: j['orig']! as String,
        originalScore: j['origScore'] as int?,
        retryText: j['retry']! as String,
        retryAssessment: Assessment.fromJson(
            (j['retryAssessment']! as Map).cast<String, Object?>()),
      );
}

/// Everything needed to reproduce a session's reports. Stored locally as JSON.
class SessionRecord {
  SessionRecord({
    required this.id,
    required this.startedAt,
    required this.scenarioId,
    required this.targetCriterion,
    required this.isBaseline,
    required this.personaLines,
    required this.replies,
    List<String>? personaSources,
    this.assessment,
    this.retry,
    this.completedAt,
    this.endedEarly = false,
    this.rubricVersion = 1,
  }) : personaSources = personaSources ?? List.filled(personaLines.length, 'scripted', growable: true);

  final String id;
  final DateTime startedAt;
  final String scenarioId;
  final String targetCriterion;
  final bool isBaseline;
  final List<String> personaLines;

  /// Parallel to [personaLines]: 'scripted' or 'local-llm' (reworded by a local model).
  final List<String> personaSources;
  final List<Utterance> replies;
  Assessment? assessment;
  RetryRecord? retry;
  DateTime? completedAt;
  bool endedEarly;
  final int rubricVersion;

  Map<String, Object?> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'scenario': scenarioId,
        'target': targetCriterion,
        'baseline': isBaseline,
        'persona': personaLines,
        'psrc': personaSources,
        'replies': replies.map((r) => r.toJson()).toList(),
        'assessment': assessment?.toJson(),
        'retry': retry?.toJson(),
        'completedAt': completedAt?.toIso8601String(),
        'early': endedEarly,
        'rv': rubricVersion,
      };

  factory SessionRecord.fromJson(Map<String, Object?> j) => SessionRecord(
        id: j['id']! as String,
        startedAt: DateTime.parse(j['startedAt']! as String),
        scenarioId: j['scenario']! as String,
        targetCriterion: j['target']! as String,
        isBaseline: j['baseline']! as bool,
        personaLines: (j['persona']! as List).cast<String>(),
        personaSources: (j['psrc'] as List?)?.cast<String>(),
        replies: (j['replies']! as List)
            .map((r) => Utterance.fromJson((r as Map).cast<String, Object?>()))
            .toList(),
        assessment: j['assessment'] == null
            ? null
            : Assessment.fromJson((j['assessment']! as Map).cast<String, Object?>()),
        retry: j['retry'] == null
            ? null
            : RetryRecord.fromJson((j['retry']! as Map).cast<String, Object?>()),
        completedAt:
            j['completedAt'] == null ? null : DateTime.parse(j['completedAt']! as String),
        endedEarly: j['early'] as bool? ?? false,
        rubricVersion: j['rv'] as int? ?? 1,
      );
}

class CoachFeedback {
  const CoachFeedback({
    required this.worked,
    required this.weakened,
    required this.missed,
    required this.technique,
    required this.strongerExample,
    required this.primaryCriterion,
  });

  final List<String> worked;
  final List<String> weakened;
  final String missed;
  final String technique;
  final String strongerExample;
  final String primaryCriterion;
}

class SessionSummary {
  const SessionSummary({
    required this.baselineScore,
    required this.finalScore,
    required this.improvement,
    required this.remainingWeakness,
    required this.rule,
    required this.action,
    required this.tomorrow,
    required this.corrected,
  });

  /// Score on the targeted criterion in the first attempt / the retry (null if no retry).
  final int? baselineScore;
  final int? finalScore;
  final String improvement;
  final String remainingWeakness;
  final String rule;
  final String action;
  final String tomorrow;
  final bool? corrected;
}

const _rules = {
  'ask': 'Ask before you answer.',
  'hold': 'The first price is not a negotiation; the second question is.',
  'value': 'Price is justified by what it protects, not by what it includes.',
  'trade': 'Never give without getting.',
  'commit': 'No meeting ends without a name, a task and a time.',
  'clarity': 'Say the conclusion first, then stop.',
};

const _actions = {
  'ask': 'In your next real conversation about price, ask one "what" or "how" question before you respond.',
  'hold': 'The next time someone asks for a discount, reply with a question and note what they say.',
  'value': 'Write one sentence linking your price to a risk it removes for your next client, and say it aloud twice.',
  'trade': 'Before your next concession, write down what you want in return.',
  'commit': 'End your next meeting by stating who does what by when. Record whether it was confirmed.',
  'clarity': 'Answer your next three work questions in one sentence plus one reason.',
};

CoachFeedback buildFeedback(Assessment a, Scenario sc, Rubric rubric) {
  final assessed = a.criteria.where((c) => c.assessed).toList();
  final worked = [
    for (final c in assessed.where((c) => c.score! >= kPassScore))
      '${c.label}: ${c.comment}'
  ];
  // Largest weighted gap first.
  final weak = assessed.where((c) => c.score! < kPassScore).toList()
    ..sort((x, y) {
      final gx = rubric.spec(x.id).weight * (100 - x.score!);
      final gy = rubric.spec(y.id).weight * (100 - y.score!);
      final c = gy.compareTo(gx);
      return c != 0 ? c : x.id.compareTo(y.id);
    });
  final primary = weak.isNotEmpty ? weak.first.id : (assessed.isEmpty ? 'ask' : assessed.first.id);
  final spec = rubric.spec(primary);
  return CoachFeedback(
    worked: worked,
    weakened: [for (final c in weak) '${c.label} (${c.score}/100): ${c.comment}'],
    missed: weak.isEmpty
        ? 'No criterion fell below $kPassScore. Raise the difficulty next time.'
        : spec.anchors.entries.last.value,
    technique: spec.technique,
    strongerExample: sc.strongerExamples[primary] ?? '',
    primaryCriterion: primary,
  );
}

/// Drives one session. Deterministic given inputs and an injected clock.
class SessionController {
  SessionController({
    required this.mission,
    required this.scenario,
    required this.book,
    required DateTime Function() clock,
    required this.rubric,
    String? id,
    this.engine = const AssessmentEngine(),
  })  : _clock = clock,
        _run = ScenarioRun(scenario),
        record = SessionRecord(
          id: id ?? clock().microsecondsSinceEpoch.toString(),
          startedAt: clock(),
          scenarioId: scenario.id,
          targetCriterion: mission.criterionId,
          isBaseline: mission.isBaseline,
          personaLines: [],
          replies: [],
          rubricVersion: rubric.version,
        ) {
    record.personaLines.add(scenario.opening);
    record.personaSources.add('scripted');
  }

  final DailyMission mission;
  final Scenario scenario;
  final SkillBook book;
  final Rubric rubric;
  final AssessmentEngine engine;
  final DateTime Function() _clock;
  final ScenarioRun _run;
  final SessionRecord record;

  SessionPhase phase = SessionPhase.roleplay;
  CoachFeedback? feedback;
  SessionSummary? summary;
  bool _applied = false;

  String get currentPersonaLine => _run.lines.last.text;
  int get replyCount => _run.replies.length;
  bool get roleplayFinished => _run.finished;

  /// Returns the persona's response. Throws if not in roleplay.
  String submitReply(String text, {double? asrConfidence, bool corrected = false}) {
    if (phase != SessionPhase.roleplay) throw StateError('Not in roleplay: $phase');
    if (text.trim().isEmpty) throw ArgumentError('Empty reply');
    final u = Utterance(
        turn: _run.replies.length + 1,
        text: text.trim(),
        asrConfidence: asrConfidence,
        corrected: corrected);
    final line = _run.reply(u);
    record.replies.add(u);
    record.personaLines.add(line.text);
    record.personaSources.add('scripted');
    if (_run.finished) _finishRoleplay();
    return line.text;
  }

  /// Like [submitReply], then optionally lets [reword] (e.g. a local LLM) change
  /// the persona's WORDING. The scripted line already decided the meaning, the
  /// flags and the scoring; if [reword] returns null or throws, the scripted
  /// line stands.
  Future<String> submitReplyAsync(
    String text, {
    Future<String?> Function(String scriptedLine, String userReply)? reword,
    double? asrConfidence,
    bool corrected = false,
  }) async {
    final scripted = submitReply(text, asrConfidence: asrConfidence, corrected: corrected);
    if (reword == null) return scripted;
    final idx = record.personaLines.length - 1;
    try {
      final alt = await reword(scripted, text.trim());
      if (alt != null && alt.trim().isNotEmpty && idx < record.personaLines.length) {
        record.personaLines[idx] = alt.trim();
        record.personaSources[idx] = 'local-llm';
        return alt.trim();
      }
    } catch (_) {
      // keep the scripted line
    }
    return scripted;
  }

  /// Graceful early end: assesses whatever was said, if enough evidence exists.
  void endEarly() {
    if (phase != SessionPhase.roleplay) return;
    record.endedEarly = true;
    if (record.replies.isEmpty) {
      phase = SessionPhase.summary;
      record.completedAt = _clock();
      return;
    }
    _finishRoleplay();
  }

  /// User fixes a mis-transcribed reply; the session is re-assessed from the record.
  void correctTranscript(int turn, String newText) {
    if (phase != SessionPhase.feedback) throw StateError('Can only correct at feedback');
    final i = record.replies.indexWhere((r) => r.turn == turn);
    if (i < 0) throw ArgumentError('No such turn');
    record.replies[i] = Utterance(
        turn: turn, text: newText.trim(), asrConfidence: record.replies[i].asrConfidence, corrected: true);
    record.assessment = engine.assess(rubric, record.replies,
        only: _criteriaFor(record.replies.length >= Scenario.turnsPerRun));
    feedback = buildFeedback(record.assessment!, scenario, rubric);
  }

  Set<String> _criteriaFor(bool full) =>
      full ? rubric.criteria.map((c) => c.id).toSet() : rubric.criteria.map((c) => c.id).where((id) => id != 'commit').toSet();

  void _finishRoleplay() {
    final a = engine.assess(rubric, record.replies, only: _criteriaFor(_run.finished));
    record.assessment = a;
    if (a.insufficientEvidence) {
      phase = SessionPhase.summary;
      record.completedAt = _clock();
      summary = const SessionSummary(
        baselineScore: null,
        finalScore: null,
        improvement: 'Not enough speech to assess. Nothing was scored or recorded.',
        remainingWeakness: 'Not assessed.',
        rule: 'Say enough for the coach to work with.',
        action: 'Try a full session tomorrow.',
        tomorrow: 'Same objective.',
        corrected: null,
      );
      return;
    }
    feedback = buildFeedback(a, scenario, rubric);
    phase = SessionPhase.feedback;
  }

  /// The weak moment to replay: where the targeted criterion's evidence sits.
  int get retryTurn {
    final a = record.assessment;
    final c = a?.criterion(mission.criterionId);
    if (c != null && c.evidence.isNotEmpty) return c.evidence.first.turn;
    return mission.criterionId == 'commit' ? record.replies.length : 1;
  }

  String get retryPrompt => record.personaLines[retryTurn - 1];

  void startRetry() {
    if (phase != SessionPhase.feedback) throw StateError('Retry only after feedback');
    phase = SessionPhase.retry;
  }

  /// Assesses ONLY the targeted criterion on the single replayed reply.
  RetryRecord submitRetry(String text, {double? asrConfidence, bool corrected = false}) {
    if (phase != SessionPhase.retry) throw StateError('Not in retry');
    final turn = retryTurn;
    final orig = record.replies.firstWhere((r) => r.turn == turn);
    final u = Utterance(turn: turn, text: text.trim(), asrConfidence: asrConfidence, corrected: corrected);
    final ra = engine.assess(rubric, [u], only: {mission.criterionId});
    final r = RetryRecord(
      turn: turn,
      promptLine: retryPrompt,
      originalText: orig.text,
      originalScore: record.assessment!.criterion(mission.criterionId)?.score,
      retryText: u.text,
      retryAssessment: ra,
    );
    record.retry = r;
    _complete();
    return r;
  }

  void skipRetry() {
    if (phase == SessionPhase.feedback || phase == SessionPhase.retry) _complete();
  }

  void _complete() {
    final now = _clock();
    final a = record.assessment!;
    if (!_applied && !a.insufficientEvidence) {
      // Only the full-session assessment updates the learning state; the
      // immediate retry is stored but not counted (it is not spaced practice).
      const LearningPlanner().applyAssessment(
          book: book, assessment: a, scenarioId: scenario.id, now: now);
      _applied = true;
    }
    record.completedAt = now;
    summary = _buildSummary(now);
    phase = SessionPhase.summary;
  }

  SessionSummary _buildSummary(DateTime now) {
    final a = record.assessment!;
    final fb = feedback!;
    final target = mission.criterionId;
    final base = a.criterion(target)?.score;
    final rt = record.retry;
    final fin = rt?.retryScore(target);
    final corrected = (base != null && fin != null) ? fin > base && fin >= kPassScore : null;

    String improvement;
    if (base != null && fin != null && fin > base) {
      improvement =
          '${rubric.spec(target).label} improved from $base to $fin on the replayed moment.';
    } else {
      final best = a.criteria.where((c) => c.assessed && c.score! >= kPassScore).toList()
        ..sort((x, y) => y.score!.compareTo(x.score!));
      improvement = best.isEmpty
          ? 'No improvement demonstrated yet. That is information, not failure.'
          : 'Strongest area: ${best.first.label} (${best.first.score}/100).';
    }
    final weakSpec = rubric.spec(fb.primaryCriterion);
    final next = const LearningPlanner().planDay(
      book: book,
      now: now.add(const Duration(days: 1)),
      scenarios: negotiationScenarios,
      rubric: rubric,
      lastScenarioId: scenario.id,
    );
    return SessionSummary(
      baselineScore: base,
      finalScore: fin,
      improvement: improvement,
      remainingWeakness: fb.weakened.isEmpty
          ? 'None below $kPassScore this session; scores are from one session only.'
          : fb.weakened.first,
      rule: _rules[fb.primaryCriterion] ?? weakSpec.technique,
      action: _actions[fb.primaryCriterion] ?? weakSpec.technique,
      tomorrow: 'Provisional: ${next.criterionLabel}. ${next.reason}',
      corrected: corrected,
    );
  }
}
