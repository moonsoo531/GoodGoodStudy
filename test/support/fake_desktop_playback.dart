import 'dart:async';

import 'package:media_kit/media_kit.dart' show Player;
import 'package:offline_player/playback/playback_transport.dart';

class FakeDesktopPlaybackTransport implements PlaybackTransport {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);
  final attempted = <Uri>[];
  final opened = <Uri>[];
  final seeks = <Duration>[];
  final failures = <String, Object>{};
  final durations = <String, Duration>{};
  void Function(Duration)? onSeek;
  Duration currentPosition = Duration.zero;
  Duration currentDuration = const Duration(minutes: 2);
  bool currentPlaying = false;
  double currentRate = 1;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;

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

  void finish() {
    emitPosition(currentDuration);
    emitPlaying(false);
    _completed.add(true);
  }

  @override
  Future<void> open(Uri file) async {
    attempted.add(file);
    final failure = failures[file.toFilePath()];
    if (failure != null) throw failure;
    opened.add(file);
    currentPosition = Duration.zero;
    currentDuration =
        durations[file.toFilePath()] ?? const Duration(minutes: 2);
    currentPlaying = false;
    currentRate = 1;
    _durations.add(currentDuration);
  }

  @override
  Future<void> play() async {
    playCount++;
    emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    onSeek?.call(position);
    seeks.add(position);
    emitPosition(position);
  }

  @override
  Future<void> setRate(double rate) async => currentRate = rate;

  @override
  Future<void> dispose() async {
    if (disposeCount++ > 0) return;
    await Future.wait([
      _positions.close(),
      _durations.close(),
      _playing.close(),
      _buffering.close(),
      _completed.close(),
      _errors.close(),
    ]);
  }
}
