import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/playlist_import.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('playlist-scan-control-');
  });

  tearDown(() async => temporary.delete(recursive: true));

  Future<String> file(String relative) async {
    final fixture = File('${temporary.path}/$relative');
    await fixture.parent.create(recursive: true);
    await fixture.writeAsString('unchanged media fixture');
    return fixture.path;
  }

  test(
    'a pre-cancelled scan does not visit supplied folders or files',
    () async {
      final video = await file('folder/lesson.mp4');
      final cancellation = MediaScanCancellation()..cancel();
      final progress = <MediaScanProgress>[];
      final scan = await scanLocalMedia(
        [File(video).parent.path, video],
        cancellation: cancellation,
        onProgress: progress.add,
      );
      expect(scan.cancelled, isTrue);
      expect(scan.lessons, isEmpty);
      expect(scan.directMediaPath, isNull);
      expect(scan.unreadablePaths, isEmpty);
      expect(progress, isNotEmpty);
      expect(progress.last.files, 0);
      expect(progress.last.media, 0);
      expect(progress.last.directories, 0);
    },
  );

  test(
    'cancelling at progress stops discovery and skips remaining roots',
    () async {
      for (var index = 0; index < 100; index++) {
        await file('first/lesson-$index.mp4');
      }
      await file('second/later.mp4');
      final directLater = await file('direct-later.mp4');
      final cancellation = MediaScanCancellation();
      final reports = <MediaScanProgress>[];
      int? mediaAtCancellation;
      final scan = await scanLocalMedia(
        ['${temporary.path}/first', '${temporary.path}/second', directLater],
        cancellation: cancellation,
        onProgress: (progress) {
          reports.add(progress);
          if (progress.media >= 24 && !cancellation.cancelled) {
            mediaAtCancellation = progress.media;
            cancellation.cancel();
          }
        },
      );
      expect(mediaAtCancellation, isNotNull);
      expect(mediaAtCancellation, lessThan(100));
      expect(scan.cancelled, isTrue);
      expect(scan.lessons, hasLength(mediaAtCancellation!));
      expect(reports.last.media, mediaAtCancellation);
      expect(reports.last.directories, 1);
      expect(
        scan.lessons.every(
          (lesson) =>
              File(lesson.primaryPath).parent.path == '${temporary.path}/first',
        ),
        isTrue,
      );
      expect(scan.directMediaPath, isNull);
      expect(scan.unreadablePaths, isEmpty);
    },
  );

  test(
    'cancelling when a folder is announced prevents its descendants',
    () async {
      await file('nested/deeper/lesson.mp4');
      final cancellation = MediaScanCancellation();
      final reports = <MediaScanProgress>[];
      final scan = await scanLocalMedia(
        [temporary.path],
        cancellation: cancellation,
        onProgress: (progress) {
          reports.add(progress);
          if (progress.directories == 1) cancellation.cancel();
        },
      );
      expect(scan.cancelled, isTrue);
      expect(scan.lessons, isEmpty);
      expect(reports.last.directories, 1);
      expect(reports.last.files, 0);
      expect(reports.last.media, 0);
    },
  );

  test(
    'flat folder progress counts inspected files and unique media files',
    () async {
      await file('lesson.mp4');
      await file('lesson.mp3');
      await file('lesson.srt');
      await file('second.wav');
      await file('orphan.vtt');
      await file('notes.pdf');
      await file('.hidden.mp4');
      final reports = <MediaScanProgress>[];
      final scan = await scanLocalMedia([
        temporary.path,
      ], onProgress: reports.add);
      expect(scan.cancelled, isFalse);
      expect(scan.lessons, hasLength(2));
      expect(reports.last.files, 6);
      expect(reports.last.media, 3);
      expect(reports.last.directories, 1);
      for (var index = 1; index < reports.length; index++) {
        expect(
          reports[index].files,
          greaterThanOrEqualTo(reports[index - 1].files),
        );
        expect(
          reports[index].media,
          greaterThanOrEqualTo(reports[index - 1].media),
        );
        expect(
          reports[index].directories,
          greaterThanOrEqualTo(reports[index - 1].directories),
        );
      }
    },
  );

  test(
    'authorized parent scan pairs only same-stem direct companions',
    () async {
      final video = await file('lesson.MP4');
      final audio = await file('lesson.mp3');
      final subtitle = await file('lesson.srt');
      await file('unrelated.mp4');
      await file('unrelated.srt');
      await file('nested/lesson.vtt');
      final progress = <MediaScanProgress>[];
      final scan = await scanLocalMedia(
        [video],
        includeCompanions: true,
        onProgress: progress.add,
      );
      expect(scan.cancelled, isFalse);
      expect(scan.directMediaPath, video);
      expect(scan.containsDirectories, isFalse);
      expect(scan.foldersOnly, isFalse);
      expect(scan.lessons, hasLength(1));
      expect(scan.lessons.single.videoPath, video);
      expect(scan.lessons.single.audioPath, audio);
      expect(scan.lessons.single.subtitlePath, subtitle);
      expect(progress.last.media, 2);
      expect(scan.unreadablePaths, isEmpty);
      expect(await File(video).readAsString(), 'unchanged media fixture');
      expect(await File(subtitle).readAsString(), 'unchanged media fixture');
    },
  );

  test(
    'multiple direct selections do not mix companions or duplicate media',
    () async {
      final first = await file('first.mp4');
      final second = await file('second.mp4');
      final firstSubtitle = await file('first.srt');
      final secondSubtitle = await file('second.vtt');
      final progress = <MediaScanProgress>[];
      final scan = await scanLocalMedia(
        [second, first, second],
        includeCompanions: true,
        onProgress: progress.add,
      );
      expect(scan.directMediaPath, second);
      expect(scan.lessons.map((lesson) => lesson.title), ['first', 'second']);
      expect(scan.lessons.first.subtitlePath, firstSubtitle);
      expect(scan.lessons.last.subtitlePath, secondSubtitle);
      expect(progress.last.media, 2);
    },
  );

  test('companion discovery ignores a same-stem symbolic link', () async {
    final video = await file('lesson.mp4');
    final otherSubtitle = await file('other.vtt');
    await Link('${temporary.path}/lesson.vtt').create(otherSubtitle);
    final scan = await scanLocalMedia([video], includeCompanions: true);
    expect(scan.lessons.single.videoPath, video);
    expect(scan.lessons.single.subtitlePath, isNull);
    expect(scan.cancelled, isFalse);
  });

  test('omitting new arguments preserves direct-file and explicit-subtitle behavior', () async {
    final video = await file('lesson.mp4');
    await file('lesson.mp3');
    final subtitle = await file('lesson.srt');
    final directOnly = await scanLocalMedia([video]);
    expect(directOnly.lessons.single.videoPath, video);
    expect(directOnly.lessons.single.audioPath, isNull);
    expect(directOnly.lessons.single.subtitlePath, isNull);
    expect(directOnly.cancelled, isFalse);
    final explicitlyPaired = await scanLocalMedia([video, subtitle]);
    expect(explicitlyPaired.lessons.single.subtitlePath, subtitle);
    expect(explicitlyPaired.directMediaPath, video);
  });
}
