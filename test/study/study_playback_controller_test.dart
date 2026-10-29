import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/study_audio.dart';
import 'package:offline_player/study/study_models.dart';
import 'package:offline_player/study/study_playback_controller.dart';

void main() {
  late _Audio audio;
  late StudyPlaybackController playback;
  setUp(() {
    audio = _Audio();
    playback = StudyPlaybackController(audio: audio);
  });
  tearDown(() {
    playback.dispose();
    audio.dispose();
  });

  test('lesson setup and restored sentence settings stay paused', () async {
    await playback.setLesson(_lesson());
    expect(audio.calls, ['pause', 'clearLoop']);
    expect(playback.scope, StudyPlaybackScope.passage);
    expect(playback.hasPlayableUnit, isTrue);
    expect(playback.unitStart, Duration.zero);
    expect(playback.unitEnd, const Duration(seconds: 20));
    expect(audio.playing, isFalse);
    await playback.setLesson(
      _lesson(),
      scope: StudyPlaybackScope.sentence,
      selectedIndex: 2,
      repeatCount: 3,
    );
    expect(playback.selectedIndex, 2);
    expect(playback.repeatCount, 3);
    expect(audio.position, const Duration(seconds: 11));
    expect(audio.playing, isFalse);
    expect(audio.loop, isNull);
    await playback.setLesson(null);
    expect(playback.hasPlayableUnit, isFalse);
    expect(playback.canPlaySentence, isFalse);
    expect(audio.loop, isNull);
  });

  test(
    'passage single play pauses and resumes without reinstalling range',
    () async {
      await playback.setLesson(_lesson());
      audio.calls.clear();
      await playback.play();
      expect(audio.calls, ['setLoop', 'play']);
      expect(audio.loop!.start, Duration.zero);
      expect(audio.loop!.end, const Duration(seconds: 20));
      expect(audio.loop!.repeatCount, 1);
      audio.emitPosition(const Duration(seconds: 7));
      await playback.pause();
      await playback.play();
      expect(audio.calls, ['setLoop', 'play', 'pause', 'play']);
      expect(audio.position, const Duration(seconds: 7));
      audio.finishPass();
      expect(playback.completed, isTrue);
      expect(playback.completedPasses, 1);
      expect(playback.playing, isFalse);
      await playback.play();
      expect(audio.position, Duration.zero);
      expect(playback.completedPasses, 0);
      expect(audio.playing, isTrue);
    },
  );

  test('sentence playback uses exact prepared bounds and navigation', () async {
    await playback.setLesson(_lesson());
    await playback.setScope(StudyPlaybackScope.sentence);
    expect(audio.position, const Duration(seconds: 1));
    expect(audio.playing, isFalse);
    await playback.play();
    expect(audio.loop!.start, const Duration(seconds: 1));
    expect(audio.loop!.end, const Duration(seconds: 4));
    expect(audio.loop!.repeatCount, 1);
    audio.finishPass();
    expect(audio.playing, isFalse);
    expect(playback.selectedIndex, 0);
    await playback.next();
    expect(playback.selectedIndex, 1);
    expect(audio.position, const Duration(seconds: 5));
    expect(audio.playing, isFalse);
    await playback.next(autoplay: true);
    expect(playback.selectedIndex, 2);
    expect(audio.loop!.start, const Duration(seconds: 11));
    expect(audio.loop!.end, const Duration(seconds: 18));
    expect(audio.playing, isTrue);
    await playback.previous();
    expect(playback.selectedIndex, 1);
    expect(audio.position, const Duration(seconds: 5));
    expect(audio.playing, isFalse);
  });

  test(
    'finite and infinite repeats rely on backend events without Dart seeks',
    () async {
      await playback.setLesson(
        _lesson(),
        scope: StudyPlaybackScope.sentence,
        repeatCount: 3,
      );
      await playback.play();
      expect(audio.loop!.repeatCount, 3);
      final calls = List<String>.of(audio.calls);
      for (var pass = 1; pass <= 3; pass++) {
        audio.emitPosition(const Duration(milliseconds: 3900));
        audio.finishPass();
        expect(playback.completedPasses, pass);
      }
      expect(playback.completed, isTrue);
      expect(audio.playing, isFalse);
      expect(audio.calls, calls);
      await playback.setRepeatCount(null, autoplay: true);
      expect(audio.loop!.repeatCount, isNull);
      final infiniteCalls = List<String>.of(audio.calls);
      for (var pass = 0; pass < 10; pass++) {
        audio.finishPass();
      }
      expect(playback.completedPasses, 10);
      expect(playback.completed, isFalse);
      expect(audio.playing, isTrue);
      expect(audio.calls, infiniteCalls);
      expect(() => playback.setRepeatCount(0), throwsArgumentError);
    },
  );

  test('missing or out-of-duration timings are never guessed', () async {
    await playback.setLesson(
      _lesson(
        segments: [_segment('bad', 0, 21000), _segment('missing', null, null)],
      ),
      scope: StudyPlaybackScope.sentence,
      selectedIndex: 1,
    );
    expect(playback.scope, StudyPlaybackScope.passage);
    expect(playback.canPlaySentence, isFalse);
    expect(playback.timedSegmentIndexes, isEmpty);
    await expectLater(
      playback.setScope(StudyPlaybackScope.sentence),
      throwsStateError,
    );
    await expectLater(playback.selectSegment(0), throwsStateError);
    await playback.play();
    expect(audio.loop!.end, const Duration(seconds: 20));
    await playback.setLesson(_lesson(audioRef: null));
    expect(playback.hasPlayableUnit, isFalse);
    expect(playback.canPlaySentence, isFalse);
    await expectLater(playback.play(), throwsStateError);
  });

  test(
    'partial timelines navigate valid units and invalid saved index falls back',
    () async {
      await playback.setLesson(
        _lesson(
          segments: [
            _segment('a', 1000, 4000),
            _segment('missing', null, null),
            _segment('c', 11000, 18000),
          ],
        ),
        scope: StudyPlaybackScope.sentence,
        selectedIndex: 1,
      );
      expect(playback.timedSegmentIndexes, [0, 2]);
      expect(playback.selectedIndex, 0);
      await playback.previous();
      expect(playback.selectedIndex, 0);
      await playback.next();
      expect(playback.selectedIndex, 2);
      await playback.next();
      expect(playback.selectedIndex, 2);
      await playback.previous();
      expect(playback.selectedIndex, 0);
      await playback.setLesson(
        _lesson(),
        scope: StudyPlaybackScope.sentence,
        selectedIndex: 999,
      );
      expect(playback.selectedIndex, 0);
      await expectLater(playback.selectSegment(-1), throwsRangeError);
    },
  );

  test(
    'seek resumes its target, changes timed sentence or clamps gaps',
    () async {
      await playback.setLesson(_lesson(), scope: StudyPlaybackScope.sentence);
      await playback.seek(const Duration(seconds: 3));
      expect(audio.position, const Duration(seconds: 3));
      expect(audio.playing, isFalse);
      final loopsBefore = audio.calls.where((c) => c == 'setLoop').length;
      await playback.play();
      expect(audio.position, const Duration(seconds: 3));
      expect(audio.calls.where((c) => c == 'setLoop').length, loopsBefore);
      await playback.seek(const Duration(seconds: 12));
      expect(playback.selectedIndex, 2);
      expect(audio.position, const Duration(seconds: 12));
      expect(audio.loop!.start, const Duration(seconds: 11));
      expect(audio.playing, isTrue);
      await playback.seek(const Duration(milliseconds: 10500));
      expect(playback.selectedIndex, 2);
      expect(audio.position, const Duration(seconds: 11));
      await playback.seek(const Duration(seconds: 25));
      expect(audio.position, const Duration(seconds: 18));
      expect(audio.playing, isFalse);
      await playback.play();
      expect(audio.position, const Duration(seconds: 11));
    },
  );

  test(
    'switching scope clears old loop progress and restart resets the unit',
    () async {
      await playback.setLesson(
        _lesson(),
        scope: StudyPlaybackScope.sentence,
        repeatCount: 3,
      );
      await playback.play();
      audio.finishPass();
      audio.finishPass();
      expect(playback.completedPasses, 2);
      await playback.setScope(StudyPlaybackScope.passage);
      expect(audio.loop, isNull);
      expect(audio.playing, isFalse);
      expect(playback.completedPasses, 0);
      await playback.play();
      expect(audio.loop!.start, Duration.zero);
      expect(audio.loop!.end, const Duration(seconds: 20));
      audio.finishPass();
      await playback.restart();
      expect(playback.completedPasses, 0);
      expect(audio.position, Duration.zero);
      expect(audio.playing, isTrue);
    },
  );

  test(
    'latest selection cancels an in-flight autoplay before it can play',
    () async {
      await playback.setLesson(_lesson());
      final loopStarted = Completer<void>();
      final loopGate = Completer<void>();
      audio.onLoop = () {
        loopStarted.complete();
        return loopGate.future;
      };
      audio.calls.clear();
      final oldPlay = playback.play();
      await loopStarted.future;
      expect(playback.busy, isTrue);
      final selection = playback.selectSegment(2);
      loopGate.complete();
      await Future.wait([oldPlay, selection]);
      expect(playback.selectedIndex, 2);
      expect(audio.position, const Duration(seconds: 11));
      expect(audio.playing, isFalse);
      expect(audio.calls.where((c) => c == 'play'), isEmpty);
      expect(playback.busy, isFalse);
    },
  );

  test(
    'rapid queued selection wins without a superseded play command',
    () async {
      await playback.setLesson(_lesson());
      audio.calls.clear();
      final oldScope = playback.setScope(
        StudyPlaybackScope.sentence,
        autoplay: true,
      );
      final latest = playback.selectSegment(2);
      await Future.wait([oldScope, latest]);
      expect(playback.selectedIndex, 2);
      expect(audio.calls, ['pause', 'clearLoop', 'seek']);
      expect(audio.playing, isFalse);
    },
  );

  test(
    'queued toggles follow current state and do not duplicate range setup',
    () async {
      await playback.setLesson(_lesson());
      audio.calls.clear();
      await Future.wait([playback.toggle(), playback.toggle()]);
      expect(audio.calls, ['setLoop', 'play', 'pause']);
      expect(audio.playing, isFalse);
    },
  );

  test(
    'a failed backend command does not poison later playback commands',
    () async {
      await playback.setLesson(_lesson());
      audio.failNextLoop = true;
      await expectLater(playback.play(), throwsStateError);
      expect(playback.busy, isFalse);
      await playback.play();
      expect(audio.playing, isTrue);
    },
  );

  test('native range installation keeps its position but restart and scope changes begin at the start', () async {
    audio.preservePositionInLoop = true;
    await playback.setLesson(_lesson(), scope: StudyPlaybackScope.sentence);
    await playback.play();
    audio.emitPosition(const Duration(seconds: 3));
    await playback.restart();
    expect(audio.position, const Duration(seconds: 1));
    expect(audio.playing, isTrue);
    audio.emitPosition(const Duration(seconds: 3));
    await playback.setScope(StudyPlaybackScope.passage, autoplay: true);
    expect(audio.position, Duration.zero);
    expect(audio.playing, isTrue);
    audio.emitPosition(const Duration(seconds: 8));
    await playback.setRepeatCount(3, autoplay: true);
    expect(audio.position, Duration.zero);
    expect(audio.loop!.repeatCount, 3);
  });

  test(
    'native range installation still allows seeking exactly to the unit start',
    () async {
      audio.preservePositionInLoop = true;
      await playback.setLesson(_lesson(), scope: StudyPlaybackScope.sentence);
      await playback.play();
      audio.emitPosition(const Duration(seconds: 3));
      await playback.seek(const Duration(seconds: 1));
      expect(audio.position, const Duration(seconds: 1));
      expect(audio.playing, isTrue);
      await playback.pause();
      audio.emitPosition(const Duration(seconds: 3));
      await playback.seek(const Duration(seconds: 1));
      expect(audio.position, const Duration(seconds: 1));
      expect(audio.playing, isFalse);
    },
  );
}

