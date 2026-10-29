import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class AppleAudioTransport {
  Stream<Map<String, Object?>> get events;
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]);
  Future<void> close();
}

final class AppleAudioChannelTransport implements AppleAudioTransport {
  AppleAudioChannelTransport({MethodChannel? commands, EventChannel? events})
    : _commands = commands ?? const MethodChannel('offline_player/ios_audio'),
      _events = events ?? const EventChannel('offline_player/ios_audio_events');

  final MethodChannel _commands;
  final EventChannel _events;

  @override
  Stream<Map<String, Object?>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, Object?>.from(event as Map));

  @override
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final result = await _commands.invokeMapMethod<String, Object?>(
      command,
      arguments,
    );
    if (result == null) throw StateError('Native audio returned no state.');
    return result;
  }

  @override
  Future<void> close() async {}
}

@immutable
class AppleAudioCommandException implements Exception {
  const AppleAudioCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class AppleAudioLoop {
  const AppleAudioLoop({
    required this.start,
    required this.end,
    required this.completed,
    this.repeatCount,
    this.completedPasses = 0,
  });

  final Duration start;
  final Duration end;
  final int? repeatCount;
  final int completedPasses;
  final bool completed;

  factory AppleAudioLoop.fromMap(Map<String, Object?> value) => AppleAudioLoop(
    start: Duration(milliseconds: (value['startMs'] as num).round()),
    end: Duration(milliseconds: (value['endMs'] as num).round()),
    repeatCount: (value['repeatCount'] as num?)?.round(),
    completedPasses: (value['completedPasses'] as num?)?.round() ?? 0,
    completed: value['completed'] as bool? ?? false,
  );
}

class AppleAudioController extends ChangeNotifier {
  AppleAudioController({AppleAudioTransport? transport})
    : _transport = transport ?? AppleAudioChannelTransport() {
    _eventSubscription = _transport.events.listen(
      _receiveEvent,
      onError: (Object error) => _recordFailure(error),
    );
  }

  static const _extensions = {'mp3', 'm4a', 'aac', 'wav', 'caf', 'aiff', 'aif'};

  final AppleAudioTransport _transport;
  late final StreamSubscription<Map<String, Object?>> _eventSubscription;
  Future<void> _commands = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;
  int _pendingCommands = 0;
  String? _expectedPath;
  String? _path;
  String? _title;
  String? _error;
  String? _dismissedNativeError;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  double _rate = 1;
  double _volume = 100;
  AppleAudioLoop? _loop;
  DateTime? _stopAt;

  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get busy => _pendingCommands > 0;
  bool get buffering => _buffering;
  double get rate => _rate;
  double get volume => _volume;
  String? get path => _path;
  String? get title => _title;
  String? get error => _error;
  AppleAudioLoop? get loop => _loop;
  DateTime? get stopAt => _stopAt;

  Future<void> openLocal(
    String path, {
    required String title,
    Duration? position,
    bool autoplay = false,
  }) async {
    _requireOpenController();
    final file = await _localFile(path);
    final start = position ?? Duration.zero;
    if (start < Duration.zero) throw ArgumentError.value(position, 'position');
    await _enqueue(() async {
      _expectedPath = file.path;
      _error = null;
      _dismissedNativeError = null;
      try {
        final result = await _transport.invoke('open', {
          'path': file.path,
          'title': title,
          'positionMs': start.inMilliseconds,
          'rate': _rate,
          'autoplay': autoplay,
        });
        _applyCommandSnapshot(result);
        if (result['path'] != file.path) {
          throw StateError(
            'Native audio did not open the selected local file.',
          );
        }
      } catch (_) {
        _path = null;
        _title = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _playing = false;
        _buffering = false;
        _loop = null;
        rethrow;
      }
    });
  }

  Future<void> play() => _send('play');
  Future<void> pause() => _send('pause');
  Future<void> toggle() =>
      _enqueue(() => _invokeAndApply(_playing ? 'pause' : 'play'));

  Future<void> seek(Duration position) {
    if (position < Duration.zero) {
      return Future<void>.error(ArgumentError.value(position, 'position'));
    }
    return _send('seek', {'positionMs': position.inMilliseconds});
  }

  Future<void> setRate(double rate) {
    if (!rate.isFinite || rate < 0.25 || rate > 3) {
      return Future<void>.error(ArgumentError.value(rate, 'rate'));
    }
    return _send('setRate', {'rate': rate});
  }

