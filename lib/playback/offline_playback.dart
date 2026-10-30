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

/// Local playback coordinated through one ordered command lane.
///
/// Stream observations update presentation state. User intent and boundary work
/// have separate identities, so an asynchronous rewind cannot revive old intent.
class OfflinePlayback extends ChangeNotifier {
  OfflinePlayback() : this.withTransport(MediaKitPlaybackTransport());

  OfflinePlayback.withTransport(PlaybackTransport transport)
    : _transport = transport {
    _live.add(this);
    _subscriptions.addAll([
      transport.positionStream.listen(_observePosition),
      transport.durationStream.listen(_observeDuration),
      transport.playingStream.listen(_observePlaying),
      transport.bufferingStream.listen(_observeBuffering),
      transport.completedStream.listen(_observeCompletion),
      transport.errorStream.listen(_observeError),
    ]);
  }

  static final Set<OfflinePlayback> _live = {};
  static Future<void>? _globalClose;
  static const _extensions = {
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
  Future<void> _lane = Future<void>.value();
  Future<void>? _closeFuture;
  bool _notifierDisposed = false;
  bool _acceptEvents = false;
  bool _runIntent = false;
  bool _naturalEligible = false;
  bool _naturalEnded = false;
  bool _completionConsumed = false;
  bool _completionHigh = false;
  bool _boundaryPending = false;
  bool _suppressCompletionUntilProgress = false;
  int _intentVersion = 0;
  int _transitionDepth = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _busy = false;
  double _rate = 1;
  String? _localPath;
  String? _error;
  PlaybackLoop? _loop;
  int _completedCount = 0;

  Player get player =>
      _transport.nativePlayer ??
      (throw StateError('This playback transport has no video player.'));
  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  bool get busy => _busy;
  double get rate => _rate;
  String? get localPath => _localPath;
  String? get error => _error;
  PlaybackLoop? get loop => _loop;
  int get completedCount => _completedCount;

  void _changed() {
    if (!_notifierDisposed && _closeFuture == null) notifyListeners();
  }

  Future<void> _schedule(Future<void> Function() action) {
    if (_closeFuture != null || _notifierDisposed) {
      return Future<void>.error(StateError('Playback has been closed.'));
    }
    final result = _lane.then((_) async {
      try {
        await action();
      } catch (failure) {
        _error = failure.toString();
        _naturalEligible = false;
        _changed();
        rethrow;
      }
    });
    // The shared lane always settles successfully, independently of whether a
    // caller observes its command's result.
    _lane = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _requireMedia() {
    if (_localPath == null) throw StateError('Open local media first.');
  }

  Duration _bounded(Duration value) {
    if (value.isNegative) return Duration.zero;
    if (_duration > Duration.zero && value > _duration) return _duration;
    return value;
  }

  static Future<File> _localFile(String input) async {
    if (input.startsWith('//')) {
      throw ArgumentError.value(
        input,
        'path',
        'Network-style file authorities are unsupported.',
      );
    }
    File file;
    if (input.startsWith('/')) {
      file = File(input);
    } else {
      final uri = Uri.tryParse(input);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'file' ||
          uri.host.isNotEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.hasFragment ||
          !uri.path.startsWith('/')) {
        throw ArgumentError.value(
          input,
          'path',
          'An absolute local file is required.',
        );
      }
      file = File.fromUri(uri);
    }
    if (!file.isAbsolute) {
      throw ArgumentError.value(
        input,
        'path',
        'An absolute local file is required.',
      );
    }
    final basename = file.path.split(Platform.pathSeparator).last;
    final fileType = await FileSystemEntity.type(file.path);
    if (fileType == FileSystemEntityType.directory) {
      throw FileSystemException('The media path names a directory.', file.path);
    }
    final dot = basename.lastIndexOf('.');
    if (dot < 0 ||
        !_extensions.contains(basename.substring(dot + 1).toLowerCase())) {
      throw ArgumentError.value(input, 'path', 'Unsupported media file type.');
    }
    if (fileType != FileSystemEntityType.file) {
      throw FileSystemException('The media file does not exist.', file.path);
    }
    return file;
  }

  Future<void> openLocal(String path, {Duration? position, bool? autoplay}) {
    _intentVersion++;
    return _schedule(() async {
      _busy = true;
      _error = null;
      _changed();
      var backendEntered = false;
      try {
        final file = await _localFile(path);
        final shouldPlay = autoplay ?? (_localPath == null || _runIntent);
        _acceptEvents = false;
        _runIntent = false;
        _naturalEligible = false;
        _loop = null;
        _naturalEnded = false;
        _completionConsumed = false;
        _completionHigh = false;
        _suppressCompletionUntilProgress = false;
        backendEntered = true;
        await _transport.open(file.uri);
        _duration = _nonnegative(_transport.snapshot.duration);
        final destination = _bounded(position ?? Duration.zero);
        await _transport.setRate(_rate);
        await _transport.seek(destination);
        _localPath = file.path;
        _position = destination;
        _playing = shouldPlay;
        _buffering = _transport.snapshot.buffering;
        _runIntent = shouldPlay;
        _naturalEligible =
            shouldPlay &&
            (_duration == Duration.zero || destination < _duration);
        _acceptEvents = _closeFuture == null;
        if (shouldPlay) {
          await _transport.play();
        } else if (_transport.snapshot.playing) {
          await _transport.pause();
        }
      } catch (_) {
        if (backendEntered) {
          _resetMedia();
        }
        rethrow;
      } finally {
        _busy = false;
        _changed();
      }
    });
  }

  Future<void> play() {
    _intentVersion++;
    return _schedule(_playNow);
  }

  Future<void> _playNow() async {
    _requireMedia();
    _transitionDepth++;
    try {
      final selected = _loop;
      if (selected != null && selected.completed) {
        _loop = selected.restart();
        await _transport.seek(selected.start);
        _position = selected.start;
      } else if (selected != null && _position >= selected.end) {
        await _transport.seek(selected.start);
        _position = selected.start;
      } else if (_naturalEnded ||
          (_duration > Duration.zero && _position >= _duration)) {
        await _transport.seek(Duration.zero);
        _position = Duration.zero;
      }
    } finally {
      _transitionDepth--;
    }
    _completionConsumed = false;
    _completionHigh = false;
    _naturalEnded = false;
    _suppressCompletionUntilProgress = false;
    _runIntent = true;
    _naturalEligible = true;
    _playing = true;
    _error = null;
    await _transport.play();
    _changed();
  }

  Future<void> pause() {
    _intentVersion++;
    _runIntent = false;
    _naturalEligible = false;
    return _schedule(_pauseNow);
  }

  Future<void> _pauseNow() async {
    _requireMedia();
    await _transport.pause();
    _playing = false;
    _runIntent = false;
    _naturalEligible = false;
    _changed();
  }

  Future<void> toggle() {
    _intentVersion++;
    if (_playing) {
      _runIntent = false;
      _naturalEligible = false;
    }
    return _schedule(() => _playing ? _pauseNow() : _playNow());
  }

  Future<void> seek(Duration target) {
    _intentVersion++;
    // Invalidate natural completion before the queued native seek starts.
    _naturalEligible = false;
    return _schedule(() async {
      _requireMedia();
      final destination = _bounded(target);
      final selected = _loop;
      if (selected != null &&
          !selected.completed &&
          (destination < selected.start || destination >= selected.end)) {
        _loop = null;
      }
      _transitionDepth++;
      _naturalEligible = false;
      try {
        await _transport.seek(destination);
        _position = destination;
        _completionConsumed = false;
        _completionHigh = false;
        _naturalEnded = false;
        _suppressCompletionUntilProgress = false;
        _naturalEligible =
            _runIntent &&
            (_duration == Duration.zero || destination < _duration);
      } finally {
        _transitionDepth--;
        _changed();
      }
    });
  }

  Future<void> setRate(double value) {
    if (!value.isFinite || value < 0.25 || value > 4) {
      return Future<void>.error(
        ArgumentError.value(value, 'value', 'Rate must be between 0.25 and 4.'),
      );
    }
    return _schedule(() async {
      await _transport.setRate(value);
      _rate = value;
      _changed();
    });
  }

  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) {
    _intentVersion++;
    return _schedule(() async {
      _requireMedia();
      if (start.isNegative ||
          end <= start ||
          (repeatCount != null && repeatCount < 1) ||
          completedPasses < 0 ||
          (repeatCount != null && completedPasses >= repeatCount)) {
        throw ArgumentError('The loop range and pass count must be positive.');
      }
      final boundedEnd = _bounded(end);
      if (boundedEnd <= start) {
        throw ArgumentError('The loop starts beyond this media.');
      }
      final selected = PlaybackLoop(
        start: start,
        end: boundedEnd,
        repeatCount: repeatCount,
        completedPasses: completedPasses,
      );
      _transitionDepth++;
      try {
        await _transport.seek(start);
        _position = start;
        _loop = selected;
        _completionConsumed = false;
        _completionHigh = false;
        _naturalEnded = false;
        _suppressCompletionUntilProgress = false;
      } finally {
        _transitionDepth--;
        _changed();
      }
    });
  }

