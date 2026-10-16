library;

/// A real-world action to practise outside the app, written as an
/// implementation intention ("When X, I will Y"; see docs/RESEARCH_EVIDENCE.md E8/E9).
class Mission {
  Mission({
    required this.id,
    required this.createdAt,
    required this.sessionId,
    required this.criterionId,
    required this.trigger,
    required this.action,
    this.status = MissionStatus.open,
    this.completedAt,
    this.outcome,
    this.reflection,
  });

  final String id;
  final DateTime createdAt;
  final String sessionId;
  final String criterionId;
  final String trigger;
  final String action;
  MissionStatus status;
  DateTime? completedAt;

  /// What the user says happened (self-reported; the app cannot verify it).
  String? outcome;
  String? reflection;

  String get text => 'When $trigger, I will $action.';

  void complete({required DateTime now, required String outcome, String? reflection}) {
    status = MissionStatus.done;
    completedAt = now;
    this.outcome = outcome.trim();
    this.reflection = reflection?.trim();
  }

  void skip(DateTime now) {
    status = MissionStatus.skipped;
    completedAt = now;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'created': createdAt.toIso8601String(),
        'session': sessionId,
        'criterion': criterionId,
        'trigger': trigger,
        'action': action,
        'status': status.name,
        'completed': completedAt?.toIso8601String(),
        'outcome': outcome,
        'reflection': reflection,
      };

  factory Mission.fromJson(Map<String, Object?> j) => Mission(
        id: j['id']! as String,
        createdAt: DateTime.parse(j['created']! as String),
        sessionId: j['session']! as String,
        criterionId: j['criterion']! as String,
        trigger: j['trigger']! as String,
        action: j['action']! as String,
        status: MissionStatus.values.byName(j['status']! as String),
        completedAt: j['completed'] == null ? null : DateTime.parse(j['completed']! as String),
        outcome: j['outcome'] as String?,
        reflection: j['reflection'] as String?,
      );
}

enum MissionStatus { open, done, skipped }

const _templates = <String, ({String trigger, String action})>{
  'ask': (
    trigger: 'a client or supplier raises price in my next real conversation',
    action: 'ask one open "what" or "how" question before I respond'
  ),
  'hold': (
    trigger: 'someone asks me for a discount',
    action: 'reply with a question about what is driving the request, and note their answer'
  ),
  'value': (
    trigger: 'I quote a price to my next client',
    action: 'link it to one risk it removes or one outcome it secures, in a single sentence'
  ),
  'trade': (
    trigger: 'I am about to concede on anything',
    action: 'write down what I want in return first, and say "if you..., I can..."'
  ),
  'commit': (
    trigger: 'my next meeting is ending',
    action: 'state who does what by when, and note whether it was confirmed'
  ),
  'clarity': (
    trigger: 'I answer a work question in the next 24 hours',
    action: 'give the conclusion in one sentence, then one reason, then stop'
  ),
};

Mission missionFor({
  required String sessionId,
  required String criterionId,
  required DateTime now,
}) {
  final t = _templates[criterionId] ?? _templates['clarity']!;
  return Mission(
    id: 'm-$sessionId',
    createdAt: now,
    sessionId: sessionId,
    criterionId: criterionId,
    trigger: t.trigger,
    action: t.action,
  );
}
