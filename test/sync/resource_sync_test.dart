import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/quiz/quiz_store.dart';
import 'package:offline_player/study/study_models.dart';
import 'package:offline_player/study/study_store.dart';
import 'package:offline_player/sync/icloud_transport.dart';
import 'package:offline_player/sync/resource_sync_controller.dart';
import 'package:offline_player/sync/sync_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'content-addressed metadata rejects changed content and invalid parents',
    () {
      final record = _progress({
        'entry_notes': {'entry-1': 'synthetic note'},
      });
      expect(SyncRecord.parse(record.name, record.text).progress, {
        'entry_notes': {'entry-1': 'synthetic note'},
      });
      expect(
        () => SyncRecord.parse(
          record.name,
          record.text.replaceFirst('synthetic note', 'altered note'),
        ),
        throwsFormatException,
      );
      final badParent = _progress({}, parents: ['b_${'1' * 64}.ggpack']);
      expect(
        () => SyncRecord.parse(badParent.name, badParent.text),
        throwsFormatException,
      );
      final badProgressHash = _NamedRecord({
        ...record.data,
        'fingerprint': '0' * 64,
      });
      expect(
        () => SyncRecord.parse(badProgressHash.name, badProgressHash.text),
        throwsFormatException,
      );
    },
  );

  test('three-way merge combines independent entry notes without conflict', () {
    final base = <String, dynamic>{
      'entry_notes': {'entry-1': 'base one', 'entry-2': 'base two'},
      'lesson_id': 'lesson-1',
      'audio_segment_id': 'segment-1',
    };
    final result = mergeStudyProgress(
      base,
      {
        ...base,
        'entry_notes': {'entry-1': 'local one', 'entry-2': 'base two'},
      },
      {
        ...base,
        'entry_notes': {'entry-1': 'base one', 'entry-2': 'remote two'},
      },
    );
    expect(result.conflicts, isEmpty);
    expect(result.progress['entry_notes'], {
      'entry-1': 'local one',
      'entry-2': 'remote two',
    });
  });

  test(
    'conflicting note and learning location preserve the entire local value',
    () {
      final base = <String, dynamic>{
        'entry_notes': {'entry-1': 'base'},
        'lesson_id': 'lesson-1',
        'audio_segment_id': 'segment-1',
        'position': 0,
      };
      final local = <String, dynamic>{
        'entry_notes': {'entry-1': 'local'},
        'lesson_id': 'lesson-2',
        'audio_segment_id': 'segment-2',
        'position': 2,
      };
      final remote = <String, dynamic>{
        'entry_notes': {'entry-1': 'remote'},
        'lesson_id': 'lesson-3',
        'audio_segment_id': 'segment-3',
        'position': 3,
      };
      final result = mergeStudyProgress(base, local, remote);
      expect(
        result.conflicts,
        unorderedEquals(['entry_notes.entry-1', 'learning_position']),
      );
      expect(
        result.progress,
        local,
        reason: 'A remote segment must not be spliced into the local lesson.',
      );
    },
  );

  test('a fresh controller stays off and only probes availability', () async {
    final f = await _Fixture.create();
    await f.install();
    await f.controller.synchronize();
    f.transport.onChanged?.call('changed');
    await f.controller.synchronize();
    expect(f.controller.enabled, isFalse);
    expect(f.controller.phase, 'off');
    expect(f.transport.calls.map((c) => c.method), everyElement('status'));
    expect(f.transport.uploads, isEmpty);
    expect(await Directory(f.accountPath(_accountA)).exists(), isFalse);
  });

  test(
    'disabling a paused download prevents commit and reenabling resumes safely',
    () async {
      final f = await _Fixture.create();
      await f.install();
      final remote = f.progress({
        'entry_notes': {'entry-1': 'remote note'},
      });
      f.transport.putRecord(remote);
      final pause = f.transport.pauseNextDownload();
      final enabling = f.controller.setEnabled(true);
      await pause.entered.future.timeout(const Duration(seconds: 10));
      final disabling = f.controller.setEnabled(false);
      expect(f.controller.enabled, isFalse);
      pause.resume.complete();
      await Future.wait([enabling, disabling]);
      expect(await f.study.loadProgress(_packageId), isEmpty);
      expect(f.transport.uploads, isEmpty);
      expect(
        await File('${f.accountPath(_accountA)}/records/${remote.name}')
            .exists(),
        isFalse,
      );
      await f.controller.setEnabled(true);
      expect(await f.study.loadProgress(_packageId), remote.data['progress']);
      expect(f.controller.enabled, isTrue);
    },
  );

  test(
    'an account change during download requires a new explicit enable',
    () async {
      final f = await _Fixture.create();
      await f.install();
      final remoteA = f.progress({
        'entry_notes': {'entry-1': 'account A only'},
      });
      f.transport.putRecord(remoteA);
      final pause = f.transport.pauseNextDownload();
      final enabling = f.controller.setEnabled(true);
      await pause.entered.future.timeout(const Duration(seconds: 10));
      f.transport.account = _accountB;
      f.transport.onChanged?.call('accountChanged');
      pause.resume.complete();
      await enabling;
      await f.controller.synchronize();
      expect(f.controller.enabled, isFalse);
      expect(f.controller.accountChanged, isTrue);
      expect(await f.study.loadProgress(_packageId), isEmpty);
      expect(f.transport.uploads, isEmpty);
      expect(
        f.transport.calls
            .where((c) => c.account == _accountB)
            .map((c) => c.method),
        everyElement(anyOf('status', 'stop')),
      );
      await f.controller.setEnabled(true);
      expect(f.controller.enabled, isTrue);
      expect(f.controller.accountChanged, isFalse);
      expect(f.transport.uploads, isNotEmpty);
      expect(
        f.transport.uploads.map((c) => c.account),
        everyElement(_accountB),
      );
      expect(
        f.transport.uploads.map((c) => c.arguments['sourcePath']),
        everyElement(startsWith('${f.accountPath(_accountB)}/outbox/')),
      );
      expect(
        await File('${f.accountPath(_accountB)}/records/${remoteA.name}')
            .exists(),
        isFalse,
      );
      expect(await f.study.loadProgress(_packageId), isEmpty);
    },
  );

  test('a child received before its parent waits without overwriting local progress', () async {
    final f = await _Fixture.create();
    await f.install();
    final parent = f.progress({
      'entry_notes': {'entry-1': 'base'},
    }, created: 1);
    final child = f.progress(
      {
        'entry_notes': {'entry-1': 'remote descendant'},
      },
      parents: [parent.name],
      created: 2,
    );
    f.transport.putRecord(child);
    await f.controller.setEnabled(true);
    expect(f.controller.pendingRemote, isTrue);
    expect(await f.study.loadProgress(_packageId), isEmpty);
    f.transport.putRecord(parent);
    await f.controller.synchronize();
    expect(await f.study.loadProgress(_packageId), child.data['progress']);
    expect(f.controller.conflicts, isEmpty);
  });

  test('a newer local save wins the compare-and-swap race with an older remote snapshot', () async {
    final f = await _Fixture.create();
    await f.install();
    final old = f.progress({
      'entry_notes': {'entry-1': 'older remote note'},
    });
    f.transport.putRecord(old);
    final fresh = <String, dynamic>{
      'entry_notes': {'entry-1': 'newly saved local note'},
    };
    f.study.beforeApply = () => f.study.saveProgress(_packageId, fresh);
    await f.controller.setEnabled(true);
    expect(f.study.applyCalls, 1);
    expect(await f.study.loadProgress(_packageId), fresh);
    expect(f.controller.pendingRemote, isTrue);
    await f.controller.synchronize();
    expect(await f.study.loadProgress(_packageId), fresh);
    expect(
      f.controller.conflicts,
      isNotEmpty,
      reason:
          'The rejected remote branch must remain available for a decision.',
    );
  });

  test('corrupt and interrupted blob caches do not install and a valid retry recovers', () async {
    final f = await _Fixture.create();
    await f.install();
    final notes = <String, dynamic>{
      'entry_notes': {'entry-1': 'keep my local note'},
    };
    await f.study.saveProgress(_packageId, notes);
    final upgrade = _SyntheticPackage(revision: 2);
    final blobName = 'b_${sha256.convert(upgrade.bytes)}.ggpack';
    final metadata = _NamedRecord({
      'schema': 1,
      'kind': 'studyPackage',
      'package_id': _packageId,
      'title': 'Synthetic sync fixture',
      'revision': 2,
      'fingerprint': jsonHash(upgrade.content),
      'blob': blobName,
      'device': _remoteDevice,
      'created_ms': 1,
    });
    f.transport.putRecord(metadata);
    f.transport.put(blobName, [11, 22, 33]);
    final cache = Directory('${f.accountPath(_accountA)}/blobs');
    await cache.create(recursive: true);
    await File('${cache.path}/$blobName').writeAsBytes([44]);
    await File('${cache.path}/$blobName.tmp').writeAsBytes([55]);
    await f.controller.setEnabled(true);
    expect((await f.study.packages()).single.package.contentRevision, 1);
    expect(await f.study.loadProgress(_packageId), notes);
    expect(f.controller.lastError, 'invalidCloudData');
    expect(await File('${cache.path}/$blobName').exists(), isFalse);
    expect(
      await cache.list().where((e) => e.path.contains('.damaged-')).length,
      greaterThanOrEqualTo(1),
    );
    f.transport.put(blobName, upgrade.bytes);
    await f.controller.synchronize();
    expect((await f.study.packages()).single.package.contentRevision, 2);
    expect(await f.study.loadProgress(_packageId), notes);
    expect(f.controller.lastError, isNull);
    expect(f.transport.calls.where((c) => c.method == 'release'), isNotEmpty);
  });

  test('an outbox-only journal survives restart and is retained until upload acknowledgement', () async {
    final f = await _Fixture.create(initialize: false);
    final own = _progress({
      'entry_notes': {'entry-1': 'durable local note'},
    }, device: _localDevice);
    final syncRoot = Directory('${f.support.path}/cloud-sync');
    await syncRoot.create(recursive: true);
    await File('${syncRoot.path}/preferences.json').writeAsString(
      jsonEncode({
        'schema': 1,
        'enabled': true,
        'account': _accountA,
        'device': _localDevice,
      }),
    );
    final outbox = Directory('${f.accountPath(_accountA)}/outbox');
    await outbox.create(recursive: true);
    await File('${outbox.path}/${own.name}').writeAsString(own.text);
    await File('${outbox.path}/interrupted.tmp').writeAsString('{partial');
    await f.initialize();
    await f.controller.synchronize();
    expect(
      await File('${f.accountPath(_accountA)}/records/${own.name}')
          .readAsString(),
      own.text,
    );
    expect(
      f.transport.uploads.map((c) => c.arguments['name']),
      contains(own.name),
    );
    expect(await File('${outbox.path}/${own.name}').exists(), isTrue);
    expect(
      f.transport.uploads.map((c) => c.arguments['name']),
      isNot(contains('interrupted.tmp')),
    );
    f.transport.acknowledgeUploads();
    await f.controller.synchronize();
    expect(await File('${outbox.path}/${own.name}').exists(), isFalse);
    expect(
      await File('${f.accountPath(_accountA)}/records/${own.name}').exists(),
      isTrue,
    );
    expect(await f.study.packages(), isEmpty);
  });
}

