import 'package:flutter_test/flutter_test.dart';

import 'package:offline_player/subtitles/subtitles.dart';

Duration _ms(int value) => Duration(milliseconds: value);

const _input =
    '1\n00:00:01,000 --> 00:00:02,000\nA\n\n'
    '2\n00:00:03,000 --> 00:00:04,000\nB\n\n'
    '3\n00:00:04,000 --> 00:00:05,000\nC\n';

void main() {
  group('cueAt', () {
    test('uses inclusive start and exclusive end with gaps', () {
      final cues = parseSrt(_input);

      expect(cueAt(cues, _ms(999)), isNull);
      expect(cueAt(cues, _ms(1000)), cues[0]);
      expect(cueAt(cues, _ms(1999)), cues[0]);
      expect(cueAt(cues, _ms(2000)), isNull);
      expect(cueAt(cues, _ms(2999)), isNull);
      expect(cueAt(cues, _ms(3000)), cues[1]);
      expect(cueAt(cues, _ms(4000)), cues[2]);
      expect(cueAt(cues, _ms(5000)), isNull);
    });

    test('positive offsets delay without changing stored cue times', () {
      final cues = parseSrt(_input);

      expect(cueAt(cues, _ms(1000), offset: _ms(500)), isNull);
      expect(cueAt(cues, _ms(1500), offset: _ms(500)), cues[0]);
      expect(cueAt(cues, _ms(2499), offset: _ms(500)), cues[0]);
      expect(cueAt(cues, _ms(2500), offset: _ms(500)), isNull);
      expect(cues.first.start, _ms(1000));
      expect(cues.first.end, _ms(2000));
    });

    test('negative offsets advance subtitles and allow early first cues', () {
      final cues = parseSrt(_input);

      expect(cueAt(cues, Duration.zero, offset: _ms(-1500)), cues[0]);
      expect(cueAt(cues, _ms(499), offset: _ms(-1500)), cues[0]);
      expect(cueAt(cues, _ms(500), offset: _ms(-1500)), isNull);
    });

    test('latest containing cue wins and earlier long cue can resume', () {
      final cues = parseSrt(
        '1\n00:00:01,000 --> 00:00:10,000\nLong\n\n'
        '2\n00:00:02,000 --> 00:00:03,000\nShort\n\n'
        '3\n00:00:02,000 --> 00:00:02,500\nTie\n',
      );

      expect(cueAt(cues, _ms(2000)), cues[2]);
      expect(cueAt(cues, _ms(2500)), cues[1]);
      expect(cueAt(cues, _ms(3000)), cues[0]);
      expect(cueAt(cues, _ms(9999)), cues[0]);
      expect(cueAt(cues, _ms(10000)), isNull);
      expect(cueAt(List.of(cues), _ms(3000)), cues[0]);
    });

    test('empty tracks return null', () {
      expect(cueAt(const [], Duration.zero), isNull);
      expect(previousCue(const [], Duration.zero), isNull);
      expect(nextCue(const [], Duration.zero), isNull);
    });
  });

  group('navigation', () {
    test('returns neighboring cues while active', () {
      final cues = parseSrt(_input);

      expect(previousCue(cues, _ms(1500)), isNull);
      expect(nextCue(cues, _ms(1500)), cues[1]);
      expect(previousCue(cues, _ms(3500)), cues[0]);
      expect(nextCue(cues, _ms(3500)), cues[2]);
      expect(previousCue(cues, _ms(4500)), cues[1]);
      expect(nextCue(cues, _ms(4500)), isNull);
    });

    test('gaps and track boundaries select nearest appropriate cues', () {
      final cues = parseSrt(_input);

      expect(previousCue(cues, _ms(0)), isNull);
      expect(nextCue(cues, _ms(0)), cues[0]);
      expect(previousCue(cues, _ms(2500)), cues[0]);
      expect(nextCue(cues, _ms(2500)), cues[1]);
      expect(previousCue(cues, _ms(5000)), cues[2]);
      expect(nextCue(cues, _ms(5000)), isNull);
    });

    test('navigation uses the same positive and negative offset contract', () {
      final cues = parseSrt(_input);

      expect(previousCue(cues, _ms(4000), offset: _ms(500)), cues[0]);
      expect(nextCue(cues, _ms(4000), offset: _ms(500)), cues[2]);
      expect(previousCue(cues, _ms(3000), offset: _ms(-500)), cues[0]);
      expect(nextCue(cues, _ms(3000), offset: _ms(-500)), cues[2]);
    });
  });

  test('large track lookups agree with a simple containment reference', () {
    final cues = List.generate(
      5000,
      (index) => SubtitleCue(
        index: index,
        start: _ms(index * 2000),
        end: _ms(index * 2000 + 1500),
        text: 'Synthetic cue $index',
      ),
    );

    for (final index in [0, 1, 42, 1023, 2499, 4998, 4999]) {
      for (final delta in [-1, 0, 1499, 1500, 1999]) {
        final position = _ms(index * 2000 + delta);
        final expected = cues.where(
          (cue) => cue.start <= position && position < cue.end,
        );

        expect(
          cueAt(cues, position),
          expected.isEmpty ? null : expected.last,
          reason: 'cue $index, delta $delta ms',
        );
      }
    }
  });

  test(
    'parsed overlapping track agrees with containment across its timeline',
    () {
      final input = StringBuffer();
      for (var i = 0; i < 100; i++) {
        final startSeconds = i;
        final endSeconds = i + (i % 11) + 1;
        input
          ..writeln(i + 1)
          ..writeln('${_timestamp(startSeconds)} --> ${_timestamp(endSeconds)}')
          ..writeln('Synthetic overlapping cue $i')
          ..writeln();
      }
      final cues = parseSrt(input.toString());
      expect(cues, hasLength(100));

      for (var timeMs = -500; timeMs <= 112000; timeMs += 250) {
        final position = _ms(timeMs);
        final expected = cues.where(
          (cue) => cue.start <= position && position < cue.end,
        );
        expect(
          cueAt(cues, position),
          expected.isEmpty ? null : expected.last,
          reason: '$timeMs ms',
        );
      }
    },
  );
}

String _timestamp(int seconds) =>
    '00:${(seconds ~/ 60).toString().padLeft(2, '0')}:'
    '${(seconds % 60).toString().padLeft(2, '0')},000';
