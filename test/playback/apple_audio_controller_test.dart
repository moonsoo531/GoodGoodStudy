import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/playback/apple_audio_controller.dart';

void main() {
  late Directory temporary;
  late File audio;
  late FakeAppleAudioTransport transport;
  late AppleAudioController controller;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('apple-audio-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    audio = await File('${temporary.path}/日本語.mp3').writeAsBytes([0]);
    transport = FakeAppleAudioTransport();
    controller = AppleAudioController(transport: transport);
  });

  tearDown(() async {
    await controller.close();
    controller.dispose();
    await temporary.delete(recursive: true);
  });

  test(
    'opens only supported existing local audio using the native protocol',
    () async {
      for (final path in [
        'https://example.com/lesson.mp3',
        'file://remote-host/lesson.mp3',
        '//remote-host/lesson.mp3',
        'lesson.mp3',
        '${temporary.path}/lesson.m3u8',
        '${temporary.path}/lesson.mp4',
        '${temporary.path}/lesson.flac',
      ]) {
        await expectLater(
          controller.openLocal(path, title: 'Lesson'),
          throwsArgumentError,
        );
      }
      await expectLater(
        controller.openLocal('${temporary.path}/missing.mp3', title: 'Missing'),
        throwsA(isA<FileSystemException>()),
      );
      expect(transport.calls, isEmpty);
      await controller.openLocal(
        audio.uri.toString(),
        title: '日本語',
        position: const Duration(milliseconds: 2345),
      );
      expect(transport.calls.single.command, 'open');
      expect(transport.calls.single.arguments, {
        'path': audio.path,
        'title': '日本語',
        'positionMs': 2345,
        'rate': 1.0,
        'autoplay': false,
      });
      expect(controller.path, audio.path);
      expect(controller.position, const Duration(milliseconds: 2345));
      expect(controller.playing, isFalse);
      expect(controller.busy, isFalse);
    },
  );

  test('remote control events update playback and native loop state without Dart seeks', () async {
    await controller.openLocal(audio.path, title: 'Lesson');
    transport.calls.clear();
    transport.emit({
      ...transport.state,
      'playing': true,
      'positionMs': 12500,
      'rate': 0.75,
      'loop': {
        'startMs': 10000,
        'endMs': 14000,
        'repeatCount': 3,
        'completedPasses': 2,
        'completed': false,
      },
      'stopAtEpochMs': 1800000000000,
    });
    expect(controller.playing, isTrue);
    expect(controller.position, const Duration(milliseconds: 12500));
    expect(controller.rate, 0.75);
    expect(controller.loop!.completedPasses, 2);
    expect(controller.loop!.start, const Duration(seconds: 10));
    expect(controller.stopAt!.millisecondsSinceEpoch, 1800000000000);
    transport.emit({
      ...transport.state,
      'positionMs': 14000,
      'playing': false,
      'loop': {
        'startMs': 10000,
        'endMs': 14000,
        'repeatCount': 3,
        'completedPasses': 3,
        'completed': true,
      },
      'stopAtEpochMs': null,
    });
    expect(controller.playing, isFalse);
    expect(controller.loop!.completed, isTrue);
    expect(controller.stopAt, isNull);
    expect(transport.calls, isEmpty);
  });

  test(
    'serializes commands and ignores previous-file events during open',
    () async {
      transport.emit({...transport.state, 'path': '/old.mp3', 'title': 'Old'});
      final started = Completer<void>();
      final opening = Completer<Map<String, Object?>>();
      transport.handler = (command, arguments) async {
        if (command == 'open') {
          started.complete();
          return opening.future;
        }
        return {...transport.state, 'playing': false};
      };
      final pendingOpen = controller.openLocal(
        audio.path,
        title: 'New',
        autoplay: true,
      );
      await started.future;
      final pendingPause = controller.pause();
      expect(controller.busy, isTrue);
      transport.emit({
        ...transport.state,
        'path': '/old.mp3',
        'positionMs': 59000,
      });
      expect(controller.position, Duration.zero);
      transport.emit({
        ...transport.state,
        'path': audio.path,
        'title': 'New',
        'positionMs': 2500,
        'playing': true,
      });
      expect(controller.position, const Duration(milliseconds: 2500));
      expect(controller.busy, isTrue);
      expect(transport.calls.map((call) => call.command), ['open']);
      opening.complete({...transport.state, 'path': audio.path});
      await Future.wait([pendingOpen, pendingPause]);
      expect(transport.calls.map((call) => call.command), ['open', 'pause']);
      expect(controller.path, audio.path);
      expect(controller.playing, isFalse);
      expect(controller.busy, isFalse);
      transport.emit({
        ...transport.state,
        'path': '/old.mp3',
        'positionMs': 59000,
      });
      expect(controller.path, audio.path);
      expect(controller.position, const Duration(milliseconds: 2500));
    },
  );

  test(
    'sends loop and stop commands while native owns their execution',
    () async {
      await controller.openLocal(audio.path, title: 'Lesson');
      transport.calls.clear();
      await controller.setLoop(
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 2000),
        repeatCount: 3,
        completedPasses: 2,
      );
      final stopAt = DateTime.fromMillisecondsSinceEpoch(1800000000000);
      await controller.setStopAt(stopAt);
      expect(transport.calls.first.arguments, {
        'startMs': 1000,
        'endMs': 2000,
        'repeatCount': 3,
        'completedPasses': 2,
      });
      expect(transport.calls[1].arguments, {'epochMs': 1800000000000});
      expect(controller.loop!.completedPasses, 2);
      expect(controller.stopAt, stopAt);
      await controller.clearLoop();
      await controller.setStopAt(null);
      expect(controller.loop, isNull);
      expect(controller.stopAt, isNull);
      expect(transport.calls.map((call) => call.command), [
        'setLoop',
        'setStopAt',
        'clearLoop',
        'setStopAt',
      ]);
    },
  );

  test('reports native command and event errors and can recover', () async {
    await controller.openLocal(audio.path, title: 'Lesson');
    transport.handler = (_, _) => Future.error(
      PlatformException(code: 'audio_session', message: 'Audio session failed'),
    );
    await expectLater(controller.play(), throwsA(isA<PlatformException>()));
    expect(controller.error, 'Audio session failed');
    expect(controller.busy, isFalse);
    transport.handler = null;
    await controller.play();
    expect(controller.error, isNull);
    transport.emit({...transport.state, 'error': 'Audio interrupted'});
    expect(controller.error, 'Audio interrupted');
    controller.clearError();
    transport.emit(transport.state);
    expect(controller.error, isNull);
    transport.emit({...transport.state, 'error': null});
    transport.emit({...transport.state, 'error': 'Audio interrupted'});
    expect(controller.error, 'Audio interrupted');
    transport.eventsController.addError(
      PlatformException(code: 'events', message: 'Native event failed'),
    );
    expect(controller.error, 'Native event failed');
  });

  test(
    'snapshot command errors stop dependent playback and recover on retry',
    () async {
      await controller.openLocal(audio.path, title: 'Lesson');
      transport.calls.clear();
      transport.handler = (command, _) async => {
        ...transport.state,
        'error': command == 'setLoop' ? 'Loop exceeds media duration' : null,
      };
      Future<void> loopThenPlay() async {
        await controller.setLoop(
          const Duration(seconds: 50),
          const Duration(seconds: 70),
        );
        await controller.play();
      }

      await expectLater(
        loopThenPlay(),
        throwsA(isA<AppleAudioCommandException>()),
      );
      expect(transport.calls.map((call) => call.command), ['setLoop']);
      expect(controller.error, 'Loop exceeds media duration');
      expect(controller.playing, isFalse);
      expect(controller.busy, isFalse);
      controller.clearError();
      await expectLater(
        loopThenPlay(),
        throwsA(isA<AppleAudioCommandException>()),
      );
      expect(controller.error, 'Loop exceeds media duration');
      transport.handler = null;
      await controller.setLoop(
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      );
      await controller.play();
      expect(controller.error, isNull);
      expect(controller.playing, isTrue);
    },
  );

  test(
    'open rejects native error snapshots even when the returned path matches',
    () async {
      transport.handler = (_, arguments) async => {
        ...transport.state,
        'path': arguments['path'],
        'error': 'The audio file could not be decoded',
      };
      await expectLater(
        controller.openLocal(
          audio.path,
          title: 'Invalid audio',
          autoplay: true,
        ),
        throwsA(isA<AppleAudioCommandException>()),
      );
      expect(controller.error, 'The audio file could not be decoded');
      expect(controller.path, isNull);
      expect(controller.playing, isFalse);
      expect(controller.busy, isFalse);
      transport.handler = (_, _) async => {
        ...transport.state,
        'path': '/another-file.mp3',
        'error': null,
      };
      await expectLater(
        controller.openLocal(audio.path, title: 'Wrong response'),
        throwsStateError,
      );
      expect(controller.path, isNull);
      transport.handler = null;
      await controller.openLocal(audio.path, title: 'Recovered');
      expect(controller.error, isNull);
      expect(controller.path, audio.path);
    },
  );

  test('rejects invalid settings before invoking native commands', () async {
    await expectLater(controller.setRate(double.nan), throwsArgumentError);
    await expectLater(controller.setRate(0), throwsArgumentError);
    await expectLater(controller.setRate(0.249), throwsArgumentError);
    await expectLater(controller.setRate(3.001), throwsArgumentError);
    await expectLater(controller.setVolume(101), throwsArgumentError);
    await expectLater(
      controller.seek(const Duration(seconds: -1)),
      throwsArgumentError,
    );
    await expectLater(
      controller.setLoop(
        Duration.zero,
        const Duration(seconds: 1),
        repeatCount: 3,
        completedPasses: 3,
      ),
      throwsArgumentError,
    );
    expect(transport.calls, isEmpty);
    await controller.setRate(0.25);
    expect(controller.rate, 0.25);
    await controller.setRate(3);
    expect(controller.rate, 3);
    expect(transport.calls.last.arguments, {'rate': 3.0});
  });

  test(
    'toggle uses the latest remote state and close disposes native once',
    () async {
      await controller.openLocal(audio.path, title: 'Lesson');
      transport.emit({...transport.state, 'playing': true});
      await controller.toggle();
      expect(transport.calls.last.command, 'pause');
      await controller.setVolume(65);
      expect(controller.volume, 65);
      await controller.close();
      await controller.close();
      expect(
        transport.calls.where((call) => call.command == 'dispose').length,
        1,
      );
      expect(transport.closeCount, 1);
      await expectLater(controller.play(), throwsStateError);
    },
  );
}

