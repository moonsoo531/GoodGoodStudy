import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../library/local_library.dart';
import 'offline_playback.dart';

abstract interface class MediaDurationProbe {
  Future<Duration> readDuration(String localPath);
  Future<void> close();
}

/// Reads unknown local media durations one at a time, independently from the
/// foreground player. Updating the queue never interrupts playback or seeks it.
class MediaMetadataReader {
  MediaMetadataReader({
    required void Function(LocalLesson lesson, Duration duration) onDuration,
  }) : this.withProbe(_NativeMediaDurationProbe(), onDuration);

  @visibleForTesting
  MediaMetadataReader.withProbe(this._probe, this._onDuration);

  final MediaDurationProbe _probe;
  final void Function(LocalLesson lesson, Duration duration) _onDuration;
  Map<String, _MetadataRequest> _wanted = {};
  final Map<String, _MetadataRequest> _pending = {};
  final Map<String, int> _attempted = {};
  Future<void>? _running;
  Future<void>? _closing;
  int _generation = 0;
  String? _activePath;
  int? _activeGeneration;
  bool _suspended = false;
  bool _disposed = false;

  bool get suspended => _suspended;
  bool get busy => _running != null;

  /// Completes when the currently active drain stops, including suspension.
  /// A suspended queue that has not started is already idle.
  Future<void> get whenIdle => _running ?? Future<void>.value();

  /// Supply only lessons whose duration is unknown. Repeated calls deduplicate
  /// each normalized path, including failures, until that item is removed and
  /// added again. A removed/re-added path gets a fresh generation so results
  /// from an earlier in-flight read cannot update a replacement queue item.
  void updateQueue(Iterable<LocalLesson> lessons) {
    if (_disposed) return;
    final next = <String, _MetadataRequest>{};
    for (final lesson in lessons) {
      final path = _localMediaPath(lesson.primaryPath);
      if (path == null || next.containsKey(path)) continue;
      next[path] = _MetadataRequest(
        lesson,
        path,
        _wanted[path]?.generation ?? _generation++,
      );
    }
    _wanted = next;
    _attempted.removeWhere((path, _) => !next.containsKey(path));
    _pending.clear();
    for (final request in next.values) {
      if (_attempted[request.path] == request.generation ||
          (_activePath == request.path &&
              _activeGeneration == request.generation)) {
        continue;
      }
      _pending[request.path] = request;
    }
    _start();
  }

  /// The current read may finish; no later item starts until resumed.
  void setSuspended(bool suspended) {
    if (_disposed || _suspended == suspended) return;
    _suspended = suspended;
    if (!suspended) _start();
  }

  void _start() {
    if (_disposed || _suspended || _running != null || _pending.isEmpty) return;
    final running = _drain();
    _running = running;
    unawaited(
      running.whenComplete(() {
        _running = null;
        _start();
      }),
    );
  }

  Future<void> _drain() async {
    while (!_disposed && !_suspended && _pending.isNotEmpty) {
      final path = _pending.keys.first;
      final request = _pending.remove(path)!;
      _activePath = path;
      _activeGeneration = request.generation;
      _attempted[path] = request.generation;
      try {
        final duration = await _probe.readDuration(path);
        final current = _wanted[path];
        if (!_disposed &&
            current?.generation == request.generation &&
            duration > Duration.zero) {
          _onDuration(current!.lesson, duration);
        }
      } catch (_) {
        // Missing, unsupported and unreadable files must not block the rest of
        // the queue. The foreground player retains its normal error reporting.
      } finally {
        _activePath = null;
        _activeGeneration = null;
      }
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _disposed = true;
    _pending.clear();
    _wanted.clear();
    return _closing = _close();
  }

  Future<void> _close() async {
    await _running;
    await _probe.close();
  }

  void dispose() {
    unawaited(close().catchError((Object _) {}));
  }
}

class _MetadataRequest {
  const _MetadataRequest(this.lesson, this.path, this.generation);
  final LocalLesson lesson;
  final String path;
  final int generation;
}

String? _localMediaPath(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null ||
      (uri.hasScheme && uri.scheme != 'file') ||
      (uri.scheme == 'file' &&
          uri.host.isNotEmpty &&
          uri.host != 'localhost') ||
      input.startsWith('//')) {
    return null;
  }
  try {
    final path = uri.scheme == 'file' ? uri.toFilePath() : input;
    if (!path.startsWith('/') || path.startsWith('//')) return null;
    final extension = extensionOf(path);
    if (!audioExtensions.contains(extension) &&
        !videoExtensions.contains(extension)) {
      return null;
    }
    return File(path).absolute.uri.normalizePath().toFilePath();
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

/// Uses the existing metadata-ready wait and local-file validation. A separate
/// player is created lazily, without VideoController, output windows or sound.
class _NativeMediaDurationProbe implements MediaDurationProbe {
  OfflinePlayback? _playback;
  bool _closed = false;

  @override
  Future<Duration> readDuration(String localPath) async {
    if (_closed) throw StateError('Metadata reader is closed.');
    final path = _localMediaPath(localPath);
    if (path == null) {
      throw ArgumentError('Only local media files are supported.');
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Metadata requires a local regular file.',
        path,
      );
    }
    final playback = _playback ??= OfflinePlayback();
    final player = playback.player;
    final native = player.platform;
    if (native is! NativePlayer) {
      throw UnsupportedError('Headless metadata requires the native backend.');
    }

    // Both streams disabled prevents libmpv from publishing a duration for
    // some files. Select streams but keep outputs null, muted and paused;
    // this allows demuxing metadata without starting continuous playback.
    await native.setProperty('vo', 'null');
    await native.setProperty('ao', 'null');
    await native.setProperty('pause', 'yes');
    await native.setProperty('cache', 'no');
    await native.setProperty('demuxer-lavf-o', 'protocol_whitelist=[file]');
    // Player.open uses a local loadlist, which access-references=no would
    // reject as well. Permit safe local playlist references while keeping
    // remote protocols excluded at the entrance and the lavf layer.
    await native.setProperty('load-unsafe-playlists', 'no');
    await player.setVolume(0);
    await player.setVideoTrack(VideoTrack.auto());
    await player.setAudioTrack(AudioTrack.auto());
    await player.setSubtitleTrack(SubtitleTrack.no());
    try {
      await playback.openLocal(path, autoplay: false);
      return playback.duration;
    } finally {
      // Release the probed file and demuxer cache before the next foreground
      // playback phase, rather than retaining one more paused media handle.
      await playback.clearMedia();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final playback = _playback;
    if (playback != null) {
      await playback.close();
      playback.dispose();
    }
  }
}
