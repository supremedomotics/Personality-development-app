/// Lexical, rule-based text analysis. These are heuristics, not understanding:
/// every consumer must treat results as observable-pattern evidence only.

library;

class Sentence {
  const Sentence(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

class Hit {
  const Hit(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

final _sentenceRe = RegExp(r'\S.*?(?:[.!?]+(?=\s|$)|$)', dotAll: true);
final _wordRe = RegExp(r"[A-Za-z0-9][A-Za-z0-9'’%$.-]*");

final _calibratedRe = RegExp(
    r'\b(what|how|help me understand|walk me through|tell me more|tell me about)\b',
    caseSensitive: false);
final _whyRe = RegExp(r'\bwhy\b', caseSensitive: false);
final _askRequestRe = RegExp(
    r'^(help me understand|walk me through|tell me more|tell me about)\b',
    caseSensitive: false);
final _concessionRe = RegExp(
    r"(\d{1,2}(?:\.\d+)?\s?(?:%|percent)|discount|knock\s+(?:\w+\s+){0,3}off|(?:reduce|lower|drop|cut|slash)\s+(?:the|our|my)\s+price|meet\s+you\s+(?:halfway|in the middle)|i\s+can\s+do\s+(?:it\s+)?for|take\s+(?:\w+\s+){0,3}off)",
    caseSensitive: false);
final _negationRe = RegExp(
    r"\b(can't|cannot|can not|won't|will not|not able to|unable to|don't|do not|not going to|never|no|without)\b",
    caseSensitive: false);
final _conditionalRe = RegExp(
    r'\b(if|in exchange|in return|provided|as long as|assuming|once you|only if|but only|trade|on condition|subject to)\b',
    caseSensitive: false);

final _fillerRe = RegExp(
    r'\b(um+|uh+|erm?|hmm+|you know|i mean|basically|literally|actually)\b',
    caseSensitive: false);
final _hedgeRe = RegExp(
    r'\b(maybe|perhaps|i think|i guess|i suppose|i hope|hopefully|sort of|kind of|probably|a bit|i just)\b',
    caseSensitive: false);

final _commitRe = RegExp(
    r'\b(next step|by (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|the end of|\d)|send you|i will send|i\x27ll send|schedule|confirm|sign|agree|deadline|this week|tomorrow|on (?:monday|tuesday|wednesday|thursday|friday))\b',
    caseSensitive: false);

/// Stem → regex for value-framing vocabulary. Distinct stems are counted.
final Map<String, RegExp> _valueTerms = {
  for (final e in {
    'value': r'\bvalue\b',
    'outcome': r'\boutcomes?\b',
    'result': r'\bresults?\b',
    'reliab': r'\breliab\w*',
    'warranty': r'\bwarrant(?:y|ies)\b',
    'support': r'\bsupport\b',
    'integration': r'\bintegrat\w*',
    'saving': r'\bsav(?:e|es|ing|ings)\b',
    'risk': r'\brisks?\b',
    'longterm': r'\blong[- ]term\b',
    'experience': r'\bexperience\b',
    'guarantee': r'\bguarantee\w*',
    'quality': r'\bquality\b',
    'roi': r'\b(?:roi|return on investment|total cost)\b',
    'maintenance': r'\bmaintenance\b',
    'uptime': r'\b(?:uptime|downtime)\b',
  }.entries)
    e.key: RegExp(e.value, caseSensitive: false),
};

int wordCount(String t) => _wordRe.allMatches(t).length;

List<Sentence> splitSentences(String t) => [
      for (final m in _sentenceRe.allMatches(t))
        Sentence(m.start, m.end, m.group(0)!),
    ];

enum QuestionKind { none, calibrated, why, closed }

/// A question needs a trailing "?" or an explicit request phrase
/// ("help me understand..."). Whisper-style transcripts carry punctuation;
/// a transcript without it will under-detect questions (documented limitation).
QuestionKind classifyQuestion(String s) {
  final t = s.trim();
  final isQ = t.endsWith('?') || _askRequestRe.hasMatch(t);
  if (!isQ) return QuestionKind.none;
  if (_calibratedRe.hasMatch(t)) return QuestionKind.calibrated;
  if (_whyRe.hasMatch(t)) return QuestionKind.why;
  return QuestionKind.closed;
}

class ConcessionHit {
  const ConcessionHit(this.sentence, this.hit, this.conditional);
  final Sentence sentence;
  final Hit hit;
  final bool conditional;
}

/// Finds price/terms concessions; refusals ("I can't offer a discount") are skipped.
List<ConcessionHit> findConcessions(String text) {
  final out = <ConcessionHit>[];
  for (final s in splitSentences(text)) {
    for (final m in _concessionRe.allMatches(s.text)) {
      final from = m.start - 40 < 0 ? 0 : m.start - 40;
      final before = s.text.substring(from, m.start);
      if (_negationRe.hasMatch(before)) continue;
      out.add(ConcessionHit(
        s,
        Hit(s.start + m.start, s.start + m.end, m.group(0)!),
        _conditionalRe.hasMatch(s.text),
      ));
      break; // one hit per sentence is enough
    }
  }
  return out;
}

List<Hit> findFillers(String t) => _hits(_fillerRe, t);
List<Hit> findHedges(String t) => _hits(_hedgeRe, t);
List<Hit> findCommitments(String t) => _hits(_commitRe, t);

List<Hit> _hits(RegExp re, String t) =>
    [for (final m in re.allMatches(t)) Hit(m.start, m.end, m.group(0)!)];

/// One hit per distinct value-framing stem.
List<Hit> findValueTerms(String t) {
  final out = <Hit>[];
  for (final re in _valueTerms.values) {
    final m = re.firstMatch(t);
    if (m != null) out.add(Hit(m.start, m.end, m.group(0)!));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
