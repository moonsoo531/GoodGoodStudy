import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  group('parseRubyText', () {
    test(
      'keeps plain Japanese, existing parenthesis readings, and line breaks',
      () {
        const text = '（話者）日本語(にほんご)を読む。\n♪ [音楽]';

        expect(parseRubyText(text), const [RubyTextSegment(text: text)]);
        expect(plainSubtitleText(text), text);
      },
    );

    test(
      'returns only explicitly authored readings without correcting them',
      () {
        const text = '<ruby>漢字<rt>手書きの読音</rt></ruby>を読む。';

        expect(parseRubyText(text), const [
          RubyTextSegment(text: '漢字', reading: '手書きの読音'),
          RubyTextSegment(text: 'を読む。'),
        ]);
        expect(plainSubtitleText(text), '漢字を読む。');
        expect(parseRubyText('漢字').single.reading, isNull);
      },
    );

    test('keeps separate ruby pairs and original multiline layout', () {
      const text =
          '<ruby>今日<rt>きょう</rt></ruby>は\n'
          '<ruby>日本語<rt>にほんご</rt></ruby>を勉強する。';

      expect(parseRubyText(text), const [
        RubyTextSegment(text: '今日', reading: 'きょう'),
        RubyTextSegment(text: 'は\n'),
        RubyTextSegment(text: '日本語', reading: 'にほんご'),
        RubyTextSegment(text: 'を勉強する。'),
      ]);
      expect(plainSubtitleText(text), '今日は\n日本語を勉強する。');
    });

    test('supports several base-reading pairs inside one ruby group', () {
      const text = '<ruby>東<rt>とう</rt>京<rt>きょう</rt>へ</ruby>';

      expect(parseRubyText(text), const [
        RubyTextSegment(text: '東', reading: 'とう'),
        RubyTextSegment(text: '京', reading: 'きょう'),
        RubyTextSegment(text: 'へ'),
      ]);
      expect(plainSubtitleText(text), '東京へ');
    });

    test(
      'ignores valid ruby fallback parentheses and presentation wrappers',
      () {
        const text =
            '<v 花子><c.blue><b><ruby>漢字<rp>（</rp>'
            '<rt><i>かんじ</i></rt><rp>）</rp></ruby></b></c></v><br>次';

        expect(parseRubyText(text), const [
          RubyTextSegment(text: '漢字', reading: 'かんじ'),
          RubyTextSegment(text: '\n次'),
        ]);
      },
    );

    test('decodes supported named and numeric entities exactly once', () {
      const text =
          '&amp;&lt;&gt;&quot;&apos;&nbsp;&lrm;&rlm; '
          '&#26085;&#x672c;&#X8A9E; &#x1F600; '
          '<ruby>&#x6F22;字<rt>かん&#12376;</rt></ruby>';

      expect(parseRubyText(text), const [
        RubyTextSegment(text: '&<>"\'\u00a0\u200e\u200f 日本語 😀 '),
        RubyTextSegment(text: '漢字', reading: 'かんじ'),
      ]);
      expect(plainSubtitleText('&amp;lt;'), '&lt;');
    });

    test(
      'escaped markup stays literal text and never becomes an annotation',
      () {
        const text = '&lt;ruby&gt;漢字&lt;rt&gt;かんじ&lt;/rt&gt;&lt;/ruby&gt;';

        expect(parseRubyText(text), const [
          RubyTextSegment(text: '<ruby>漢字<rt>かんじ</rt></ruby>'),
        ]);
        expect(parseRubyText('<script>文字</script>').single.text, '文字');
      },
    );

    test(
      'unknown entities, invalid code points, and non-tag brackets survive',
      () {
        const text = '&unknown; &#0; &#xD800; &#x110000; <未定> 1 < 2';

        expect(plainSubtitleText(text), text);
      },
    );

    test(
      'malformed groups keep both base and reading in readable source order',
      () {
        const cases = {
          '<ruby>漢字<rt>かんじ</ruby>': '漢字かんじ',
          '<ruby>漢字<rt>かんじ</rt>': '漢字かんじ',
          '<ruby>漢字</ruby>': '漢字',
          '<ruby><rt>かな</rt></ruby>': 'かな',
          '<ruby>漢字<rt></rt></ruby>': '漢字',
          '<ruby>漢字<ruby>言葉<rt>ことば</rt></ruby></ruby>': '漢字言葉ことば',
          '<ruby>漢字<rt>かんじ</rt><rt>かな</rt></ruby>': '漢字かんじかな',
          '前<rt>よみ</rt>後': '前よみ後',
        };

        for (final entry in cases.entries) {
          expect(plainSubtitleText(entry.key), entry.value, reason: entry.key);
          expect(
            parseRubyText(entry.key)
                .every((segment) => segment.reading == null),
            isTrue,
            reason: entry.key,
          );
        }
      },
    );

    test('segment lists are immutable and segment equality is value based', () {
      final segments = parseRubyText('<ruby>漢字<rt>かんじ</rt></ruby>');
      const expected = RubyTextSegment(text: '漢字', reading: 'かんじ');

      expect(segments.single, expected);
      expect(segments.single.hashCode, expected.hashCode);
      expect(() => segments.clear(), throwsUnsupportedError);
      expect(parseRubyText(''), isEmpty);
    });
  });
}
