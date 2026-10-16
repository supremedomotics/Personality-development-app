library;

import 'models.dart';
import 'text_analysis.dart';

/// What the simulated person noticed about the user's last reply.
class ReplyFlags {
  const ReplyFlags({
    required this.askedOpen,
    required this.concededUnconditionally,
    required this.concededConditionally,
    required this.valueFramed,
    required this.committed,
    required this.rambling,
    required this.tooShort,
  });

  final bool askedOpen;
  final bool concededUnconditionally;
  final bool concededConditionally;
  final bool valueFramed;
  final bool committed;
  final bool rambling;
  final bool tooShort;

  static ReplyFlags of(String text) {
    final qs = splitSentences(text).map((s) => classifyQuestion(s.text));
    final cons = findConcessions(text);
    final words = wordCount(text);
    return ReplyFlags(
      askedOpen: qs.contains(QuestionKind.calibrated),
      concededUnconditionally: cons.any((c) => !c.conditional),
      concededConditionally: cons.any((c) => c.conditional),
      valueFramed: findValueTerms(text).isNotEmpty,
      committed: findCommitments(text).isNotEmpty,
      rambling: words > 110,
      tooShort: words < 6,
    );
  }
}

class PersonaRule {
  const PersonaRule(this.when, this.line);
  final bool Function(ReplyFlags f, PersonaMemory m) when;
  final String line;
}

/// Light state so the persona remembers what the user did earlier.
class PersonaMemory {
  bool interestRevealed = false;
  bool userConceded = false;
  int pressure = 1;
}

class Scenario {
  const Scenario({
    required this.id,
    required this.skill,
    required this.title,
    required this.persona,
    required this.setting,
    required this.opening,
    required this.targets,
    required this.minDifficulty,
    required this.reactions,
    required this.closers,
    required this.strongerExamples,
    required this.whyItMatters,
  });

  final String id;
  final String skill;
  final String title;
  final String persona;
  final String setting;

  /// The persona's first line.
  final String opening;

  /// Criteria this scenario can train.
  final Set<String> targets;
  final int minDifficulty;

  /// Ordered rules for reacting after the user's reply on turns 1 and 2.
  final List<PersonaRule> reactions;

  /// Final line, chosen by whether the user committed.
  final ({String committed, String vague}) closers;

  /// criterion → example of a stronger response. Revealed only AFTER the first attempt.
  final Map<String, String> strongerExamples;
  final String whyItMatters;

  static const int turnsPerRun = 3;
}

/// Runs one role-play. Deterministic: same replies ⇒ same persona lines.
class ScenarioRun {
  ScenarioRun(this.scenario) {
    lines.add(PersonaLine(0, scenario.opening));
  }

  final Scenario scenario;
  final memory = PersonaMemory();
  final List<PersonaLine> lines = [];
  final List<Utterance> replies = [];

  bool get finished => replies.length >= Scenario.turnsPerRun;

  /// Records the user's reply and returns the persona's response.
  PersonaLine reply(Utterance u) {
    assert(!finished);
    replies.add(u);
    final f = ReplyFlags.of(u.text);
    if (f.concededUnconditionally) memory.userConceded = true;
    if (f.askedOpen) memory.interestRevealed = true;
    final String line;
    if (finished) {
      line = f.committed ? scenario.closers.committed : scenario.closers.vague;
    } else {
      line = scenario.reactions
          .firstWhere((r) => r.when(f, memory),
              orElse: () => scenario.reactions.last)
          .line;
      memory.pressure++;
    }
    final pl = PersonaLine(replies.length, line);
    lines.add(pl);
    return pl;
  }
}

class PersonaLine {
  const PersonaLine(this.turn, this.text);
  final int turn;
  final String text;
}

// --- Scenario library (MVP: negotiation) ---------------------------------

