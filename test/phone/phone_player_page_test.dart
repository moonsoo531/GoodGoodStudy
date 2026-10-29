import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/phone/phone_media_store.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/phone/phone_player_page.dart';
import 'package:offline_player/playback/apple_audio_controller.dart';
import 'package:offline_player/study/study_page.dart';
import 'package:offline_player/quiz/quiz_page.dart';
import 'package:offline_player/widgets/ruby_subtitle_text.dart';
import 'package:offline_player/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final sample in [
      (size: const Size(320, 568), extension: 'srt'),
      (size: const Size(390, 844), extension: 'vtt'),
      (size: const Size(844, 390), extension: 'srt'),
    ]) {
      testWidgets(
        '${brightness.name} ${sample.size.width.toInt()}x${sample.size.height.toInt()} ${sample.extension} imports, reflects remote state and seeks next cue while paused',
        (tester) async {
          tester.view.physicalSize = sample.size;
          tester.view.devicePixelRatio = 1;
          Directory? documents;
          PhoneMediaStore? store;
          AppleAudioController? audio;
          AppThemeController? themeController;
          final transport = _PhoneNativeTransport();
          try {
            await tester.runAsync(() async {
              final temporary = await Directory.systemTemp.createTemp(
                'phone-ui-',
              );
              documents = Directory(await temporary.resolveSymbolicLinks());
              final media = await Directory('${documents!.path}/Media')
                  .create();
              await File('${media.path}/lesson.mp3').writeAsBytes([0, 1, 2]);
              await File('${media.path}/lesson.${sample.extension}')
                  .writeAsString(sample.extension == 'vtt' ? _vtt : _srt);
              store = PhoneMediaStore(documents: documents);
              audio = AppleAudioController(transport: transport);
              themeController = AppThemeController(
                preferences: ThemePreferences(directory: documents),
              );
              await tester.pumpWidget(
                AppThemeScope(
                  controller: themeController!,
                  child: MaterialApp(
                    theme: buildAppTheme(brightness),
                    home: PhonePlayerPage(audio: audio, store: store),
                  ),
                ),
              );
              await _pumpNativeIo(tester, transport.initialized.future);
            });
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('lesson'), findsOneWidget);
            expect(find.byTooltip('外观主题'), findsOneWidget);
            expect(tester.getSize(find.text('本地播放')).height, lessThan(40));
            expect(
              tester
                  .widget<RubySubtitleText>(find.byType(RubySubtitleText).first)
                  .style
                  ?.color,
              buildAppTheme(brightness).colorScheme.onSurface,
            );
            expect(find.text('字幕  2'), findsOneWidget);
            expect(find.text('03:00'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              tester
                  .widget<RubySubtitleText>(find.byType(RubySubtitleText).first)
                  .text,
              '一番目の文です。',
            );
            expect(audio!.playing, isFalse);
            final beforeRemote = transport.calls.length;
            transport.emit(playing: true, positionMs: 12000);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
            expect(find.text('00:12'), findsOneWidget);
            expect(
              tester
                  .widget<RubySubtitleText>(find.byType(RubySubtitleText).first)
                  .text,
              contains('明日'),
            );
            expect(transport.calls.length, beforeRemote);
            transport.emit(playing: false, positionMs: 1000);
            await tester.pumpAndSettle();
            expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
            expect(find.text('00:01'), findsOneWidget);
            transport.calls.clear();
            final sought = Completer<void>();
            transport.onSeek = () => sought.complete();
            await tester.runAsync(() async {
              await tester.tap(find.byTooltip('下一句'));
              await _pumpNativeIo(tester, sought.future);
            });
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(transport.calls.map((call) => call.command), [
              'clearLoop',
              'seek',
            ]);
            expect(transport.calls.last.arguments, {'positionMs': 10000});
            expect(audio!.position, const Duration(seconds: 10));
            expect(audio!.playing, isFalse);
            expect(audio!.busy, isFalse);
            expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
          } finally {
            await tester.runAsync(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              themeController?.dispose();
              if (store != null) {
                await _pumpNativeIo(tester, store!.saveState({}));
              }
              if (audio != null) {
                await _pumpNativeIo(tester, audio!.close());
                audio!.dispose();
              } else {
                await transport.close();
              }
              if (documents != null) await documents!.delete(recursive: true);
            });
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
          expect(transport.closeCount, 1);
          expect(
            transport.calls.where((call) => call.command == 'dispose').length,
            1,
          );
        },
      );
    }
  }

  testWidgets(
    '320px quiz and study peer entries preserve paused player state on return',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      Directory? documents;
      PhoneMediaStore? store;
      AppleAudioController? audio;
      AppThemeController? themeController;
      final transport = _PhoneNativeTransport();
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      try {
        await tester.runAsync(() async {
          final temporary = await Directory.systemTemp.createTemp(
            'phone-quiz-return-',
          );
          documents = Directory(await temporary.resolveSymbolicLinks());
          final media = await Directory('${documents!.path}/Media').create();
          await File('${media.path}/lesson.mp3').writeAsBytes([0, 1, 2]);
          store = PhoneMediaStore(documents: documents);
          audio = AppleAudioController(transport: transport);
          themeController = AppThemeController(
            preferences: ThemePreferences(directory: documents),
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                pathProvider,
                (_) async => documents!.path,
              );
          await tester.pumpWidget(
            AppThemeScope(
              controller: themeController!,
              child: MaterialApp(
                theme: buildAppTheme(Brightness.light),
                home: PhonePlayerPage(audio: audio, store: store),
              ),
            ),
          );
          await _pumpNativeIo(tester, transport.initialized.future);
          await audio!.setRate(1.25);
        });
        await tester.pumpAndSettle();
        final study = find.byTooltip('基础知识学习');
        final quiz = find.byTooltip('基础知识测试');
        expect(study, findsOneWidget);
        expect(quiz, findsOneWidget);
        expect(
          tester.getCenter(study).dy,
          closeTo(tester.getCenter(quiz).dy, .1),
        );
        expect(tester.getBottomRight(quiz).dx, lessThanOrEqualTo(320));
        transport.emit(playing: true, positionMs: 34000);
        await tester.pumpAndSettle();
        transport.calls.clear();
        await tester.runAsync(() async {
          await tester.tap(quiz);
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (find.text('选择一本资料，开始测试').evaluate().isEmpty) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Quiz page did not open.');
            }
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pumpAndSettle();
        expect(find.byType(QuizPage), findsOneWidget);
        expect(audio!.playing, isFalse);
        expect(
          transport.calls.where((call) => call.command == 'open'),
          isEmpty,
        );
        Navigator.of(tester.element(find.byType(QuizPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(QuizPage), findsNothing);
        expect(audio!.position, const Duration(seconds: 34));
        expect(audio!.rate, 1.25);
        expect(audio!.playing, isFalse);
        expect(
          transport.calls.where((call) => call.command == 'open'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          themeController?.dispose();
          if (store != null) await _pumpNativeIo(tester, store!.saveState({}));
          if (audio != null) {
            await _pumpNativeIo(tester, audio!.close());
            audio!.dispose();
          } else {
            await transport.close();
          }
          if (documents != null) await documents!.delete(recursive: true);
        });
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'returning from study waits for route disposal and shared cleanup before restoring original audio',
    (tester) async {
      Directory? documents;
      PhoneMediaStore? store;
      AppleAudioController? audio;
      AppThemeController? themeController;
      final transport = _PhoneNativeTransport();
      final cleanupGate = Completer<void>();
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      try {
        await tester.runAsync(() async {
          final temporary = await Directory.systemTemp.createTemp(
            'phone-study-return-',
          );
          documents = Directory(await temporary.resolveSymbolicLinks());
          final media = await Directory('${documents!.path}/Media').create();
          await File('${media.path}/lesson.mp3').writeAsBytes([0, 1, 2]);
          store = PhoneMediaStore(documents: documents);
          audio = AppleAudioController(transport: transport);
          themeController = AppThemeController(
            preferences: ThemePreferences(directory: documents),
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                pathProvider,
                (_) async => documents!.path,
              );
          await tester.pumpWidget(
            AppThemeScope(
              controller: themeController!,
              child: MaterialApp(
                home: PhonePlayerPage(audio: audio, store: store),
              ),
            ),
          );
          await _pumpNativeIo(tester, transport.initialized.future);
          await audio!.setRate(1.25);
        });
        await tester.pumpAndSettle();
        transport.emit(playing: false, positionMs: 34000);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('基础知识学习'));
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (find.text('把材料变成自己的学习课').evaluate().isEmpty) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Study library did not finish opening.');
            }
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pumpAndSettle();
        final cleanupStarted = Completer<void>();
        final restored = Completer<void>();
        transport.onClearLoop = () async {
          cleanupStarted.complete();
          await cleanupGate.future;
        };
        transport.onSetRate = () => restored.complete();
        transport.calls.clear();
        Navigator.of(tester.element(find.byType(StudyPage))).pop();
        await tester.pump();
        // pop has delivered its result, but its outgoing StudyPage still exists.
        expect(
          transport.calls.where((call) => call.command == 'open'),
          isEmpty,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => _pumpNativeIo(tester, cleanupStarted.future),
        );
        expect(transport.calls.map((call) => call.command), ['clearLoop']);
        expect(
          transport.calls.where((call) => call.command == 'open'),
          isEmpty,
        );
        cleanupGate.complete();
        await tester.runAsync(() => _pumpNativeIo(tester, restored.future));
        await tester.pumpAndSettle();
        expect(transport.calls.map((call) => call.command), [
          'clearLoop',
          'pause',
          'open',
          'setRate',
        ]);
        expect(audio!.path, '${documents!.path}/Media/lesson.mp3');
        expect(audio!.position, const Duration(seconds: 34));
        expect(audio!.rate, 1.25);
        expect(audio!.playing, isFalse);
        expect(transport.closeCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!cleanupGate.isCompleted) cleanupGate.complete();
        transport.onClearLoop = null;
        transport.onSetRate = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          themeController?.dispose();
          if (store != null) await _pumpNativeIo(tester, store!.saveState({}));
          if (audio != null) {
            await _pumpNativeIo(tester, audio!.close());
            audio!.dispose();
          } else {
            await transport.close();
          }
          if (documents != null) await documents!.delete(recursive: true);
        });
      }
    },
  );

  for (final language in ['zh', 'ja', 'en']) {
    testWidgets(
      '$language phone player keeps media content and controls at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        final locale = Locale(language);
        final strings = AppLocalizations(locale);
        final transport = _PhoneNativeTransport();
        Directory? documents;
        PhoneMediaStore? store;
        AppleAudioController? audio;
        final theme = AppThemeController();
        try {
          await tester.runAsync(() async {
            documents = await Directory.systemTemp.createTemp('phone-locale-');
            documents = Directory(await documents!.resolveSymbolicLinks());
            final media = await Directory('${documents!.path}/Media').create();
            await File('${media.path}/学习资料_日本語.mp3').writeAsBytes([0, 1, 2]);
            await File('${media.path}/学习资料_日本語.srt').writeAsString(_srt);
            store = PhoneMediaStore(documents: documents);
            audio = AppleAudioController(transport: transport);
            await tester.pumpWidget(
              _localizedPhone(locale, theme, audio!, store!),
            );
            await _pumpNativeIo(tester, transport.initialized.future);
          });
          await tester.pumpAndSettle();
          expect(find.text(strings.text('本地播放')), findsOneWidget);
          expect(find.text('学习资料_日本語'), findsOneWidget);
          expect(find.byTooltip(strings.text('下一句')), findsOneWidget);
          expect(
            find.text(strings.text('字幕  {count}', {'count': 2})),
            findsOneWidget,
          );
          expect(
            tester
                .widget<RubySubtitleText>(find.byType(RubySubtitleText).first)
                .text,
            '一番目の文です。',
          );
          final opens = transport.calls
              .where((call) => call.command == 'open')
              .length;
          await tester.tap(find.byTooltip(strings.text('字幕和循环设置')));
          await tester.pumpAndSettle();
          expect(find.text(strings.text('字幕与循环')), findsOneWidget);
          expect(find.text(strings.text('显示已有假名')), findsOneWidget);
          await tester.ensureVisible(find.text(strings.text('完成')));
          await tester.tap(find.text(strings.text('完成')));
          await tester.pumpAndSettle();
          expect(
            transport.calls.where((call) => call.command == 'open'),
            hasLength(opens),
          );
          expect(audio!.playing, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.runAsync(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            if (store != null) {
              await _pumpNativeIo(tester, store!.saveState({}));
            }
            if (audio != null) {
              await _pumpNativeIo(tester, audio!.close());
              audio!.dispose();
            } else {
              await transport.close();
            }
            if (documents != null) await documents!.delete(recursive: true);
          });
          theme.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );

    testWidgets('$language empty phone library is usable without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      final locale = Locale(language);
      final strings = AppLocalizations(locale);
      final transport = _PhoneNativeTransport();
      Directory? documents;
      PhoneMediaStore? store;
      AppleAudioController? audio;
      final theme = AppThemeController();
      try {
        await tester.runAsync(() async {
          documents = await Directory.systemTemp.createTemp(
            'phone-empty-locale-',
          );
          store = PhoneMediaStore(documents: documents);
          audio = AppleAudioController(transport: transport);
          await tester.pumpWidget(
            _localizedPhone(locale, theme, audio!, store!),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (find.text(strings.text('选择本地MP3或M4A音频')).evaluate().isEmpty) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Empty phone library did not open');
            }
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pumpAndSettle();
        expect(find.text(strings.text('导入音频与字幕')), findsOneWidget);
        expect(find.byTooltip(strings.text('导入音频')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (store != null) await _pumpNativeIo(tester, store!.saveState({}));
          if (audio != null) {
            await _pumpNativeIo(tester, audio!.close());
            audio!.dispose();
          } else {
            await transport.close();
          }
          if (documents != null) await documents!.delete(recursive: true);
        });
        theme.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }

  testWidgets(
    'changing phone UI language preserves active media and playback',
    (tester) async {
      final transport = _PhoneNativeTransport();
      Directory? documents;
      PhoneMediaStore? store;
      AppleAudioController? audio;
      final theme = AppThemeController();
      try {
        await tester.runAsync(() async {
          documents = await Directory.systemTemp.createTemp(
            'phone-switch-locale-',
          );
          documents = Directory(await documents!.resolveSymbolicLinks());
          final media = await Directory('${documents!.path}/Media').create();
          await File('${media.path}/lesson.mp3').writeAsBytes([0, 1, 2]);
          await File('${media.path}/lesson.srt').writeAsString(_srt);
          store = PhoneMediaStore(documents: documents);
          audio = AppleAudioController(transport: transport);
          await tester.pumpWidget(
            _localizedPhone(const Locale('en'), theme, audio!, store!),
          );
          await _pumpNativeIo(tester, transport.initialized.future);
        });
        await tester.pumpAndSettle();
        transport.emit(playing: true, positionMs: 12000);
        await tester.pumpAndSettle();
        final calls = transport.calls.length;
        final path = audio!.path;
        await tester.pumpWidget(
          _localizedPhone(const Locale('ja'), theme, audio!, store!),
        );
        await tester.pumpAndSettle();
        expect(find.text('ローカル再生'), findsOneWidget);
        expect(find.byTooltip('次の文'), findsOneWidget);
        expect(find.text('lesson'), findsOneWidget);
        expect(transport.calls, hasLength(calls));
        expect(audio!.path, path);
        expect(audio!.position, const Duration(seconds: 12));
        expect(audio!.playing, isTrue);
        expect(
          tester
              .widget<RubySubtitleText>(find.byType(RubySubtitleText).first)
              .text,
          contains('明日'),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (store != null) await _pumpNativeIo(tester, store!.saveState({}));
          if (audio != null) {
            await _pumpNativeIo(tester, audio!.close());
            audio!.dispose();
          } else {
            await transport.close();
          }
          if (documents != null) await documents!.delete(recursive: true);
        });
        theme.dispose();
      }
    },
  );
}

Widget _localizedPhone(
  Locale locale,
  AppThemeController theme,
  AppleAudioController audio,
  PhoneMediaStore store,
) => AppThemeScope(
  controller: theme,
  child: MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationDelegates,
    theme: buildAppTheme(Brightness.light),
    home: PhonePlayerPage(audio: audio, store: store),
  ),
);

Future<void> _pumpNativeIo(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  future.then(
    (_) => done = true,
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      trace = stackTrace;
      done = true;
    },
  );
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Phone initialization or file I/O did not settle.',
      );
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

const _srt = '''1
00:00:00,000 --> 00:00:10,000
一番目の文です。

2
00:00:10,000 --> 00:00:20,000
<ruby>明日<rt>あした</rt></ruby>も勉強します。
''';

const _vtt = '''WEBVTT

first
00:00.000 --> 00:10.000
一番目の文です。

second
00:10.000 --> 00:20.000
<ruby>明日<rt>あした</rt></ruby>も勉強します。
''';

class _PhoneNativeCall {
  _PhoneNativeCall(this.command, Map<String, Object?> arguments)
    : arguments = Map.unmodifiable(arguments);

  final String command;
  final Map<String, Object?> arguments;
}

class _PhoneNativeTransport implements AppleAudioTransport {
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final initialized = Completer<void>();
  final calls = <_PhoneNativeCall>[];
  VoidCallback? onSeek;
  Future<void> Function()? onClearLoop;
  VoidCallback? onSetRate;
  int closeCount = 0;
  Map<String, Object?> state = {
    'path': null,
    'title': null,
    'positionMs': 0,
    'durationMs': 180000,
    'playing': false,
    'buffering': false,
    'rate': 1.0,
    'volume': 100.0,
    'error': null,
    'loop': null,
    'stopAtEpochMs': null,
  };

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void emit({required bool playing, required int positionMs}) {
    state = {...state, 'playing': playing, 'positionMs': positionMs};
    _events.add(Map.from(state));
  }

  @override
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add(_PhoneNativeCall(command, arguments));
    switch (command) {
      case 'snapshot':
        break;
      case 'open':
        state = {
          ...state,
          'path': arguments['path'],
          'title': arguments['title'],
          'positionMs': arguments['positionMs'],
          'playing': arguments['autoplay'],
          'rate': arguments['rate'],
        };
      case 'setRate':
        state = {...state, 'rate': arguments['rate']};
        if (!initialized.isCompleted) initialized.complete();
        onSetRate?.call();
      case 'clearLoop':
        await onClearLoop?.call();
        state = {...state, 'loop': null};
      case 'seek':
        state = {...state, 'positionMs': arguments['positionMs']};
        onSeek?.call();
      case 'play':
        state = {...state, 'playing': true};
      case 'pause':
        state = {...state, 'playing': false};
      case 'dispose':
        state = {...state, 'playing': false};
      default:
        throw StateError('Unexpected phone UI command: $command');
    }
    return Map.from(state);
  }

  @override
  Future<void> close() async {
    closeCount++;
    await _events.close();
  }
}
