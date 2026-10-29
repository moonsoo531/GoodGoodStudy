import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitles.dart';

void main() {
  final folder = Platform.environment['FURIGANA_SAMPLE_DIR'];
  final originalPath = Platform.environment['SAMPLE_SRT'];
  test(
    'manual sample preserves source text and all 54 timing intervals',
    () async {
      final directory = Directory(folder!);
      final original = parseSrt(await File(originalPath!).readAsString());
      final vtt = parseWebVtt(
        await File('${directory.path}/first3min.manual.ruby.vtt')
            .readAsString(),
      );
      final brackets = parseSrt(
        await File('${directory.path}/first3min.manual.brackets.srt')
            .readAsString(),
      );
      final review = jsonDecode(
        await File('${directory.path}/first3min.manual.review.json')
            .readAsString(),
      ) as Map<String, dynamic>;
      final reviewed = review['cues'] as List<dynamic>;
      expect(vtt, hasLength(54));
      expect(brackets, hasLength(54));
      var rubyCount = 0;
      for (var i = 0; i < vtt.length; i++) {
        final item = reviewed[i] as Map<String, dynamic>;
        expect(
          item['original'],
          original[i].text,
          reason: 'original cue ${i + 1}',
        );
        var normalized = original[i].text;
        for (final normalization
            in item['existingReadingNormalizations'] as List<dynamic>) {
          normalized = normalized.replaceAll(
            normalization['from'] as String,
            normalization['base'] as String,
          );
        }
        expect(
          plainSubtitleText(vtt[i].text),
          normalized,
          reason: 'base cue ${i + 1}',
        );
        expect(vtt[i].start, original[i].start);
        expect(vtt[i].end, original[i].end);
        expect(brackets[i].start, original[i].start);
        expect(brackets[i].end, original[i].end);
        rubyCount += parseRubyText(vtt[i].text)
            .where((segment) => segment.reading != null)
            .length;
      }
      expect(rubyCount, 94);
      for (final item in review['pendingReadings'] as List<dynamic>) {
        final cue = vtt[(item['cue'] as int) - 1];
        final term = item['term'] as String;
        expect(plainSubtitleText(cue.text), contains(term));
        expect(
          parseRubyText(cue.text).where(
            (segment) => segment.reading != null && segment.text.contains(term),
          ),
          isEmpty,
        );
      }
    },
    skip: folder == null || originalPath == null
        ? 'Set FURIGANA_SAMPLE_DIR and SAMPLE_SRT for the local manual sample.'
        : false,
  );
}
