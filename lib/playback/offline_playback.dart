import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_transport.dart';

class PlaybackLoop {
  const PlaybackLoop({
    required this.start,
    required this.end,
    this.repeatCount,
    this.completedPasses = 0,
  });

  final Duration start;
  final Duration end;
  final int? repeatCount;
  final int completedPasses;

  bool get completed => repeatCount != null && completedPasses >= repeatCount!;

  PlaybackLoop nextPass() => PlaybackLoop(
    start: start,
    end: end,
    repeatCount: repeatCount,
    completedPasses: completedPasses + 1,
  );

  PlaybackLoop restart() =>
      PlaybackLoop(start: start, end: end, repeatCount: repeatCount);
}

class OfflinePlayback extends ChangeNotifier {
  OfflinePlayback() : this.withTransport(MediaKitPlaybackTransport());

  @visibleForTesting
  OfflinePlayback.withTransport(this._transport) {
    _readSnapshot();
    _subscriptions.addAll([
      _transport.positionStream.listen(_receivePosition),
      _transport.durationStream.listen((value) {
        if (_ignoreMediaEvents) return;
        _duration = value;
        _notify();
      }),
      _transport.playingStream.listen((value) {
        if (_ignoreMediaEvents) return;
        _playing = value;
        _notify();
      }),
      _transport.bufferingStream.listen((value) {
        if (_ignoreMediaEvents) return;
        _buffering = value;
        _notify();
      }),
      _transport.completedStream.listen(_receiveCompletion),
      _transport.errorStream.listen((value) {
        if (_ignoreMediaEvents) return;
        _completionArmed = false;
        _error = value;
        _notify();
      }),
    ]);
    _instances.add(this);
  }

  static final Set<OfflinePlayback> _instances = {};

  /// Releases every live playback backend before the application exits.
  ///
  /// Instances remain registered until their close attempt finishes, so this
  /// also waits for owners that have already started closing their players.
  /// Every backend is attempted before the first failure is reported. Owners
  /// still dispose their own ChangeNotifier after removing their listeners.
  static Future<void> closeAll() async {
    await Future.wait<void>([
      for (final playback in _instances.toList(growable: false))
        playback.close(),
    ]);
  }

  static const _mediaExtensions = {
    'mp3',
    'mp4',
    'm4a',
    'm4v',
    'mkv',
    'mov',
    'wav',
    'flac',
    'aac',
    'aiff',
    'aif',
    'ogg',
    'opus',
    'webm',
    'avi',
    'wma',
    'wmv',
    'mpg',
    'mpeg',
    'ts',
    'm2ts',
    'caf',
    'alac',
  };

  final PlaybackTransport _transport;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _commands = Future<void>.value();
  Future<void>? _closing;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _busy = false;
  bool _disposed = false;
  bool _opening = false;
  bool _loopPending = false;
  bool _completionArmed = false;
  bool _ignoreMediaEvents = false;
  int _completedCount = 0;
  double _rate = 1;
  String? _localPath;
  String? _error;
  PlaybackLoop? _loop;
  int _loopEpoch = 0;

  Player get player =>
      _transport.nativePlayer ??
      (throw StateError('This playback transport has no native player.'));

  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  bool get busy => _busy;
  double get rate => _rate;
  String? get localPath => _localPath;
  String? get error => _error;
  PlaybackLoop? get loop => _loop;

  /// Increases once when a playing media file reaches its natural end.
  ///
  /// Explicit pauses, seeking to the end, and sentence/A–B loops do not count.
  /// This counter persists across opens so a playlist can listen for changes.
  int get completedCount => _completedCount;

