import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  group('parseWebVtt', () {
    test(
      'parses header, optional identifier, settings, and both timestamp forms',
      () {
        final cues = parseWebVtt('''
WEBVTT 手動注音
Kind: captions
Language: ja

opening
00:01.250 --> 00:03.500 line:90% align:center
<ruby>漢字<rt>かんじ</rt></ruby>を読む。

00:01:03.000 --> 00:01:04.250
次の文。
''');

        expect(cues, hasLength(2));
        expect(cues.first.start, const Duration(milliseconds: 1250));
        expect(cues.first.end, const Duration(milliseconds: 3500));
        expect(cues.last.start, const Duration(seconds: 63));
        expect(cues.last.duration, const Duration(milliseconds: 1250));
        expect(cues.first.text, '<ruby>漢字<rt>かんじ</rt></ruby>を読む。');
        expect(plainSubtitleText(cues.first.text), '漢字を読む。');
      },
    );

    test(
      'skips NOTE STYLE REGION blocks even when they contain timing lines',
      () {
        final cues = parseWebVtt('''
WEBVTT

NOTE note heading
00:01.000 --> 00:02.000
この文は注釈。

STYLE
::cue { color: red; }

REGION
id:bottom
width:80%

NOTEBOOK
00:03.000 --> 00:04.000
表示する文。
''');

        expect(cues, hasLength(1));
        expect(cues.single.text, '表示する文。');
        expect(cues.single.start, const Duration(seconds: 3));
      },
    );

    test(
      'keeps entities and original multiline markup until inline parsing',
      () {
        final cues = parseWebVtt('''
WEBVTT

00:01.000 --> 00:03.000
<ruby>今日<rt>きょう</rt></ruby>は &amp; 明日。
二行目。
''');

        expect(
          cues.single.text,
          '<ruby>今日<rt>きょう</rt></ruby>は &amp; 明日。\n二行目。',
        );
        expect(plainSubtitleText(cues.single.text), '今日は & 明日。\n二行目。');
      },
    );

    test('normalizes BOM and all common line endings', () {
      const input = 'WEBVTT\n\n00:01.000 --> 00:02.000\n文。\n';
      final expected = parseWebVtt(input);

      expect(parseWebVtt('\uFEFF$input'), expected);
      expect(parseWebVtt(input.replaceAll('\n', '\r\n')), expected);
      expect(parseWebVtt(input.replaceAll('\n', '\r')), expected);
    });

    test('sorts by start with stable ties and chronological indices', () {
      final cues = parseWebVtt('''
WEBVTT

late
00:05.000 --> 00:06.000
後。

first
00:01.000 --> 00:02.000
先。

second
00:01.000 --> 00:03.000
同時。
''');

      expect(cues.map((cue) => cue.index), [0, 1, 2]);
      expect(cues.map((cue) => cue.text), ['先。', '同時。', '後。']);
      expect(() => cues.clear(), throwsUnsupportedError);
      expect(cueAt(cues, const Duration(milliseconds: 2500)), cues[1]);
      expect(cueAt(cues, const Duration(seconds: 4)), isNull);
      expect(
        cueAt(
          cues,
          const Duration(milliseconds: 3000),
          offset: const Duration(milliseconds: 500),
        ),
        cues[1],
      );
    });

    test('drops invalid timestamps and empty zero or reversed cues', () {
      const invalidTiming = [
        '00:60.000 --> 00:61.000',
        '60:00.000 --> 61:00.000',
        '00:60:01.000 --> 02:00:00.000',
        '-00:01.000 --> 00:02.000',
        '00:01,000 --> 00:02,000',
        '00:01.000 --> 00:02.0000',
        '00:02.000 --> 00:01.000',
        '00:01.000 --> 00:01.000',
        '999999999999999999999999:00:00.000 --> 999999999999999999999999:00:01.000',
      ];
      for (final timing in invalidTiming) {
        expect(parseWebVtt('WEBVTT\n\n$timing\n文。\n'), isEmpty, reason: timing);
      }
      expect(parseWebVtt('WEBVTT\n\n00:01.000 --> 00:02.000\n'), isEmpty);
    });

    test('accepts headerless cues and large valid hour fields', () {
      final cues = parseWebVtt('100:00:01.000 --> 100:00:02.000\n文。');

      expect(cues.single.start, const Duration(hours: 100, seconds: 1));
      expect(parseWebVtt('garbage'), isEmpty);
      expect(parseWebVtt(''), isEmpty);
    });
  });
}
