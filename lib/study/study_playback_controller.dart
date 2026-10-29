import 'package:flutter/foundation.dart';

import 'study_audio.dart';
import 'study_models.dart';

enum StudyPlaybackScope { passage, sentence }

/// Selects ranges and repeat limits; the platform player owns loop execution.
/// No timer or position listener issues seeks during ordinary playback.
class StudyPlaybackController extends ChangeNotifier {
  StudyPlaybackController({required this.audio}) {
    audio.addListener(_audioChanged);
  }

  final StudyAudio audio;
  StudyLesson? _lesson;
  StudyPlaybackScope _scope = StudyPlaybackScope.passage;
  int _selectedIndex = 0;
  int? _repeatCount = 1;
  Future<void> _pending = Future<void>.value();
  int _pendingCount = 0;
  int _generation = 0;
  bool _closed = false;

  StudyLesson? get lesson => _lesson;
  StudyPlaybackScope get scope => _scope;
  int get selectedIndex => _selectedIndex;
  int? get repeatCount => _repeatCount;
  bool get busy => _pendingCount > 0 || audio.busy;
  bool get playing => audio.playing;
  StudySegment? get selectedSegment {
    final segments = _lesson?.segments;
    return segments != null &&
            _selectedIndex >= 0 &&
            _selectedIndex < segments.length
        ? segments[_selectedIndex]
        : null;
  }

  List<int> get timedSegmentIndexes => [
    for (var i = 0; i < (_lesson?.segments.length ?? 0); i++)
      if (_segmentRange(_lesson!.segments[i]) != null) i,
  ];
  bool get canPlaySentence => timedSegmentIndexes.isNotEmpty;
  bool get hasPlayableUnit => _range != null;
  Duration get unitStart => _range?.start ?? Duration.zero;
  Duration get unitEnd => _range?.end ?? Duration.zero;
  int get completedPasses => _matchingLoop?.completedPasses ?? 0;
  bool get completed => _matchingLoop?.completed ?? false;

  ({Duration start, Duration end})? _segmentRange(StudySegment segment) {
    final start = segment.audioStartMs, end = segment.audioEndMs;
    if (_lesson?.audioRef == null ||
        start == null ||
        end == null ||
        start < 0 ||
        end <= start ||
        audio.duration <= Duration.zero ||
        end > audio.duration.inMilliseconds) {
      return null;
    }
    return (
      start: Duration(milliseconds: start),
      end: Duration(milliseconds: end),
    );
  }

  ({Duration start, Duration end})? get _range {
    if (_lesson?.audioRef == null || audio.duration <= Duration.zero) {
      return null;
    }
    if (_scope == StudyPlaybackScope.passage) {
      return (start: Duration.zero, end: audio.duration);
    }
    final segment = selectedSegment;
    return segment == null ? null : _segmentRange(segment);
  }

  StudyAudioLoop? get _matchingLoop {
    final loop = audio.loop, range = _range;
    return loop != null &&
            range != null &&
            loop.start == range.start &&
            loop.end == range.end &&
            loop.repeatCount == _repeatCount
        ? loop
        : null;
  }

  bool _current(int generation) => !_closed && generation == _generation;

  Future<void> _enqueue(
    Future<void> Function(int generation) work, {
    bool supersede = false,
  }) {
    if (_closed) {
      return Future<void>.error(StateError('Study playback is closed.'));
    }
    final generation = supersede ? ++_generation : _generation;
    _pendingCount++;
    notifyListeners();
    final next = _pending.then((_) async {
      if (_current(generation)) await work(generation);
    });
    _pending = next.catchError((Object _) {});
    return next.whenComplete(() {
      _pendingCount--;
      if (!_closed) notifyListeners();
    });
  }

  /// Reset with null before audio.open(), then configure the opened lesson.
  /// Restored settings never start playback automatically.
  Future<void> setLesson(
    StudyLesson? lesson, {
    StudyPlaybackScope scope = StudyPlaybackScope.passage,
    int selectedIndex = 0,
    int? repeatCount = 1,
  }) {
    _validateCount(repeatCount);
    return _enqueue((generation) async {
      await audio.pause();
      if (!_current(generation)) return;
      await audio.clearLoop();
      if (!_current(generation)) return;
      _lesson = lesson;
      _scope = lesson == null ? StudyPlaybackScope.passage : scope;
      _repeatCount = repeatCount;
      _selectedIndex =
          lesson != null &&
              selectedIndex >= 0 &&
              selectedIndex < lesson.segments.length
          ? selectedIndex
          : 0;
      if (_scope == StudyPlaybackScope.sentence) {
        final indexes = timedSegmentIndexes;
        if (indexes.isEmpty) {
          _scope = StudyPlaybackScope.passage;
        } else if (!indexes.contains(_selectedIndex)) {
          _selectedIndex = indexes.first;
        }
      }
      if (_scope == StudyPlaybackScope.sentence && hasPlayableUnit) {
        await audio.seek(unitStart);
      }
    }, supersede: true);
  }

