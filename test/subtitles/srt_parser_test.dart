import 'package:flutter_test/flutter_test.dart';

import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  group('parseSrt', () {
    test(
      'parses timestamp precision, multiline text, and missing final blank',
      () {
        final cues = parseSrt(
          '15\n00:00:01,234 --> 00:00:03,567\n'
          'First line\nSecond line',
        );

        expect(cues, hasLength(1));
        expect(cues.single.index, 0);
        expect(cues.single.start, const Duration(milliseconds: 1234));
        expect(cues.single.end, const Duration(milliseconds: 3567));
        expect(cues.single.duration, const Duration(milliseconds: 2333));
        expect(cues.single.text, 'First line\nSecond line');
      },
    );

    test('preserves existing readings, speakers, effects, and markup', () {
      const text = '（話者）漢字(かんじ)を読む。\n♪ [音楽] <i>Hello</i>';
      final cues = parseSrt('1\n00:00:01,000 --> 00:00:02,000\n$text\n');

      expect(cues.single.text, text);
    });

    test('handles BOM, CRLF, CR, and mixed line separators', () {
      const input =
          '1\n00:00:01,000 --> 00:00:02,000\nA\n\n'
          '2\n00:00:03,000 --> 00:00:04,000\nB\n';
      final expected = parseSrt(input);

      expect(parseSrt('\uFEFF$input'), expected);
      expect(parseSrt(input.replaceAll('\n', '\r\n')), expected);
      expect(parseSrt(input.replaceAll('\n', '\r')), expected);
      expect(
        parseSrt(
          '1\r\n00:00:01,000 --> 00:00:02,000\rA\n\n'
          '2\n00:00:03,000 --> 00:00:04,000\nB\r',
        ),
        expected,
      );
    });

    test('accepts indexless cues, dot fractions, and one digit hours', () {
      final cues = parseSrt(
        '1:00:01.500 --> 1:00:02.000\nA\n\n'
        '1:00:03,000 --> 1:00:04,000\nB\n',
      );

      expect(cues, hasLength(2));
      expect(cues.first.start, const Duration(milliseconds: 3601500));
      expect(cues.last.index, 1);
    });

    test('sorts by time and retains source order for tied starts', () {
      final cues = parseSrt(
        '10\n00:00:05,000 --> 00:00:06,000\nLater\n\n'
        '40\n00:00:01,000 --> 00:00:02,000\nFirst tie\n\n'
        '40\n00:00:01,000 --> 00:00:03,000\nSecond tie\n',
      );

      expect(cues.map((cue) => cue.text), ['First tie', 'Second tie', 'Later']);
      expect(cues.map((cue) => cue.index), [0, 1, 2]);
    });

    test('drops invalid starts instead of turning them into time zero', () {
      final cues = parseSrt(
        '1\n00:60:01,000 --> 02:00:00,000\nInvalid minute\n\n'
        '2\n00:00:60,000 --> 00:01:02,000\nInvalid second\n\n'
        '3\n00:00:00,500 --> 00:00:01,000\nValid\n',
      );

      expect(cues, hasLength(1));
      expect(cues.single.text, 'Valid');
      expect(cues.single.start, const Duration(milliseconds: 500));
    });

    test('drops empty, zero length, reversed, and invalid end cues', () {
      final cues = parseSrt(
        '1\n00:00:01,000 --> 00:00:02,000\n  \n\n'
        '2\n00:00:01,000 --> 00:00:01,000\nZero\n\n'
        '3\n00:00:02,000 --> 00:00:01,000\nReversed\n\n'
        '4\n00:00:01,000 --> 00:60:02,000\nInvalid end\n',
      );

      expect(cues, isEmpty);
    });

    test('rejects malformed timestamp prefixes and trailing digits', () {
      final cues = parseSrt(
        '1\n-00:00:01,000 --> 00:00:02,000\nNegative\n\n'
        '2\n100:00:01,000 --> 100:00:02,000\nToo many hours\n\n'
        '3\n00:00:01,000 --> 00:00:02,0000\nExtra digit\n\n'
        '4\nnot-a-timestamp\nInvalid\n\n'
        '5\n00:00:01,000 --> 00:00:02,000 X1:1 X2:2\nValid\n',
      );

      expect(cues, hasLength(1));
      expect(cues.single.text, 'Valid');
    });

    test('returns empty immutable list for empty or garbage content', () {
      for (final input in ['', '\uFEFF', '1', '@@@\n###\n']) {
        expect(parseSrt(input), isEmpty);
      }
      final cues = parseSrt('1\n00:00:01,000 --> 00:00:02,000\nA\n');

      expect(() => cues.clear(), throwsUnsupportedError);
      expect(() => cues[0] = cues.first, throwsUnsupportedError);
    });

    test('cue values have consistent equality and hash codes', () {
      final first = parseSrt('1\n00:00:01,000 --> 00:00:02,000\nA\n').single;
      final second = parseSrt('1\n00:00:01,000 --> 00:00:02,000\nA\n').single;

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
