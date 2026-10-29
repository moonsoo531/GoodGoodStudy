import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/phone/phone_media_store.dart';
import 'package:offline_player/phone/phone_player_page.dart';
import 'package:offline_player/playback/apple_audio_controller.dart';
import 'package:offline_player/study/study_audio.dart';
import 'package:offline_player/study/study_page.dart';
import 'package:offline_player/study/study_store.dart';
import 'package:offline_player/theme/app_theme.dart';

void main() {
  for (final section in [AppSection.study, AppSection.player]) {
    for (final language in ['zh', 'ja', 'en']) {
      testWidgets(
        '$language ${section.name} home arrow waits for pause and returns home at 320px',
        (tester) async {
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('mobile-home-back-'),
          ))!;
          final controller = AppNavigationController(
            preferences: NavigationPreferences(directory: root),
          );
          final theme = AppThemeController(
            preferences: ThemePreferences(directory: root),
          );
          final fixture = _PageFixture(
            section,
            Directory('${root.path}/shell'),
          );
          _PageFixture? standalone;
          try {
            await tester.runAsync(() async {
              await fixture.prepare();
              await controller.load();
            });
            await tester.pumpWidget(
              _host(
                language,
                theme,
                GoodGoodStudyShell(
                  controller: controller,
                  iconAsset: null,
                  phonePlayback: true,
                  builders: {section: (_) => fixture.page},
                ),
              ),
            );
            final entry = find.byKey(ValueKey('home-entry-${section.name}'));
            await tester.ensureVisible(entry);
            await tester.pumpAndSettle();
            await tester.tap(entry);
            await _pumpUntil(tester, fixture.isReady);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final arrow = find.byKey(const ValueKey('app-home-back'));
            expect(arrow, findsOneWidget);
            final expectedTooltip = switch (language) {
              'ja' => 'ホームに戻る',
              'en' => 'Back to home',
              _ => '返回首页',
            };
            expect(find.byTooltip(expectedTooltip), findsOneWidget);
            expect(tester.getRect(arrow).left, lessThan(56));
            expect(tester.getRect(arrow).right, lessThanOrEqualTo(320));
            expect(tester.widget<IconButton>(arrow).onPressed, isNotNull);

            fixture.pauseGate.armed = true;
            await tester.tap(arrow);
            await _pumpUntil(
              tester,
              () => fixture.pauseGate.entered.isCompleted,
            );
            expect(find.byType(fixture.page.runtimeType), findsOneWidget);
            expect(
              find.byKey(const ValueKey('home-entry-study')),
              findsNothing,
            );
            expect(controller.section, section);

            fixture.pauseGate.release();
            await _pumpUntil(
              tester,
              () =>
                  controller.section == AppSection.home &&
                  !controller.isSwitching,
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('home-entry-study')),
              findsOneWidget,
            );
            expect(find.byType(fixture.page.runtimeType), findsNothing);
            expect(fixture.pauseGate.completed, isTrue);
            await _complete(tester, fixture.flush());
            if (fixture.phoneStore != null) {
              final saved = await tester.runAsync(
                fixture.phoneStore!.loadState,
              );
              expect(saved, isNotEmpty);
            }
            expect(tester.takeException(), isNull);

            // The same real pages still use Navigator's default back button
            // when opened by older callers without an AppNavigationScope.
            if (language == 'zh') {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              standalone = _PageFixture(
                section,
                Directory('${root.path}/standalone'),
              );
              await tester.runAsync(standalone.prepare);
              await tester.pumpWidget(
                _host(
                  language,
                  theme,
                  Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => standalone!.page),
                        ),
                        child: const Text('open-standalone'),
                      ),
                    ),
                  ),
                  key: const ValueKey('standalone-host'),
                ),
              );
              await tester.tap(find.text('open-standalone'));
              await _pumpUntil(tester, standalone.isReady);
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('app-home-back')), findsNothing);
              expect(find.byType(BackButton), findsOneWidget);
              await tester.tap(find.byType(BackButton));
              await tester.pumpAndSettle();
              expect(find.text('open-standalone'), findsOneWidget);
              expect(find.byType(standalone.page.runtimeType), findsNothing);
              expect(tester.takeException(), isNull);
            }
          } finally {
            fixture.pauseGate.release();
            standalone?.pauseGate.release();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await _complete(tester, () async {
              await fixture.close();
              await standalone?.close();
              await controller.flush();
              await root.delete(recursive: true);
            }());
            controller.dispose();
            theme.dispose();
          }
        },
      );
    }
  }
}