  Future<void> openLocal(
    String path, {
    Duration? position,
    bool? autoplay,
  }) async {
    final file = await _resolveLocalMedia(path);
    _completionArmed = false;
    _loopEpoch++;
    await _execute(() async {
      final shouldPlay = autoplay ?? (_localPath == null || _playing);
      final savedRate = _rate;
      _opening = true;
      _ignoreMediaEvents = false;
      _busy = true;
      _error = null;
      _loop = null;
      _loopPending = false;
      _notify();
      try {
        await _transport.open(file.uri);
        _localPath = file.path;
        _readSnapshot();
        await _transport.setRate(savedRate);
        _rate = savedRate;
        final target = _bounded(position ?? Duration.zero);
        if (target > Duration.zero) await _transport.seek(target);
        _position = target;
        if (shouldPlay) {
          _completionArmed = true;
          await _transport.play();
        } else {
          await _transport.pause();
        }
        _playing = shouldPlay;
      } catch (_) {
        _completionArmed = false;
        _localPath = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _playing = false;
        rethrow;
      } finally {
        _opening = false;
        _busy = false;
        _notify();
      }
    });
  }

  Future<void> play() => _execute(_play);

  Future<void> _play() async {
    _requireMedia();
    final currentLoop = _loop;
    if (currentLoop != null && currentLoop.completed) {
      _loopEpoch++;
      _loop = currentLoop.restart();
      await _transport.seek(currentLoop.start);
      _position = currentLoop.start;
    } else if (_duration > Duration.zero && _position >= _duration) {
      await _transport.seek(Duration.zero);
      _position = Duration.zero;
    }
    _completionArmed = true;
    await _transport.play();
    _playing = true;
    _notify();
  }

  Future<void> pause() {
    _completionArmed = false;
    return _execute(_pause);
  }

  /// Unloads the current media while retaining this player and its speed.
  ///
  /// Natural completion and queued loop rewinds are invalidated immediately.
  /// An optional transport capability releases the native media file; older
  /// transports fall back to pausing. Late stop events cannot restore the
  /// cleared timeline, and a later [openLocal] enables media events again.
  Future<void> clearMedia() {
    _completionArmed = false;
    _loopEpoch++;
    return _execute(() async {
      final wasIgnoring = _ignoreMediaEvents;
      _ignoreMediaEvents = true;
      _completionArmed = false;
      _busy = true;
      _loop = null;
      _loopPending = false;
      _notify();
      try {
        final transport = _transport;
        if (transport case final ClearablePlaybackTransport clearable) {
          await clearable.clearMedia();
        } else {
          await transport.pause();
        }
        _localPath = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _playing = false;
        _buffering = false;
        _error = null;
      } catch (_) {
        // A failed unload must not pretend that the file has been released.
        _ignoreMediaEvents = wasIgnoring;
        rethrow;
      } finally {
        _busy = false;
        _notify();
      }
    });
  }

  Future<void> _pause() async {
    _completionArmed = false;
    await _transport.pause();
    _playing = false;
    _notify();
  }

  Future<void> toggle() {
    if (_playing) _completionArmed = false;
    return _execute(() => _playing ? _pause() : _play());
  }

  Future<void> seek(Duration target) {
    _loopEpoch++;
    if (_duration > Duration.zero && target >= _duration) {
      _completionArmed = false;
    }
    return _execute(() async {
      _requireMedia();
      final bounded = _bounded(target);
      if (_duration > Duration.zero && bounded >= _duration) {
        _completionArmed = false;
      }
      final currentLoop = _loop;
      if (currentLoop != null &&
          (bounded < currentLoop.start || bounded >= currentLoop.end)) {
        _loop = null;
      }
      await _transport.seek(bounded);
      _position = bounded;
      _notify();
    });
  }

