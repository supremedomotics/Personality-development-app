/// Rubrics are defined BEFORE any response is evaluated and are versioned.
/// Changing weights, anchors or detection rules requires bumping [Rubric.version]
/// so older scores are flagged as not comparable.

library;

class CriterionSpec {
  const CriterionSpec({
    required this.id,
    required this.label,
    required this.weight,
    required this.what,
    required this.anchors,
    required this.technique,
    required this.measuredBy,
    this.conditional = false,
  });

  final String id;
  final String label;
  final double weight;

  /// What good behaviour looks like.
  final String what;

  /// Score anchors → observable description (documented in ASSESSMENT_RUBRICS.md).
  final Map<int, String> anchors;

  /// One practical technique to apply when this criterion is weak.
  final String technique;

  /// Honest description of how it is measured (heuristic limits).
  final String measuredBy;

  /// True when the criterion can only be assessed if a specific event occurs
  /// (e.g. trading requires a concession). Used by the planner to avoid
  /// proposing a criterion forever that the user's play never triggers.
  final bool conditional;
}

class Rubric {
  const Rubric(this.id, this.version, this.criteria);
  final String id;
  final int version;
  final List<CriterionSpec> criteria;

  CriterionSpec spec(String cid) => criteria.firstWhere((c) => c.id == cid);
}

const negotiationRubric = Rubric('negotiation', 1, [
  CriterionSpec(
    id: 'ask',
    label: 'Discovery question',
    weight: 0.20,
    what: 'Ask an open "what/how" question to learn the other side\'s real need before moving on price.',
    anchors: {
      0: 'No question about the other party\'s needs or constraints.',
      40: 'Only closed yes/no questions.',
      60: 'Open question asked, but only after already moving on price; or a "why" question.',
      100: 'Open what/how question asked before any price movement.',
    },
    technique:
        'Before you defend or discount, ask: "What would need to be true for this to work for you?" or "How are you comparing the quotes?"',
    measuredBy: 'Sentence-level pattern match (what/how/help me understand + question mark). Does not judge question quality.',
  ),
  CriterionSpec(
    id: 'hold',
    label: 'Price discipline',
    weight: 0.25,
    what: 'Do not move on price before you understand the need; any move should follow discovery.',
    anchors: {
      0: 'Unconditional concession before any discovery question.',
      60: 'Unconditional concession after discovery (acceptable, but untraded).',
      70: 'Conditional concession offered before discovery.',
      100: 'No unilateral concession.',
    },
    technique:
        'Name your price once, then stay silent or ask. Treat the first request for a discount as information, not a deadline.',
    measuredBy: 'Pattern match for percent/discount/price-cut phrases, with simple negation and condition detection.',
  ),
  CriterionSpec(
    id: 'value',
    label: 'Value framing',
    weight: 0.20,
    what: 'Link the price to outcomes, risk reduction or total cost that matter to this client.',
    anchors: {
      0: 'No value or outcome language.',
      50: 'One value/outcome term.',
      100: 'Two or more distinct value/outcome terms.',
    },
    technique:
        'Use: "The reason this costs more is X, which protects you from Y." Tie each feature to a consequence for the client.',
    measuredBy: 'Counts distinct value-vocabulary stems. A proxy: it cannot tell whether the value is relevant or true.',
  ),
  CriterionSpec(
    id: 'trade',
    label: 'Conditional trading',
    weight: 0.10,
    what: 'If you concede, trade it for something: scope, term, payment timing, commitment.',
    anchors: {
      0: 'Every concession is unconditional.',
      50: 'Mix of conditional and unconditional concessions.',
      100: 'Every concession is tied to a condition.',
    },
    technique: 'Never give without getting: "If we adjust X, I can look at Y."',
    measuredBy: 'Applies only if a concession was made. Detects condition words (if / in exchange / provided / as long as).',
    conditional: true,
  ),
  CriterionSpec(
    id: 'commit',
    label: 'Commitment & next step',
    weight: 0.10,
    what: 'Close with a specific next step, owner and time.',
    anchors: {
      0: 'No concrete next step.',
      100: 'Specific next step with a time or confirmation.',
    },
    technique: 'End with: "So, I\'ll send X by Thursday; you confirm Y by Friday. Does that work?"',
    measuredBy: 'Pattern match in the final reply only. Does not verify the step is realistic.',
  ),
  CriterionSpec(
    id: 'clarity',
    label: 'Clarity & concision',
    weight: 0.15,
    what: 'Answer in short, direct sentences without filler or hedging.',
    anchors: {
      0: 'Very long answers with many fillers/hedges.',
      70: 'A few fillers/hedges or answers somewhat long.',
      100: 'Concise, no filler or hedging.',
    },
    technique: 'Lead with the conclusion in one sentence, then one reason. Pause instead of saying "um".',
    measuredBy: 'Word counts, a fixed filler/hedge list. Grammar and pronunciation are NOT assessed here.',
  ),
]);
