import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  test('independent cue value and immutability contract', _valueSemantics);
  test(
    'independent SRT opaque text and stable ordering',
    _srtPayloadAndOrdering,
  );
  test('independent SRT invalid timestamp matrix', _srtRejections);
  test('independent WebVTT reserved blocks and payloads', _webVttStructure);
  test('independent WebVTT invalid timestamp matrix', _webVttRejections);
  test(
    'independent overlap and gap lookup contract',
    _lookupBoundariesAndOverlaps,
  );
  test('mutable external cue lists are not cached', _externalListChanges);
  test(
    'subtitle offset arithmetic handles duration extremes',
    _arithmeticExtremes,
  );
  test(
    'seeded overlap lookup agrees with a linear reference',
    _generatedLookupAgreement,
  );
  test('indexed long-overlap track remains efficient', _largeParsedTrack);
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _equal(Object? actual, Object? expected, String description) {
  _expect(actual == expected, '$description: expected $expected, got $actual');
}

void _immutable(List<SubtitleCue> cues) {
  final candidate = const SubtitleCue(
    index: 5,
    start: Duration.zero,
    end: Duration(seconds: 1),
    text: 'replacement',
  );
  final operations = <void Function()>[
    () => cues.add(candidate),
    () => cues.clear(),
    () => cues.length = 0,
    () => cues.sort((a, b) => 0),
    if (cues.isNotEmpty) () => cues[0] = candidate,
    if (cues.isNotEmpty) () => cues.removeAt(0),
  ];
  for (final operation in operations) {
    var rejected = false;
    try {
      operation();
    } on UnsupportedError {
      rejected = true;
    }
    _expect(rejected, 'parsed track rejects mutation');
  }
}

void _valueSemantics() {
  const a = SubtitleCue(
    index: 7,
    start: Duration(milliseconds: 1234),
    end: Duration(milliseconds: 1545),
    text: '[鈴] <ruby>春<rt>はる</rt></ruby> &amp;',
  );
  const b = SubtitleCue(
    index: 7,
    start: Duration(milliseconds: 1234),
    end: Duration(milliseconds: 1545),
    text: '[鈴] <ruby>春<rt>はる</rt></ruby> &amp;',
  );
  _equal(a.duration, const Duration(milliseconds: 311), 'duration');
  _equal(a, b, 'all fields define equality');
  _equal(a.hashCode, b.hashCode, 'equal cue hashes agree');
  for (final unequal in [
    SubtitleCue(index: 8, start: a.start, end: a.end, text: a.text),
    SubtitleCue(index: 7, start: Duration.zero, end: a.end, text: a.text),
    SubtitleCue(index: 7, start: a.start, end: Duration.zero, text: a.text),
    SubtitleCue(index: 7, start: a.start, end: a.end, text: 'different'),
  ]) {
    _expect(a != unequal, 'each value field participates in equality');
  }
  final unrelated = Object();
  _expect(a != unrelated, 'other types are unequal');
}

void _srtPayloadAndOrdering() {
  final veryLongLine = List.filled(18000, '語').join();
  final cues = parseSrt(
    '\uFEFF700\r\n'
    '0:00:08,010 --> 00:00:10.200 X1:12\r\n'
    '  <ruby>森<rt>もり</rt></ruby> &amp;\r'
    '  [鳥の声]  \n\n'
    '00:00:02.001 --> 00:00:03,002\r'
    '$veryLongLine\r\r'
    '19\n00:00:08,010 --> 0:00:11,200\n'
    '<v Sora><i>後の同時刻</i>\n',
  );
  _equal(cues.length, 3, 'numbered and unnumbered blocks');
  _equal(cues[0].text, veryLongLine, 'arbitrary dialogue length');
  _equal(
    cues[1].text,
    '<ruby>森<rt>もり</rt></ruby> &amp;\n  [鳥の声]',
    'only outer payload whitespace is trimmed',
  );
  _equal(cues[2].text, '<v Sora><i>後の同時刻</i>', 'markup retained');
  _equal(cues[0].start, const Duration(milliseconds: 2001), 'dot timestamp');
  _equal(cues[1].end, const Duration(milliseconds: 10200), 'settings ignored');
  for (var i = 0; i < cues.length; i++) {
    _equal(cues[i].index, i, 'returned order assigns fresh indices');
  }
  _immutable(cues);
  final maximum = parseSrt('99:59:59,998 --> 99:59:59,999\n終');
  _equal(maximum.length, 1, 'two-digit maximum SRT hour');
}

