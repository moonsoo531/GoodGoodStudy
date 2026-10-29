import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'media_history.dart';

enum LocalStateStatus { unread, ready, recovered, blocked }

class LocalStateReadException implements Exception {
  const LocalStateReadException({
    required this.path,
    required this.cause,
    this.backupCause,
  });

  final String path;
  final Object cause;
  final Object? backupCause;

  @override
  String toString() => '无法恢复播放记录，已停止自动保存以保留原记录。原文件和备份均不会被覆盖。';
}

class LocalStateWriteBlockedException implements Exception {
  const LocalStateWriteBlockedException(this.readError);

  final LocalStateReadException? readError;

  @override
  String toString() => '播放记录尚未成功读取，已阻止保存以保护原记录。';
}

/// Serializes desktop player records, preserving a validated `.bak` copy.
/// Failed reads block writes until a later successful read, so an error
/// handler's empty page state cannot destroy recoverable records.
class LocalStateStore {
  LocalStateStore({Directory? directory, File? file})
    : assert(directory == null || file == null),
      _directory = directory,
      _file = file;

  final Directory? _directory;
  File? _file;
  Future<void> _pending = Future.value();
  LocalStateStatus _status = LocalStateStatus.unread;
  LocalStateReadException? _readError;
  String? _lastGoodEncoded;
  String? _recoveryMessage;
  final List<String> _preservedCorruptPaths = [];
  static int _fileSequence = 0;

  LocalStateStatus get status => _status;
  bool get canWrite =>
      _status == LocalStateStatus.ready ||
      _status == LocalStateStatus.recovered;
  String? get recoveryMessage => _recoveryMessage;
  List<String> get preservedCorruptPaths =>
      List.unmodifiable(_preservedCorruptPaths);

