import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/local_state.dart';
import 'package:offline_player/main.dart';
import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/theme/app_theme.dart';

import 'support/fake_desktop_playback.dart';

void main() {
  const channel = MethodChannel('offline_player/local_files');
  for (final code in ['zh', 'ja', 'en']) {
    for (final empty in [false, true]) {
      testWidgets(
        '$code desktop ${empty ? 'empty' : 'loaded'} player fits 900x600',
        (tester) async {
          final h = (await tester.runAsync(
            () => _Fixture.create(empty: empty),
          ))!;
          final locale = ValueNotifier(Locale(code));
          tester.view.physicalSize = const Size(900, 600);
          tester.view.devicePixelRatio = 1;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getFullScreen' ? false : null,
          );
          try {
            await tester.pumpWidget(_app(locale, h));
            await tester.pumpAndSettle();
            await _settle(
              tester,
              () => empty
                  ? find
                        .text(AppLocalizations(Locale(code)).text('你的音视频学习空间'))
                        .evaluate()
                        .isNotEmpty
                  : h.playback.localPath != null && !h.playback.busy,
            );
            final strings = AppLocalizations(Locale(code));
            expect(find.text(strings.text('打开文件夹')), findsWidgets);
            if (!empty) {
              expect(find.text('教材 日本語 中文'), findsWidgets);
              expect(find.text('原字幕：日本語と中文'), findsOneWidget);
              expect(h.playback.position, const Duration(seconds: 12));
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await _withIo(tester, () async {
              await h.playback.close();
              await h.store.flush();
            });
            h.theme.dispose();
            locale.dispose();
            await tester.runAsync(() => h.directory.delete(recursive: true));
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              null,
            );
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        },
      );
    }
  }

  testWidgets(
    'desktop language switches preserve media, position, rate and subtitles',
    (tester) async {
      final h = (await tester.runAsync(() => _Fixture.create()))!;
      final locale = ValueNotifier(const Locale('zh'));
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getFullScreen' ? false : null,
      );
      try {
        await tester.pumpWidget(_app(locale, h));
        await tester.pumpAndSettle();
        await _settle(
          tester,
          () => h.playback.localPath != null && !h.playback.busy,
        );
        await h.playback.setRate(1.5);
        await h.playback.play();
        h.transport.emitPosition(const Duration(seconds: 37));
        await tester.pump();
        final count = h.transport.opened.length;
        for (final code in ['ja', 'en', 'zh']) {
          locale.value = Locale(code);
          await tester.pumpAndSettle();
          expect(h.transport.opened, hasLength(count));
          expect(h.playback.position, const Duration(seconds: 37));
          expect(h.playback.rate, 1.5);
          expect(h.playback.playing, isTrue);
          expect(find.text('教材 日本語 中文'), findsWidgets);
          expect(find.text('原字幕：日本語と中文'), findsOneWidget);
          expect(
            find.text(AppLocalizations(Locale(code)).text('打开文件')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _withIo(tester, () async {
          await h.playback.close();
          await h.store.flush();
        });
        h.theme.dispose();
        locale.dispose();
        await tester.runAsync(() => h.directory.delete(recursive: true));
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}

Widget _app(ValueNotifier<Locale> locale, _Fixture h) => AppThemeScope(
  controller: h.theme,
  child: ValueListenableBuilder<Locale>(
    valueListenable: locale,
    builder: (context, value, _) => MaterialApp(
      locale: value,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: appLocalizationDelegates,
      theme: buildAppTheme(Brightness.light),
      home: PlayerPage(
        playback: h.playback,
        stateStore: h.store,
        videoSurface: const ColoredBox(color: Colors.black),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    do {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Player did not restore.');
      }
    } while (!ready() ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
  });
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.directory, this.store, this.theme, this.transport)
    : playback = OfflinePlayback.withTransport(transport);
  final Directory directory;
  final LocalStateStore store;
  final AppThemeController theme;
  final FakeDesktopPlaybackTransport transport;
  final OfflinePlayback playback;

  static Future<_Fixture> create({bool empty = false}) async {
    final temp = await Directory.systemTemp.createTemp('desktop-language-');
    final directory = Directory(await temp.resolveSymbolicLinks());
    final media = await File('${directory.path}/教材 日本語 中文.mp4')
        .writeAsBytes([0]);
    final subtitle = await File('${directory.path}/字幕.srt')
        .writeAsString('1\n00:00:00,000 --> 00:02:00,000\n原字幕：日本語と中文\n');
    final lesson = LocalLesson(
      title: '教材 日本語 中文',
      videoPath: media.path,
      subtitlePath: subtitle.path,
    );
    final store = LocalStateStore(
      directory: Directory('${directory.path}/records'),
    );
    await store.write({
      'lessons': empty ? [] : [lesson.toJson()],
      'current': empty ? null : media.path,
      'positionMs': empty ? 0 : 12000,
      'subtitlePath': empty ? null : subtitle.path,
      'showPlaylist': true,
    });
    return _Fixture(
      directory,
      store,
      AppThemeController(preferences: ThemePreferences(directory: directory)),
      FakeDesktopPlaybackTransport(),
    );
  }
}

Future<void> _withIo(
  WidgetTester tester,
  Future<void> Function() operation,
) async {
  await tester.runAsync(() async {
    var done = false;
    Object? error;
    operation().then(
      (_) => done = true,
      onError: (Object value) {
        error = value;
        done = true;
      },
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Player cleanup did not finish.');
      }
    }
    if (error != null) throw error!;
  });
}