const _packageId = 'synthetic-sync';
final _accountA = 'a' * 64, _accountB = 'b' * 64;
final _localDevice = 'c' * 32, _remoteDevice = 'd' * 32;
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

class _NamedRecord {
  _NamedRecord(this.data);
  final Map<String, dynamic> data;
  String get text => canonicalJson(data);
  String get name => 'm_${jsonHash(data)}.ggsync';
}

_NamedRecord _progress(
  Map<String, dynamic> value, {
  List<String> parents = const [],
  String? device,
  int created = 1,
  String? resourceFingerprint,
}) => _NamedRecord({
  'schema': 1,
  'kind': 'studyProgress',
  'package_id': _packageId,
  'title': 'Synthetic sync fixture',
  'fingerprint': jsonHash(value),
  'parents': parents,
  'progress': value,
  'resource_revision': 1,
  'resource_fingerprint': resourceFingerprint ?? 'e' * 64,
  'device': device ?? _remoteDevice,
  'created_ms': created,
});

class _SyntheticPackage {
  _SyntheticPackage({int revision = 1}) {
    // Original test-only text and arbitrary bytes: no personal learning data.
    final audio = [0, 1, 2];
    final manifest = <String, dynamic>{
      'schema_version': '1.0',
      'package_id': _packageId,
      'content_revision': revision,
      'title': 'Synthetic sync fixture',
      'language': 'ja',
      'translation_language': 'zh-CN',
      'level_tags': <String>[],
      'media': [
        {
          'id': 'audio-1',
          'path': 'media/test.mp3',
          'sha256': sha256.convert(audio).toString(),
        },
      ],
    };
    final lessons = [
      {
        'id': 'lesson-1',
        'title': 'Synthetic lesson',
        'topic': 'Synthetic topic',
        'audio_ref': 'audio-1',
        'segments': [
          {
            'id': 'segment-1',
            'text': 'テスト。',
            'translation_zh': '合成示例。',
            'highlights': <dynamic>[],
          },
        ],
      },
    ];
    final entries = <dynamic>[];
    content = StudyPackage.fromJson(
      manifest,
      lessons: lessons,
      entries: entries,
    ).toJson();
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(ArchiveFile.string('lessons.json', jsonEncode(lessons)))
      ..addFile(ArchiveFile.string('entries.json', jsonEncode(entries)))
      ..addFile(ArchiveFile.bytes('media/test.mp3', audio));
    bytes = ZipEncoder().encode(archive);
  }
  late final Map<String, dynamic> content;
  late final List<int> bytes;
}

