import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/media_history.dart';

void main() {
  const a = LocalLesson(title: 'A', videoPath: '/lessons/A.mp4');
  const b = LocalLesson(title: 'B', videoPath: '/lessons/B.mp4');

  test('A-B-A retains independent positions across persistence', () {
    final history = MediaHistory();
    history.record(
      a,
      position: const Duration(minutes: 4),
      duration: const Duration(minutes: 10),
    );
    history.record(
      b,
      position: const Duration(minutes: 2),
      duration: const Duration(minutes: 20),
    );
    final state = jsonDecode(
      jsonEncode({'mediaHistory': history.toJson()}),
    ) as Map<String, dynamic>;
    final restored = MediaHistory.fromJson(state);
    expect(restored.resumePosition(a), const Duration(minutes: 4));
    expect(restored.resumePosition(b), const Duration(minutes: 2));
    expect(restored.getForLesson(a)!.progress, 0.4);
    expect(restored.getForLesson(b)!.duration, const Duration(minutes: 20));
  });

  test(
    'legacy current progress and subtitle settings migrate by lesson identity',
    () {
      final history = MediaHistory.fromJson({
        'current': '/lessons/A.mp4',
        'positionMs': 20000,
        'subtitlePath': '/subtitles/a.vtt',
        'offsetMs': -200,
      });
      expect(history.resumePosition(a), const Duration(seconds: 20));
      expect(history.getForLesson(a)!.subtitlePath, '/subtitles/a.vtt');
      expect(
        history.getForLesson(a)!.offset,
        const Duration(milliseconds: -200),
      );
      expect(history.getForLesson(a)!.hasDuration, isFalse);
      expect(history.resumePosition(b), Duration.zero);
    },
  );

  test('new history wins over a stale legacy current position', () {
    final history = MediaHistory()
      ..record(a, position: const Duration(seconds: 25));
    final restored = MediaHistory.fromJson({
      'current': a.primaryPath,
      'positionMs': 1000,
      'mediaHistory': history.toJson(),
    });
    expect(restored.resumePosition(a), const Duration(seconds: 25));
    expect(restored.entries, hasLength(1));
  });

  test(
    'audio/video companions share progress but different directories do not',
    () {
      const audioA = LocalLesson(title: 'A', audioPath: '/lessons/A.mp3');
      const elsewhere = LocalLesson(title: 'A', videoPath: '/other/A.mp4');
      final history = MediaHistory()
        ..record(audioA, position: const Duration(seconds: 30));
      expect(history.resumePosition(a), const Duration(seconds: 30));
      expect(history.resumePosition(elsewhere), Duration.zero);
    },
  );

  test('completed and exact-end media restart while explicit false clears completion', () {
    final history = MediaHistory();
    history.record(
      a,
      position: const Duration(seconds: 100),
      duration: const Duration(seconds: 100),
      completed: true,
    );
    expect(history.getForLesson(a)!.completed, isTrue);
    expect(history.resumePosition(a), Duration.zero);
    history.record(a, position: const Duration(seconds: 25), completed: false);
    expect(history.getForLesson(a)!.completed, isFalse);
    expect(history.resumePosition(a), const Duration(seconds: 25));
    history.record(a, position: const Duration(seconds: 100), completed: false);
    expect(history.getForLesson(a)!.completed, isFalse);
    expect(history.resumePosition(a), Duration.zero);
  });

  test('near-end inference is bounded for short videos and long videos', () {
    final history = MediaHistory();
    history.record(
      a,
      position: const Duration(seconds: 7),
      duration: const Duration(seconds: 8),
    );
    expect(history.getForLesson(a)!.completed, isFalse);
    history.record(a, position: const Duration(milliseconds: 7930));
    expect(history.getForLesson(a)!.completed, isTrue);
    history.record(
      b,
      position: const Duration(minutes: 59, seconds: 57),
      duration: const Duration(hours: 1),
    );
    expect(history.getForLesson(b)!.completed, isFalse);
    history.record(b, position: const Duration(minutes: 59, seconds: 58));
    expect(history.getForLesson(b)!.completed, isTrue);
    history.record(
      b,
      position: const Duration(minutes: 59, seconds: 58),
      completed: false,
    );
    expect(history.getForLesson(b)!.completed, isFalse);
  });

  test('unknown opening duration preserves measured duration and track preferences', () {
    final history = MediaHistory();
    history.record(
      a,
      position: const Duration(seconds: 20),
      duration: const Duration(seconds: 80),
      subtitlePath: '/subs/a.srt',
      offset: const Duration(milliseconds: 100),
      audioTrackId: '2',
      subtitleTrackId: '3',
      subtitleSource: 'embedded',
    );
    history.record(
      a,
      position: const Duration(seconds: 30),
      duration: Duration.zero,
    );
    final entry = history.getForLesson(a)!;
    expect(entry.duration, const Duration(seconds: 80));
    expect(entry.audioTrackId, '2');
    expect(entry.subtitleTrackId, '3');
    expect(entry.subtitleSource, 'embedded');
    expect(entry.subtitlePath, '/subs/a.srt');
    expect(entry.offset, const Duration(milliseconds: 100));
    final restored = MediaHistory.fromJson(
      jsonDecode(jsonEncode({'mediaHistory': history.toJson()}))
          as Map<String, dynamic>,
    );
    expect(restored.getForLesson(a)!.toJson(), entry.toJson());
    history.record(
      a,
      position: const Duration(seconds: 30),
      subtitleSource: 'off',
    );
    expect(history.getForLesson(a)!.subtitleSource, 'off');
  });

  test(
    'progress is bounded and positions are normalized to a known duration',
    () {
      final history = MediaHistory();
      history.record(a, position: const Duration(seconds: -3));
      expect(history.resumePosition(a), Duration.zero);
      history.record(
        a,
        position: const Duration(seconds: 200),
        duration: const Duration(seconds: 100),
      );
      expect(history.getForLesson(a)!.position, const Duration(seconds: 100));
      expect(history.getForLesson(a)!.progress, 1);
    },
  );

  test(
    'malformed optional history is rejected rather than silently discarded',
    () {
      for (final value in [
        [],
        {'/a': 'wrong'},
        {
          '/a': {'positionMs': -1},
        },
        {
          '/a': {'durationMs': 'long'},
        },
        {
          '/a': {'completed': 'yes'},
        },
        {
          '/a': {'subtitleSource': 'unknown'},
        },
      ]) {
        expect(
          () => MediaHistory.fromJson({'mediaHistory': value}),
          throwsFormatException,
        );
      }
    },
  );

  test('future unrelated player fields do not affect history migration', () {
    final history = MediaHistory.fromJson({
      'futurePreference': {'x': true},
    });
    expect(history.entries, isEmpty);
    expect(history.resumePosition(a), Duration.zero);
    expect(MediaHistory.fromJson(null).entries, isEmpty);
  });
}
