import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_state.dart';

void main() {
  late Directory directory;
  late File primary;
  late File backup;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('local-player-state-');
    primary = File('${directory.path}/offline-player-state.json');
    backup = File('${primary.path}.bak');
  });

  tearDown(() async => directory.delete(recursive: true));

  Map<String, dynamic> state(int position) => {
    'lessons': [
      {
        'title': 'lesson',
        'video': '/media/lesson.mp4',
        'audio': null,
        'subtitle': '/media/lesson.srt',
      },
    ],
    'current': '/media/lesson.mp4',
    'positionMs': position,
    'rate': 1.25,
    'fontSize': 27,
    'subtitleBottom': 0.1,
    'volume': 65,
    'showPlaylist': true,
  };

  Future<Map<String, dynamic>> load(File file) async =>
      jsonDecode(await file.readAsString()) as Map<String, dynamic>;

  test('fresh store becomes writable only after a successful read', () async {
    final store = LocalStateStore(directory: directory);
    expect(store.status, LocalStateStatus.unread);
    expect(store.canWrite, isFalse);
    expect(await store.read(), isNull);
    expect(store.status, LocalStateStatus.ready);
    expect(store.canWrite, isTrue);
    expect(await primary.exists(), isFalse);
  });

  test('flush waits for queued writes and their atomic backups', () async {
    final store = LocalStateStore(directory: directory);
    final first = store.write(state(10));
    final second = store.write(state(20));
    await store.flush();
    expect(await load(primary), state(20));
    expect(await load(backup), state(10));
    await Future.wait([first, second]);
    expect(
      await directory
          .list()
          .where((file) => file.path.contains('.tmp-'))
          .toList(),
      isEmpty,
    );
  });

  test('flush does not create files or clear a blocked read', () async {
    final store = LocalStateStore(directory: directory);
    await store.flush();
    expect(store.status, LocalStateStatus.unread);
    expect(await primary.exists(), isFalse);
    await primary.writeAsString('{broken record');
    await expectLater(store.read(), throwsA(isA<LocalStateReadException>()));
    await store.flush();
    expect(store.status, LocalStateStatus.blocked);
    expect(store.canWrite, isFalse);
    expect(await primary.readAsString(), '{broken record');
  });

  test(
    'first write creates backup; next write preserves previous good state',
    () async {
      final store = LocalStateStore(file: primary);
      await store.write(state(100));
      expect(await load(primary), state(100));
      expect(await load(backup), state(100));
      await store.write(state(200));
      expect(await load(primary), state(200));
      expect(await load(backup), state(100));
      expect(
        await directory
            .list()
            .where((file) => file.path.contains('.tmp-'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'queued writes snapshot values and a queued read sees the final write',
    () async {
      final store = LocalStateStore(directory: directory);
      final mutable = state(10);
      final first = store.write(mutable);
      mutable['positionMs'] = 999;
      await first;
      expect((await load(primary))['positionMs'], 10);
      final writes = [
        for (var index = 1; index <= 20; index++) store.write(state(index)),
      ];
      final read = store.read();
      await Future.wait(writes);
      expect((await read)?['positionMs'], 20);
      expect((await load(backup))['positionMs'], 19);
    },
  );

  test(
    'malformed primary restores last good backup and retains corrupt bytes',
    () async {
      final original = LocalStateStore(directory: directory);
      await original.write(state(100));
      await original.write(state(200));
      await primary.writeAsString('{invalid JSON');
      final restored = LocalStateStore(directory: directory);
      expect(await restored.read(), state(100));
      expect(restored.status, LocalStateStatus.recovered);
      expect(restored.canWrite, isTrue);
      expect(restored.recoveryMessage, contains('备份恢复'));
      expect(restored.preservedCorruptPaths, hasLength(1));
      expect(
        await File(restored.preservedCorruptPaths.single).readAsString(),
        '{invalid JSON',
      );
      expect(await load(primary), state(100));
      expect(await load(backup), state(100));
      await restored.write(state(300));
      expect(await load(primary), state(300));
    },
  );

  test('JSON with an invalid lesson shape also recovers instead of reaching UI casts', () async {
    await primary.writeAsString(
      jsonEncode({
        'lessons': [
          {'title': 'broken', 'video': 7},
        ],
      }),
    );
    await backup.writeAsString(jsonEncode(state(1234)));
    final store = LocalStateStore(directory: directory);
    expect(await store.read(), state(1234));
    expect(store.status, LocalStateStatus.recovered);
    expect(store.preservedCorruptPaths, hasLength(1));
  });

  test(
    'two invalid records block later empty saves and remain unchanged',
    () async {
      await primary.writeAsString('{bad primary');
      await backup.writeAsString('["bad backup shape"]');
      final store = LocalStateStore(directory: directory);
      await expectLater(store.read(), throwsA(isA<LocalStateReadException>()));
      expect(store.status, LocalStateStatus.blocked);
      expect(store.canWrite, isFalse);
      await expectLater(
        store.write({'lessons': [], 'current': null, 'positionMs': 0}),
        throwsA(isA<LocalStateWriteBlockedException>()),
      );
      expect(await primary.readAsString(), '{bad primary');
      expect(await backup.readAsString(), '["bad backup shape"]');
      // A subsequent, explicitly repaired record can enable saving again.
      await primary.writeAsString(jsonEncode(state(50)));
      expect(await store.read(), state(50));
      expect(store.canWrite, isTrue);
      await store.write(state(70));
      expect(await load(primary), state(70));
    },
  );

  test(
    'write before read cannot overwrite an unread corrupt original',
    () async {
      await primary.writeAsString('{unread corrupt data');
      final store = LocalStateStore(directory: directory);
      await expectLater(
        store.write(state(0)),
        throwsA(isA<LocalStateReadException>()),
      );
      expect(store.canWrite, isFalse);
      expect(await primary.readAsString(), '{unread corrupt data');
      expect(await backup.exists(), isFalse);
    },
  );

  test('missing primary recovers from backup without losing it', () async {
    await backup.writeAsString(jsonEncode(state(99)));
    final store = LocalStateStore(directory: directory);
    expect(await store.read(), state(99));
    expect(store.status, LocalStateStatus.recovered);
    expect(store.recoveryMessage, contains('缺失'));
    expect(store.preservedCorruptPaths, isEmpty);
    expect(await load(primary), state(99));
    expect(await load(backup), state(99));
  });

  test('corrupt backup is preserved when valid primary is rotated', () async {
    await primary.writeAsString(jsonEncode(state(10)));
    await backup.writeAsString('{bad old backup');
    final store = LocalStateStore(directory: directory);
    expect(await store.read(), state(10));
    await store.write(state(20));
    expect(await load(backup), state(10));
    expect(
      await File(store.preservedCorruptPaths.single).readAsString(),
      '{bad old backup',
    );
  });

  test(
    'external corruption after read never replaces the known good backup',
    () async {
      final store = LocalStateStore(directory: directory);
      await store.write(state(10));
      await primary.writeAsString('{externally truncated');
      await store.write(state(20));
      expect(await load(primary), state(20));
      expect(await load(backup), state(10));
      expect(
        await File(store.preservedCorruptPaths.single).readAsString(),
        '{externally truncated',
      );
    },
  );

  test(
    'invalid settings/history writes fail before changing either file',
    () async {
      final store = LocalStateStore(directory: directory);
      await store.write(state(10));
      for (final invalid in [
        {...state(20), 'rate': 20},
        {...state(20), 'volume': 'loud'},
        {
          ...state(20),
          'lessons': [5],
        },
        {
          ...state(20),
          'lessons': [
            {'title': 'invalid primary path', 'video': '', 'audio': '/a.mp3'},
          ],
        },
        {
          ...state(20),
          'mediaHistory': {
            '/a/lesson': {'positionMs': 'bad'},
          },
        },
      ]) {
        await expectLater(store.write(invalid), throwsFormatException);
        expect(await load(primary), state(10));
        expect(await load(backup), state(10));
      }
    },
  );

  test('custom file location is honored and creates its parent', () async {
    final custom = File('${directory.path}/nested/custom-player.json');
    final store = LocalStateStore(file: custom);
    await store.write(state(1));
    expect(await load(custom), state(1));
    expect(await primary.exists(), isFalse);
  });
}
