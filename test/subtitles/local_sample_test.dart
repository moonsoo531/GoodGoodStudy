import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  final samplePath = Platform.environment['SAMPLE_SRT'];

  test(
    'local sample keeps all 704 cues with navigation and offset alignment',
    () {
      final cues = parseSrt(File(samplePath!).readAsStringSync());

      expect(cues, hasLength(704));
      expect(cues.first.start, const Duration(milliseconds: 16750));
      expect(cues.last.end, const Duration(milliseconds: 2639970));
      for (var index = 0; index < cues.length; index++) {
        final cue = cues[index];
        expect(cue.index, index);
        expect(cue.text, isNotEmpty);
        expect(cue.end > cue.start, isTrue);
        expect(cueAt(cues, cue.start), cue);
        expect(
          cueAt(
            cues,
            cue.start + const Duration(milliseconds: 750),
            offset: const Duration(milliseconds: 750),
          ),
          cue,
        );
        if (index > 0) {
          expect(cue.start >= cues[index - 1].end, isTrue);
          expect(previousCue(cues, cue.start), cues[index - 1]);
        }
        if (index < cues.length - 1) {
          expect(nextCue(cues, cue.start), cues[index + 1]);
        }
      }
    },
    skip: samplePath == null ? 'Set SAMPLE_SRT to a local sample path.' : false,
  );
}