void _srtRejections() {
  final invalidTimes = [
    '000:00:00,000',
    '-1:00:00,000',
    '1:60:00,000',
    '1:00:60,000',
    '1:0:00,000',
    '1:00:0,000',
    '1:00:00,00',
    '1:00:00,0000',
    '1:00:00.000x',
    '1:00:00:000',
    '１:00:00,000',
    '999999999999999999999:00:00,000',
  ];
  for (final value in invalidTimes) {
    _equal(
      parseSrt('$value --> 99:59:59,999\nrejected').length,
      0,
      'invalid SRT start $value',
    );
    _equal(
      parseSrt('00:00:00,000 --> $value\nrejected').length,
      0,
      'invalid SRT end $value',
    );
  }
  for (final body in [
    '',
    'unstructured text',
    '5\n',
    '00:00:01,000 --> 00:00:01,000\nequal',
    '00:00:02,000 --> 00:00:01,000\nbackward',
    '00:00:00,000 --> 00:00:01,000\n   \t',
    'label\n00:00:00,000 --> 00:00:01,000\ninvalid identifier',
    '00:00:00,000 --> 00:00:01,0009\ntrailing digit',
  ]) {
    final empty = parseSrt(body);
    _equal(empty.length, 0, 'invalid block does not produce a zero cue');
    _immutable(empty);
  }
  final recovered = parseSrt(
    '00:99:00,000 --> 00:99:01,000\nbad\n\n'
    '00:00:05,000 --> 00:00:06,000\ngood',
  );
  _equal(recovered.single.text, 'good', 'invalid blocks are isolated');
}

void _webVttStructure() {
  final cues = parseWebVtt(
    '\uFEFFWEBVTT custom header\r\n'
    'Language: ja\r\n'
    '00:00.000 --> 00:59.000\r\nmetadata only\r\n\r\n'
    'NOTE explanation\n00:00.000 --> 00:30.000\nnot a cue\n\n'
    'STYLE\n00:00.000 --> 00:30.000\nnot a cue\n\n'
    'REGION\n00:00.000 --> 00:30.000\nnot a cue\n\n'
    'NOTEBOOK\n00:07.007 --> 00:09.009 align:start\n'
    '  <ruby>雲<rt>くも</rt></ruby> &lt; [風]\n'
    '  <v Aoi>そのまま  \n\n'
    'identifier C\n001:00:00.000 --> 001:00:01.000\nthird\n\n'
    '00:01.001 --> 00:02.002\nfirst\n\n'
    'id-tie\n00:07.007 --> 00:08.008\nsecond tie',
  );
  _equal(cues.length, 4, 'metadata and reserved blocks are skipped');
  _equal(cues[0].text, 'first', 'WebVTT start sorting');
  _equal(
    cues[1].text,
    '<ruby>雲<rt>くも</rt></ruby> &lt; [風]\n  <v Aoi>そのまま',
    'WebVTT payload is opaque',
  );
  _equal(cues[2].text, 'second tie', 'WebVTT ties preserve source order');
  _equal(cues[3].start, const Duration(hours: 1), '2+ hour digits');
  for (var i = 0; i < cues.length; i++) {
    _equal(cues[i].index, i, 'WebVTT returned indices');
  }
  _immutable(cues);
  _equal(
    parseWebVtt('00:00.000 --> 00:00.001\nno header').single.text,
    'no header',
    'headerless timing blocks',
  );
  _equal(
    parseWebVtt('NOTE\tcomment\n00:00.000 --> 00:01.000\nignored').length,
    0,
    'NOTE with tab starts a comment',
  );
  _equal(
    parseWebVtt('NOTES\n00:00.000 --> 00:01.000\nkept').length,
    1,
    'NOTE prefix alone does not start a comment',
  );
  _equal(
    parseWebVtt('000000:00:00.000 --> 000000:00:00.001\nzero').length,
    1,
    'leading hour zeros obey the numeric bound',
  );
  _equal(
    parseWebVtt('2562047787:59:59.998 --> 2562047787:59:59.999\nmaximum')
        .length,
    1,
    'supported maximum WebVTT hours do not overflow',
  );
}