  Future<void> setRate(double value) {
    if (!value.isFinite || value < 0.25 || value > 4) {
      return Future<void>.error(
        ArgumentError.value(value, 'rate', 'Use a rate between 0.25 and 4.'),
      );
    }
    return _execute(() async {
      await _transport.setRate(value);
      _rate = value;
      _notify();
    });
  }

  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) {
    if (start < Duration.zero ||
        end <= start ||
        completedPasses < 0 ||
        (repeatCount != null &&
            (repeatCount < 1 || completedPasses >= repeatCount))) {
      return Future<void>.error(ArgumentError('Invalid playback loop.'));
    }
    final epoch = ++_loopEpoch;
    return _execute(() async {
      _requireMedia();
      final boundedEnd = _bounded(end);
      if (boundedEnd <= start) {
        throw ArgumentError('Loop starts after the end of this media.');
      }
      if (epoch != _loopEpoch) return;
      _loop = PlaybackLoop(
        start: start,
        end: boundedEnd,
        repeatCount: repeatCount,
        completedPasses: completedPasses,
      );
      await _transport.seek(start);
      _position = start;
      _notify();
    });
  }

  void clearLoop() {
    _loopEpoch++;
    _loop = null;
    _notify();
  }

  void clearError() {
    _error = null;
    _notify();
  }

  void _receivePosition(Duration value) {
    if (_disposed || _ignoreMediaEvents) return;
    _position = value;
    _enforceLoop(value);
    _notify();
  }

  void _receiveCompletion(bool completed) {
    if (!completed || _disposed || _opening || _ignoreMediaEvents) return;
    final currentLoop = _loop;
    if (currentLoop != null) {
      if (!currentLoop.completed) {
        _enforceLoop(currentLoop.end, completed: true);
      } else {
        _completionArmed = false;
        _playing = false;
        _notify();
      }
    } else {
      if (_completionArmed && _localPath != null) {
        _completionArmed = false;
        _completedCount++;
      }
      _playing = false;
      _notify();
    }
  }

  void _enforceLoop(Duration value, {bool completed = false}) {
    final currentLoop = _loop;
    if (_opening ||
        _loopPending ||
        currentLoop == null ||
        currentLoop.completed ||
        (!_playing && !completed) ||
        value < currentLoop.end) {
      return;
    }
    final epoch = _loopEpoch;
    _loopPending = true;
    unawaited(
      _execute(() async {
        if (_disposed || epoch != _loopEpoch) return;
        final advanced = currentLoop.nextPass();
        _loop = advanced;
        if (advanced.completed) {
          _completionArmed = false;
          await _transport.pause();
          if (epoch != _loopEpoch) return;
          _playing = false;
          await _transport.seek(advanced.end);
          _position = advanced.end;
        } else {
          await _transport.seek(advanced.start);
          if (epoch != _loopEpoch) return;
          _position = advanced.start;
          if (completed) {
            await _transport.play();
            _playing = true;
          }
        }
        _notify();
      }).catchError((Object _) {}).whenComplete(() {
        _loopPending = false;
      }),
    );
  }

  Duration _bounded(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    if (_duration > Duration.zero && target > _duration) return _duration;
    return target;
  }

  void _requireMedia() {
    if (_localPath == null) throw StateError('Open a local media file first.');
  }

  void _readSnapshot() {
    final snapshot = _transport.snapshot;
    _position = snapshot.position;
    _duration = snapshot.duration;
    _playing = snapshot.playing;
    _buffering = snapshot.buffering;
    _rate = snapshot.rate;
  }

  Future<void> _execute(Future<void> Function() operation) {
    final result = _commands.then((_) async {
      if (_disposed) throw StateError('Playback has been disposed.');
      try {
        await operation();
      } catch (error) {
        _completionArmed = false;
        _error = error.toString();
        _notify();
        rethrow;
      }
    });
    _commands = result.catchError((Object _) {});
    return result;
  }

  static Future<File> _resolveLocalMedia(String input) async {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        (uri.hasScheme && uri.scheme != 'file') ||
        (uri.scheme == 'file' &&
            uri.host.isNotEmpty &&
            uri.host != 'localhost') ||
        input.startsWith('//')) {
      throw ArgumentError('Only local media files are supported.');
    }
    final path = uri.scheme == 'file' ? uri.toFilePath() : input;
    if (!path.startsWith('/')) {
      throw ArgumentError('Select a media file using its absolute local path.');
    }
    final extension = path.split('.').last.toLowerCase();
    if (!_mediaExtensions.contains(extension)) {
      throw ArgumentError('Unsupported media extension: $extension.');
    }
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
      throw FileSystemException('Local media file not found.', path);
    }
    return File(await File(path).resolveSymbolicLinks());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> close() {
    return _closing ??= _close();
  }

  Future<void> _close() async {
    _disposed = true;
    _loopEpoch++;
    try {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      await _commands;
      await _transport.dispose();
    } finally {
      _instances.remove(this);
    }
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