  Future<File> _location() async {
    if (_file != null) return _file!;
    final directory = _directory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return _file = File('${directory.path}/offline-player-state.json');
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Map<String, dynamic>?> read() => _serialize(_readGuarded);

  /// Waits for reads/writes already enqueued when called. Individual operation
  /// errors remain on their returned futures; flushing does not unblock a
  /// failed read or attempt to replace protected records.
  Future<void> flush() => _pending;

  Future<Map<String, dynamic>?> _readGuarded() async {
    try {
      return await _readState();
    } on LocalStateReadException {
      rethrow;
    } catch (error) {
      _status = LocalStateStatus.blocked;
      throw _readError = LocalStateReadException(
        path: _file?.path ?? _directory?.path ?? 'offline-player-state.json',
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>?> _readState() async {
    final file = await _location();
    final backup = File('${file.path}.bak');
    final hasPrimary = await file.exists();
    final hasBackup = await backup.exists();
    if (!hasPrimary && !hasBackup) {
      _status = LocalStateStatus.ready;
      _readError = null;
      _lastGoodEncoded = null;
      _recoveryMessage = null;
      return null;
    }

    Object? primaryError;
    if (hasPrimary) {
      try {
        final encoded = await file.readAsString();
        final state = _decode(encoded);
        _lastGoodEncoded = encoded;
        _status = LocalStateStatus.ready;
        _readError = null;
        _recoveryMessage = null;
        return state;
      } catch (error) {
        primaryError = error;
      }
    } else {
      primaryError = const FileSystemException(
        'The primary record is missing.',
      );
    }

    try {
      final encoded = await backup.readAsString();
      final state = _decode(encoded);
      if (hasPrimary) await _preserveCorrupt(file);
      await _replaceAtomically(file, encoded);
      _lastGoodEncoded = encoded;
      _status = LocalStateStatus.recovered;
      _readError = null;
      _recoveryMessage = hasPrimary
          ? '播放记录读取失败，已从最近的正常备份恢复；原文件已保留。'
          : '播放记录文件缺失，已从最近的正常备份恢复。';
      return state;
    } catch (backupError) {
      _status = LocalStateStatus.blocked;
      throw _readError = LocalStateReadException(
        path: file.path,
        cause: primaryError,
        backupCause: backupError,
      );
    }
  }

  Future<void> write(Map<String, dynamic> state) {
    // Snapshot before enqueueing, so caller mutations cannot change this write.
    late final String encoded;
    try {
      encoded = jsonEncode(state);
      _decode(encoded);
    } catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
    return _serialize(() async {
      if (_status == LocalStateStatus.unread) await _readGuarded();
      if (!canWrite) throw LocalStateWriteBlockedException(_readError);
      final file = await _location();
      await file.parent.create(recursive: true);
      final backup = File('${file.path}.bak');

      var previous = _lastGoodEncoded;
      if (await file.exists()) {
        try {
          final onDisk = await file.readAsString();
          _decode(onDisk);
          previous = onDisk;
        } on FormatException {
          // Do not rotate a malformed primary over the last good backup.
          await _preserveCorrupt(file);
        }
      }
      if (await backup.exists()) {
        try {
          _decode(await backup.readAsString());
        } on FormatException {
          await _preserveCorrupt(backup);
        }
      }
      await _replaceAtomically(backup, previous ?? encoded);
      await _replaceAtomically(file, encoded);
      _lastGoodEncoded = encoded;
    });
  }

  Future<void> _preserveCorrupt(File file) async {
    final suffix =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}'
        '-${_fileSequence++}';
    final preserved = await file.copy('${file.path}.corrupt-$suffix');
    _preservedCorruptPaths.add(preserved.path);
  }

  Future<void> _replaceAtomically(File destination, String encoded) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp-$pid-${_fileSequence++}');
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Map<String, dynamic> _decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Player state must be a JSON object.');
    }
    final lessons = value['lessons'];
    if (lessons != null) {
      if (lessons is! List) {
        throw const FormatException('Player lessons must be a list.');
      }
      for (final lesson in lessons) {
        if (lesson is! Map<String, dynamic> ||
            lesson['title'] is! String ||
            !_optionalPath(lesson['video']) ||
            !_optionalPath(lesson['audio']) ||
            !_optionalString(lesson['subtitle']) ||
            !(_nonemptyString(lesson['video']) ||
                _nonemptyString(lesson['audio']))) {
          throw const FormatException('A player lesson has an invalid shape.');
        }
      }
    }
    for (final key in ['current', 'subtitlePath']) {
      if (!_optionalString(value[key])) {
        throw FormatException('Player $key must be a string or null.');
      }
    }
    for (final key in ['positionMs', 'offsetMs']) {
      if (value[key] != null && value[key] is! int) {
        throw FormatException('Player $key must be an integer.');
      }
    }
    for (final key in ['rate', 'fontSize', 'subtitleBottom', 'volume']) {
      final setting = value[key];
      if (setting != null && (setting is! num || !setting.isFinite)) {
        throw FormatException('Player $key must be a finite number.');
      }
    }
    for (final key in [
      'showReadings',
      'audioMode',
      'showPlaylist',
      'autoAdvance',
      'showSubtitles',
      'showVideoSubtitles',
      'showListSubtitles',
    ]) {
      if (value[key] != null && value[key] is! bool) {
        throw FormatException('Player $key must be a boolean.');
      }
    }
    final rate = value['rate'] as num?;
    final volume = value['volume'] as num?;
    final fontSize = value['fontSize'] as num?;
    final bottom = value['subtitleBottom'] as num?;
    if ((value['positionMs'] as int? ?? 0) < 0 ||
        (rate != null && (rate < 0.25 || rate > 4)) ||
        (volume != null && (volume < 0 || volume > 100)) ||
        (fontSize != null && (fontSize < 16 || fontSize > 46)) ||
        (bottom != null && (bottom < 0.02 || bottom > 0.65))) {
      throw const FormatException('A player setting is outside its range.');
    }
    if (value['mediaHistory'] != null) {
      MediaHistory.validateEntries(value['mediaHistory']);
    }
    return value;
  }

  bool _optionalString(Object? value) => value == null || value is String;
  bool _optionalPath(Object? value) => value == null || _nonemptyString(value);
  bool _nonemptyString(Object? value) => value is String && value.isNotEmpty;
}
