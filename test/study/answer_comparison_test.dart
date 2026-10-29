import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/answer_comparison.dart';

String _different(List<ComparisonSpan> spans) =>
    spans.where((span) => span.different).map((span) => span.text).join();

String _all(List<ComparisonSpan> spans) =>
    spans.map((span) => span.text).join();

void main() {
  test('exact source text matches without altered original strings', () {
    const text = '先週行った駅前の創作料理の店。';
    final result = compareStudyAnswer(text, text);
    expect(result.matches, isTrue);
    expect(result.hasContent, isTrue);
    expect(result.tooLong, isFalse);
    expect(_different(result.actualSpans), isEmpty);
    expect(_different(result.expectedSpans), isEmpty);
    expect(_all(result.actualSpans), text);
    expect(_all(result.expectedSpans), text);
  });

  test('a replacement highlights only the differing input and answer', () {
    final result = compareStudyAnswer('昨日は雨でした。', '昨日は雪でした。');
    expect(result.matches, isFalse);
    expect(_different(result.actualSpans), '雨');
    expect(_different(result.expectedSpans), '雪');
  });

  test('an extra character does not shift the matching remainder', () {
    final result = compareStudyAnswer('駅前のの店が閉店する。', '駅前の店が閉店する。');
    expect(_different(result.actualSpans), 'の');
    expect(_different(result.expectedSpans), isEmpty);
    expect(_all(result.actualSpans), '駅前のの店が閉店する。');
  });

  test('a missing character is marked in the answer, not innocent input', () {
    final result = compareStudyAnswer('駅の店が閉店する。', '駅前の店が閉店する。');
    expect(_different(result.actualSpans), isEmpty);
    expect(_different(result.expectedSpans), '前');
    expect(result.matches, isFalse);
  });

  test('prefix and suffix omissions align with the interior', () {
    final result = compareStudyAnswer('前の店', '駅前の店です');
    expect(_different(result.actualSpans), isEmpty);
    expect(_different(result.expectedSpans), '駅です');
  });

  test('repeated characters have deterministic minimal alignment', () {
    final first = compareStudyAnswer('あああい', 'ああい');
    final second = compareStudyAnswer('あああい', 'ああい');
    expect(_different(first.actualSpans), 'あ');
    expect(_different(first.expectedSpans), isEmpty);
    expect(
      first.actualSpans.map((span) => (span.text, span.different)),
      second.actualSpans.map((span) => (span.text, span.different)),
    );
  });

  test('supplementary kanji and emoji remain whole Unicode runes', () {
    final result = compareStudyAnswer('𠮷田さん🐶です。', '𠮷田さん🐱です。');
    expect(_different(result.actualSpans), '🐶');
    expect(_different(result.expectedSpans), '🐱');
    expect(_all(result.actualSpans), '𠮷田さん🐶です。');
    expect(_all(result.expectedSpans), '𠮷田さん🐱です。');
    expect(
      result.actualSpans.every((span) => !span.text.contains('\ufffd')),
      isTrue,
    );
  });

  test('ignores whitespace and common punctuation while preserving both', () {
    const input = '「創作　料理」\nです!?';
    const answer = '創作料理です。';
    final result = compareStudyAnswer(input, answer);
    expect(result.matches, isTrue);
    expect(_all(result.actualSpans), input);
    expect(_all(result.expectedSpans), answer);
    expect(_different(result.actualSpans), isEmpty);
    expect(_different(result.expectedSpans), isEmpty);
  });

  test('folds ASCII width without inferring Japanese spellings', () {
    expect(compareStudyAnswer('Ｎ２のＡ店。', 'N2のA店。').matches, isTrue);
    expect(compareStudyAnswer('ねこ', '猫').matches, isFalse);
    expect(compareStudyAnswer('ネコ', 'ねこ').matches, isFalse);
    expect(compareStudyAnswer('アレルギ', 'アレルギー').matches, isFalse);
  });

  test('blank and punctuation-only inputs report missing expected text', () {
    for (final actual in ['', '　\n', '。！？']) {
      final result = compareStudyAnswer(actual, '創作料理。');
      expect(result.hasContent, isFalse);
      expect(result.matches, isFalse);
      expect(_different(result.actualSpans), isEmpty);
      expect(_different(result.expectedSpans), '創作料理');
      expect(_all(result.actualSpans), actual);
    }
    expect(compareStudyAnswer('', '').matches, isFalse);
  });

  test('empty answer highlights nonempty input as extra text', () {
    final result = compareStudyAnswer('創作', '');
    expect(result.matches, isFalse);
    expect(result.hasContent, isTrue);
    expect(_different(result.actualSpans), '創作');
    expect(result.expectedSpans, isEmpty);
  });

  test('large alignment returns an explicit unverified result', () {
    final input = 'あ' * (maxStudyComparisonCharacters + 1);
    final result = compareStudyAnswer(input, 'あ');
    expect(result.tooLong, isTrue);
    expect(result.matches, isFalse);
    expect(result.hasContent, isTrue);
    expect(_different(result.actualSpans), isEmpty);
    expect(_all(result.actualSpans), input);
    expect(_all(result.expectedSpans), 'あ');
    final veryLongWhitespace = compareStudyAnswer(' ' * 16001, 'あ');
    expect(veryLongWhitespace.tooLong, isTrue);
    expect(veryLongWhitespace.hasContent, isFalse);
  });

  test('alignment at the maximum supported length remains valid', () {
    final input = 'あ' * maxStudyComparisonCharacters;
    final result = compareStudyAnswer(input, input);
    expect(result.tooLong, isFalse);
    expect(result.matches, isTrue);
  });
}
