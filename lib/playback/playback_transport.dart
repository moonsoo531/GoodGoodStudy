import 'dart:async';

import 'package:media_kit/media_kit.dart';

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

/// Optional capability for unloading media without disposing the player.
/// Transports without it can still be cleared at the controller level by
/// pausing, while native transports can additionally release file resources.
abstract interface class ClearablePlaybackTransport {
  Future<void> clearMedia();
}

final class MediaKitPlaybackTransport
    implements PlaybackTransport, ClearablePlaybackTransport {
  MediaKitPlaybackTransport() : _player = Player();

  static const _openTimeout = Duration(seconds: 15);

  final Player _player;

  @override
  Player get nativePlayer => _player;

  @override
  PlaybackSnapshot get snapshot => PlaybackSnapshot(
    position: _player.state.position,
    duration: _player.state.duration,
    playing: _player.state.playing,
    buffering: _player.state.buffering,
    rate: _player.state.rate,
  );

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

  @override
  Future<void> open(Uri file) async {
    final native = _player.platform;
    if (native is NativePlayer) {
      // External SRT/VTT belongs to the app's ruby/timeline renderer. Avoid
      // exposing an automatically loaded sidecar as a second embedded track.
      await native.setProperty('sub-auto', 'no');
    }
    final media = Media(file.toString());
    final ready = Completer<void>();
    var resetSeen = false;
    var checkingSource = false;
    final durationSubscription = _player.stream.duration.listen((
      duration,
    ) async {
      if (duration == Duration.zero) {
        resetSeen = true;
        return;
      }
      if (!resetSeen ||
          duration < Duration.zero ||
          ready.isCompleted ||
          checkingSource) {
        return;
      }
      checkingSource = true;
      try {
        final native = _player.platform;
        if (native is NativePlayer) {
          final path = await native.getProperty(
            'path',
            waitForInitialization: false,
          );
          if (Media.normalizeURI(path) != media.uri) return;
        }
        if (!ready.isCompleted) ready.complete();
      } catch (error, stackTrace) {
        if (!ready.isCompleted) ready.completeError(error, stackTrace);
      } finally {
        checkingSource = false;
      }
    });
    final errorSubscription = _player.stream.error.listen((error) {
      if (resetSeen && error.isNotEmpty && !ready.isCompleted) {
        ready.completeError(StateError(error));
      }
    });
    final metadataReady = ready.future.timeout(
      _openTimeout,
      onTimeout: () => throw TimeoutException(
        'Local media metadata did not become ready.',
        _openTimeout,
      ),
    );
    try {
      await Future.wait<void>([
        _player.open(media, play: false),
        metadataReady,
      ], eagerError: true);
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } finally {
      await durationSubscription.cancel();
      await errorSubscription.cancel();
      if (!ready.isCompleted) {
        ready.completeError(StateError('Local media open was cancelled.'));
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> clearMedia() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