void _webVttRejections() {
  final invalidTimes = [
    '1:00:00.000',
    '00:60.000',
    '60:00.000',
    '00:00:60.000',
    '00:60:00.000',
    '-00:00.000',
    '00:00,000',
    '00:00.00',
    '00:00.0000',
    '00:00.000x',
    '0:00.000',
    '00:0.000',
    '2562047788:00:00.000',
    '99999999999999999999999999:00:00.000',
  ];
  for (final value in invalidTimes) {
    _equal(
      parseWebVtt('$value --> 2562047787:59:59.999\nrejected').length,
      0,
      'invalid WebVTT start $value',
    );
    _equal(
      parseWebVtt('00:00.000 --> $value\nrejected').length,
      0,
      'invalid WebVTT end $value',
    );
  }
  for (final body in [
    '',
    'WEBVTT\n\n',
    'unknown\nmetadata',
    '00:01.000 --> 00:01.000\nequal',
    '00:02.000 --> 00:01.000\nbackward',
    'id\n00:00.000 --> 00:01.000\n  \t',
  ]) {
    final empty = parseWebVtt(body);
    _equal(empty.length, 0, 'bad WebVTT payload or range');
    _immutable(empty);
  }
}

SubtitleCue _cue(int index, int start, int end) => SubtitleCue(
  index: index,
  start: Duration(milliseconds: start),
  end: Duration(milliseconds: end),
  text: 'cue $index',
);

void _lookupBoundariesAndOverlaps() {
  final cues = [
    _cue(44, 1000, 10000),
    _cue(8, 2000, 2500),
    _cue(99, 2000, 3000),
    _cue(2, 5000, 6000),
    _cue(1, 12000, 13000),
  ];
  _equal(cueAt(cues, const Duration(milliseconds: 999)), null, 'before');
  _equal(cueAt(cues, const Duration(seconds: 1)), cues[0], 'inclusive start');
  _equal(cueAt(cues, const Duration(seconds: 2)), cues[2], 'last equal start');
  _equal(cueAt(cues, const Duration(seconds: 3)), cues[0], 'long cue resumes');
  _equal(
    cueAt(cues, const Duration(seconds: 6)),
    cues[0],
    'exclusive short end',
  );
  _equal(cueAt(cues, const Duration(seconds: 10)), null, 'exclusive long end');
  _equal(
    previousCue(cues, const Duration(seconds: 2)),
    cues[1],
    'active previous',
  );
  _equal(nextCue(cues, const Duration(seconds: 2)), cues[3], 'active next');
  _equal(
    previousCue(cues, const Duration(seconds: 3)),
    null,
    'resumed previous',
  );
  _equal(
    nextCue(cues, const Duration(seconds: 3)),
    cues[1],
    'resumed adjacency',
  );
  _equal(
    previousCue(cues, const Duration(seconds: 11)),
    cues[3],
    'gap previous',
  );
  _equal(nextCue(cues, const Duration(seconds: 11)), cues[4], 'gap upcoming');
  _equal(nextCue(cues, const Duration(seconds: 13)), null, 'after track');
  _equal(previousCue(cues, Duration.zero), null, 'before previous boundary');
  _equal(nextCue(cues, Duration.zero), cues[0], 'before upcoming');
  _equal(
    cueAt(cues, const Duration(seconds: 3), offset: const Duration(seconds: 1)),
    cues[2],
    'positive offset delays subtitles',
  );
  _equal(
    cueAt(
      cues,
      const Duration(seconds: 1),
      offset: const Duration(seconds: -1),
    ),
    cues[2],
    'negative offset advances subtitles',
  );
  for (final finder in [cueAt, previousCue, nextCue]) {
    _equal(finder([], Duration.zero), null, 'empty list');
  }
}

