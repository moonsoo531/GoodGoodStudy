import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/local_state.dart';
import 'package:offline_player/main.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/theme/app_theme.dart';

import '../support/fake_desktop_playback.dart';

const _files = MethodChannel('offline_player/local_files');

void main() {
  for (final state in ['empty', 'missing-media', 'corrupt-record']) {
    for (final target in [AppSection.home, AppSection.study, AppSection.quiz]) {
      testWidgets('$state desktop player can leave for ${target.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('desktop-navigation-'),
        ))!;
        final store = _StateStore(corrupt: state == 'corrupt-record');
        final navigation = AppNavigationController(
          preferences: _PlayerPreferences(),
        );
        final theme = AppThemeController(
          preferences: ThemePreferences(directory: root),
        );
        final transport = _RestoreTransport();
        final playback = OfflinePlayback.withTransport(transport);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _files,
          (call) async => switch (call.method) {
            'getFullScreen' => false,
            'restorePaths' => <String>[],
            _ => null,
          },
        );
        try {
          await tester.runAsync(() async {
            await navigation.load();
            if (state == 'missing-media') {
              final lesson = LocalLesson(
                title: 'Missing synthetic media',
                videoPath: '${root.path}/missing.mp4',
              );
              store.data = {
                'lessons': [lesson.toJson()],
                'current': lesson.primaryPath,
              };
            }
          });
          await tester.pumpWidget(
            AppThemeScope(
              controller: theme,
              child: MaterialApp(
                theme: buildAppTheme(Brightness.light),
                home: GoodGoodStudyShell(
                  controller: navigation,
                  iconAsset: null,
                  builders: {
                    AppSection.player: (_) => PlayerPage(
                      playback: playback,
                      stateStore: store,
                      videoSurface: const ColoredBox(color: Colors.black),
                    ),
                    for (final section in [AppSection.study, AppSection.quiz])
                      section: (_) =>
                          Scaffold(body: Text('module-${section.name}')),
                  },
                ),
              ),
            ),
          );
          await _pumpUntil(
            tester,
            () => switch (state) {
              'corrupt-record' => store.status == LocalStateStatus.blocked,
              'missing-media' => playback.error != null,
              _ => transport.rateRestored,
            },
          );
          expect(playback.localPath, isNull);
          expect(playback.playing, isFalse);
          expect(playback.error, isNot(contains('Open local media first')));

          switch (target) {
            case AppSection.home:
              await tester.tap(find.byKey(const ValueKey('app-home-back')));
            case AppSection.study:
              await tester.tap(find.text('基础知识学习'));
            case AppSection.quiz:
              await tester.tap(find.byKey(const ValueKey('app-section-menu')));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('app-section-quiz')));
            case AppSection.player:
              throw StateError('This test must leave the player.');
          }
          await _pumpUntil(
            tester,
            () => navigation.section == target && !navigation.isSwitching,
          );
          await tester.pumpAndSettle();
          expect(find.byType(PlayerPage), findsNothing);
          expect(navigation.errorMessage, isNull);
          expect(transport.pauseCount, 0);
          expect(transport.disposeCount, 1);
          expect(transport.opened, isEmpty);
          if (target == AppSection.home) {
            expect(
              find.byKey(const ValueKey('home-entry-study')),
              findsOneWidget,
            );
          } else {
            expect(find.text('module-${target.name}'), findsOneWidget);
          }
          if (state == 'corrupt-record') {
            expect(store.writes, 0);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          var closed = false;
          final closing = Future.wait<void>([playback.close(), store.flush()]);
          unawaited(closing.then((_) => closed = true));
          await _pumpUntil(tester, () => closed);
          await closing;
          await tester.runAsync(() async {
            await root.delete(recursive: true);
          });
          playback.dispose();
          navigation.dispose();
          theme.dispose();
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _files,
            null,
          );
        }
      });
    }
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Desktop navigation did not complete.');
      }
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  await tester.pump();
}

class _RestoreTransport extends FakeDesktopPlaybackTransport {
  bool rateRestored = false;
  @override
  Future<void> setRate(double rate) async {
    await super.setRate(rate);
    rateRestored = true;
  }
}

class _PlayerPreferences extends NavigationPreferences {
  @override
  Future<AppSection> read() async => AppSection.player;
  @override
  Future<void> write(AppSection section) async {}
}

class _StateStore extends LocalStateStore {
  _StateStore({required this.corrupt});
  final bool corrupt;
  Map<String, dynamic>? data;
  bool readAttempted = false;
  int writes = 0;
  @override
  bool get canWrite => readAttempted && !corrupt;
  @override
  LocalStateStatus get status => !readAttempted
      ? LocalStateStatus.unread
      : corrupt
      ? LocalStateStatus.blocked
      : LocalStateStatus.ready;
  @override
  Future<Map<String, dynamic>?> read() async {
    readAttempted = true;
    if (corrupt) {
      throw const LocalStateReadException(
        path: 'synthetic-record',
        cause: FormatException('Synthetic corrupt record'),
      );
    }
    return data;
  }

  @override
  Future<void> write(Map<String, dynamic> state) async {
    writes++;
    data = state;
  }

  @override
  Future<void> flush() async {}
}