  void clearLoop() {
    _intentVersion++;
    _loop = null;
    _changed();
  }

  void clearError() {
    _error = null;
    _changed();
  }

  Future<void> clearMedia() {
    _intentVersion++;
    _runIntent = false;
    _naturalEligible = false;
    return _schedule(() async {
      _busy = true;
      _changed();
      _transitionDepth++;
      try {
        final backend = _transport;
        if (backend is ClearablePlaybackTransport) {
          await (backend as ClearablePlaybackTransport).clearMedia();
        } else {
          await backend.pause();
        }
        _resetMedia();
        _error = null;
      } finally {
        _transitionDepth--;
        _busy = false;
        _changed();
      }
    });
  }

  void _resetMedia() {
    _acceptEvents = false;
    _localPath = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _buffering = false;
    _loop = null;
    _runIntent = false;
    _naturalEligible = false;
    _naturalEnded = false;
    _completionConsumed = false;
    _completionHigh = false;
    _suppressCompletionUntilProgress = false;
  }

  static Duration _nonnegative(Duration value) =>
      value.isNegative ? Duration.zero : value;

  void _observePosition(Duration value) {
    if (!_acceptEvents) return;
    _position = _nonnegative(value);
    final selected = _loop;
    if (_transitionDepth == 0 && selected != null && !selected.completed) {
      if (_position > selected.start && _position < selected.end) {
        _suppressCompletionUntilProgress = false;
      }
      if (_position >= selected.end && _runIntent) _requestBoundary();
    }
    _changed();
  }

