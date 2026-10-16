/// Typed, JSON-serialisable records shared by the deterministic coaching core.
/// No Flutter or platform imports here: this layer must stay unit-testable.

library;

const int kEngineVersion = 1;

class Utterance {
  const Utterance({
    required this.turn,
    required this.text,
    this.asrConfidence,
    this.corrected = false,
  });

  final int turn;
  final String text;

  /// 0..1 from the speech recogniser, null for typed input.
  final double? asrConfidence;

  /// True when the user verified/edited the transcript.
  final bool corrected;

  Map<String, Object?> toJson() => {
        'turn': turn,
        'text': text,
        'asr': asrConfidence,
        'corrected': corrected,
      };

  factory Utterance.fromJson(Map<String, Object?> j) => Utterance(
        turn: j['turn']! as int,
        text: j['text']! as String,
        asrConfidence: (j['asr'] as num?)?.toDouble(),
        corrected: j['corrected'] as bool? ?? false,
      );
}

class Evidence {
  const Evidence({
    required this.turn,
    required this.start,
    required this.end,
    required this.quote,
    required this.note,
  });

  final int turn;
  final int start;
  final int end;
  final String quote;
  final String note;

  Map<String, Object?> toJson() =>
      {'turn': turn, 's': start, 'e': end, 'q': quote, 'n': note};

  factory Evidence.fromJson(Map<String, Object?> j) => Evidence(
        turn: j['turn']! as int,
        start: j['s']! as int,
        end: j['e']! as int,
        quote: j['q']! as String,
        note: j['n']! as String,
      );
}

class CriterionResult {
  const CriterionResult({
    required this.id,
    required this.label,
    required this.score,
    required this.confidence,
    required this.evidence,
    required this.comment,
  });

  final String id;
  final String label;

  /// 0..100, or null when the criterion did not apply to this attempt.
  final int? score;
  final double confidence;
  final List<Evidence> evidence;
  final String comment;

  bool get assessed => score != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'score': score,
        'conf': confidence,
        'ev': evidence.map((e) => e.toJson()).toList(),
        'comment': comment,
      };

  factory CriterionResult.fromJson(Map<String, Object?> j) => CriterionResult(
        id: j['id']! as String,
        label: j['label']! as String,
        score: j['score'] as int?,
        confidence: (j['conf']! as num).toDouble(),
        evidence: (j['ev']! as List)
            .map((e) => Evidence.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        comment: j['comment']! as String,
      );
}

class Assessment {
  const Assessment({
    required this.rubricId,
    required this.rubricVersion,
    required this.engineVersion,
    required this.criteria,
    required this.overall,
    required this.confidence,
    required this.insufficientEvidence,
    required this.caveats,
    required this.wordCount,
  });

  final String rubricId;
  final int rubricVersion;
  final int engineVersion;
  final List<CriterionResult> criteria;

  /// Weighted mean over assessed criteria only; null if evidence is insufficient.
  final int? overall;
  final double confidence;
  final bool insufficientEvidence;
  final List<String> caveats;
  final int wordCount;

  CriterionResult? criterion(String id) {
    for (final c in criteria) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Scores are only comparable when rubric and engine versions match.
  bool comparableWith(Assessment o) =>
      rubricId == o.rubricId &&
      rubricVersion == o.rubricVersion &&
      engineVersion == o.engineVersion;

  Map<String, Object?> toJson() => {
        'rubric': rubricId,
        'rv': rubricVersion,
        'ev': engineVersion,
        'criteria': criteria.map((c) => c.toJson()).toList(),
        'overall': overall,
        'conf': confidence,
        'insufficient': insufficientEvidence,
        'caveats': caveats,
        'words': wordCount,
      };

  factory Assessment.fromJson(Map<String, Object?> j) => Assessment(
        rubricId: j['rubric']! as String,
        rubricVersion: j['rv']! as int,
        engineVersion: j['ev']! as int,
        criteria: (j['criteria']! as List)
            .map((c) =>
                CriterionResult.fromJson((c as Map).cast<String, Object?>()))
            .toList(),
        overall: j['overall'] as int?,
        confidence: (j['conf']! as num).toDouble(),
        insufficientEvidence: j['insufficient']! as bool,
        caveats: (j['caveats']! as List).cast<String>(),
        wordCount: j['words']! as int,
      );
}