void _externalListChanges() {
  final cues = [_cue(0, 0, 1000)];
  _equal(cueAt(cues, const Duration(milliseconds: 500)), cues[0], 'plain list');
  cues[0] = _cue(1, 0, 400);
  _equal(
    cueAt(cues, const Duration(milliseconds: 500)),
    null,
    'replacement seen',
  );
  cues.add(_cue(2, 500, 900));
  _equal(
    cueAt(cues, const Duration(milliseconds: 500)),
    cues[1],
    'addition seen',
  );
}

void _arithmeticExtremes() {
  const minimum = Duration(microseconds: -0x8000000000000000);
  const maximum = Duration(microseconds: 0x7fffffffffffffff);
  final cues = [
    const SubtitleCue(index: 0, start: minimum, end: maximum, text: 'extreme'),
  ];
  _equal(
    cueAt(cues, minimum, offset: const Duration(microseconds: 1)),
    null,
    'subtraction below representable range',
  );
  _equal(
    nextCue(cues, minimum, offset: const Duration(microseconds: 1)),
    cues[0],
    'upcoming below representable range',
  );
  _equal(
    cueAt(cues, maximum, offset: const Duration(microseconds: -1)),
    null,
    'subtraction above representable range',
  );
  _equal(
    previousCue(cues, maximum, offset: const Duration(microseconds: -1)),
    cues[0],
    'previous above representable range',
  );
}

String _srtTime(int milliseconds) {
  final h = milliseconds ~/ 3600000;
  final m = milliseconds ~/ 60000 % 60;
  final s = milliseconds ~/ 1000 % 60;
  final ms = milliseconds % 1000;
  return '$h:${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')},${ms.toString().padLeft(3, '0')}';
}

void _generatedLookupAgreement() {
  final random = Random(1729);
  final source = StringBuffer();
  for (var i = 0; i < 450; i++) {
    final start = random.nextInt(10000);
    final end = start + 1 + random.nextInt(4000);
    source.writeln('${_srtTime(start)} --> ${_srtTime(end)}\nitem $i\n');
  }
  final indexed = parseSrt(source.toString());
  _equal(indexed.length, 450, 'generated cues all accepted');
  final plain = indexed.toList();
  for (var trial = 0; trial < 3000; trial++) {
    final position = Duration(microseconds: random.nextInt(16000000) - 1000000);
    final offset = Duration(microseconds: random.nextInt(2000000) - 1000000);
    final time = position - offset;
    var active = -1;
    var latest = -1;
    for (var i = 0; i < plain.length; i++) {
      if (plain[i].start <= time) {
        latest = i;
        if (time < plain[i].end) active = i;
      }
    }
    final before = active < 0 ? latest : active - 1;
    final after = (active < 0 ? latest : active) + 1;
    for (final track in [indexed, plain]) {
      _equal(
        cueAt(track, position, offset: offset),
        active < 0 ? null : plain[active],
        'generated containment',
      );
      _equal(
        previousCue(track, position, offset: offset),
        before < 0 ? null : plain[before],
        'generated previous',
      );
      _equal(
        nextCue(track, position, offset: offset),
        after >= plain.length ? null : plain[after],
        'generated next',
      );
    }
  }
}

void _largeParsedTrack() {
  final source = StringBuffer('00:00:00,000 --> 20:00:00,000\nlong\n\n');
  for (var i = 1; i <= 16000; i++) {
    source.writeln(
      '${_srtTime(i * 1000)} --> ${_srtTime(i * 1000 + 200)}\nshort $i\n',
    );
  }
  final cues = parseSrt(source.toString());
  _equal(cues.length, 16001, 'large parsed track');
  final watch = Stopwatch()..start();
  for (var i = 0; i < 100000; i++) {
    _equal(
      cueAt(cues, Duration(milliseconds: 20000000 + i)),
      cues[0],
      'long cue survives thousands of expired intervals',
    );
  }
  watch.stop();
  debugPrint(
    '100,000 indexed overlap lookups: ${watch.elapsedMilliseconds} ms.',
  );
  _equal(cueAt(cues, const Duration(hours: 21)), null, 'large-track final gap');
}
