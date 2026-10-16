/// Word error rate = (substitutions + deletions + insertions) / reference words.
/// Case/punctuation-insensitive. Returns null if the reference is empty.
double? wordErrorRate(String reference, String hypothesis) {
  List<String> norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final r = norm(reference), h = norm(hypothesis);
  if (r.isEmpty) return null;
  var prev = List<int>.generate(h.length + 1, (i) => i);
  for (var i = 1; i <= r.length; i++) {
    final cur = List<int>.filled(h.length + 1, 0)..[0] = i;
    for (var j = 1; j <= h.length; j++) {
      final cost = r[i - 1] == h[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((a, b) => a < b ? a : b);
    }
    prev = cur;
  }
  return prev[h.length] / r.length;
}