class _RaceStudyStore extends StudyStore {
  _RaceStudyStore({required super.root});
  Future<void> Function()? beforeApply;
  int applyCalls = 0;

  @override
  Future<bool> applySyncedProgress(
    String packageId, {
    required Map<String, dynamic> expectedLocal,
    required Map<String, dynamic> progress,
  }) async {
    applyCalls++;
    final action = beforeApply;
    beforeApply = null;
    if (action != null) await action();
    return super.applySyncedProgress(
      packageId,
      expectedLocal: expectedLocal,
      progress: progress,
    );
  }
}

class _Fixture {
  _Fixture(this.directory);
  final Directory directory;
  late final Directory support;
  late final _FakeICloudTransport transport;
  late final _RaceStudyStore study;
  late final ResourceSyncController controller;
  _SyntheticPackage? package;
  bool canApply = true, initialized = false;

  static Future<_Fixture> create({bool initialize = true}) async {
    final temporary = await Directory.systemTemp.createTemp(
      'ggs-synthetic-sync-',
    );
    final f = _Fixture(Directory(await temporary.resolveSymbolicLinks()));
    f.support = await Directory('${f.directory.path}/support').create();
    f.transport = _FakeICloudTransport(f.directory);
    f.study = _RaceStudyStore(root: Directory('${f.directory.path}/study'));
    f.controller = ResourceSyncController(
      study: f.study,
      quiz: QuizStore(root: Directory('${f.directory.path}/quiz')),
      canApplyRemote: () => f.canApply,
      transport: f.transport,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (_) async => f.support.path);
    addTearDown(f.close);
    if (initialize) await f.initialize();
    return f;
  }

