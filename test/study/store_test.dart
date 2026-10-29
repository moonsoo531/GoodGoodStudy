import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/study_store.dart';

void main() {
  late Directory temporary;
  late StudyStore store;
  var counter = 0;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('study-import-test-');
    store = StudyStore(root: Directory('${temporary.path}/library'));
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<File> writeZip(Archive archive) async =>
      File('${temporary.path}/input-${counter++}.zip')
          .writeAsBytes(ZipEncoder().encode(archive));

  test(
    'valid ZIP copies local audio, round-trips metadata and preserves source',
    () async {
      final source = await writeZip(_package());
      final before = await source.readAsBytes();
      final installed = await store.importZip(source);
      expect(installed.package.packageId, 'n2-sample');
      expect(
        installed.package.lessons.single.segments.single.translationZh,
        '创作料理。',
      );
      expect(await File(installed.audioPath('audio-1')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await source.readAsBytes(), before);
      final reopened = StudyStore(root: Directory('${temporary.path}/library'));
      final listed = await reopened.packages();
      expect(listed.single.directory.path, installed.directory.path);
      expect(listed.single.package.toJson(), installed.package.toJson());
      expect(() => installed.audioPath('missing'), throwsArgumentError);
    },
  );

  test('reimport is idempotent and upgrades keep learning progress', () async {
    final source = await writeZip(_package());
    final first = await store.importZip(source);
    await store.saveProgress('n2-sample', {
      'lesson_id': 'lesson-1',
      'position': 2,
    });
    final again = await store.importZip(source);
    expect(again.directory.path, first.directory.path);
    final upgraded = await store.importZip(
      await writeZip(_package(revision: 2)),
    );
    expect(upgraded.package.contentRevision, 2);
    expect(await first.directory.exists(), isTrue);
    expect((await store.packages()).single.package.contentRevision, 2);
    expect(await store.loadProgress('n2-sample'), {
      'lesson_id': 'lesson-1',
      'position': 2,
    });
    await expectLater(store.importZip(source), throwsFormatException);
    expect((await store.packages()).single.package.contentRevision, 2);
  });

  test(
    'invalid upgrades and same-revision mutations leave installed data intact',
    () async {
      await store.importZip(await writeZip(_package()));
      final corrupt = _package(revision: 2, hash: '0' * 64);
      await expectLater(
        store.importZip(await writeZip(corrupt)),
        throwsFormatException,
      );
      final mutated = _package(title: 'changed');
      await expectLater(
        store.importZip(await writeZip(mutated)),
        throwsFormatException,
      );
      final installed = (await store.packages()).single;
      expect(installed.package.title, 'N2 学习样本');
      expect(installed.package.contentRevision, 1);
      expect(await File(installed.audioPath('audio-1')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      final stages = Directory('${temporary.path}/library/staging');
      expect(await stages.list().toList(), isEmpty);
    },
  );

  test(
    'missing, undeclared, malformed and damaged archives do not install',
    () async {
      final missing = _package();
      missing.removeFile(missing.find('entries.json')!);
      final undeclared = _package()
        ..addFile(ArchiveFile.string('media/extra.mp3', 'extra'));
      final malformed = _package()
        ..addFile(ArchiveFile.string('entries.json', '{}'));
      for (final archive in [missing, undeclared, malformed]) {
        await expectLater(
          store.importZip(await writeZip(archive)),
          throwsFormatException,
        );
        expect(await store.packages(), isEmpty);
      }
      final invalid = await File('${temporary.path}/invalid.zip')
          .writeAsBytes([0, 1, 2]);
      await expectLater(store.importZip(invalid), throwsFormatException);
    },
  );

  test(
    'traversal, absolute paths, backslashes and symlinks are rejected',
    () async {
      for (final path in [
        '../outside.txt',
        '/outside.txt',
        'media/../outside.mp3',
        'media\\a.mp3',
        'C:/outside.mp3',
      ]) {
        final archive = _package()..addFile(ArchiveFile.string(path, 'bad'));
        await expectLater(
          store.importZip(await writeZip(archive)),
          throwsFormatException,
        );
        expect(await store.packages(), isEmpty);
      }
      final archive = _package();
      final link = ArchiveFile.string('media/link.mp3', '../outside')
        ..mode = 0xa1ff;
      archive.addFile(link);
      await expectLater(
        store.importZip(await writeZip(archive)),
        throwsFormatException,
      );
      expect(await File('${temporary.path}/outside.txt').exists(), isFalse);
    },
  );

  test(
    'header encryption, oversized expansion and case conflicts are rejected',
    () async {
      final encoded = ZipEncoder().encode(_package());
      for (final offset in [8, 24]) {
        final bytes = List<int>.from(encoded);
        final central = _signature(bytes, [0x50, 0x4b, 0x01, 0x02]);
        if (offset == 8) {
          bytes[central + offset] |= 1;
        } else {
          // Header's declared uncompressed size exceeds maxFileBytes.
          final size = StudyStore.maxFileBytes + 1;
          for (var i = 0; i < 4; i++) {
            bytes[central + offset + i] = (size >> (8 * i)) & 255;
          }
        }
        final file = await File('${temporary.path}/crafted-${counter++}.zip')
            .writeAsBytes(bytes);
        await expectLater(store.importZip(file), throwsFormatException);
      }
      final conflicting = _package()
        ..addFile(ArchiveFile.string('MEDIA/T1.MP3', 'bad'));
      await expectLater(
        store.importZip(await writeZip(conflicting)),
        throwsFormatException,
      );
      expect(await store.packages(), isEmpty);
    },
  );

  test('progress writes serialize and reject unsafe package ids', () async {
    await Future.wait([
      store.saveProgress('n2-sample', {'position': 1}),
      store.saveProgress('n2-sample', {'position': 2}),
    ]);
    expect(await store.loadProgress('n2-sample'), {'position': 2});
    expect(await store.loadProgress('unknown'), isEmpty);
    await expectLater(store.saveProgress('../escape', {}), throwsArgumentError);
    expect(await store.loadProgress('n2-sample'), {'position': 2});
  });

  test('damaged content does not hide other packages and same-version import repairs it', () async {
    final first = await store.importZip(await writeZip(_package()));
    await store.saveProgress('n2-sample', {'note': 'keep me'});
    await store.importZip(
      await writeZip(_package(id: 'n2-good', title: 'Other')),
    );
    await File('${first.directory.path}/entries.json').writeAsString('{');
    expect((await store.packages()).single.package.packageId, 'n2-good');
    expect(store.libraryWarnings.single, contains('n2-sample'));
    final repaired = await store.importZip(await writeZip(_package()));
    expect(repaired.directory.path, isNot(first.directory.path));
    expect(await first.directory.exists(), isTrue);
    expect(await store.packages(), hasLength(2));
    expect(store.libraryWarnings, isEmpty);
    expect(await store.loadProgress('n2-sample'), {'note': 'keep me'});
    expect(
      (await store.importZip(await writeZip(_package()))).directory.path,
      repaired.directory.path,
    );
  });

  test(
    'damaged audio and version pointers can be repaired without downgrading',
    () async {
      final first = await store.importZip(
        await writeZip(_package(revision: 2)),
      );
      await File(first.audioPath('audio-1')).writeAsBytes([9]);
      final repaired = await store.importZip(
        await writeZip(_package(revision: 2)),
      );
      expect(await File(repaired.audioPath('audio-1')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      final pointer = File(
        '${temporary.path}/library/packages/n2-sample/current.json',
      );
      await pointer.writeAsString('bad json');
      expect(await store.packages(), isEmpty);
      expect(store.libraryWarnings, hasLength(1));
      await expectLater(
        store.importZip(await writeZip(_package())),
        throwsFormatException,
      );
      await store.importZip(await writeZip(_package(revision: 2)));
      expect((await store.packages()).single.package.contentRevision, 2);
    },
  );

  test(
    'damaged learning progress is backed up and does not block lessons',
    () async {
      await store.saveProgress('n2-sample', {'note': 'original'});
      final state = Directory('${temporary.path}/library/state');
      final file = File('${state.path}/n2-sample-progress.json');
      await file.writeAsString('{broken');
      expect(await store.loadProgress('n2-sample'), isEmpty);
      expect(store.libraryWarnings.single, contains('原文件已保留备份'));
      final backups = await state
          .list()
          .where((e) => e.path.contains('.damaged-'))
          .toList();
      expect(backups, hasLength(1));
      expect(await File(backups.single.path).readAsString(), '{broken');
      await store.saveProgress('n2-sample', {'position': 1});
      expect(await store.loadProgress('n2-sample'), {'position': 1});
    },
  );

  test('deflate cannot expand past a forged small uncompressed size', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('media/bomb.mp3', List.filled(2 * 1024 * 1024, 65)),
      );
    final bytes = List<int>.from(ZipEncoder().encode(archive));
    final central = _signature(bytes, [0x50, 0x4b, 0x01, 0x02]);
    final local = _signature(bytes, [0x50, 0x4b, 0x03, 0x04]);
    for (final offset in [central + 24, local + 22]) {
      bytes[offset] = 16;
      bytes[offset + 1] = 0;
      bytes[offset + 2] = 0;
      bytes[offset + 3] = 0;
    }
    final file = await File('${temporary.path}/small-header.zip')
        .writeAsBytes(bytes);
    await expectLater(
      store.importZip(file),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'limit',
          contains('larger than the 16 bytes allowed'),
        ),
      ),
    );
    expect(await store.packages(), isEmpty);
  });
}

Archive _package({
  int revision = 1,
  String title = 'N2 学习样本',
  String? hash,
  String id = 'n2-sample',
}) {
  final manifest = {
    'schema_version': '1.0',
    'package_id': id,
    'content_revision': revision,
    'title': title,
    'language': 'ja',
    'translation_language': 'zh-CN',
    'level_tags': ['N2'],
    'media': [
      {
        'id': 'audio-1',
        'path': 'media/T1.mp3',
        'sha256': hash ?? sha256.convert([1, 2, 3]).toString(),
      },
    ],
  };
  final lessons = [
    {
      'id': 'lesson-1',
      'title': '食事',
      'topic': '食事',
      'audio_ref': 'audio-1',
      'segments': [
        {
          'id': 'segment-1',
          'text': '創作料理。',
          'translation_zh': '创作料理。',
          'highlights': [
            {'start': 0, 'end': 2, 'entry_id': 'entry-1'},
          ],
        },
      ],
    },
  ];
  final entries = [
    {
      'id': 'entry-1',
      'surface': '創作',
      'reading': 'そうさく',
      'meaning_zh': '创作',
      'kind': 'vocabulary',
      'attributes': {'词性': '名词'},
      'tags': ['N2'],
      'relations': [],
    },
  ];
  return Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
    ..addFile(ArchiveFile.string('lessons.json', jsonEncode(lessons)))
    ..addFile(ArchiveFile.string('entries.json', jsonEncode(entries)))
    ..addFile(ArchiveFile.bytes('media/T1.mp3', [1, 2, 3]));
}

int _signature(List<int> bytes, List<int> signature) {
  for (var i = 0; i <= bytes.length - signature.length; i++) {
    if (List.generate(
      signature.length,
      (j) => bytes[i + j],
    ).indexed.every((e) => e.$2 == signature[e.$1])) {
      return i;
    }
  }
  throw StateError('signature missing');
}
