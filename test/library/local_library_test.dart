import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';

void main() {
  test(
    'same-stem media and subtitle form one lesson without crossing folders',
    () {
      final lessons = groupLocalFiles([
        '/a/episode.mkv',
        '/a/episode.mp3',
        '/a/episode.srt',
        '/b/episode.mp3',
        '/b/notes.pdf',
        '/a/orphan.srt',
      ]);
      expect(lessons, hasLength(2));
      expect(lessons.first.videoPath, '/a/episode.mkv');
      expect(lessons.first.audioPath, '/a/episode.mp3');
      expect(lessons.first.subtitlePath, '/a/episode.srt');
      expect(lessons.last.subtitlePath, isNull);
    },
  );

  test(
    'duplicate selection does not duplicate lessons and round-trip is local',
    () {
      final lesson = groupLocalFiles(['/a/Japanese.MP3', '/a/Japanese.MP3'])
          .single;
      expect(lesson.title, 'Japanese');
      expect(
        LocalLesson.fromJson(lesson.toJson()).primaryPath,
        lesson.primaryPath,
      );
    },
  );
  test('WebVTT pairs with same-stem local media and SRT stays the default when both exist', () {
    final vtt = groupLocalFiles(['/a/lesson.mp3', '/a/lesson.vtt']).single;
    expect(vtt.subtitlePath, '/a/lesson.vtt');
    final both = groupLocalFiles([
      '/a/lesson.vtt',
      '/a/lesson.srt',
      '/a/lesson.mp3',
    ]).single;
    expect(both.subtitlePath, '/a/lesson.srt');
  });

  test(
    'numbered lessons sort naturally and unsupported bare names are ignored',
    () {
      final lessons = groupLocalFiles([
        '/a/第10课.mp4',
        '/a/第2课.mp4',
        '/a/第1课.mp4',
        '/a/mp4',
        '/a/notes.pdf',
      ]);
      expect(lessons.map((lesson) => lesson.title), ['第1课', '第2课', '第10课']);
      expect(extensionOf('/a/no-extension'), isEmpty);
      expect(extensionOf('/a/lesson.MP4'), 'mp4');
    },
  );

  test('all media formats supported by playback can enter the library', () {
    final paths = [
      for (final extension in [...audioExtensions, ...videoExtensions])
        '/a/$extension.$extension',
    ];
    expect(groupLocalFiles(paths), hasLength(paths.length));
    expect(audioExtensions, containsAll(['wma', 'alac']));
    expect(videoExtensions, containsAll(['wmv', 'mpg', 'mpeg', 'm2ts']));
  });

  test(
    'playlist keeps queue order and fills companions without duplicates',
    () {
      final existing = groupLocalFiles(['/a/第2课.mp3', '/a/第1课.mp4']);
      final incoming = groupLocalFiles([
        '/a/第2课.mp4',
        '/a/第2课.srt',
        '/a/第3课.mp4',
        '/a/第1课.mp4',
      ]);
      final merged = mergePlaylist(existing, incoming);
      expect(merged.map((lesson) => lesson.title), ['第1课', '第2课', '第3课']);
      final updated = merged[1];
      expect(updated.audioPath, '/a/第2课.mp3');
      expect(updated.videoPath, '/a/第2课.mp4');
      expect(updated.subtitlePath, '/a/第2课.srt');
      expect(updated.identity, existing[1].identity);
      expect(mergePlaylist(merged, incoming), hasLength(3));
    },
  );

  test('playlist retains manual order and treats matching titles in separate folders independently', () {
    const existing = [
      LocalLesson(title: '第10课', videoPath: '/a/第10课.mp4'),
      LocalLesson(title: '第2课', videoPath: '/a/第2课.mp4'),
    ];
    final incoming = groupLocalFiles([
      '/a/第10课.mp4',
      '/b/第2课.mp4',
      '/a/第1课.mp4',
    ]);
    final merged = mergePlaylist(existing, incoming);
    expect(merged.map((lesson) => lesson.primaryPath), [
      '/a/第10课.mp4',
      '/a/第2课.mp4',
      '/a/第1课.mp4',
      '/b/第2课.mp4',
    ]);
  });

  test('identity normalizes equivalent local paths', () {
    const first = LocalLesson(title: 'lesson', audioPath: '/a/lesson.mp3');
    const second = LocalLesson(
      title: 'lesson',
      videoPath: '/a/../a/lesson.mp4',
    );
    expect(first.identity, second.identity);
    expect(mergePlaylist([first], [second]), hasLength(1));
  });

  test('directly dropped video replaces its old variant in the same queue position', () {
    const existing = [
      LocalLesson(title: 'first', videoPath: '/a/first.mp4'),
      LocalLesson(
        title: 'lesson',
        videoPath: '/a/lesson.mkv',
        audioPath: '/a/lesson.mp3',
        subtitlePath: '/a/lesson.srt',
      ),
      LocalLesson(title: 'last', videoPath: '/a/last.mp4'),
    ];
    final incoming = groupLocalFiles(['/a/lesson.mp4']);
    final merged = mergePlaylist(
      existing,
      incoming,
      preferredMediaPath: '/a/lesson.mp4',
    );
    expect(merged.map((lesson) => lesson.title), ['first', 'lesson', 'last']);
    expect(merged[1].videoPath, '/a/lesson.mp4');
    expect(merged[1].audioPath, '/a/lesson.mp3');
    expect(merged[1].subtitlePath, '/a/lesson.srt');
    expect(merged[1].identity, existing[1].identity);
    expect(mergePlaylist(existing, incoming)[1].videoPath, '/a/lesson.mkv');
  });

  test(
    'preferred video wins when grouping multiple variants from one batch',
    () {
      final incoming = groupLocalFiles([
        '/a/lesson.mp4',
        '/a/lesson.mkv',
        '/a/lesson.mp3',
        '/a/lesson.vtt',
      ]);
      expect(incoming.single.videoPath, '/a/lesson.mkv');
      final merged = mergePlaylist(
        const [],
        incoming,
        preferredMediaPath: '/a/lesson.mp4',
      );
      expect(merged, hasLength(1));
      expect(merged.single.videoPath, '/a/lesson.mp4');
      expect(merged.single.audioPath, '/a/lesson.mp3');
      expect(merged.single.subtitlePath, '/a/lesson.vtt');
    },
  );

  test('preferred audio selects its exact variant and preserves video and subtitles', () {
    final existing = groupLocalFiles([
      '/a/lesson.mkv',
      '/a/lesson.m4a',
      '/a/lesson.srt',
    ]);
    final incoming = groupLocalFiles([
      '/a/lesson.mp3',
      '/a/lesson.m4a',
      '/a/lesson.mp4',
    ]);
    final merged = mergePlaylist(
      existing,
      incoming,
      preferredMediaPath: '/a/lesson.mp3',
    );
    expect(merged, hasLength(1));
    expect(merged.single.audioPath, '/a/lesson.mp3');
    expect(merged.single.videoPath, '/a/lesson.mkv');
    expect(merged.single.subtitlePath, '/a/lesson.srt');
  });

  test('preferred media outside incoming lesson identities is ignored', () {
    final existing = groupLocalFiles(['/a/lesson.mkv']);
    final incoming = groupLocalFiles(['/b/new.mp4']);
    final merged = mergePlaylist(
      existing,
      incoming,
      preferredMediaPath: '/a/lesson.mp4',
    );
    expect(merged.map((lesson) => lesson.primaryPath), [
      '/a/lesson.mkv',
      '/b/new.mp4',
    ]);
    expect(
      mergePlaylist(
        existing,
        incoming,
        preferredMediaPath: '/missing/lesson.mp4',
      ).map((lesson) => lesson.primaryPath),
      merged.map((lesson) => lesson.primaryPath),
    );
  });

  test('subtitle or unsupported preference never replaces a media field', () {
    final lessons = groupLocalFiles([
      '/a/lesson.mkv',
      '/a/lesson.mp3',
      '/a/lesson.srt',
    ]);
    for (final path in ['/a/lesson.vtt', '/a/lesson.pdf', '/a/lesson']) {
      final merged = mergePlaylist(const [], lessons, preferredMediaPath: path);
      expect(merged.single.toJson(), lessons.single.toJson());
    }
  });
}
