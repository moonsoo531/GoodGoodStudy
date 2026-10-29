import 'local_library.dart';

/// A progress record for one same-stem local lesson and its companion media.
class MediaHistoryEntry {
  const MediaHistoryEntry({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.completed = false,
    this.subtitlePath,
    this.offset = Duration.zero,
    this.audioTrackId,
    this.subtitleTrackId,
    this.subtitleSource,
  });

  final Duration position;
  final Duration duration;
  final bool completed;
  final String? subtitlePath;
  final Duration offset;
  final String? audioTrackId;
  final String? subtitleTrackId;
  final String? subtitleSource;

  bool get hasDuration => duration > Duration.zero;
  double get progress => hasDuration
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0;

  Duration get resumePosition =>
      completed || (hasDuration && position >= duration)
      ? Duration.zero
      : position;

  Map<String, dynamic> toJson() => {
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'completed': completed,
    'subtitlePath': subtitlePath,
    'offsetMs': offset.inMilliseconds,
    'audioTrackId': audioTrackId,
    'subtitleTrackId': subtitleTrackId,
    'subtitleSource': subtitleSource,
  };

  factory MediaHistoryEntry.fromJson(Map<String, dynamic> json) {
    _validateEntry(json);
    final duration = Duration(milliseconds: json['durationMs'] as int? ?? 0);
    final rawPosition = Duration(milliseconds: json['positionMs'] as int? ?? 0);
    return MediaHistoryEntry(
      position: duration > Duration.zero && rawPosition > duration
          ? duration
          : rawPosition,
      duration: duration,
      completed: json['completed'] as bool? ?? false,
      subtitlePath: json['subtitlePath'] as String?,
      offset: Duration(milliseconds: json['offsetMs'] as int? ?? 0),
      audioTrackId: json['audioTrackId'] as String?,
      subtitleTrackId: json['subtitleTrackId'] as String?,
      subtitleSource: json['subtitleSource'] as String?,
    );
  }

  static void _validateEntry(Map<String, dynamic> json) {
    for (final key in ['positionMs', 'durationMs', 'offsetMs']) {
      if (json[key] != null && json[key] is! int) {
        throw FormatException('Media history $key must be an integer.');
      }
    }
    if ((json['positionMs'] as int? ?? 0) < 0 ||
        (json['durationMs'] as int? ?? 0) < 0) {
      throw const FormatException('Media history times cannot be negative.');
    }
    if (json['completed'] != null && json['completed'] is! bool) {
      throw const FormatException('Media history completed must be a boolean.');
    }
    for (final key in [
      'subtitlePath',
      'audioTrackId',
      'subtitleTrackId',
      'subtitleSource',
    ]) {
      if (json[key] != null && json[key] is! String) {
        throw FormatException('Media history $key must be a string or null.');
      }
    }
    final source = json['subtitleSource'];
    if (source != null &&
        !const {'external', 'embedded', 'off'}.contains(source)) {
      throw const FormatException('Unknown media history subtitle source.');
    }
  }
}

/// In-memory per-lesson history. Persist [toJson] under `mediaHistory` in the
/// player's state object; [fromJson] accepts that entire state object and also
/// migrates its legacy `current` + `positionMs` progress without overwriting a
/// newer per-lesson entry.
class MediaHistory {
  MediaHistory();

  final Map<String, MediaHistoryEntry> _entries = {};

  Map<String, MediaHistoryEntry> get entries => Map.unmodifiable(_entries);

  factory MediaHistory.fromJson(Map<String, dynamic>? state) {
    final history = MediaHistory();
    if (state == null) return history;
    final raw = state['mediaHistory'];
    if (raw != null) {
      validateEntries(raw);
      for (final entry in (raw as Map<String, dynamic>).entries) {
        history._entries[entry.key] = MediaHistoryEntry.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    final current = state['current'];
    final position = state['positionMs'];
    if (current is String && current.isNotEmpty && position is int) {
      final key = keyForPath(current);
      if (!history._entries.containsKey(key)) {
        final legacyDuration = state['durationMs'];
        final durationMs = legacyDuration is int && legacyDuration > 0
            ? legacyDuration
            : 0;
        final positionMs = position < 0
            ? 0
            : durationMs > 0 && position > durationMs
            ? durationMs
            : position;
        history._entries[key] = MediaHistoryEntry(
          position: Duration(milliseconds: positionMs),
          duration: Duration(milliseconds: durationMs),
          completed: durationMs > 0 && positionMs >= durationMs,
          subtitlePath: state['subtitlePath'] is String
              ? state['subtitlePath'] as String
              : null,
          offset: Duration(
            milliseconds: state['offsetMs'] is int
                ? state['offsetMs'] as int
                : 0,
          ),
        );
      }
    }
    return history;
  }

  static String keyForPath(String path) =>
      LocalLesson(title: stemOf(path), videoPath: path).identity;

  MediaHistoryEntry? getForLesson(LocalLesson lesson) =>
      _entries[lesson.identity];

  Duration resumePosition(LocalLesson lesson) =>
      getForLesson(lesson)?.resumePosition ?? Duration.zero;

  /// Nullable preference arguments preserve their existing values when omitted.
  /// A non-positive/unknown duration retains any previously measured duration.
  /// Explicit [completed] false clears the old completed flag. Otherwise only
  /// the final 1% (at most two seconds) counts as complete, so short clips do not
  /// restart simply because the user paused a couple of seconds before the end.
  MediaHistoryEntry record(
    LocalLesson lesson, {
    required Duration position,
    Duration? duration,
    bool? completed,
    String? subtitlePath,
    Duration? offset,
    String? audioTrackId,
    String? subtitleTrackId,
    String? subtitleSource,
  }) {
    if (subtitleSource != null &&
        !const {'external', 'embedded', 'off'}.contains(subtitleSource)) {
      throw ArgumentError.value(subtitleSource, 'subtitleSource');
    }
    final previous = _entries[lesson.identity];
    final knownDuration = duration != null && duration > Duration.zero
        ? duration
        : previous?.duration ?? Duration.zero;
    final boundedPosition = position < Duration.zero
        ? Duration.zero
        : knownDuration > Duration.zero && position > knownDuration
        ? knownDuration
        : position;
    final windowMs = (knownDuration.inMilliseconds ~/ 100).clamp(1, 2000);
    final nearEnd =
        knownDuration > Duration.zero &&
        boundedPosition.inMilliseconds >=
            knownDuration.inMilliseconds - windowMs;
    final entry = MediaHistoryEntry(
      position: boundedPosition,
      duration: knownDuration,
      completed: completed ?? nearEnd,
      subtitlePath: subtitlePath ?? previous?.subtitlePath,
      offset: offset ?? previous?.offset ?? Duration.zero,
      audioTrackId: audioTrackId ?? previous?.audioTrackId,
      subtitleTrackId: subtitleTrackId ?? previous?.subtitleTrackId,
      subtitleSource: subtitleSource ?? previous?.subtitleSource,
    );
    _entries[lesson.identity] = entry;
    return entry;
  }

  Map<String, dynamic> toJson() => {
    for (final entry in _entries.entries) entry.key: entry.value.toJson(),
  };

  static void validateEntries(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Media history must be a JSON object.');
    }
    for (final entry in value.entries) {
      if (entry.key.isEmpty || entry.value is! Map<String, dynamic>) {
        throw const FormatException('A media history entry has invalid shape.');
      }
      MediaHistoryEntry._validateEntry(entry.value as Map<String, dynamic>);
    }
  }
}
