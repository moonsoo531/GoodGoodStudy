import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// A value captured from the transport's current state.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.rate = 1,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double rate;
}

abstract interface class PlaybackTransport {
  Player? get nativePlayer;
  PlaybackSnapshot get snapshot;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;

  Future<void> open(Uri file);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

abstract interface class ClearablePlaybackTransport {
  Future<void> clearMedia();
}

/// Owns one native player and never replaces it when media changes.
class MediaKitPlaybackTransport
    implements PlaybackTransport, ClearablePlaybackTransport {
  MediaKitPlaybackTransport()
    : _player = Player(
        configuration: const PlayerConfiguration(
          libass: false,
          protocolWhitelist: ['file'],
        ),
      );

  final Player _player;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _closing = false;

  @override
  Player get nativePlayer => _player;

  @override
  PlaybackSnapshot get snapshot {
    final state = _player.state;
    return PlaybackSnapshot(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      rate: state.rate,
    );
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<bool> get completedStream => _player.stream.completed;
  @override
  Stream<String> get errorStream => _player.stream.error;

  Future<void> _submit(Future<void> Function() command) {
    if (_closing) {
      return Future<void>.error(StateError('The media transport is closed.'));
    }
    final result = _tail.then((_) => command());
    // Keep a successful queue tail even when the command's caller sees failure.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> open(Uri file) {
    if (file.scheme != 'file' ||
        file.authority.isNotEmpty ||
        !file.hasAbsolutePath ||
        file.hasQuery ||
        file.hasFragment) {
      return Future<void>.error(
        ArgumentError.value(
          file,
          'file',
          'An absolute local file URI is required.',
        ),
      );
    }
    return _submit(() async {
      // The reset removes both old metadata and media_kit's distinct-stream
      // history before listening for metadata from the next file.
      await _player.stop();
      await _disableSubtitleSelection();
      await _loadMetadata(file);
      await _player.setSubtitleTrack(SubtitleTrack.no());
    });
  }

  Future<void> _disableSubtitleSelection() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-auto', 'no');
    }
    await _player.setSubtitleTrack(SubtitleTrack.no());
  }

  Future<void> _loadMetadata(Uri file) async {
    final ready = Completer<void>();
    var sawDuration = false;
    var probing = false;

    void fail(Object error, [StackTrace? stack]) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    }

    Future<void> probe() async {
      if (ready.isCompleted || probing || !sawDuration) return;
      probing = true;
      try {
        final stateDuration = _player.state.duration;
        if (stateDuration <= Duration.zero) return;
        final platform = _player.platform;
        if (platform is NativePlayer) {
          final path = await platform.getProperty('path');
          if (!_matchesFile(path, file)) return;
          final seconds = double.tryParse(
            await platform.getProperty('duration'),
          );
          if (seconds == null || !seconds.isFinite || seconds <= 0) return;
          // The direct metadata query also guards against an old duration event
          // that was already in flight when the previous file was stopped.
          final streamSeconds = stateDuration.inMicroseconds / 1000000;
          if ((streamSeconds - seconds).abs() > 0.01) return;
        }
        if (!ready.isCompleted) ready.complete();
      } catch (error, stack) {
        fail(error, stack);
      } finally {
        probing = false;
      }
    }

    final durations = durationStream.listen((value) {
      if (value > Duration.zero) {
        sawDuration = true;
        unawaited(probe());
      }
    }, onError: fail);
    final errors = errorStream.listen((message) {
      fail(StateError('The decoder could not prepare this file: $message'));
    }, onError: fail);
    final timeout = Timer(const Duration(seconds: 15), () {
      fail(
        TimeoutException(
          'Local media metadata was not available.',
          const Duration(seconds: 15),
        ),
      );
    });
    final poll = Timer.periodic(const Duration(milliseconds: 40), (_) {
      unawaited(probe());
    });
    try {
      // Listen before submitting open: a backend is allowed to publish metadata
      // synchronously, and open completing alone does not establish readiness.
      await Future.wait<void>([
        ready.future,
        _player.open(Media(file.toString()), play: false),
      ], eagerError: true);
    } finally {
      timeout.cancel();
      poll.cancel();
      await durations.cancel();
      await errors.cancel();
    }
  }

  bool _matchesFile(String path, Uri file) {
    if (path.isEmpty) return false;
    try {
      final uri = Uri.parse(path);
      final actual = uri.scheme == 'file' ? File.fromUri(uri).path : path;
      return actual == File.fromUri(file).path;
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  @override
  Future<void> play() => _submit(_player.play);
  @override
  Future<void> pause() => _submit(_player.pause);
  @override
  Future<void> seek(Duration position) => _submit(() => _player.seek(position));
  @override
  Future<void> setRate(double rate) => _submit(() => _player.setRate(rate));
  @override
  Future<void> clearMedia() => _submit(_player.stop);

  @override
  Future<void> dispose() {
    final existing = _disposal;
    if (existing != null) return existing;
    _closing = true;
    return _disposal = _tail.then((_) => _player.dispose());
  }
}
