import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';

void main() {
  test('companion selection is exact, deterministic and local', () async {
    final dir = await Directory.systemTemp.createTemp('companion-test');
    addTearDown(() => dir.delete(recursive: true));
    final video = '${dir.path}/Episode.01.mkv';
    await File('${dir.path}/Episode.010.srt').writeAsString('other');
    expect(await findCompanionSubtitle(video), isNull);
    await File('${dir.path}/Episode.01.en.srt').writeAsString('English');
    expect(await findCompanionSubtitle(video), '${dir.path}/Episode.01.en.srt');
    await File('${dir.path}/Episode.01.en-ja.srt').writeAsString('bilingual');
    expect(
      await findCompanionSubtitle(video),
      '${dir.path}/Episode.01.en-ja.srt',
    );
    await File('${dir.path}/EPISODE.01.SRT').writeAsString('exact');
    expect(await findCompanionSubtitle(video), '${dir.path}/EPISODE.01.SRT');
    expect(
      await findCompanionSubtitle('${dir.path}/missing/movie.mkv'),
      isNull,
    );
  });
}