  Future<void> setScope(StudyPlaybackScope value, {bool autoplay = false}) =>
      _enqueue((generation) async {
        if (value == StudyPlaybackScope.sentence && !canPlaySentence) {
          throw StateError('本篇没有有效的句子音频时间轴。');
        }
        if (_scope == value) {
          if (autoplay) await _play(generation);
          return;
        }
        await _stopRange(generation);
        if (!_current(generation)) return;
        _scope = value;
        if (value == StudyPlaybackScope.sentence &&
            !timedSegmentIndexes.contains(_selectedIndex)) {
          _selectedIndex = timedSegmentIndexes.first;
        }
        await _beginUnit(generation, autoplay: autoplay);
      }, supersede: true);

  Future<void> setRepeatCount(int? count, {bool autoplay = false}) {
    _validateCount(count);
    return _enqueue((generation) async {
      if (_repeatCount == count) {
        if (autoplay) await _play(generation);
        return;
      }
      await _stopRange(generation);
      if (!_current(generation)) return;
      _repeatCount = count;
      await _beginUnit(generation, autoplay: autoplay);
    }, supersede: true);
  }

  /// Choosing a sentence selects sentence scope and restarts that unit.
  Future<void> selectSegment(int index, {bool autoplay = false}) => _enqueue(
    (generation) => _select(index, generation, autoplay: autoplay),
    supersede: true,
  );

  Future<void> _select(
    int index,
    int generation, {
    required bool autoplay,
  }) async {
    final segments = _lesson?.segments;
    if (segments == null || index < 0 || index >= segments.length) {
      throw RangeError.index(index, segments ?? const [], 'index');
    }
    if (_segmentRange(segments[index]) == null) {
      throw StateError('本句没有有效的音频时间轴。');
    }
    await _stopRange(generation);
    if (!_current(generation)) return;
    _scope = StudyPlaybackScope.sentence;
    _selectedIndex = index;
    await _beginUnit(generation, autoplay: autoplay);
  }

  Future<void> previous({bool autoplay = false}) => _step(-1, autoplay);
  Future<void> next({bool autoplay = false}) => _step(1, autoplay);
  Future<void> _step(int delta, bool autoplay) => _enqueue((generation) async {
    final indexes = timedSegmentIndexes;
    if (indexes.isEmpty) throw StateError('本篇没有有效的句子音频时间轴。');
    final position = indexes.indexOf(_selectedIndex);
    final target = (position < 0 ? 0 : position + delta).clamp(
      0,
      indexes.length - 1,
    );
    if (position >= 0 &&
        target == position &&
        _scope == StudyPlaybackScope.sentence) {
      return;
    }
    await _select(indexes[target], generation, autoplay: autoplay);
  }, supersede: true);

  Future<void> _stopRange(int generation) async {
    await audio.pause();
    if (!_current(generation)) return;
    await audio.clearLoop();
  }

  Future<void> _beginUnit(int generation, {required bool autoplay}) async {
    if (!_current(generation) || !hasPlayableUnit) return;
    if (autoplay) {
      await _play(generation);
    } else {
      await audio.seek(unitStart);
    }
  }

  Future<void> play() => _enqueue(_play);
  Future<void> _play(int generation) async {
    final range = _range;
    if (range == null) throw StateError('没有可播放的学习音频范围。');
    final loop = _matchingLoop;
    final inside = audio.position >= range.start && audio.position < range.end;
    if (audio.playing && loop != null && !loop.completed && inside) return;
    if (loop == null || loop.completed || !inside) {
      await audio.setLoop(range.start, range.end, repeatCount: _repeatCount);
      if (!_current(generation)) return;
      // Native setLoop preserves a position already inside its new range.
      // Starting a new unit always begins with its first word on every backend.
      if (audio.position != range.start) {
        await audio.seek(range.start);
        if (!_current(generation)) return;
      }
    }
    await audio.play();
  }

  Future<void> pause() => _enqueue((_) => audio.pause(), supersede: true);
  Future<void> toggle() => _enqueue(
    (generation) => audio.playing ? audio.pause() : _play(generation),
  );

  Future<void> restart() => _enqueue((generation) async {
    await _stopRange(generation);
    if (!_current(generation)) return;
    await _play(generation);
  }, supersede: true);

  /// Keeps seeking inside the chosen sentence. A target inside another timed
  /// sentence selects it; targets in unaligned gaps clamp to the current unit.
  Future<void> seek(Duration target) => _enqueue((generation) async {
    if (!hasPlayableUnit) throw StateError('没有可播放的学习音频范围。');
    final resume = audio.playing;
    await _stopRange(generation);
    if (!_current(generation)) return;
    if (_scope == StudyPlaybackScope.sentence) {
      for (final index in timedSegmentIndexes) {
        final range = _segmentRange(_lesson!.segments[index])!;
        if (target >= range.start && target < range.end) {
          _selectedIndex = index;
          break;
        }
      }
    }
    final range = _range!;
    final bounded = target < range.start
        ? range.start
        : target > range.end
        ? range.end
        : target;
    await audio.setLoop(range.start, range.end, repeatCount: _repeatCount);
    if (!_current(generation)) return;
    if (audio.position != bounded) await audio.seek(bounded);
    if (!_current(generation)) return;
    if (resume && bounded < range.end) await audio.play();
  }, supersede: true);

  void _validateCount(int? count) {
    if (count != null && count < 1) {
      throw ArgumentError.value(count, 'repeatCount');
    }
  }

  void _audioChanged() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    audio.removeListener(_audioChanged);
    super.dispose();
  }
}
