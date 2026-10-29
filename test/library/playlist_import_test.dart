import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/playlist_import.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('playlist-import-test-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<String> file(String relativePath) async {
    final result = File('${temporary.path}/$relativePath');
    await result.parent.create(recursive: true);
    await result.writeAsString('fixture');
    return result.path;
  }

  test(
    'folder drop includes nested media and pairs same-stem companions',
    () async {
      final lesson10 = await file('第10课.MP4');
      final lesson2 = await file('nested/第2课.mp4');
      final audio2 = await file('nested/第2课.mp3');
      final subtitle2 = await file('nested/第2课.vtt');
      await file('notes.pdf');
      await file('orphan.srt');
      final scan = await scanLocalMedia([temporary.path]);
      expect(scan.lessons.map((lesson) => lesson.primaryPath), [
        lesson2,
        lesson10,
      ]);
      expect(scan.lessons.first.audioPath, audio2);
      expect(scan.lessons.first.subtitlePath, subtitle2);
      expect(scan.directMediaPath, isNull);
      expect(scan.foldersOnly, isTrue);
      expect(scan.unreadablePaths, isEmpty);
    },
  );

  test(
    'recursive scans skip hidden folders, hidden files, and symbolic links',
    () async {
      final visible = await file('visible.mp4');
      await file('.hidden/secret.mp4');
      await file('nested/.hidden.mp4');
      await file('hidden-target/hidden.mp4');
      await Link('${temporary.path}/nested/loop').create(temporary.path);
      await Link('${temporary.path}/linked.mp4').create(visible);
      final scan = await scanLocalMedia([
        '${temporary.path}/nested',
        visible,
        '${temporary.path}/linked.mp4',
        '${temporary.path}/.hidden',
      ]);
      // An explicitly chosen hidden root is allowed, but recursion never enters it.
      expect(scan.lessons.map((lesson) => lesson.title), ['secret', 'visible']);
      final fullScan = await scanLocalMedia([temporary.path]);
      expect(fullScan.lessons.map((lesson) => lesson.title), [
        'hidden',
        'visible',
      ]);
      expect(
        fullScan.lessons.where(
          (lesson) => lesson.primaryPath.endsWith('linked.mp4'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'direct media choice retains drop order independently of list sorting',
    () async {
      final second = await file('第2课.mp4');
      final tenth = await file('第10课.mp4');
      final scan = await scanLocalMedia([tenth, second, tenth]);
      expect(scan.directMediaPath, tenth);
      expect(scan.lessons.map((lesson) => lesson.primaryPath), [second, tenth]);
      expect(scan.containsDirectories, isFalse);
      expect(scan.foldersOnly, isFalse);
    },
  );

  test('mixed file and folder drop chooses directly dropped media', () async {
    await file('folder/第1课.mp4');
    final direct = await file('第10课.mp4');
    final scan = await scanLocalMedia(['${temporary.path}/folder', direct]);
    expect(scan.containsDirectories, isTrue);
    expect(scan.foldersOnly, isFalse);
    expect(scan.directMediaPath, direct);
    expect(scan.lessons, hasLength(2));
  });

  test('overlapping folder and file drops produce a single lesson', () async {
    final video = await file('nested/lesson.mp4');
    final scan = await scanLocalMedia([
      temporary.path,
      '${temporary.path}/nested',
      video,
      temporary.path,
    ]);
    expect(scan.lessons, hasLength(1));
    expect(scan.directMediaPath, video);
  });

  test(
    'missing items do not prevent readable media from being imported',
    () async {
      final video = await file('lesson.mp4');
      final missing = '${temporary.path}/missing';
      final scan = await scanLocalMedia([missing, video]);
      expect(scan.lessons.single.primaryPath, video);
      expect(scan.unreadablePaths, [missing]);
    },
  );

  test(
    'subtitle-only and unsupported folders never create playlist entries',
    () async {
      await file('lesson.vtt');
      await file('notes.pdf');
      await file('mp4');
      final scan = await scanLocalMedia([temporary.path]);
      expect(scan.lessons, isEmpty);
      expect(scan.foldersOnly, isTrue);
    },
  );

  test(
    'imported companions merge into their previous queue position',
    () async {
      final audio = await file('lesson.mp3');
      final video = await file('lesson.mp4');
      final subtitle = await file('lesson.srt');
      final initial = [LocalLesson(title: 'lesson', audioPath: audio)];
      final scan = await scanLocalMedia([temporary.path]);
      final merged = mergePlaylist(initial, scan.lessons);
      expect(merged, hasLength(1));
      expect(merged.single.audioPath, audio);
      expect(merged.single.videoPath, video);
      expect(merged.single.subtitlePath, subtitle);
      expect(merged.single.identity, initial.single.identity);
    },
  );

  test(
    'direct choice survives same-stem variants discovered in a folder',
    () async {
      final video = await file('lesson.mp4');
      final otherVideo = await file('lesson.mkv');
      final audio = await file('lesson.mp3');
      final scan = await scanLocalMedia([temporary.path, video]);
      expect(scan.directMediaPath, video);
      expect(scan.lessons.single.videoPath, otherVideo);
      final merged = mergePlaylist(
        const [],
        scan.lessons,
        preferredMediaPath: scan.directMediaPath,
      );
      expect(merged.single.videoPath, video);
      expect(merged.single.audioPath, audio);
    },
  );
}