  void _observeDuration(Duration value) {
    if (!_acceptEvents) return;
    _duration = _nonnegative(value);
    _changed();
  }

  void _observePlaying(bool value) {
    if (!_acceptEvents) return;
    // A fresh stop edge after a resumed loop is enough evidence of the next
    // native EOF even if the backend emits no intermediate position samples.
    if (!value &&
        _playing &&
        _transitionDepth == 0 &&
        !_boundaryPending &&
        _loop != null &&
        !_loop!.completed) {
      _suppressCompletionUntilProgress = false;
      _completionHigh = false;
    }
    _playing = value;
    _changed();
  }

  void _observeBuffering(bool value) {
    if (!_acceptEvents) return;
    _buffering = value;
    _changed();
  }

  void _observeCompletion(bool value) {
    if (!_acceptEvents) return;
    if (!value) {
      _completionHigh = false;
      return;
    }
    if (_completionHigh) return;
    _completionHigh = true;
    if (_transitionDepth != 0) return;
    final selected = _loop;
    if (selected != null) {
      if (!selected.completed &&
          _runIntent &&
          !_suppressCompletionUntilProgress) {
        _requestBoundary();
      }
      return;
    }
    if (!_runIntent || !_naturalEligible || _completionConsumed) return;
    _completionConsumed = true;
    _naturalEligible = false;
    _naturalEnded = true;
    _runIntent = false;
    _playing = false;
    if (_duration > Duration.zero) _position = _duration;
    _completedCount++;
    _changed();
  }

  void _observeError(String value) {
    if (!_acceptEvents) return;
    _error = value;
    _naturalEligible = false;
    _changed();
  }

  void _requestBoundary() {
    if (_boundaryPending || _closeFuture != null) return;
    final selected = _loop;
    if (selected == null || selected.completed) return;
    final version = _intentVersion;
    _boundaryPending = true;
    final work = _schedule(() async {
      if (version != _intentVersion ||
          !identical(_loop, selected) ||
          !_runIntent ||
          !_acceptEvents) {
        return;
      }
      final advanced = selected.nextPass();
      _loop = advanced;
      _transitionDepth++;
      _suppressCompletionUntilProgress = true;
      try {
        if (advanced.completed) {
          _runIntent = false;
          _naturalEligible = false;
          await _transport.pause();
          if (version != _intentVersion || !identical(_loop, advanced)) return;
          await _transport.seek(advanced.end);
          _position = advanced.end;
          _playing = false;
        } else {
          await _transport.seek(advanced.start);
          if (version != _intentVersion ||
              !identical(_loop, advanced) ||
              !_runIntent) {
            return;
          }
          _position = advanced.start;
          await _transport.play();
          _playing = true;
        }
      } finally {
        _transitionDepth--;
        _changed();
      }
    });
    unawaited(
      work.then<void>(
        (_) {
          _boundaryPending = false;
        },
        onError: (Object _, StackTrace _) {
          _boundaryPending = false;
        },
      ),
    );
  }

  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _intentVersion++;
    _acceptEvents = false;
    _runIntent = false;
    _naturalEligible = false;
    final completer = Completer<void>();
    _closeFuture = completer.future;
    unawaited(
      _closeWork().then<void>(
        completer.complete,
        onError: (Object error, StackTrace trace) =>
            completer.completeError(error, trace),
      ),
    );
    return completer.future;
  }

  Future<void> _closeWork() async {
    Object? failure;
    StackTrace? trace;
    try {
      await _lane;
      await Future.wait(
        _subscriptions.map((subscription) async {
          try {
            await subscription.cancel();
          } catch (error, stack) {
            failure ??= error;
            trace ??= stack;
          }
        }),
      );
      try {
        await _transport.dispose();
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    } finally {
      _live.remove(this);
    }
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  }

  static Future<void> closeAll() {
    final current = _globalClose;
    if (current != null) return current;
    final completer = Completer<void>();
    _globalClose = completer.future;
    unawaited(
      _closeEveryInstance().then<void>(
        (_) {
          _globalClose = null;
          completer.complete();
        },
        onError: (Object error, StackTrace trace) {
          _globalClose = null;
          completer.completeError(error, trace);
        },
      ),
    );
    return completer.future;
  }

  static Future<void> _closeEveryInstance() async {
    Object? failure;
    StackTrace? trace;
    while (_live.isNotEmpty) {
      final batch = List<OfflinePlayback>.of(_live);
      await Future.wait(
        batch.map((instance) async {
          try {
            await instance.close();
          } catch (error, stack) {
            failure ??= error;
            trace ??= stack;
          }
        }),
      );
    }
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