Widget _host(
  String language,
  AppThemeController theme,
  Widget home, {
  Key? key,
}) => AppThemeScope(
  controller: theme,
  child: MaterialApp(
    key: key,
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationDelegates,
    theme: buildAppTheme(Brightness.light)
        .copyWith(platform: TargetPlatform.iOS),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'The mobile page did not complete its transition.',
        );
      }
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  await tester.pump();
}

Future<void> _complete(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    future.then<void>(
      (_) => done = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  await _pumpUntil(tester, () => done);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

class _PageFixture {
  _PageFixture(this.section, this.directory) {
    if (section == AppSection.study) {
      studyStore = StudyStore(root: directory);
      studyAudio = _StudyAudio(pauseGate);
    } else {
      phoneStore = PhoneMediaStore(documents: directory);
      phoneAudio = AppleAudioController(transport: _PhoneTransport(pauseGate));
    }
  }

  final AppSection section;
  final Directory directory;
  final pauseGate = _PauseGate();
  StudyStore? studyStore;
  _StudyAudio? studyAudio;
  PhoneMediaStore? phoneStore;
  AppleAudioController? phoneAudio;

  Widget get page => section == AppSection.study
      ? StudyPage(store: studyStore, audio: studyAudio)
      : PhonePlayerPage(store: phoneStore, audio: phoneAudio);

  Future<void> prepare() async {
    await directory.create(recursive: true);
  }

  bool isReady() {
    final finder = find.widgetWithIcon(
      IconButton,
      section == AppSection.study ? Icons.library_add_outlined : Icons.add,
    );
    return finder.evaluate().length == 1 &&
        (finder.evaluate().single.widget as IconButton).onPressed != null;
  }

  Future<void> flush() async {
    await studyStore?.flush();
    await phoneStore?.flush();
  }

  Future<void> close() async {
    pauseGate.release();
    await flush();
    if (phoneAudio != null) {
      await phoneAudio!.close();
      phoneAudio!.dispose();
    }
    if (studyAudio != null && !studyAudio!.disposed) {
      await studyAudio!.close();
      studyAudio!.dispose();
    }
  }
}

class _PauseGate {
  bool armed = false;
  bool completed = false;
  final entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> pause() async {
    if (!armed) return;
    if (!entered.isCompleted) entered.complete();
    await _released.future;
    completed = true;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _StudyAudio extends StudyAudio {
  _StudyAudio(this.gate);
  final _PauseGate gate;
  bool disposed = false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  bool get playing => false;
  @override
  bool get busy => false;
  @override
  double get rate => 1;
  @override
  String? get error => null;
  @override
  Future<void> open(String path, String title) async =>
      throw StateError('An empty study library must not open audio.');
  @override
  Future<void> play() async =>
      throw StateError('An empty study library must not start playback.');
  @override
  Future<void> pause() => gate.pause();
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRate(double value) async {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    super.dispose();
  }
}

class _PhoneTransport implements AppleAudioTransport {
  _PhoneTransport(this.gate);
  final _PauseGate gate;
  final _events = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async {
    switch (command) {
      case 'snapshot':
      case 'dispose':
        break;
      case 'pause':
        await gate.pause();
      default:
        throw StateError('An empty phone library sent unexpected $command.');
    }
    return {'path': null, 'playing': false, 'positionMs': 0, 'durationMs': 0};
  }

  @override
  Future<void> close() => _events.close();
}