class NativeCall {
  NativeCall(this.command, Map<String, Object?> arguments)
    : arguments = Map.unmodifiable(arguments);

  final String command;
  final Map<String, Object?> arguments;
}

class FakeAppleAudioTransport implements AppleAudioTransport {
  final eventsController = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  final calls = <NativeCall>[];
  Map<String, Object?> state = {
    'path': null,
    'title': null,
    'positionMs': 0,
    'durationMs': 60000,
    'playing': false,
    'buffering': false,
    'rate': 1.0,
    'volume': 100.0,
    'error': null,
    'loop': null,
    'stopAtEpochMs': null,
  };
  Future<Map<String, Object?>> Function(String, Map<String, Object?>)? handler;
  int closeCount = 0;

  @override
  Stream<Map<String, Object?>> get events => eventsController.stream;

  void emit(Map<String, Object?> snapshot) {
    state = Map.from(snapshot);
    eventsController.add(Map.from(snapshot));
  }

  @override
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add(NativeCall(command, arguments));
    if (handler != null) {
      state = await handler!(command, arguments);
      return Map.from(state);
    }
    state = {...state, 'error': null};
    switch (command) {
      case 'open':
        state = {
          ...state,
          ...arguments,
          'playing': arguments['autoplay'],
          'loop': null,
        };
      case 'play':
        state['playing'] = true;
      case 'pause':
        state['playing'] = false;
      case 'seek':
        state['positionMs'] = arguments['positionMs'];
      case 'setRate':
        state['rate'] = arguments['rate'];
      case 'setVolume':
        state['volume'] = arguments['volume'];
      case 'setLoop':
        state['loop'] = {...arguments, 'completed': false};
      case 'clearLoop':
        state['loop'] = null;
      case 'setStopAt':
        state['stopAtEpochMs'] = arguments['epochMs'];
      case 'snapshot':
      case 'dispose':
        break;
      default:
        throw StateError('Unexpected command: $command');
    }
    return Map.from(state);
  }

  @override
  Future<void> close() async {
    closeCount++;
    await eventsController.close();
  }
}