  Future<void> setVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      return Future<void>.error(ArgumentError.value(volume, 'volume'));
    }
    return _send('setVolume', {'volume': volume});
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
    return _send('setLoop', {
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
      'repeatCount': repeatCount,
      'completedPasses': completedPasses,
    });
  }

  Future<void> clearLoop() => _send('clearLoop');

  Future<void> setStopAt(DateTime? value) =>
      _send('setStopAt', {'epochMs': value?.millisecondsSinceEpoch});

  Future<void> refresh() => _send('snapshot');

  void clearError() {
    _dismissedNativeError = _error;
    _error = null;
    _notify();
  }

  Future<void> _send(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) => _enqueue(() => _invokeAndApply(command, arguments));

  Future<void> _invokeAndApply(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async =>
      _applyCommandSnapshot(await _transport.invoke(command, arguments));

  void _applyCommandSnapshot(Map<String, Object?> value) {
    final nativeError = _snapshotError(value);
    if (nativeError != null) _dismissedNativeError = null;
    _applySnapshot(value);
    if (nativeError != null) throw AppleAudioCommandException(nativeError);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_closed) return Future<void>.error(StateError('Audio is closed.'));
    _pendingCommands++;
    _notify();
    final result = _commands.then((_) async {
      _requireOpenController();
      try {
        await operation();
      } catch (error) {
        _recordFailure(error);
        rethrow;
      }
    });
    _commands = result.catchError((Object _) {});
    return result.whenComplete(() {
      _pendingCommands--;
      _notify();
    });
  }

  void _receiveEvent(Map<String, Object?> value) {
    if (_closed) return;
    if (_expectedPath != null && value['path'] != _expectedPath) return;
    _applySnapshot(value);
  }

  void _applySnapshot(Map<String, Object?> value) {
    if (_closed) return;
    _path = value['path'] as String?;
    _expectedPath ??= _path;
    _title = value['title'] as String?;
    _position = Duration(
      milliseconds: (value['positionMs'] as num?)?.round() ?? 0,
    );
    _duration = Duration(
      milliseconds: (value['durationMs'] as num?)?.round() ?? 0,
    );
    _playing = value['playing'] as bool? ?? false;
    _buffering = value['buffering'] as bool? ?? false;
    _rate = (value['rate'] as num?)?.toDouble() ?? 1;
    _volume = (value['volume'] as num?)?.toDouble() ?? 100;
    final nativeError = _snapshotError(value);
    if (nativeError == null) _dismissedNativeError = null;
    _error = nativeError == _dismissedNativeError ? null : nativeError;
    final nativeLoop = value['loop'];
    _loop = nativeLoop is Map
        ? AppleAudioLoop.fromMap(Map<String, Object?>.from(nativeLoop))
        : null;
    final stopAtMs = value['stopAtEpochMs'] as num?;
    _stopAt = stopAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stopAtMs.round());
    _notify();
  }

  static String? _snapshotError(Map<String, Object?> value) {
    final error = value['error'] as String?;
    return error == null || error.trim().isEmpty ? null : error;
  }

  void _recordFailure(Object error) {
    if (_closed) return;
    _dismissedNativeError = null;
    _error = error is PlatformException
        ? error.message ?? error.code
        : error.toString();
    _notify();
  }

  void _requireOpenController() {
    if (_closed) throw StateError('Audio is closed.');
  }

  static Future<File> _localFile(String input) async {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        (uri.hasScheme && uri.scheme != 'file') ||
        (uri.scheme == 'file' && uri.host.isNotEmpty) ||
        input.startsWith('//')) {
      throw ArgumentError('Only local audio files are supported.');
    }
    final path = uri.scheme == 'file' ? uri.toFilePath() : input;
    if (!path.startsWith('/') ||
        !_extensions.contains(path.split('.').last.toLowerCase())) {
      throw ArgumentError('Select an absolute local audio file path.');
    }
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
      throw FileSystemException('Local audio file not found.', path);
    }
    return File(await File(path).resolveSymbolicLinks());
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _eventSubscription.cancel();
    await _commands;
    try {
      final result = await _transport.invoke('dispose');
      final error = _snapshotError(result);
      if (error != null) throw AppleAudioCommandException(error);
    } finally {
      await _transport.close();
    }
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
