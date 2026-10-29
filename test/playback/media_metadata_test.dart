import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/playback/media_metadata.dart';

const _a = LocalLesson(title: 'A', videoPath: '/media/a.mp4');
const _b = LocalLesson(title: 'B', audioPath: '/media/b.mp3');
const _c = LocalLesson(title: 'C', videoPath: '/media/c.mkv');

void main() {
  late _ControlledProbe probe;
  late MediaMetadataReader reader;
  late List<MapEntry<LocalLesson, Duration>> results;

  setUp(() {
    probe = _ControlledProbe();
    results = [];
    reader = MediaMetadataReader.withProbe(
      probe,
      (lesson, duration) => results.add(MapEntry(lesson, duration)),
    );
  });

  tearDown(() async {
    final closing = reader.close();
    for (final request in probe.requests) {
      if (!request.isCompleted) request.complete(Duration.zero);
    }
    await closing;
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'queue is strictly serial and does not start another probe early',
    () async {
      reader.updateQueue([_a, _b, _c]);
      expect(probe.paths, [_a.primaryPath]);
      expect(reader.busy, isTrue);
      expect(probe.maximumActive, 1);
      probe.requests[0].complete(const Duration(seconds: 8));
      await flush();
      expect(probe.paths, [_a.primaryPath, _b.primaryPath]);
      expect(results.single.key, _a);
      probe.requests[1].complete(const Duration(seconds: 20));
      await flush();
      expect(probe.paths, [_a.primaryPath, _b.primaryPath, _c.primaryPath]);
      probe.requests[2].complete(const Duration(minutes: 2));
      await reader.whenIdle;
      expect(probe.maximumActive, 1);
      expect(results.map((entry) => entry.key), [_a, _b, _c]);
      expect(results.last.value, const Duration(minutes: 2));
    },
  );

  test('duplicates and equivalent normalized paths are read once', () async {
    const alias = LocalLesson(title: 'alias', videoPath: '/media/./a.mp4');
    reader.updateQueue([_a, _a, alias, _b]);
    reader.updateQueue([alias, _b, _b]);
    expect(probe.paths, [_a.primaryPath]);
    probe.requests[0].complete(const Duration(seconds: 8));
    await flush();
    expect(results.single.key, alias);
    probe.requests[1].complete(const Duration(seconds: 20));
    await reader.whenIdle;
    reader.updateQueue([alias, _b]);
    await reader.whenIdle;
    expect(probe.paths, [_a.primaryPath, _b.primaryPath]);
    expect(results, hasLength(2));
  });

  test('initial suspension prevents startup; in-flight work may finish during suspension', () async {
    reader.setSuspended(true);
    reader.updateQueue([_a, _b]);
    await reader.whenIdle;
    expect(probe.paths, isEmpty);
    expect(reader.suspended, isTrue);
    reader.setSuspended(false);
    expect(probe.paths, [_a.primaryPath]);
    reader.setSuspended(true);
    probe.requests[0].complete(const Duration(seconds: 8));
    await reader.whenIdle;
    expect(results.single.key, _a);
    expect(probe.paths, [_a.primaryPath]);
    expect(reader.busy, isFalse);
    reader.setSuspended(false);
    expect(probe.paths, [_a.primaryPath, _b.primaryPath]);
    probe.requests[1].complete(const Duration(seconds: 20));
    await reader.whenIdle;
    expect(results.map((entry) => entry.key), [_a, _b]);
  });

  test('removing a queued lesson prevents it from starting', () async {
    reader.updateQueue([_a, _b]);
    reader.updateQueue([_a]);
    probe.requests[0].complete(const Duration(seconds: 8));
    await reader.whenIdle;
    expect(probe.paths, [_a.primaryPath]);
    expect(results.single.key, _a);
  });

  test('removing an in-flight lesson suppresses its stale result', () async {
    reader.updateQueue([_a, _b]);
    reader.updateQueue([_b]);
    probe.requests[0].complete(const Duration(seconds: 8));
    await flush();
    expect(results, isEmpty);
    expect(probe.paths, [_a.primaryPath, _b.primaryPath]);
    probe.requests[1].complete(const Duration(seconds: 20));
    await reader.whenIdle;
    expect(results.single.key, _b);
  });

  test('removed and re-added path ignores an earlier generation', () async {
    reader.updateQueue([_a]);
    reader.updateQueue(const []);
    const replacement = LocalLesson(
      title: 'replacement A',
      videoPath: '/media/a.mp4',
    );
    reader.updateQueue([replacement]);
    probe.requests[0].complete(const Duration(seconds: 8));
    await flush();
    expect(results, isEmpty);
    expect(probe.paths, [_a.primaryPath, _a.primaryPath]);
    probe.requests[1].complete(const Duration(seconds: 11));
    await reader.whenIdle;
    expect(results.single.key, replacement);
    expect(results.single.value, const Duration(seconds: 11));
  });

  test(
    'close waits for in-flight work but suppresses callbacks and later probes',
    () async {
      reader.updateQueue([_a, _b]);
      final closing = reader.close();
      expect(identical(reader.close(), closing), isTrue);
      expect(probe.closed, isFalse);
      reader.setSuspended(false);
      reader.updateQueue([_c]);
      probe.requests[0].complete(const Duration(seconds: 8));
      await closing;
      expect(probe.closed, isTrue);
      expect(probe.closeCalls, 1);
      expect(probe.paths, [_a.primaryPath]);
      expect(results, isEmpty);
    },
  );

  test(
    'dispose immediately prevents callbacks even when a probe completes later',
    () async {
      reader.updateQueue([_a, _b]);
      reader.dispose();
      probe.requests[0].complete(const Duration(seconds: 8));
      await reader.close();
      expect(probe.paths, [_a.primaryPath]);
      expect(probe.closed, isTrue);
      expect(results, isEmpty);
    },
  );

  test('failed and unknown durations do not block later files or retry on every refresh', () async {
    reader.updateQueue([_a, _b, _c]);
    probe.requests[0].completeError(StateError('Unreadable media'));
    await flush();
    probe.requests[1].complete(Duration.zero);
    await flush();
    probe.requests[2].complete(const Duration(seconds: 20));
    await reader.whenIdle;
    expect(results.single.key, _c);
    reader.updateQueue([_a, _b, _c]);
    await reader.whenIdle;
    expect(probe.paths, [_a.primaryPath, _b.primaryPath, _c.primaryPath]);
    reader.updateQueue(const []);
    reader.updateQueue([_a]);
    expect(probe.paths.last, _a.primaryPath);
    expect(probe.paths, hasLength(4));
    probe.requests[3].complete(const Duration(seconds: 8));
    await reader.whenIdle;
    expect(results.last.key, _a);
  });

  test('remote URIs, authority paths, relative paths and unsupported formats never reach probe', () async {
    reader.updateQueue(const [
      LocalLesson(
        title: 'remote',
        videoPath: 'https://example.invalid/video.mp4',
      ),
      LocalLesson(
        title: 'remote file',
        videoPath: 'file://remote.invalid/video.mp4',
      ),
      LocalLesson(title: 'authority', videoPath: '//remote.invalid/video.mp4'),
      LocalLesson(title: 'relative', videoPath: 'relative.mp4'),
      LocalLesson(title: 'unsupported', videoPath: '/media/playlist.m3u8'),
    ]);
    await reader.whenIdle;
    expect(probe.paths, isEmpty);
    expect(results, isEmpty);
    const local = LocalLesson(
      title: 'local URI',
      videoPath: 'file:///media/local.mp4',
    );
    reader.updateQueue([local]);
    expect(probe.paths, ['/media/local.mp4']);
    probe.requests.single.complete(const Duration(seconds: 3));
    await reader.whenIdle;
    expect(results.single.key, local);
  });

  test(
    'callback queue refresh cannot cause duplicate or overlapping reads',
    () async {
      await reader.close();
      reader = MediaMetadataReader.withProbe(probe = _ControlledProbe(), (
        lesson,
        duration,
      ) {
        results.add(MapEntry(lesson, duration));
        reader.updateQueue(lesson == _a ? [_b] : const []);
      });
      reader.updateQueue([_a, _b]);
      probe.requests[0].complete(const Duration(seconds: 8));
      await flush();
      probe.requests[1].complete(const Duration(seconds: 20));
      await reader.whenIdle;
      expect(probe.paths, [_a.primaryPath, _b.primaryPath]);
      expect(probe.maximumActive, 1);
      expect(results.map((entry) => entry.key), [_a, _b]);
    },
  );

  test(
    'an unused native reader closes without initializing media_kit',
    () async {
      final unused = MediaMetadataReader(
        onDuration: (_, _) => fail('No queued files.'),
      );
      unused.setSuspended(true);
      await unused.close();
    },
  );
}

class _ControlledProbe implements MediaDurationProbe {
  final paths = <String>[];
  final requests = <Completer<Duration>>[];
  var active = 0;
  var maximumActive = 0;
  var closeCalls = 0;
  var closed = false;

  @override
  Future<Duration> readDuration(String localPath) {
    if (closed) throw StateError('Probe already closed.');
    paths.add(localPath);
    final request = Completer<Duration>();
    requests.add(request);
    active++;
    if (active > maximumActive) maximumActive = active;
    return request.future.whenComplete(() => active--);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
  }
}
