import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/playback/apple_audio_controller.dart';
import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/study/study_audio.dart';

import '../playback/apple_audio_controller_test.dart'
    show FakeAppleAudioTransport;
import '../playback/offline_playback_test.dart' show FakeTransport, settle;

void main() {
  late Directory temporary;
  late File original;
  late File lesson;
  late FakeAppleAudioTransport transport;
  late AppleAudioController controller;
  var controllerDisposedByAdapter = false;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('study-audio-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    original = await File('${temporary.path}/original.mp3').writeAsBytes([1]);
    lesson = await File('${temporary.path}/lesson.mp3').writeAsBytes([2]);
    transport = FakeAppleAudioTransport();
    controller = AppleAudioController(transport: transport);
    controllerDisposedByAdapter = false;
  });
  tearDown(() async {
    await controller.close();
    if (!controllerDisposedByAdapter) controller.dispose();
    await temporary.delete(recursive: true);
  });

  test('shared adapter forwards controls and detaches without closing the original player', () async {
    await controller.openLocal(original.path, title: 'Original');
    final adapter = AppleStudyAudio(controller);
    var notifications = 0;
    adapter.addListener(() => notifications++);
    transport.calls.clear();

    await adapter.open(lesson.path, 'Lesson');
    expect(transport.calls.single.command, 'open');
    expect(transport.calls.single.arguments, {
      'path': lesson.path,
      'title': 'Lesson',
      'positionMs': 0,
      'rate': 1.0,
      'autoplay': false,
    });
    expect(adapter.playing, isFalse);
    expect(adapter.duration, const Duration(seconds: 60));
    await adapter.setRate(0.75);
    await adapter.seek(const Duration(seconds: 12));
    await adapter.play();
    expect(adapter.rate, 0.75);
    expect(adapter.position, const Duration(seconds: 12));
    expect(adapter.playing, isTrue);
    await adapter.pause();
    expect(adapter.playing, isFalse);
    expect(transport.calls.map((c) => c.command), [
      'open',
      'setRate',
      'seek',
      'play',
      'pause',
    ]);
    expect(transport.calls[1].arguments, {'rate': 0.75});
    expect(transport.calls[2].arguments, {'positionMs': 12000});
    expect(notifications, greaterThan(0));

    await adapter.close();
    expect(transport.calls.last.command, 'pause');
    expect(transport.calls.where((c) => c.command == 'dispose'), isEmpty);
    expect(transport.closeCount, 0);
    final detachedCount = notifications;
    transport.emit({...transport.state, 'positionMs': 15000});
    expect(notifications, detachedCount);
    expect(controller.position, const Duration(seconds: 15));
    adapter.dispose();

    // Returning from the learning route can reopen the original media while
    // the shared native session stays alive, paused and at its saved position.
    await controller.openLocal(
      original.path,
      title: 'Original',
      position: const Duration(seconds: 34),
    );
    await controller.setRate(1.25);
    expect(controller.path, original.path);
    expect(controller.position, const Duration(seconds: 34));
    expect(controller.rate, 1.25);
    expect(controller.playing, isFalse);
    expect(transport.closeCount, 0);
    await controller.play();
    expect(controller.playing, isTrue);
  });

  test('owned adapter closes the native session once and adapter disposal does not repeat it', () async {
    final adapter = AppleStudyAudio(controller, ownsController: true);
    await adapter.open(lesson.path, 'Lesson');
    await adapter.play();
    await adapter.close();
    controllerDisposedByAdapter = true;
    adapter.dispose();
    await controller.close();
    expect(transport.calls.where((c) => c.command == 'dispose'), hasLength(1));
    expect(transport.closeCount, 1);
    await expectLater(
      controller.openLocal(original.path, title: 'Original'),
      throwsStateError,
    );
  });

  test(
    'Apple adapter sends range limits to native and observes loop progress',
    () async {
      final adapter = AppleStudyAudio(controller);
      await adapter.open(lesson.path, 'Lesson');
      transport.calls.clear();
      await adapter.setLoop(
        const Duration(seconds: 5),
        const Duration(seconds: 12),
        repeatCount: 3,
        completedPasses: 1,
      );
      await adapter.play();
      expect(transport.calls.map((c) => c.command), ['setLoop', 'play']);
      expect(transport.calls.first.arguments, {
        'startMs': 5000,
        'endMs': 12000,
        'repeatCount': 3,
        'completedPasses': 1,
      });
      expect(adapter.loop!.start, const Duration(seconds: 5));
      expect(adapter.loop!.end, const Duration(seconds: 12));
      expect(adapter.loop!.completedPasses, 1);
      expect(adapter.loop!.completed, isFalse);
      transport.emit({
        ...transport.state,
        'positionMs': 12000,
        'playing': false,
        'loop': {
          'startMs': 5000,
          'endMs': 12000,
          'repeatCount': 3,
          'completedPasses': 3,
          'completed': true,
        },
      });
      expect(adapter.loop!.completedPasses, 3);
      expect(adapter.loop!.completed, isTrue);
      expect(adapter.playing, isFalse);
      // A native boundary event only updates state; the adapter issues no seek.
      expect(transport.calls.map((c) => c.command), ['setLoop', 'play']);
      await adapter.clearLoop();
      expect(adapter.loop, isNull);
      await adapter.close();
      adapter.dispose();
    },
  );

  test('shared Apple adapter clears its learning loop when detached', () async {
    final adapter = AppleStudyAudio(controller);
    await adapter.open(lesson.path, 'Lesson');
    await adapter.setLoop(Duration.zero, const Duration(seconds: 12));
    await adapter.play();
    transport.calls.clear();
    await adapter.close();
    expect(transport.calls.map((c) => c.command), ['clearLoop', 'pause']);
    expect(controller.loop, isNull);
    expect(controller.playing, isFalse);
    expect(transport.closeCount, 0);
    adapter.dispose();
  });

  test(
    'desktop adapter forwards range playback and boundary completion',
    () async {
      final desktopTransport = FakeTransport();
      final backend = OfflinePlayback.withTransport(desktopTransport);
      final adapter = DesktopStudyAudio(playback: backend);
      await adapter.open(lesson.path, 'Lesson');
      expect(adapter.playing, isFalse);
      await adapter.setLoop(
        const Duration(seconds: 5),
        const Duration(seconds: 12),
        repeatCount: 2,
      );
      expect(adapter.position, const Duration(seconds: 5));
      await adapter.play();
      desktopTransport.emitPosition(const Duration(seconds: 12));
      await settle();
      expect(adapter.loop!.completedPasses, 1);
      expect(adapter.position, const Duration(seconds: 5));
      expect(adapter.playing, isTrue);
      desktopTransport.emitPosition(const Duration(seconds: 12));
      await settle();
      expect(adapter.loop!.completedPasses, 2);
      expect(adapter.loop!.completed, isTrue);
      expect(adapter.position, const Duration(seconds: 12));
      expect(adapter.playing, isFalse);
      await adapter.clearLoop();
      expect(adapter.loop, isNull);
      await adapter.close();
      adapter.dispose();
      expect(desktopTransport.disposeCount, 1);
    },
  );

  test('closing a shared adapter drains its in-flight command and rejects queued and later controls', () async {
    final adapter = AppleStudyAudio(controller);
    await adapter.open(lesson.path, 'Lesson');
    transport.calls.clear();
    final started = Completer<void>();
    final gate = Completer<void>();
    transport.handler = (command, arguments) async {
      if (command == 'setLoop') {
        started.complete();
        await gate.future;
        return {
          ...transport.state,
          'loop': {...arguments, 'completed': false},
        };
      }
      if (command == 'clearLoop') return {...transport.state, 'loop': null};
      if (command == 'pause') return {...transport.state, 'playing': false};
      throw StateError('Unexpected command during adapter close: $command');
    };
    final looping = adapter.setLoop(Duration.zero, const Duration(seconds: 12));
    await started.future;
    final queuedRate = expectLater(adapter.setRate(2), throwsStateError);
    final closing = adapter.close();
    expect(identical(adapter.close(), closing), isTrue);
    await expectLater(adapter.play(), throwsStateError);
    await expectLater(
      adapter.seek(const Duration(seconds: 2)),
      throwsStateError,
    );
    await expectLater(
      adapter.open(original.path, 'Late lesson'),
      throwsStateError,
    );
    await expectLater(adapter.setRate(0.5), throwsStateError);
    expect(transport.calls.map((c) => c.command), ['setLoop']);
    gate.complete();
    await looping;
    await queuedRate;
    await closing;
    expect(transport.calls.map((c) => c.command), [
      'setLoop',
      'clearLoop',
      'pause',
    ]);
    transport.handler = null;
    await controller.openLocal(
      original.path,
      title: 'Original',
      position: const Duration(seconds: 34),
    );
    await controller.setRate(1.25);
    await adapter.close();
    expect(controller.path, original.path);
    expect(controller.position, const Duration(seconds: 34));
    expect(controller.rate, 1.25);
    expect(controller.playing, isFalse);
    expect(transport.calls.map((c) => c.command), [
      'setLoop',
      'clearLoop',
      'pause',
      'open',
      'setRate',
    ]);
    adapter.dispose();
  });

  test('closing a shared adapter waits for its admitted audio open before returning the session', () async {
    final adapter = AppleStudyAudio(controller);
    final started = Completer<void>();
    final gate = Completer<void>();
    transport.handler = (command, arguments) async {
      if (command == 'open') {
        started.complete();
        await gate.future;
        return {
          ...transport.state,
          ...arguments,
          'playing': false,
          'loop': null,
        };
      }
      if (command == 'clearLoop') return {...transport.state, 'loop': null};
      if (command == 'pause') return {...transport.state, 'playing': false};
      throw StateError('Unexpected command during adapter close: $command');
    };
    final opening = adapter.open(lesson.path, 'Lesson');
    await started.future;
    var closed = false;
    final closing = adapter.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    await expectLater(adapter.setRate(2), throwsStateError);
    gate.complete();
    await opening;
    await closing;
    expect(closed, isTrue);
    expect(transport.calls.map((c) => c.command), [
      'open',
      'clearLoop',
      'pause',
    ]);
    expect(controller.playing, isFalse);
    transport.handler = null;
    adapter.dispose();
  });
}