final List<Scenario> negotiationScenarios = [
  Scenario(
    id: 'neg.discount.homeowner',
    skill: 'negotiation',
    title: 'The 15% discount demand',
    persona: 'Mr. Hale, luxury homeowner',
    setting:
        'You have quoted a full-home KNX automation project. Mr. Hale has two cheaper quotes and wants a decision today.',
    opening:
        'I have three quotes for the KNX installation and yours is the highest by a distance. Take 15 percent off and I will sign today.',
    targets: {'ask', 'hold', 'value', 'trade', 'commit', 'clarity'},
    minDifficulty: 1,
    reactions: [
      PersonaRule((f, m) => f.concededUnconditionally,
          'So there was room in your price all along. If you can move that far, you can do fifteen. Make it fifteen.'),
      PersonaRule((f, m) => f.askedOpen && !m.userConceded,
          'Honestly? My architect says the other quotes include lighting scenes and a two-year support plan for less money. I just do not see what I get for the difference.'),
      PersonaRule((f, m) => f.valueFramed && !f.askedOpen,
          'That sounds like a brochure. I do not care about features. I care about the number. Can you do fifteen or not?'),
      PersonaRule((f, m) => f.rambling,
          'You have said a lot and I still do not have an answer. Fifteen percent, yes or no?'),
      PersonaRule((f, m) => true,
          'That does not answer me. The other firms were far more flexible. Where are you on the price?'),
    ],
    closers: (
      committed: 'Alright. Send me the revised scope by Friday and I will give you an answer on Monday.',
      vague: 'Hm. I will think about it. Do not wait by the phone.',
    ),
    strongerExamples: {
      'ask':
          '"Fair question on price. Help me understand: what are the other quotes including, and what matters most to you in this project?"',
      'hold':
          '"I do not move on price before I understand the scope. What is driving the 15 percent?"',
      'value':
          '"The difference is a two-year support plan and certified commissioning, which protects you from a rework bill if a system fails after handover."',
      'trade':
          '"If you can confirm the lighting scope today and agree a 40 percent deposit, I can look at a five percent adjustment."',
      'commit':
          '"So I will send the revised scope by Thursday and you confirm by Monday. Does that work?"',
      'clarity':
          '"Our price reflects commissioning and support. What would you need to see to compare like for like?"',
    },
    whyItMatters:
        'Premature discounts teach clients that your first price is negotiable and cost margin on every project.',
  ),
  Scenario(
    id: 'neg.terms.supplier',
    skill: 'negotiation',
    title: 'Supplier refuses payment terms',
    persona: 'Ms. Berger, distributor account manager',
    setting:
        'You need 60-day payment terms on a large actuator order. Ms. Berger insists on payment in advance.',
    opening:
        'Our policy is full payment before shipment. If you want these actuators next month, I need the transfer by Friday.',
    targets: {'ask', 'hold', 'value', 'trade', 'commit', 'clarity'},
    minDifficulty: 2,
    reactions: [
      PersonaRule((f, m) => f.concededUnconditionally,
          'Good. So we agree on payment in advance. I will send the invoice.'),
      PersonaRule((f, m) => f.askedOpen && !m.userConceded,
          'The issue is that two customers paid late last year and finance made this policy absolute. A larger order from you would carry the same risk.'),
      PersonaRule((f, m) => f.valueFramed && !f.askedOpen,
          'I understand you are a valuable customer, but policy is policy. What are you proposing?'),
      PersonaRule((f, m) => true,
          'I cannot change the policy on my own. Tell me exactly what you are asking for.'),
    ],
    closers: (
      committed: 'Send me a written proposal with the order volume by Wednesday and I will take it to finance.',
      vague: 'Then there is nothing for me to take to finance. Let me know what you decide.',
    ),
    strongerExamples: {
      'ask':
          '"Help me understand what specifically worries finance about late payment on an order like this."',
      'hold':
          '"I cannot pay in full upfront on this volume. What options does your finance team allow?"',
      'value':
          '"We have paid on time for four years and this order is three times our usual size, which lowers your cost per delivery."',
      'trade':
          '"If you can move to 30 days, I can commit to a larger annual volume and a 20 percent deposit."',
      'commit':
          '"I will send a written proposal with volumes by Wednesday and you take it to finance. Agreed?"',
      'clarity':
          '"I need 30-day terms on this order. What would finance need to approve that?"',
    },
    whyItMatters:
        'Payment terms are a cash-flow lever as large as price, and they are rarely negotiated well.',
  ),
  Scenario(
    id: 'neg.scope.architect',
    skill: 'negotiation',
    title: 'The architect questions your competence',
    persona: 'Mr. Okafor, architect',
    setting:
        'An architect is deciding whether to specify your firm on a villa project. He doubts a small integrator can deliver.',
    opening:
        'I have worked with larger integrators for years. Why would I risk my reputation on a smaller firm, and why are you asking for a premium?',
    targets: {'ask', 'value', 'clarity', 'commit', 'hold', 'trade'},
    minDifficulty: 3,
    reactions: [
      PersonaRule((f, m) => f.concededUnconditionally,
          'So you are willing to cut your price immediately. That does not make me more confident in the quality.'),
      PersonaRule((f, m) => f.askedOpen,
          'My main worry is handover. Last time the integrator was late and the client blamed me. I need certainty on the schedule and who is accountable.'),
      PersonaRule((f, m) => f.valueFramed,
          'Those are claims. Give me something specific I can show my client.'),
      PersonaRule((f, m) => true,
          'You have not told me why I should trust you with this project.'),
    ],
    closers: (
      committed: 'Fine. Send me two reference projects and a handover schedule by Thursday. Then we will talk.',
      vague: 'I will consider it, but I will probably stay with my usual partner.',
    ),
    strongerExamples: {
      'ask':
          '"What went wrong at handover last time, and what would you need to see to feel safe specifying us?"',
      'hold': '"Our premium reflects commissioning and accountability. What is your main concern?"',
      'value':
          '"We guarantee commissioning dates in the contract and a named engineer is accountable, which removes the handover risk you described."',
      'trade':
          '"If you specify us on this villa, I can offer a fixed handover date backed by a penalty clause."',
      'commit':
          '"I will send two references and a handover schedule by Thursday. Can we meet Friday?"',
      'clarity': '"Our risk is lower than it looks: named engineer, fixed dates, references on request."',
    },
    whyItMatters:
        'Architects are referral gatekeepers. Winning them depends on reducing their risk, not on defending your size.',
  ),
];
