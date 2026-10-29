import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/playback/playback_transport.dart';

void main() {
  late Directory temporary;
  late File audio;
  late File video;
  late FakeTransport transport;
  late OfflinePlayback playback;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('offline-playback-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    audio = await File('${temporary.path}/台詞.mp3').writeAsBytes([0]);
    video = await File('${temporary.path}/映像.mkv').writeAsBytes([0]);
    transport = FakeTransport();
    playback = OfflinePlayback.withTransport(transport);
  });

  tearDown(() async {
    await playback.close();
    playback.dispose();
    await temporary.delete(recursive: true);
  });

  Future<ClearableFakeTransport> useClearableTransport() async {
    await playback.close();
    playback.dispose();
    final clearable = ClearableFakeTransport();
    transport = clearable;
    playback = OfflinePlayback.withTransport(clearable);
    return clearable;
  }

  test(
    'rejects network sources and playlists before touching the backend',
    () async {
      for (final source in [
        'https://example.org/audio.mp3',
        'http://example.org/movie.mkv',
        'smb://host/video.mp4',
        'file://remote-host/movie.mp4',
        '//remote-host/movie.mp4',
        'memory://file.mp3',
        '${temporary.path}/remote.m3u8',
        'audio.mp3',
      ]) {
        await expectLater(playback.openLocal(source), throwsArgumentError);
      }
      expect(transport.opened, isEmpty);
      expect(playback.localPath, isNull);
    },
  );

  test('requires an existing regular local file', () async {
    await expectLater(
      playback.openLocal('${temporary.path}/missing.mp3'),
      throwsA(isA<FileSystemException>()),
    );
    final directory = await Directory('${temporary.path}/folder.mp3').create();
    await expectLater(
      playback.openLocal(directory.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(transport.opened, isEmpty);
  });

  test(
    'accepts file URIs and retains paused state and speed during media switch',
    () async {
      await playback.openLocal(audio.uri.toString());
      expect(playback.playing, isTrue);
      await playback.setRate(1.5);
      await playback.pause();
      await playback.openLocal(
        video.path,
        position: const Duration(seconds: 12),
      );
      expect(transport.opened, [audio.uri, video.uri]);
      expect(playback.localPath, video.path);
      expect(playback.position, const Duration(seconds: 12));
      expect(playback.rate, 1.5);
      expect(transport.currentRate, 1.5);
      expect(playback.playing, isFalse);
    },
  );

  test(
    'preserves playing state across audio and video without a second player',
    () async {
      await playback.openLocal(
        video.path,
        position: const Duration(seconds: 22),
      );
      await playback.setRate(0.75);
      await playback.openLocal(audio.path, position: playback.position);
      expect(playback.playing, isTrue);
      expect(playback.position, const Duration(seconds: 22));
      expect(playback.rate, 0.75);
      expect(transport.opened.length, 2);
    },
  );

  test(
    'loops once per media boundary and stops at the requested total pass count',
    () async {
      await playback.openLocal(audio.path);
      await playback.setLoop(
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        repeatCount: 3,
      );
      transport.seeks.clear();
      transport.emitPosition(const Duration(milliseconds: 3999));
      await settle();
      expect(transport.seeks, isEmpty);
      for (var pass = 1; pass <= 3; pass++) {
        transport.emitPosition(const Duration(seconds: 4));
        transport.emitPosition(const Duration(milliseconds: 4100));
        await settle();
        expect(playback.loop!.completedPasses, pass);
      }
      expect(transport.seeks, [
        const Duration(seconds: 2),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      expect(playback.playing, isFalse);
      expect(playback.loop!.completed, isTrue);
      await playback.play();
      expect(playback.loop!.completedPasses, 0);
      expect(playback.position, const Duration(seconds: 2));
    },
  );

  test('restores two completed passes across media switch and stops after one more', () async {
    await playback.openLocal(video.path);
    await playback.setLoop(
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      repeatCount: 3,
    );
    for (var pass = 0; pass < 2; pass++) {
      transport.emitPosition(const Duration(seconds: 4));
      await settle();
    }
    final savedLoop = playback.loop!;
    expect(savedLoop.completedPasses, 2);
    await playback.openLocal(audio.path, position: playback.position);
    await playback.setLoop(
      savedLoop.start,
      savedLoop.end,
      repeatCount: savedLoop.repeatCount,
      completedPasses: savedLoop.completedPasses,
    );
    transport.seeks.clear();
    transport.emitPosition(const Duration(seconds: 4));
    await settle();
    expect(playback.loop!.completedPasses, 3);
    expect(playback.loop!.completed, isTrue);
    expect(playback.playing, isFalse);
    expect(transport.seeks, [const Duration(seconds: 4)]);
  });

  test(
    'infinite loops follow media time independently of playback speed',
    () async {
      await playback.openLocal(audio.path);
      await playback.setRate(2);
      await playback.setLoop(
        const Duration(seconds: 10),
        const Duration(seconds: 11),
      );
      transport.seeks.clear();
      for (var pass = 0; pass < 4; pass++) {
        transport.emitPosition(const Duration(seconds: 11));
        await settle();
      }
      expect(transport.seeks, List.filled(4, const Duration(seconds: 10)));
      expect(playback.loop!.completedPasses, 4);
      expect(playback.playing, isTrue);
      expect(playback.rate, 2);
    },
  );

  test(
    'clear invalidates queued loop rewind so it cannot affect the next media',
    () async {
      await playback.openLocal(audio.path);
      await playback.setLoop(
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      );
      transport.seeks.clear();
      transport.emitPosition(const Duration(seconds: 4));
      playback.clearLoop();
      await playback.openLocal(
        video.path,
        position: const Duration(seconds: 30),
      );
      await settle();
      expect(playback.loop, isNull);
      expect(playback.position, const Duration(seconds: 30));
      expect(transport.seeks, [const Duration(seconds: 30)]);
    },
  );

  test('end-of-file resumes an active infinite loop', () async {
    await playback.openLocal(audio.path);
    await playback.setLoop(
      const Duration(seconds: 58),
      const Duration(seconds: 60),
    );
    transport.emitPlaying(false);
    transport.emitCompleted();
    await settle();
    expect(playback.position, const Duration(seconds: 58));
    expect(playback.playing, isTrue);
    expect(playback.loop!.completedPasses, 1);
    expect(playback.completedCount, 0);
  });

  test(
    'natural completion counts once even when playing false arrives first',
    () async {
      transport.emitCompleted();
      expect(playback.completedCount, 0);
      await playback.openLocal(audio.path);
      transport.emitPosition(const Duration(seconds: 60));
      transport.emitPlaying(false);
      transport.emitCompleted();
      transport.emitCompleted();
      expect(playback.completedCount, 1);
      expect(playback.playing, isFalse);

      await playback.play();
      expect(playback.position, Duration.zero);
      transport.emitPosition(const Duration(seconds: 60));
      transport.emitCompleted();
      expect(playback.completedCount, 2);

      await playback.openLocal(video.path);
      expect(playback.completedCount, 2);
      await playback.play();
      transport.emitCompleted();
      expect(playback.completedCount, 3);
    },
  );

  test(
    'restored pauses and requested pauses do not count as completion',
    () async {
      await playback.openLocal(audio.path, autoplay: false);
      transport.emitCompleted();
      expect(playback.completedCount, 0);
      await playback.play();
      final pause = playback.pause();
      // The completion event can race a pause waiting in the command queue.
      transport.emitCompleted();
      await pause;
      transport.emitCompleted();
      expect(playback.completedCount, 0);
    },
  );

  test('seeking to the end does not advance the playlist', () async {
    await playback.openLocal(audio.path);
    final seek = playback.seek(const Duration(seconds: 80));
    transport.emitCompleted();
    await seek;
    transport.emitCompleted();
    expect(playback.completedCount, 0);
    await playback.play();
    transport.emitPosition(const Duration(seconds: 60));
    transport.emitCompleted();
    expect(playback.completedCount, 1);
  });

  test(
    'finite loops ending at end-of-file never count as media completion',
    () async {
      await playback.openLocal(audio.path);
      await playback.setLoop(
        const Duration(seconds: 58),
        const Duration(seconds: 60),
        repeatCount: 2,
      );
      for (var pass = 0; pass < 2; pass++) {
        transport.emitPlaying(false);
        transport.emitCompleted();
        await settle();
      }
      expect(playback.loop!.completed, isTrue);
      expect(playback.playing, isFalse);
      transport.emitCompleted();
      playback.clearLoop();
      transport.emitCompleted();
      expect(playback.completedCount, 0);
    },
  );

  test(
    'opening metadata and decoder errors do not signal completion',
    () async {
      await playback.openLocal(audio.path);
      transport.completeDuringOpen = true;
      await playback.openLocal(video.path, autoplay: false);
      expect(playback.completedCount, 0);
      await playback.play();
      transport.emitError('decoder failed');
      transport.emitCompleted();
      expect(playback.completedCount, 0);
    },
  );

  test(
    'seeking outside an active loop clears it and clamps to media duration',
    () async {
      await playback.openLocal(audio.path);
      await playback.setLoop(
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      );
      await playback.seek(const Duration(seconds: 80));
      expect(playback.loop, isNull);
      expect(playback.position, const Duration(seconds: 60));
      await playback.seek(const Duration(seconds: -2));
      expect(playback.position, Duration.zero);
    },
  );

  test(
    'rejects invalid rates and loops without changing current settings',
    () async {
      await playback.openLocal(audio.path);
      for (final rate in [0.0, -1.0, double.nan, double.infinity, 4.1]) {
        await expectLater(playback.setRate(rate), throwsArgumentError);
      }
      await expectLater(
        playback.setLoop(
          const Duration(seconds: 4),
          const Duration(seconds: 2),
        ),
        throwsArgumentError,
      );
      await expectLater(
        playback.setLoop(
          Duration.zero,
          const Duration(seconds: 2),
          repeatCount: 0,
        ),
        throwsArgumentError,
      );
      for (final completedPasses in [-1, 3, 4]) {
        await expectLater(
          playback.setLoop(
            Duration.zero,
            const Duration(seconds: 2),
            repeatCount: 3,
            completedPasses: completedPasses,
          ),
          throwsArgumentError,
        );
      }
      expect(playback.rate, 1);
      expect(playback.loop, isNull);
    },
  );

  test(
    'reports backend failures and recovers on the next local open',
    () async {
      transport.openFailure = StateError('decoder failed');
      await expectLater(playback.openLocal(video.path), throwsStateError);
      expect(playback.busy, isFalse);
      expect(playback.error, contains('decoder failed'));
      transport.openFailure = null;
      await playback.openLocal(audio.path);
      expect(playback.error, isNull);
      expect(playback.playing, isTrue);
    },
  );

  test('clear unloads media, resets timeline and errors, but preserves player and speed', () async {
    final clearable = await useClearableTransport();
    await playback.openLocal(audio.path);
    await playback.setRate(1.5);
    clearable.emitPosition(const Duration(seconds: 12));
    clearable.emitBuffering(true);
    clearable.emitError('old decoder error');
    expect(clearable.resourceLoaded, isTrue);

    await playback.clearMedia();
    expect(clearable.clearCount, 1);
    expect(clearable.resourceLoaded, isFalse);
    expect(clearable.disposeCount, 0);
    expect(playback.localPath, isNull);
    expect(playback.position, Duration.zero);
    expect(playback.duration, Duration.zero);
    expect(playback.playing, isFalse);
    expect(playback.buffering, isFalse);
    expect(playback.busy, isFalse);
    expect(playback.error, isNull);
    expect(playback.loop, isNull);
    expect(playback.rate, 1.5);
  });

  test(
    'clear cancels queued loop rewinds and ignores late media events',
    () async {
      final clearable = await useClearableTransport();
      await playback.openLocal(audio.path);
      await playback.setLoop(
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      );
      clearable.seeks.clear();
      clearable.emitPosition(const Duration(seconds: 4));
      final clearing = playback.clearMedia();
      clearable.emitCompleted();
      await clearing;
      await settle();
      expect(clearable.seeks, isEmpty);
      expect(playback.loop, isNull);
      expect(playback.completedCount, 0);

      clearable.emitPosition(const Duration(seconds: 59));
      clearable.emitDuration(const Duration(seconds: 60));
      clearable.emitPlaying(true);
      clearable.emitBuffering(true);
      clearable.emitError('late stop error');
      clearable.emitCompleted();
      expect(playback.localPath, isNull);
      expect(playback.position, Duration.zero);
      expect(playback.duration, Duration.zero);
      expect(playback.playing, isFalse);
      expect(playback.buffering, isFalse);
      expect(playback.error, isNull);
      expect(playback.completedCount, 0);
    },
  );

  test(
    'cleared player opens again with its saved rate and receives new events',
    () async {
      final clearable = await useClearableTransport();
      await playback.openLocal(audio.path);
      await playback.setRate(1.75);
      await playback.clearMedia();
      expect(
        clearable.currentRate,
        1,
        reason: 'The backend may reset settings on stop.',
      );
      expect(playback.rate, 1.75);
      await playback.openLocal(
        video.path,
        position: const Duration(seconds: 8),
      );
      expect(playback.localPath, video.path);
      expect(playback.position, const Duration(seconds: 8));
      expect(playback.duration, const Duration(seconds: 60));
      expect(playback.playing, isTrue);
      expect(playback.rate, 1.75);
      expect(clearable.currentRate, 1.75);
      expect(clearable.resourceLoaded, isTrue);
      clearable.emitPosition(const Duration(seconds: 10));
      expect(playback.position, const Duration(seconds: 10));
      clearable.emitCompleted();
      expect(playback.completedCount, 1);
    },
  );

  test('clear falls back to pause for an existing transport without unload support', () async {
    expect(transport, isNot(isA<ClearablePlaybackTransport>()));
    await playback.openLocal(audio.path);
    await playback.setRate(.75);
    final pauses = transport.pauseCount;
    await playback.clearMedia();
    expect(transport.pauseCount, pauses + 1);
    expect(transport.disposeCount, 0);
    expect(playback.localPath, isNull);
    expect(playback.position, Duration.zero);
    expect(playback.duration, Duration.zero);
    expect(playback.rate, .75);
    transport.emitCompleted();
    expect(playback.completedCount, 0);
    await playback.openLocal(video.path, autoplay: false);
    expect(playback.localPath, video.path);
    expect(playback.playing, isFalse);
    expect(playback.rate, .75);
  });

  test(
    'clear finishes releasing resources before the next queued open starts',
    () async {
      final clearable = await useClearableTransport();
      await playback.openLocal(audio.path);
      final gate = Completer<void>();
      clearable.clearGate = gate;
      final clearing = playback.clearMedia();
      final opening = playback.openLocal(video.path, autoplay: false);
      await settle();
      expect(playback.busy, isTrue);
      expect(clearable.clearCount, 1);
      expect(clearable.opened, [audio.uri]);
      expect(clearable.resourceLoaded, isTrue);
      gate.complete();
      await clearing;
      await opening;
      expect(clearable.opened, [audio.uri, video.uri]);
      expect(playback.localPath, video.path);
      expect(playback.playing, isFalse);
      expect(clearable.disposeCount, 0);
    },
  );

  test('failed clear reports failure without pretending the file is released and can retry', () async {
    final clearable = await useClearableTransport();
    await playback.openLocal(audio.path);
    clearable.clearFailure = StateError('stop failed');
    await expectLater(playback.clearMedia(), throwsStateError);
    expect(playback.localPath, audio.path);
    expect(clearable.resourceLoaded, isTrue);
    expect(playback.busy, isFalse);
    expect(playback.error, contains('stop failed'));
    clearable.emitPosition(const Duration(seconds: 9));
    expect(playback.position, const Duration(seconds: 9));
    clearable.clearFailure = null;
    await playback.clearMedia();
    expect(playback.localPath, isNull);
    expect(clearable.resourceLoaded, isFalse);
    expect(playback.error, isNull);
  });

  test('clear preserves the monotonic natural-completion counter', () async {
    final clearable = await useClearableTransport();
    await playback.openLocal(audio.path);
    clearable.emitCompleted();
    expect(playback.completedCount, 1);
    await playback.clearMedia();
    clearable.emitCompleted();
    expect(playback.completedCount, 1);
    await playback.openLocal(video.path);
    clearable.emitCompleted();
    expect(playback.completedCount, 2);
  });

  test(
    'close releases stream listeners and the backend exactly once',
    () async {
      await playback.openLocal(audio.path);
      await playback.close();
      await playback.close();
      expect(transport.disposeCount, 1);
      await expectLater(playback.play(), throwsStateError);
    },
  );

  test(
    'closeAll closes three players once and leaves notifier disposal to owners',
    () async {
      final secondTransport = FakeTransport();
      final thirdTransport = FakeTransport();
      final second = OfflinePlayback.withTransport(secondTransport);
      final third = OfflinePlayback.withTransport(thirdTransport);
      addTearDown(second.dispose);
      addTearDown(third.dispose);
      await playback.openLocal(audio.path);
      await second.openLocal(video.path);
      await third.openLocal(audio.path);

      await OfflinePlayback.closeAll();
      await OfflinePlayback.closeAll();
      expect(transport.disposeCount, 1);
      expect(secondTransport.disposeCount, 1);
      expect(thirdTransport.disposeCount, 1);
      void listener() {}
      for (final player in [playback, second, third]) {
        expect(() => player.addListener(listener), returnsNormally);
        player.removeListener(listener);
        await expectLater(player.play(), throwsStateError);
      }
    },
  );

  test('concurrent closeAll waits for an instance already closing', () async {
    final gate = Completer<void>();
    transport.disposeGate = gate;
    final manualClose = playback.close();
    await settle();
    expect(transport.disposeCount, 1);
    var firstFinished = false;
    var secondFinished = false;
    final first = OfflinePlayback.closeAll().then((_) => firstFinished = true);
    final second = OfflinePlayback.closeAll().then(
      (_) => secondFinished = true,
    );
    await settle();
    expect(firstFinished, isFalse);
    expect(secondFinished, isFalse);
    expect(transport.disposeCount, 1);

    gate.complete();
    await Future.wait([manualClose, first, second]);
    expect(firstFinished, isTrue);
    expect(secondFinished, isTrue);
    expect(transport.disposeCount, 1);
  });

  test('closeAll waits for other players after failure and forgets failed instances', () async {
    final failure = StateError('native player shutdown failed');
    final failingTransport = FakeTransport()..disposeFailure = failure;
    final gate = Completer<void>();
    final slowTransport = FakeTransport()..disposeGate = gate;
    final failing = OfflinePlayback.withTransport(failingTransport);
    final slow = OfflinePlayback.withTransport(slowTransport);
    addTearDown(failing.dispose);
    addTearDown(slow.dispose);
    var finished = false;
    final shutdown = OfflinePlayback.closeAll();
    final assertion = expectLater(shutdown, throwsA(same(failure)));
    final observed = shutdown.then<void>(
      (_) => finished = true,
      onError: (Object _, StackTrace _) {
        finished = true;
      },
    );
    await settle();
    expect(transport.disposeCount, 1);
    expect(failingTransport.disposeCount, 1);
    expect(slowTransport.disposeCount, 1);
    expect(finished, isFalse);

    gate.complete();
    await assertion;
    await observed;
    expect(finished, isTrue);
    await OfflinePlayback.closeAll();
    expect(failingTransport.disposeCount, 1);
    expect(slowTransport.disposeCount, 1);

    final laterTransport = FakeTransport();
    final later = OfflinePlayback.withTransport(laterTransport);
    addTearDown(later.dispose);
    await OfflinePlayback.closeAll();
    expect(laterTransport.disposeCount, 1);
  });
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

class FakeTransport implements PlaybackTransport {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);
  final List<Uri> opened = [];
  final List<Duration> seeks = [];
  Duration currentPosition = Duration.zero;
  Duration currentDuration = const Duration(seconds: 60);
  bool currentPlaying = false;
  double currentRate = 1;
  Object? openFailure;
  bool completeDuringOpen = false;
  Completer<void>? disposeGate;
  Object? disposeFailure;
  int disposeCount = 0;
  int pauseCount = 0;

  @override
  Player? get nativePlayer => null;

  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    position: currentPosition,
    duration: currentDuration,
    playing: currentPlaying,
    rate: currentRate,
  );

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<String> get errorStream => _errors.stream;

  void emitPosition(Duration value) {
    currentPosition = value;
    _positions.add(value);
  }

  void emitPlaying(bool value) {
    currentPlaying = value;
    _playing.add(value);
  }

  void emitCompleted() => _completed.add(true);

  void emitError(String message) => _errors.add(message);

  void emitDuration(Duration value) {
    currentDuration = value;
    _durations.add(value);
  }

  void emitBuffering(bool value) => _buffering.add(value);

  @override
  Future<void> open(Uri file) async {
    if (openFailure != null) throw openFailure!;
    opened.add(file);
    currentPosition = Duration.zero;
    currentRate = 1;
    currentPlaying = false;
    _durations.add(currentDuration);
    if (completeDuringOpen) emitCompleted();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPlaying(false);
  }

  @override
  Future<void> play() async => emitPlaying(true);
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    emitPosition(position);
  }

  @override
  Future<void> setRate(double rate) async => currentRate = rate;

  @override
  Future<void> dispose() async {
    disposeCount++;
    final gate = disposeGate;
    if (gate != null) await gate.future;
    await Future.wait([
      _positions.close(),
      _durations.close(),
      _playing.close(),
      _buffering.close(),
      _completed.close(),
      _errors.close(),
    ]);
    final failure = disposeFailure;
    if (failure != null) throw failure;
  }
}

class ClearableFakeTransport extends FakeTransport
    implements ClearablePlaybackTransport {
  int clearCount = 0;
  bool resourceLoaded = false;
  Completer<void>? clearGate;
  Object? clearFailure;

  @override
  Future<void> open(Uri file) async {
    currentDuration = const Duration(seconds: 60);
    await super.open(file);
    resourceLoaded = true;
  }

  @override
  Future<void> clearMedia() async {
    clearCount++;
    final failure = clearFailure;
    if (failure != null) throw failure;
    emitPlaying(false);
    emitBuffering(false);
    emitCompleted();
    final gate = clearGate;
    if (gate != null) await gate.future;
    resourceLoaded = false;
    currentRate = 1;
    emitPosition(Duration.zero);
    emitDuration(Duration.zero);
  }
}
