import 'package:ceo_forge_bench/wer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical text is 0, ignoring case and punctuation', () {
    expect(wordErrorRate('Help me understand, please.', 'help me understand please'), 0);
  });
  test('one substitution in four words = 0.25', () {
    expect(wordErrorRate('a b c d', 'a x c d'), 0.25);
  });
  test('deletions and insertions count', () {
    expect(wordErrorRate('a b c d', 'a b'), 0.5);
    expect(wordErrorRate('a b', 'a b c d'), 1.0);
  });
  test('empty hypothesis is 1.0; empty reference is null', () {
    expect(wordErrorRate('a b', ''), 1.0);
    expect(wordErrorRate('', 'a'), isNull);
  });
}
