import 'dart:io';

import 'package:flutter/foundation.dart';

import '../playback/apple_audio_controller.dart';
import '../playback/offline_playback.dart';

@immutable
class StudyAudioLoop {
  const StudyAudioLoop({
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
}

/// Uses the same platform playback implementation as the original player.
abstract class StudyAudio extends ChangeNotifier {
  factory StudyAudio.platform() => Platform.isIOS
      ? AppleStudyAudio(AppleAudioController(), ownsController: true)
      : DesktopStudyAudio();

  StudyAudio();

  Duration get position;
  Duration get duration;
  bool get playing;
  bool get busy;
  double get rate;
  String? get error;
  StudyAudioLoop? get loop => null;
  Future<void> open(String path, String title);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double value);
  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) => Future<void>.error(
    UnsupportedError('This study audio backend has no range playback.'),
  );
  Future<void> clearLoop() async {}
  Future<void> close();
}

class DesktopStudyAudio extends StudyAudio {
  DesktopStudyAudio({OfflinePlayback? playback})
    : _playback = playback ?? OfflinePlayback() {
    _playback.addListener(notifyListeners);
  }

  final OfflinePlayback _playback;

  @override
  Duration get position => _playback.position;
  @override
  Duration get duration => _playback.duration;
  @override
  bool get playing => _playback.playing;
  @override
  bool get busy => _playback.busy;
  @override
  double get rate => _playback.rate;
  @override
  String? get error => _playback.error;
  @override
  StudyAudioLoop? get loop {
    final value = _playback.loop;
    return value == null
        ? null
        : StudyAudioLoop(
            start: value.start,
            end: value.end,
            repeatCount: value.repeatCount,
            completedPasses: value.completedPasses,
          );
  }

  @override
  Future<void> open(String path, String title) =>
      _playback.openLocal(path, autoplay: false);
  @override
  Future<void> play() => _playback.play();
  @override
  Future<void> pause() => _playback.pause();
  @override
  Future<void> seek(Duration position) => _playback.seek(position);
  @override
  Future<void> setRate(double value) => _playback.setRate(value);
  @override
  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) => _playback.setLoop(
    start,
    end,
    repeatCount: repeatCount,
    completedPasses: completedPasses,
  );
  @override
  Future<void> clearLoop() async => _playback.clearLoop();
  @override
  Future<void> close() async {
    _playback.removeListener(notifyListeners);
    await _playback.close();
    _playback.dispose();
  }
}

class AppleStudyAudio extends StudyAudio {
  AppleStudyAudio(this.controller, {this.ownsController = false}) {
    controller.addListener(notifyListeners);
  }

  final AppleAudioController controller;
  final bool ownsController;
  Future<void> _commands = Future<void>.value();
  Future<void>? _closing;

  Future<void> _enqueue(Future<void> Function() command) {
    if (_closing != null) {
      return Future<void>.error(StateError('Study audio is closed.'));
    }
    final result = _commands.then((_) async {
      if (_closing != null) throw StateError('Study audio is closed.');
      await command();
    });
    _commands = result.catchError((Object _) {});
    return result;
  }

  @override
  Duration get position => controller.position;
  @override
  Duration get duration => controller.duration;
  @override
  bool get playing => controller.playing;
  @override
  bool get busy => controller.busy;
  @override
  double get rate => controller.rate;
  @override
  String? get error => controller.error;
  @override
  StudyAudioLoop? get loop {
    final value = controller.loop;
    return value == null
        ? null
        : StudyAudioLoop(
            start: value.start,
            end: value.end,
            repeatCount: value.repeatCount,
            completedPasses: value.completedPasses,
          );
  }

  @override
  Future<void> open(String path, String title) =>
      _enqueue(() => controller.openLocal(path, title: title, autoplay: false));
  @override
  Future<void> play() => _enqueue(controller.play);
  @override
  Future<void> pause() => _enqueue(controller.pause);
  @override
  Future<void> seek(Duration position) =>
      _enqueue(() => controller.seek(position));
  @override
  Future<void> setRate(double value) =>
      _enqueue(() => controller.setRate(value));
  @override
  Future<void> setLoop(
    Duration start,
    Duration end, {
    int? repeatCount,
    int completedPasses = 0,
  }) => _enqueue(
    () => controller.setLoop(
      start,
      end,
      repeatCount: repeatCount,
      completedPasses: completedPasses,
    ),
  );
  @override
  Future<void> clearLoop() => _enqueue(controller.clearLoop);
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    controller.removeListener(notifyListeners);
    // An admitted open can still be resolving a file before it reaches the
    // native command queue. Finish it before handing the shared session back.
    await _commands;
    if (ownsController) {
      await controller.close();
      controller.dispose();
    } else {
      try {
        await controller.clearLoop();
      } finally {
        await controller.pause();
      }
    }
  }
}