  Future<void> initialize() async {
    await controller.initialize();
    initialized = true;
    expect(controller.lastError, isNull);
  }

  String accountPath(String account) =>
      '${support.path}/cloud-sync/accounts/$account';

  Future<void> install() async {
    package = _SyntheticPackage();
    final input = await File('${directory.path}/synthetic.zip')
        .writeAsBytes(package!.bytes);
    await study.importZip(input);
  }

  _NamedRecord progress(
    Map<String, dynamic> value, {
    List<String> parents = const [],
    int created = 1,
  }) => _progress(
    value,
    parents: parents,
    created: created,
    resourceFingerprint: jsonHash(package!.content),
  );

  Future<void> close() async {
    transport.unblock();
    if (initialized) await controller.setEnabled(false);
    controller.dispose();
    await study.flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    await directory.delete(recursive: true);
  }
}

class _Call {
  _Call(this.method, this.account, this.arguments);
  final String method, account;
  final Map<String, Object?> arguments;
}

class _Pause {
  final entered = Completer<void>();
  final resume = Completer<void>();
}

class _CloudFile {
  _CloudFile(this.bytes, {this.uploaded = true});
  final List<int> bytes;
  bool uploaded;
}

/// Implements the public interface without invoking its real MethodChannel
/// constructor. Every cloud object and lease belongs to this test directory.
class _FakeICloudTransport implements ICloudTransport {
  _FakeICloudTransport(this.directory);
  final Directory directory;
  final calls = <_Call>[];
  final _cloud = <String, Map<String, _CloudFile>>{};
  final _pauses = <_Pause>[];
  String account = _accountA;
  int _lease = 0;
  _Pause? _nextDownload;