StudyLesson _lesson({
  List<StudySegment>? segments,
  String? audioRef = 'audio',
}) => StudyLesson(
  id: 'lesson',
  title: '测试',
  topic: '测试',
  audioRef: audioRef,
  segments:
      segments ??
      [
        _segment('a', 1000, 4000),
        _segment('b', 5000, 10000),
        _segment('c', 11000, 18000),
      ],
);

StudySegment _segment(String id, int? start, int? end) => StudySegment(
  id: id,
  text: '原文',
  translationZh: '原文',
  highlights: const [],
  audioStartMs: start,
  audioEndMs: end,
);

class _Audio extends StudyAudio {
  final calls = <String>[];
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 20);
  @override
  bool playing = false;
  @override
  bool busy = false;
  @override
  double rate = 1;
  @override
  String? error;
  @override
  StudyAudioLoop? loop;
  Future<void> Function()? onLoop;
  bool failNextLoop = false;
  bool preservePositionInLoop = false;

  @override
  Future<void> open(String path, String title) async {
    position = Duration.zero;
    playing = false;
    loop = null;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    calls.add('seek');
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setRate(double value) async {
    rate = value;
    notifyListeners();
  }

  @override
  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) async {
    calls.add('setLoop');
    if (failNextLoop) {
      failNextLoop = false;
      throw StateError('temporary failure');
    }
    final work = onLoop;
    onLoop = null;
    if (work != null) await work();
    loop = StudyAudioLoop(
      start: start,
      end: end,
      repeatCount: repeatCount,
      completedPasses: completedPasses,
    );
    if (!preservePositionInLoop || position < start || position >= end) {
      position = start;
    }
    notifyListeners();
  }

  @override
  Future<void> clearLoop() async {
    calls.add('clearLoop');
    loop = null;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    playing = false;
  }

  void emitPosition(Duration value) {
    position = value;
    notifyListeners();
  }

  void finishPass() {
    final current = loop!;
    loop = StudyAudioLoop(
      start: current.start,
      end: current.end,
      repeatCount: current.repeatCount,
      completedPasses: current.completedPasses + 1,
    );
    position = loop!.completed ? loop!.end : loop!.start;
    if (loop!.completed) playing = false;
    notifyListeners();
  }
}
