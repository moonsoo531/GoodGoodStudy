import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitle_visibility.dart';

void main() {
  test('new preferences show both regions by default', () {
    final value = SubtitleVisibility.fromJson({});
    expect(value.video, isTrue);
    expect(value.list, isTrue);
  });

  test('legacy shared preference migrates without changing its meaning', () {
    for (final visible in [false, true]) {
      final value = SubtitleVisibility.fromJson({'showSubtitles': visible});
      expect(value.video, visible);
      expect(value.list, visible);
    }
  });

  test(
    'new keys override legacy independently and ignore malformed values',
    () {
      final value = SubtitleVisibility.fromJson({
        'showSubtitles': false,
        'showVideoSubtitles': true,
        'showListSubtitles': 'invalid',
      });
      expect(value.video, isTrue);
      expect(value.list, isFalse);
      final malformed = SubtitleVisibility.fromJson({'showSubtitles': 'false'});
      expect(malformed.video, isTrue);
      expect(malformed.list, isTrue);
    },
  );

  test('all four combinations survive saving and restoring', () {
    for (final video in [false, true]) {
      for (final list in [false, true]) {
        final value = SubtitleVisibility(video: video, list: list);
        final restored = SubtitleVisibility.fromJson(
          jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>,
        );
        expect(restored.video, video);
        expect(restored.list, list);
        expect(value.toJson(), isNot(contains('showSubtitles')));
      }
    }
  });
}