  @override
  void Function(String event)? onChanged;

  Iterable<_Call> get uploads => calls.where((c) => c.method == 'upload');
  Map<String, _CloudFile> get files => _cloud.putIfAbsent(account, () => {});

  void put(String name, List<int> bytes) =>
      files[name] = _CloudFile(List.of(bytes));
  void putRecord(_NamedRecord record) =>
      put(record.name, utf8.encode(record.text));
  void acknowledgeUploads() {
    for (final file in files.values) {
      file.uploaded = true;
    }
  }

  _Pause pauseNextDownload() {
    final pause = _Pause();
    _pauses.add(pause);
    _nextDownload = pause;
    return pause;
  }

  void unblock() {
    for (final pause in _pauses) {
      if (!pause.resume.isCompleted) pause.resume.complete();
    }
  }

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final args = arguments ?? <String, Object?>{};
    calls.add(_Call(method, account, Map.of(args)));
    final expected = args['expectedAccountID'];
    void checkAccount() {
      if (expected != null && expected != account) {
        throw PlatformException(code: 'accountChanged');
      }
    }

    final status = <String, dynamic>{
      'supported': true,
      'configured': true,
      'available': true,
      'reason': 'available',
      'accountID': account,
    };
    switch (method) {
      case 'status':
        return status;
      case 'start':
        checkAccount();
        return status;
      case 'list':
        checkAccount();
        return {
          ...status,
          'gathering': false,
          'files': [
            for (final entry in files.entries)
              {
                'name': entry.key,
                'bytes': entry.value.bytes.length,
                'downloaded': true,
                'uploaded': entry.value.uploaded,
              },
          ],
        };
      case 'download':
        checkAccount();
        final pause = _nextDownload;
        _nextDownload = null;
        if (pause != null) {
          pause.entered.complete();
          await pause.resume.future;
        }
        checkAccount();
        final name = args['name'] as String;
        final item = files[name];
        if (item == null) return {'ready': false};
        final lease = await Directory('${directory.path}/leases/${_lease++}')
            .create(recursive: true);
        final file = await File('${lease.path}/$name').writeAsBytes(item.bytes);
        return {'ready': true, 'path': file.path};
      case 'upload':
        checkAccount();
        final source = File(args['sourcePath'] as String);
        final real = await source.resolveSymbolicLinks();
        if (!real.startsWith('${directory.path}/')) {
          throw StateError('Test transport refused a non-fixture source.');
        }
        files[args['name'] as String] = _CloudFile(
          await source.readAsBytes(),
          uploaded: false,
        );
        return {'requested': true};
      case 'release':
        final path = args['path'] as String;
        if (!path.startsWith('${directory.path}/leases/')) {
          throw StateError('Test transport refused a non-fixture lease.');
        }
        final file = File(path);
        if (await file.exists()) await file.delete();
        return {};
      case 'stop':
        return {};
      default:
        throw StateError('Unexpected test transport method: $method');
    }
  }

  @override
  Future<void> stop() async {
    await call('stop');
  }

  @override
  void dispose() {
    onChanged = null;
    unblock();
  }
}
