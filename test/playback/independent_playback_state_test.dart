import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/playback/playback_transport.dart';

const second = Duration(seconds: 1);
Duration seconds(int value) => Duration(seconds: value);

Future<void> settle() async {
  for (var turn = 0; turn < 25; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class MemoryTransport implements PlaybackTransport, ClearablePlaybackTransport {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration>.broadcast(sync: true);
  final plays = StreamController<bool>.broadcast(sync: true);
  final buffers = StreamController<bool>.broadcast(sync: true);
  final completions = StreamController<bool>.broadcast(sync: true);
  final errors = StreamController<String>.broadcast(sync: true);
  final calls = <String>[];
  Duration at = Duration.zero;
  Duration length = seconds(10);
  bool active = false;
  double speed = 1;
  Completer<void>? seekGate;
  Completer<void>? disposalGate;
  Completer<void>? clearGate;
  bool failOpen = false;
  bool failClear = false;
  bool failDispose = false;
  bool eofOnPlay = false;
  bool eofOnSeek = false;
  bool resetCompletionOnSeek = true;
  int concurrent = 0;
  int maximumConcurrent = 0;
  int disposals = 0;

  @override
  Player? get nativePlayer => null;
  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    position: at,
    duration: length,
    playing: active,
    rate: speed,
  );
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get durationStream => durations.stream;
  @override
  Stream<bool> get playingStream => plays.stream;
  @override
  Stream<bool> get bufferingStream => buffers.stream;
  @override
  Stream<bool> get completedStream => completions.stream;
  @override
  Stream<String> get errorStream => errors.stream;

  Future<void> command(String name, FutureOr<void> Function() body) async {
    calls.add(name);
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    try {
      await body();
    } finally {
      concurrent--;
    }
  }

  @override
  Future<void> open(Uri file) => command('open', () {
    if (failOpen) throw StateError('Synthetic open rejection');
    at = Duration.zero;
    active = false;
    positions.add(at);
    durations.add(length);
    plays.add(active);
    completions.add(false);
  });
  @override
  Future<void> play() => command('play', () {
    active = true;
    plays.add(true);
    if (eofOnPlay) eof();
  });
  @override
  Future<void> pause() => command('pause', () {
    active = false;
    plays.add(false);
  });
  @override
  Future<void> seek(Duration position) =>
      command('seek:${position.inSeconds}', () async {
        final gate = seekGate;
        seekGate = null;
        if (gate != null) await gate.future;
        at = position;
        positions.add(position);
        if (resetCompletionOnSeek) completions.add(false);
        if (eofOnSeek) eof();
      });
  @override
  Future<void> setRate(double rate) =>
      command('rate:$rate', () => speed = rate);
  @override
  Future<void> clearMedia() => command('clear', () async {
    if (clearGate != null) await clearGate!.future;
    if (failClear) throw StateError('Synthetic unload rejection');
    at = Duration.zero;
    active = false;
    positions.add(at);
    plays.add(false);
  });
  @override
  Future<void> dispose() => command('dispose', () async {
    disposals++;
    if (disposalGate != null) await disposalGate!.future;
    await Future.wait([
      positions.close(),
      durations.close(),
      plays.close(),
      buffers.close(),
      completions.close(),
      errors.close(),
    ]);
    if (failDispose) throw StateError('Synthetic disposal rejection');
  });

  void position(Duration value) {
    at = value;
    positions.add(value);
  }

  void eof() {
    active = false;
    plays.add(false);
    completions.add(true);
  }
}

void main() {
  late Directory directory;
  late File media;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('independent-playback-');
    media = await File('${directory.path}/sample.MP3')
        .writeAsString('synthetic');
  });
  tearDown(() async {
    await OfflinePlayback.closeAll();
    await directory.delete(recursive: true);
  });

  test(
    'local gate rejects unsupported locations before backend commands',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      for (final path in [
        'relative.mp3',
        'https://example.invalid/song.mp3',
        '//remote-host/movie.mp4',
        'file://host${media.path}',
        '${directory.path}/list.m3u',
      ]) {
        await expectLater(playback.openLocal(path), throwsArgumentError);
        expect(playback.busy, false);
      }
      for (final path in ['${directory.path}/absent.mp3', directory.path]) {
        await expectLater(
          playback.openLocal(path),
          throwsA(isA<FileSystemException>()),
        );
        expect(playback.busy, false);
      }
      expect(backend.calls, isEmpty);
      await playback.openLocal(media.uri.toString(), autoplay: false);
      expect(playback.localPath, media.path);
      expect(() => playback.player, throwsStateError);
    },
  );

  test(
    'opening preserves speed and active state and recovers from failure',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      expect(playback.playing, true);
      await playback.setRate(1.75);
      await playback.pause();
      await playback.setLoop(second, seconds(3));
      await playback.openLocal(media.path, position: seconds(99));
      expect(playback.playing, false);
      expect(playback.position, seconds(10));
      expect(playback.rate, 1.75);
      expect(backend.speed, 1.75);
      expect(playback.loop, isNull);
      backend.failOpen = true;
      await expectLater(playback.openLocal(media.path), throwsStateError);
      expect(playback.error, contains('Synthetic open'));
      expect(playback.busy, false);
      backend.failOpen = false;
      await playback.openLocal(media.path, autoplay: true);
      expect(playback.error, isNull);
      expect(playback.position, Duration.zero);
      expect(playback.playing, true);
    },
  );

  test(
    'commands need media and rate validation never changes backend',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await expectLater(playback.play(), throwsStateError);
      await expectLater(playback.seek(second), throwsStateError);
      for (final value in [double.nan, double.infinity, -1.0, 0.1, 4.1]) {
        await expectLater(playback.setRate(value), throwsArgumentError);
      }
      expect(backend.calls, isEmpty);
      await playback.openLocal(media.path, autoplay: false);
      await playback.seek(-second);
      expect(playback.position, Duration.zero);
      await playback.seek(seconds(100));
      expect(playback.position, seconds(10));
    },
  );

  test(
    'finite loops count once per boundary and restart their saved range',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setLoop(
        second,
        seconds(3),
        repeatCount: 3,
        completedPasses: 1,
      );
      backend.position(seconds(3));
      backend.position(seconds(3));
      backend.eof();
      await settle();
      expect(playback.loop!.completedPasses, 2);
      expect(playback.position, second);
      expect(playback.playing, true);
      backend.position(seconds(2));
      backend.position(seconds(3));
      backend.eof();
      await settle();
      expect(playback.loop!.completedPasses, 3);
      expect(playback.loop!.completed, true);
      expect(playback.position, seconds(3));
      expect(playback.playing, false);
      backend.eof();
      expect(playback.completedCount, 0);
      await playback.play();
      expect(playback.loop!.completedPasses, 0);
      expect(playback.position, second);
    },
  );

  test(
    'native EOF repeats an unfinished loop without playlist completion',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setLoop(seconds(8), seconds(15));
      expect(playback.loop!.end, seconds(10));
      backend.eof();
      backend.eof();
      await settle();
      expect(playback.loop!.completedPasses, 1);
      expect(playback.position, seconds(8));
      expect(playback.playing, true);
      backend.completions.add(true); // A delayed duplicate completion callback.
      await settle();
      expect(playback.loop!.completedPasses, 1);
      backend.position(seconds(9));
      backend.completions.add(false);
      backend.eof();
      await settle();
      expect(playback.loop!.completedPasses, 2);
      expect(playback.completedCount, 0);
    },
  );

  test(
    'explicit intent invalidates a rewind queued in the same stream turn',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setLoop(second, seconds(3));
      backend.calls.clear();
      backend.position(seconds(3));
      await playback.seek(seconds(7));
      await settle();
      expect(playback.position, seconds(7));
      expect(playback.loop, isNull);
      expect(backend.calls, ['seek:7']);
    },
  );

  test(
    'entered rewinds settle before unload and never resume after newer pause',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setLoop(second, seconds(3));
      final gate = Completer<void>();
      backend.seekGate = gate;
      backend.calls.clear();
      backend.position(seconds(3));
      await settle();
      expect(backend.calls, ['seek:1']);
      playback.clearLoop();
      expect(playback.loop, isNull);
      final pause = playback.pause();
      final unload = playback.clearMedia();
      await settle();
      expect(backend.calls, ['seek:1']);
      gate.complete();
      await Future.wait([pause, unload]);
      expect(backend.calls, ['seek:1', 'pause', 'clear']);
      expect(backend.maximumConcurrent, 1);
      expect(playback.localPath, isNull);
      backend.position(seconds(9));
      backend.eof();
      backend.errors.add('late error');
      expect(playback.position, Duration.zero);
      expect(playback.error, isNull);
      expect(playback.completedCount, 0);
    },
  );

  test(
    'failed unload keeps loaded state and retry ignores subsequent events',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      backend.failClear = true;
      await expectLater(playback.clearMedia(), throwsStateError);
      expect(playback.localPath, media.path);
      expect(playback.error, contains('Synthetic unload'));
      backend.position(seconds(4));
      expect(playback.position, seconds(4));
      backend.failClear = false;
      await playback.clearMedia();
      expect(playback.localPath, isNull);
      expect(playback.error, isNull);
    },
  );

  test(
    'natural EOF is monotonic and excludes pause, end seeks, and duplicate EOF',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      backend.eof();
      backend.eof();
      expect(playback.completedCount, 1);
      await playback.play();
      expect(playback.position, Duration.zero);
      backend.eof();
      expect(playback.completedCount, 2);
      await playback.play();
      await playback.pause();
      backend.eof();
      expect(playback.completedCount, 2);
      await playback.play();
      await playback.seek(seconds(10));
      backend.eof();
      expect(playback.completedCount, 2);
      await playback.openLocal(
        media.path,
        autoplay: false,
        position: seconds(10),
      );
      backend.eof();
      expect(playback.completedCount, 2);
      await playback.clearMedia();
      expect(playback.completedCount, 2);
    },
  );

  test('synchronous fresh completion inside play remains observable', () async {
    final backend = MemoryTransport()..eofOnPlay = true;
    final playback = OfflinePlayback.withTransport(backend);
    await playback.openLocal(media.path);
    expect(playback.completedCount, 1);
    expect(playback.playing, false);
    expect(playback.position, seconds(10));
    await playback.play();
    expect(playback.completedCount, 2);
    expect(playback.playing, false);
  });

  test(
    'native EOF-only loop passes finish and trailing EOF remains excluded',
    () async {
      final backend = MemoryTransport()
        ..length = seconds(60)
        ..resetCompletionOnSeek = false;
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setLoop(seconds(58), seconds(60), repeatCount: 2);
      backend.eof();
      await settle();
      expect(playback.loop!.completedPasses, 1);
      backend.eof();
      await settle();
      expect(playback.loop!.completed, true);
      expect(playback.playing, false);
      expect(playback.position, seconds(60));
      backend.eof();
      playback.clearLoop();
      backend.eof();
      expect(playback.completedCount, 0);
    },
  );

  test(
    'seek-generated EOF and its trailing duplicate cannot complete a run',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      backend.eofOnSeek = true;
      final seeking = playback.seek(seconds(100));
      backend.completions.add(true);
      expect(playback.completedCount, 0);
      await seeking;
      backend.eof();
      expect(playback.completedCount, 0);
      expect(playback.position, seconds(10));
      backend.eofOnSeek = false;
      await playback.play();
      backend.eof();
      expect(playback.completedCount, 1);
    },
  );

  test(
    'unload is busy until its gate resolves and reopening defaults to play',
    () async {
      final backend = MemoryTransport();
      final playback = OfflinePlayback.withTransport(backend);
      await playback.openLocal(media.path);
      await playback.setRate(1.5);
      await playback.pause();
      final gate = Completer<void>();
      backend.clearGate = gate;
      final clearing = playback.clearMedia();
      final reopening = playback.openLocal(media.path);
      await settle();
      expect(playback.busy, true);
      expect(backend.calls.last, 'clear');
      gate.complete();
      await clearing;
      await reopening;
      expect(playback.busy, false);
      expect(playback.playing, true);
      expect(playback.rate, 1.5);
      backend.eof();
      expect(playback.completedCount, 1);
    },
  );

  test('concurrent closes await one cleanup and global close attempts every instance', () async {
    final first = MemoryTransport()..disposalGate = Completer<void>();
    final second = MemoryTransport()..failDispose = true;
    final a = OfflinePlayback.withTransport(first);
    OfflinePlayback.withTransport(second);
    var finished = false;
    final closeA = a.close().then((_) => finished = true);
    final global = OfflinePlayback.closeAll();
    final globalExpectation = expectLater(global, throwsStateError);
    final sameGlobal = expectLater(
      OfflinePlayback.closeAll(),
      throwsStateError,
    );
    await settle();
    expect(finished, false);
    expect(first.disposals, 1);
    expect(second.disposals, 1);
    first.disposalGate!.complete();
    await closeA;
    await globalExpectation;
    await sameGlobal;
    await a.close();
    expect(first.disposals, 1);
    a.addListener(() {}); // Closing resources does not dispose the notifier.
    a.dispose();
    await OfflinePlayback.closeAll();
  });
}
