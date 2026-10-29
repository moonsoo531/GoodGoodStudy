import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/phone/phone_media_store.dart';

void main() {
  late Directory temporary;
  late PhoneMediaStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phone-media-store-');
    store = PhoneMediaStore(
      documents: await Directory('${temporary.path}/documents').create(),
    );
  });
  tearDown(() async => temporary.delete(recursive: true));

  test(
    'import copies audio and paired subtitles into persistent relative paths',
    () async {
      final source = await Directory('${temporary.path}/source').create();
      final audio = await File('${source.path}/lesson.mp3')
          .writeAsBytes([1, 2, 3]);
      final subtitle = await File('${source.path}/lesson.vtt')
          .writeAsString('WEBVTT\n');
      final copied = await store.copySelected([audio.path, subtitle.path]);
      final lessons = await store.scan();
      expect(lessons, hasLength(1));
      expect(lessons.single.relativeAudio.startsWith('/'), isFalse);
      expect(copied, contains(lessons.single.relativeSubtitle));
      expect(
        await File(await store.absolutePath(lessons.single.relativeAudio))
            .readAsBytes(),
        [1, 2, 3],
      );
      await File(await store.absolutePath(lessons.single.relativeAudio))
          .writeAsBytes([9]);
      expect(await audio.readAsBytes(), [1, 2, 3]);
      await store.saveState({'current': lessons.single.relativeAudio});
      expect(
        (await PhoneMediaStore(documents: await store.documents)
            .loadState())['current'],
        lessons.single.relativeAudio,
      );
    },
  );

  test(
    'different sources with duplicate names are rejected before any copy',
    () async {
      final a = await Directory('${temporary.path}/a').create();
      final b = await Directory('${temporary.path}/b').create();
      final first = await File('${a.path}/same.mp3').writeAsBytes([1]);
      final second = await File('${b.path}/same.mp3').writeAsBytes([2]);
      await expectLater(
        store.copySelected([first.path, second.path]),
        throwsFormatException,
      );
      expect(await store.scan(), isEmpty);
      expect(await first.readAsBytes(), [1]);
      expect(await second.readAsBytes(), [2]);
    },
  );

  test('relative path boundaries reject traversal and association can override default SRT', () async {
    for (final path in [
      '../outside.mp3',
      '/outside.mp3',
      'file:///outside.mp3',
      'a/../b.mp3',
      'a\\b.mp3',
    ]) {
      await expectLater(store.absolutePath(path), throwsArgumentError);
    }
    final media = await store.mediaDirectory;
    await File('${media.path}/lesson.aif').writeAsBytes([1]);
    await File('${media.path}/lesson.srt').writeAsString('srt');
    await File('${media.path}/manual.vtt').writeAsString('vtt');
    final lessons = await store.scan(
      associations: {'lesson.aif': 'manual.vtt'},
    );
    expect(lessons.single.relativeSubtitle, 'manual.vtt');
  });
}
