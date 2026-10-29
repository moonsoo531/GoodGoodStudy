import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PointerDeviceKind;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/local_state.dart';
import 'package:offline_player/library/media_history.dart';
import 'package:offline_player/library/playlist_mode.dart';
import 'package:offline_player/library/playlist_import.dart';
import 'package:offline_player/main.dart';
import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/theme/app_theme.dart';
import 'package:offline_player/widgets/player_playlist.dart';
import 'package:offline_player/widgets/player_subtitles.dart';

import 'support/fake_desktop_playback.dart';

const _files = MethodChannel('offline_player/local_files');

void main() {
  testWidgets(
    'app exit flushes the final position and closes every player once',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      final studyTransport = FakeDesktopPlaybackTransport();
      final studyPlayback = OfflinePlayback.withTransport(studyTransport);
      try {
        await harness.mount(tester);
        await harness.playback.play();
        await _withIo(
          tester,
          () => studyPlayback.openLocal(harness.second.path),
        );
        harness.transport.emitPosition(const Duration(seconds: 73));
        await tester.pump();

        final response = await _withIo(
          tester,
          tester.binding.handleRequestAppExit,
        );
        expect(response, AppExitResponse.exit);
        expect(harness.playback.playing, isFalse);
        expect(harness.transport.disposeCount, 1);
        expect(studyTransport.disposeCount, 1);
        // Read the physical file directly: a serialized store.read could hide a
        // missing flush by waiting for a queued write after the exit response.
        final raw = (await tester.runAsync(harness.stateFile.readAsString))!;
        final saved = (jsonDecode(raw) as Map).cast<String, dynamic>();
        expect(saved['current'], harness.first.path);
        expect(saved['positionMs'], 73000);
        expect(
          MediaHistory.fromJson(saved)
              .getForLesson(harness.lessons.first)!
              .position,
          const Duration(seconds: 73),
        );

        final repeated = await _withIo(
          tester,
          tester.binding.handleRequestAppExit,
        );
        expect(repeated, AppExitResponse.exit);
        expect(harness.transport.disposeCount, 1);
        expect(studyTransport.disposeCount, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _withIo(tester, studyPlayback.close);
        studyPlayback.dispose();
        await harness.close(tester);
      }
    },
  );

  testWidgets('A to B to A resumes each media and persists both positions', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      expect(harness.playback.position, const Duration(seconds: 12));
      harness.transport.emitPosition(const Duration(seconds: 37));
      await tester.pump();
      await tester.tap(_row('第一课'));
      await _flush(tester);
      // Selecting the current row must not reopen it or discard its position.
      expect(harness.transport.opened.length, 1);
      expect(harness.playback.position, const Duration(seconds: 37));

      await tester.tap(_row('第二课'));
      await _flush(
        tester,
        until: () => harness.playback.localPath == harness.second.path,
      );
      harness.transport.emitPosition(const Duration(seconds: 18));
      await tester.pump();
      await tester.tap(_row('第一课'));
      await _flush(
        tester,
        until: () => harness.playback.localPath == harness.first.path,
      );
      expect(harness.playback.position, const Duration(seconds: 37));

      final saved = await _withIo(tester, harness.store.read);
      final history = MediaHistory.fromJson(saved);
      expect(
        history.getForLesson(harness.lessons[0])!.position,
        const Duration(seconds: 37),
      );
      expect(
        history.getForLesson(harness.lessons[1])!.position,
        const Duration(seconds: 18),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('replay menu starts the selected lesson at zero', (tester) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      harness.transport.emitPosition(const Duration(seconds: 44));
      await tester.pump();
      await tester.tap(
        find.descendant(of: _row('第一课'), matching: find.byTooltip('媒体操作')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('从头播放'));
      await _flush(
        tester,
        until: () =>
            harness.playback.position == Duration.zero &&
            harness.playback.playing,
      );
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.playback.position, Duration.zero);
      expect(harness.playback.playing, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'damaged state stays untouched through restore, timer and dispose',
    (tester) async {
      final harness = (await tester.runAsync(
        () => _DesktopHarness.create(corrupt: true),
      ))!;
      const primary = '{broken-primary';
      const backup = '{broken-backup';
      try {
        await harness.mount(tester, expectMedia: false);
        expect(harness.store.status, LocalStateStatus.blocked);
        expect(harness.transport.opened, isEmpty);
        expect(find.textContaining('已停止自动保存'), findsOneWidget);
        await tester.pump(const Duration(seconds: 12));
        await _flush(tester);
        expect(await tester.runAsync(harness.stateFile.readAsString), primary);
        expect(await tester.runAsync(harness.backupFile.readAsString), backup);
        await tester.pumpWidget(const SizedBox.shrink());
        await _flush(tester);
        expect(await tester.runAsync(harness.stateFile.readAsString), primary);
        expect(await tester.runAsync(harness.backupFile.readAsString), backup);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'a good backup restores the page and preserves a damaged primary',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      const damaged = '{damaged-primary-with-good-backup';
      try {
        await tester.runAsync(() => harness.stateFile.writeAsString(damaged));
        await harness.mount(tester);
        expect(harness.playback.localPath, harness.first.path);
        expect(harness.playback.position, const Duration(seconds: 12));
        expect(find.textContaining('已从最近的正常备份恢复'), findsOneWidget);
        expect(harness.store.preservedCorruptPaths, isNotEmpty);
        expect(
          await tester.runAsync(
            () =>
                File(harness.store.preservedCorruptPaths.first).readAsString(),
          ),
          damaged,
        );
        expect(find.text('共 2 项'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('natural completion advances sequentially and stops at the end', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      harness.transport.finish();
      await _flush(
        tester,
        until: () =>
            harness.playback.localPath == harness.second.path &&
            harness.playback.playing,
      );
      expect(harness.playback.position, Duration.zero);
      expect(harness.transport.opened, [harness.first.uri, harness.second.uri]);
      harness.transport.finish();
      await _flush(tester);
      expect(harness.playback.localPath, harness.second.path);
      expect(harness.playback.playing, isFalse);
      expect(harness.transport.opened.length, 2);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'repeat-one restarts the current media after natural completion',
    (tester) async {
      final harness = (await tester.runAsync(
        () => _DesktopHarness.create(mode: PlaylistMode.repeatOne),
      ))!;
      try {
        await harness.mount(tester);
        await harness.playback.play();
        harness.transport.finish();
        await _flush(
          tester,
          until: () =>
              harness.playback.playing &&
              harness.playback.position == Duration.zero,
        );
        expect(harness.playback.localPath, harness.first.path);
        expect(harness.transport.opened, isNot(contains(harness.second.uri)));
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('sequential completion skips an unreadable next item', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await tester.runAsync(() async {
        final seed = (await harness.store.read())!;
        seed['lessons'] = [
          ...harness.lessons.map((lesson) => lesson.toJson()),
          LocalLesson(title: '第三课', videoPath: harness.third.path).toJson(),
        ];
        await harness.store.write(seed);
      });
      harness.transport.failures[harness.second.path] = StateError(
        'unreadable fixture',
      );
      await harness.mount(tester);
      await harness.playback.play();
      harness.transport.finish();
      await _flush(
        tester,
        until: () =>
            harness.playback.localPath == harness.third.path &&
            harness.playback.playing,
      );
      expect(harness.transport.attempted, contains(harness.second.uri));
      expect(harness.transport.opened, [harness.first.uri, harness.third.uri]);
      expect(
        find.descendant(of: _row('第二课'), matching: find.text('文件不可用')),
        findsOneWidget,
      );
      expect(find.textContaining('已跳过 1 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('repeat-all wraps the last lesson to the first', (tester) async {
    final harness = (await tester.runAsync(
      () =>
          _DesktopHarness.create(mode: PlaylistMode.repeatAll, initialIndex: 1),
    ))!;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      harness.transport.finish();
      await _flush(
        tester,
        until: () =>
            harness.playback.localPath == harness.first.path &&
            harness.playback.playing,
      );
      expect(harness.playback.position, Duration.zero);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('manual playback mode does not auto advance', (tester) async {
    final harness = (await tester.runAsync(
      () => _DesktopHarness.create(mode: PlaylistMode.manual),
    ))!;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      harness.transport.finish();
      await _flush(tester);
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.playback.playing, isFalse);
      expect(harness.transport.opened, [harness.first.uri]);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('EOF in the mode menu honors the newly chosen manual mode', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      await tester.tap(find.text('顺序播放'));
      await tester.pumpAndSettle();
      harness.transport.finish();
      await _flush(tester);
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.transport.opened.length, 1);
      await tester.tap(find.text('播完暂停').last);
      await _flush(
        tester,
        until: () =>
            tester.widget<PlayerPlaylist>(find.byType(PlayerPlaylist)).mode ==
            PlaylistMode.manual,
      );
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.playback.playing, isFalse);
      expect(harness.transport.opened.length, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'cancelling a mode menu after EOF resumes the existing sequence',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        await harness.mount(tester);
        await harness.playback.play();
        await tester.tap(find.text('顺序播放'));
        await tester.pumpAndSettle();
        harness.transport.finish();
        await _flush(tester);
        expect(harness.playback.localPath, harness.first.path);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _flush(
          tester,
          until: () =>
              harness.playback.localPath == harness.second.path &&
              harness.playback.playing,
        );
        expect(harness.transport.opened, [
          harness.first.uri,
          harness.second.uri,
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('playlist search keeps F and Space inside the editor', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      final search = find.descendant(
        of: find.byType(PlayerPlaylist),
        matching: find.byType(TextField),
      );
      await tester.tap(search);
      await tester.enterText(search, '第二课');
      await tester.pump();
      final plays = harness.transport.playCount;
      final seeks = harness.transport.seeks.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _flush(tester);
      expect(
        harness.platformCalls.where((call) => call.method == 'setFullScreen'),
        isEmpty,
      );
      expect(harness.transport.playCount, plays);
      expect(harness.transport.seeks.length, seeks);
      expect(harness.playback.position, const Duration(seconds: 12));
      expect(tester.widget<TextField>(search).controller!.text, '第二课');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'a failed item can be identified and relocated without native plugins',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        await harness.mount(tester);
        harness.transport.failures[harness.second.path] = StateError(
          'fixture decoder failure',
        );
        await tester.tap(_row('第二课'));
        await _flush(
          tester,
          until: () => harness.transport.attempted.contains(harness.second.uri),
        );
        expect(
          find.descendant(of: _row('第二课'), matching: find.text('文件不可用')),
          findsOneWidget,
        );
        harness.picker.picked = _PickedFile(harness.third);
        await tester.tap(
          find.descendant(of: _row('第二课'), matching: find.byTooltip('媒体操作')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新定位文件'));
        await _flush(
          tester,
          until: () =>
              harness.picker.requests > 0 &&
              find.text('文件不可用').evaluate().isEmpty,
        );
        final saved = await _withIo(tester, harness.store.read);
        expect(
          (saved!['lessons'] as List).any(
            (value) => (value as Map)['video'] == harness.third.path,
          ),
          isTrue,
        );
        expect(find.text('文件不可用'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'a dropped video is added and played through the platform channel',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        await harness.mount(tester);
        await harness.nativeCall(tester, 'filesDropped', {
          'paths': [harness.third.path],
        });
        await _flush(
          tester,
          until: () =>
              harness.playback.localPath == harness.third.path &&
              harness.playback.playing,
        );
        expect(find.text('共 3 项'), findsOneWidget);
        expect(harness.playback.position, Duration.zero);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets('native fullscreen state changes keep the player and position', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    try {
      await harness.mount(tester);
      await harness.nativeCall(tester, 'fullScreenChanged', true);
      await _flush(tester);
      expect(find.text('基础知识学习'), findsNothing);
      expect(harness.transport.opened, [harness.first.uri]);
      expect(harness.playback.position, const Duration(seconds: 12));
      await harness.nativeCall(tester, 'fullScreenChanged', false);
      await _flush(tester);
      expect(find.text('基础知识学习'), findsOneWidget);
      expect(find.byType(PlayerPlaylist), findsOneWidget);
      expect(harness.transport.opened, [harness.first.uri]);
      expect(harness.playback.position, const Duration(seconds: 12));
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
    'fullscreen controls hide while playing and Tab reveals a control',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await harness.mount(tester);
        await harness.playback.play();
        await harness.nativeCall(tester, 'fullScreenChanged', true);
        await mouse.addPointer(location: const Offset(640, 400));
        await mouse.moveTo(const Offset(641, 400));
        await tester.pump();
        final exit = find.byTooltip('退出全屏 (Esc)').first;
        final chrome = find.ancestor(
          of: exit,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedOpacity &&
                widget.duration == const Duration(milliseconds: 180),
          ),
        );
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);

        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
        expect(
          tester
              .widget<IgnorePointer>(
                find
                    .ancestor(of: exit, matching: find.byType(IgnorePointer))
                    .first,
              )
              .ignoring,
          isTrue,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);
        final focusedChrome = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<AnimatedOpacity>();
        expect(
          focusedChrome,
          isNotNull,
          reason: 'Tab must reach a fullscreen control.',
        );
        expect(focusedChrome!.opacity, 1);
        await tester.pump(const Duration(seconds: 4));
        expect(
          tester.widget<AnimatedOpacity>(chrome).opacity,
          1,
          reason: 'Keyboard users must keep their focused controls visible.',
        );
        expect(harness.playback.playing, isTrue);
        expect(harness.transport.opened, [harness.first.uri]);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'video single tap pauses and double tap requests fullscreen without toggling',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        await harness.mount(tester);
        await harness.playback.play();
        await tester.pump();
        final stage = find.byKey(const ValueKey('player-stage'));
        await tester.tap(stage);
        await tester.pump(const Duration(milliseconds: 350));
        await _flush(tester, until: () => !harness.playback.playing);
        final pauses = harness.transport.pauseCount;
        final plays = harness.transport.playCount;

        await tester.tap(stage);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(stage);
        await _flush(
          tester,
          until: () => harness.platformCalls.any(
            (call) => call.method == 'setFullScreen',
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        final request = harness.platformCalls.singleWhere(
          (call) => call.method == 'setFullScreen',
        );
        expect(request.arguments, {'enabled': true});
        expect(harness.transport.pauseCount, pauses);
        expect(harness.transport.playCount, plays);
        expect(harness.playback.playing, isFalse);
        expect(harness.transport.opened, [harness.first.uri]);
        expect(harness.playback.position, const Duration(seconds: 12));
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  for (final missing in [false, true]) {
    testWidgets(
      '${missing ? 'missing' : 'invalid'} replacement subtitle preserves the current captions and saved path',
      (tester) async {
        final harness = (await tester.runAsync(_DesktopHarness.create))!;
        try {
          final original = (await tester.runAsync(
            () => harness.seedSubtitles(),
          ))!;
          final replacement = File('${harness.directory.path}/broken.srt');
          if (!missing) {
            await tester.runAsync(
              () => replacement.writeAsString('invalid subtitle text'),
            );
          }
          harness.picker.picked = _PickedFile(replacement);
          await harness.mount(tester);
          await _flush(
            tester,
            until: () => find.byType(ScreenSubtitleText).evaluate().isNotEmpty,
          );
          expect(
            tester
                .widget<ScreenSubtitleText>(find.byType(ScreenSubtitleText))
                .text,
            '保留的原字幕',
          );
          await tester.tap(find.text('字幕'));
          await tester.pumpAndSettle();
          expect(find.text('字幕  2'), findsOneWidget);
          await tester.tap(find.text('载入字幕'));
          await _flush(
            tester,
            until: () =>
                harness.picker.requests == 1 &&
                find.byType(MaterialBanner).evaluate().isNotEmpty,
          );

          expect(find.text('字幕  2'), findsOneWidget);
          expect(
            tester
                .widget<ScreenSubtitleText>(find.byType(ScreenSubtitleText))
                .text,
            '保留的原字幕',
          );
          expect(harness.transport.opened, [harness.first.uri]);
          expect(harness.playback.position, const Duration(seconds: 12));
          final saved = (await _withIo(tester, harness.store.read))!;
          expect(saved['subtitlePath'], original.path);
          final lessons = (saved['lessons'] as List).cast<Map>();
          expect(lessons.first['subtitle'], original.path);
          expect(
            MediaHistory.fromJson(saved)
                .getForLesson(harness.lessons.first)!
                .subtitlePath,
            original.path,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await harness.close(tester);
        }
      },
    );
  }

  testWidgets(
    'opening another media with broken subtitles clears the previous captions',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        await tester.runAsync(() => harness.seedSubtitles(brokenSecond: true));
        await harness.mount(tester);
        await _flush(
          tester,
          until: () => find.byType(ScreenSubtitleText).evaluate().isNotEmpty,
        );
        expect(find.byType(ScreenSubtitleText), findsOneWidget);
        await tester.tap(_row('第二课'));
        await _flush(
          tester,
          until: () =>
              harness.playback.localPath == harness.second.path &&
              find.byType(MaterialBanner).evaluate().isNotEmpty,
        );
        expect(find.byType(ScreenSubtitleText), findsNothing);
        expect(harness.transport.opened, [
          harness.first.uri,
          harness.second.uri,
        ]);
        expect(harness.playback.playing, isTrue);
        await tester.tap(find.text('字幕'));
        await tester.pumpAndSettle();
        expect(find.text('字幕  0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'G dialog keeps editor keys local and seeks only after its route completes',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      try {
        harness.transport.durations[harness.first.path] = const Duration(
          hours: 2,
        );
        await harness.mount(tester);
        final initialSeeks = List<Duration>.of(harness.transport.seeks);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.pumpAndSettle();
        expect(find.text('跳转到时间'), findsOneWidget);
        final editor = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.pump();
        expect(
          harness.platformCalls.where((call) => call.method == 'setFullScreen'),
          isEmpty,
        );
        await tester.enterText(editor, '00:06');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(harness.transport.seeks, initialSeeks);
        expect(harness.playback.position, const Duration(seconds: 12));

        for (final target in <String, Duration>{
          '00:06': const Duration(seconds: 6),
          '1:02:03': const Duration(hours: 1, minutes: 2, seconds: 3),
        }.entries) {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
          await tester.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          final route = ModalRoute.of(tester.element(dialog))!;
          var routeCompleted = false;
          unawaited(route.completed.then((_) => routeCompleted = true));
          final completedWhenSeeking = <bool>[];
          harness.transport.onSeek = (_) =>
              completedWhenSeeking.add(routeCompleted);
          await tester.enterText(
            find.descendant(of: dialog, matching: find.byType(TextFormField)),
            target.key,
          );
          await tester.tap(find.text('跳转'));
          await tester.pump();
          expect(routeCompleted, isFalse);
          expect(
            completedWhenSeeking,
            isEmpty,
            reason: 'Seeking must wait until the dialog reverse transition finishes.',
          );
          await _flush(
            tester,
            until: () => harness.playback.position == target.value,
          );
          expect(routeCompleted, isTrue);
          expect(completedWhenSeeking, [true]);
          expect(harness.transport.seeks.last, target.value);
          expect(find.byType(AlertDialog), findsNothing);
        }
        expect(harness.transport.opened, [harness.first.uri]);
        expect(harness.playback.playing, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
      }
    },
  );

  testWidgets(
    'clearing the playlist prevents a pending dropped video from autoplaying',
    (tester) async {
      final harness = (await tester.runAsync(_DesktopHarness.create))!;
      final scanner = _HeldScanner();
      harness.scanMedia = scanner.call;
      try {
        await harness.mount(tester);
        await harness.playback.play();
        late Future<ByteData?> reply;
        await tester.runAsync(() async {
          reply = harness.beginNativeCall(tester, 'filesDropped', {
            'paths': [harness.third.path],
          });
        });
        await _flush(tester, until: () => scanner.calls == 1);
        await tester.tap(find.text('清空'));
        await _flush(tester, until: () => harness.playback.localPath == null);
        expect(find.text('共 0 项'), findsOneWidget);
        expect(harness.playback.playing, isFalse);
        expect(harness.playback.position, Duration.zero);
        expect(harness.playback.duration, Duration.zero);
        final plays = harness.transport.playCount;

        scanner.completeMedia(harness.third);
        await _withIo(tester, () => reply);
        await _flush(tester);
        expect(find.text('共 1 项'), findsOneWidget);
        expect(harness.playback.localPath, isNull);
        expect(harness.playback.playing, isFalse);
        expect(harness.transport.playCount, plays);
        expect(harness.transport.opened, [harness.first.uri]);
        final saved = (await _withIo(tester, harness.store.read))!;
        expect((saved['lessons'] as List).length, 1);
        expect(saved['current'], isNull);
        expect(tester.takeException(), isNull);
      } finally {
        scanner.finishIfPending();
        await harness.close(tester);
      }
    },
  );

  testWidgets('a pending folder scan leaves pause and seek controls usable', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    final scanner = _HeldScanner();
    harness.scanMedia = scanner.call;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      late Future<ByteData?> reply;
      await tester.runAsync(() async {
        reply = harness.beginNativeCall(tester, 'filesDropped', {
          'paths': [harness.directory.path],
        });
      });
      await _flush(tester, until: () => scanner.calls == 1);
      expect(find.textContaining('已扫描 24 项'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停 (空格)'));
      await _flush(tester, until: () => !harness.playback.playing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _flush(
        tester,
        until: () => harness.playback.position == const Duration(seconds: 17),
      );
      scanner.completeMedia(harness.third, directory: true);
      await _withIo(tester, () => reply);
      await _flush(tester);
      expect(harness.playback.playing, isFalse);
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.playback.position, const Duration(seconds: 17));
      expect(harness.transport.opened, [harness.first.uri]);
      expect(find.text('共 3 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      scanner.finishIfPending();
      await harness.close(tester);
    }
  });

  testWidgets('a pending direct drop yields to a new selection and pause', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    final scanner = _HeldScanner();
    harness.scanMedia = scanner.call;
    try {
      await harness.mount(tester);
      await harness.playback.play();
      late Future<ByteData?> reply;
      await tester.runAsync(() async {
        reply = harness.beginNativeCall(tester, 'filesDropped', {
          'paths': [harness.third.path],
        });
      });
      await _flush(tester, until: () => scanner.calls == 1);
      await tester.tap(_row('第二课'));
      await _flush(
        tester,
        until: () =>
            harness.playback.localPath == harness.second.path &&
            harness.playback.playing,
      );
      harness.transport.emitPosition(const Duration(seconds: 18));
      await tester.pump();
      await tester.tap(find.byTooltip('暂停 (空格)'));
      await _flush(tester, until: () => !harness.playback.playing);
      scanner.completeMedia(harness.third);
      await _withIo(tester, () => reply);
      await _flush(tester);
      expect(harness.playback.localPath, harness.second.path);
      expect(harness.playback.position, const Duration(seconds: 18));
      expect(harness.playback.playing, isFalse);
      expect(harness.transport.opened, [harness.first.uri, harness.second.uri]);
      expect(find.text('共 3 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      scanner.finishIfPending();
      await harness.close(tester);
    }
  });

  testWidgets('cancelling a scan ignores even partial results returned later', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_DesktopHarness.create))!;
    final scanner = _HeldScanner();
    harness.scanMedia = scanner.call;
    try {
      await harness.mount(tester);
      late Future<ByteData?> reply;
      await tester.runAsync(() async {
        reply = harness.beginNativeCall(tester, 'filesDropped', {
          'paths': [harness.directory.path],
        });
      });
      await _flush(tester, until: () => scanner.calls == 1);
      await tester.tap(find.text('取消导入'));
      await tester.pump();
      expect(scanner.cancellation!.cancelled, isTrue);
      scanner.completeMedia(harness.third, directory: true);
      await _withIo(tester, () => reply);
      await _flush(tester);
      expect(find.text('共 2 项'), findsOneWidget);
      expect(harness.playback.localPath, harness.first.path);
      expect(harness.playback.position, const Duration(seconds: 12));
      expect(harness.transport.opened, [harness.first.uri]);
      final saved = await _withIo(tester, harness.store.read);
      expect((saved!['lessons'] as List).length, 2);
      expect(tester.takeException(), isNull);
    } finally {
      scanner.finishIfPending();
      await harness.close(tester);
    }
  });
}

Finder _row(String title) => find.widgetWithText(ListTile, title);

Future<void> _flush(WidgetTester tester, {bool Function()? until}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    do {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Desktop player operation did not finish.');
      }
    } while (until != null && !until());
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pump(const Duration(milliseconds: 50));
}

Future<T> _withIo<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  late T value;
  await tester.runAsync(() async {
    var complete = false;
    Object? failure;
    StackTrace? failureStack;
    operation().then(
      (result) {
        value = result;
        complete = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        complete = true;
      },
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!complete) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Desktop player I/O did not finish.');
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  });
  return value;
}

class _DesktopHarness {
  _DesktopHarness(
    this.directory,
    this.first,
    this.second,
    this.third,
    this.initialIndex,
    this.transport,
  ) : store = LocalStateStore(directory: Directory('${directory.path}/state')),
      theme = AppThemeController(
        preferences: ThemePreferences(directory: directory),
      ),
      playback = OfflinePlayback.withTransport(transport);

  final Directory directory;
  final File first;
  final File second;
  final File third;
  final int initialIndex;
  final LocalStateStore store;
  final AppThemeController theme;
  final OfflinePlayback playback;
  final platformCalls = <MethodCall>[];
  final picker = _Picker();
  LocalMediaScanner? scanMedia;
  FilePickerPlatform? originalPicker;
  final FakeDesktopPlaybackTransport transport;
  bool _closed = false;

  List<LocalLesson> get lessons => [
    LocalLesson(title: '第一课', videoPath: first.path),
    LocalLesson(title: '第二课', videoPath: second.path),
  ];
  File get stateFile =>
      File('${directory.path}/state/offline-player-state.json');
  File get backupFile => File('${stateFile.path}.bak');

  Future<File> seedSubtitles({bool brokenSecond = false}) async {
    final subtitle = await File('${directory.path}/original.srt').writeAsString(
      '1\n00:00:00,000 --> 00:00:20,000\n保留的原字幕\n\n'
      '2\n00:00:20,000 --> 00:00:40,000\n后面的第二句\n',
    );
    final saved = (await store.read())!;
    final items = lessons.map((lesson) => lesson.toJson()).toList();
    items.first['subtitle'] = subtitle.path;
    if (brokenSecond) {
      final broken = await File('${directory.path}/broken-second.srt')
          .writeAsString('invalid subtitle text');
      items.last['subtitle'] = broken.path;
    }
    await store.write({
      ...saved,
      'lessons': items,
      'subtitlePath': subtitle.path,
    });
    return subtitle;
  }

  static Future<_DesktopHarness> create({
    PlaylistMode mode = PlaylistMode.sequential,
    int initialIndex = 0,
    bool corrupt = false,
  }) async {
    var directory = await Directory.systemTemp.createTemp(
      'desktop-player-page-',
    );
    directory = Directory(await directory.resolveSymbolicLinks());
    final first = await File('${directory.path}/第一课.mp4').writeAsBytes([0]);
    final second = await File('${directory.path}/第二课.mp4').writeAsBytes([0]);
    final third = await File('${directory.path}/重新定位.mp4').writeAsBytes([0]);
    final harness = _DesktopHarness(
      directory,
      first,
      second,
      third,
      initialIndex,
      FakeDesktopPlaybackTransport(),
    );
    if (corrupt) {
      await harness.stateFile.parent.create(recursive: true);
      await harness.stateFile.writeAsString('{broken-primary');
      await harness.backupFile.writeAsString('{broken-backup');
    } else {
      await harness.store.write({
        'lessons': harness.lessons.map((lesson) => lesson.toJson()).toList(),
        'current': harness.lessons[initialIndex].primaryPath,
        'positionMs': 12000,
        'showPlaylist': true,
        'playlistMode': mode.name,
        'autoAdvance': mode.autoAdvance,
      });
    }
    return harness;
  }

  Future<void> mount(WidgetTester tester, {bool expectMedia = true}) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_files, (
      call,
    ) async {
      platformCalls.add(call);
      return switch (call.method) {
        'getFullScreen' => false,
        'restorePaths' => <String>[],
        _ => null,
      };
    });
    await tester.pumpWidget(
      AppThemeScope(
        controller: theme,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: PlayerPage(
            playback: playback,
            stateStore: store,
            videoSurface: const ColoredBox(color: Colors.black),
            scanMedia: scanMedia,
          ),
        ),
      ),
    );
    await _flush(
      tester,
      until: () => expectMedia
          ? playback.localPath == lessons[initialIndex].primaryPath
          : store.status == LocalStateStatus.blocked,
    );
  }

  Future<void> nativeCall(
    WidgetTester tester,
    String method,
    Object? arguments,
  ) async {
    await _withIo(tester, () => beginNativeCall(tester, method, arguments));
    await tester.pump();
  }

  Future<ByteData?> beginNativeCall(
    WidgetTester tester,
    String method,
    Object? arguments,
  ) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _files.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await _withIo(tester, playback.close);
    if (store.canWrite) await _withIo(tester, store.read);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await directory.delete(recursive: true);
    });
    theme.dispose();
    if (originalPicker != null) FilePickerPlatform.instance = originalPicker!;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _files,
      null,
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class _HeldScanner {
  final _result = Completer<LocalMediaScan>();
  MediaScanCancellation? cancellation;
  int calls = 0;

  Future<LocalMediaScan> call(
    Iterable<String> paths, {
    MediaScanCancellation? cancellation,
    void Function(MediaScanProgress)? onProgress,
    required bool includeCompanions,
  }) {
    calls++;
    this.cancellation = cancellation;
    onProgress?.call(
      const MediaScanProgress(files: 24, media: 1, directories: 2),
    );
    return _result.future;
  }

  void completeMedia(File file, {bool directory = false}) {
    if (_result.isCompleted) return;
    _result.complete(
      LocalMediaScan(
        lessons: [LocalLesson(title: stemOf(file.path), videoPath: file.path)],
        directMediaPath: directory ? null : file.path,
        containsDirectories: directory,
        unreadablePaths: const [],
      ),
    );
  }

  void finishIfPending() {
    if (_result.isCompleted) return;
    _result.complete(
      const LocalMediaScan(
        lessons: [],
        directMediaPath: null,
        containsDirectories: true,
        unreadablePaths: [],
        cancelled: true,
      ),
    );
  }
}

class _Picker extends FilePickerPlatform {
  PlatformFile? picked;
  int requests = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requests++;
    return picked;
  }
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.file);
  final File file;

  @override
  String get name => file.uri.pathSegments.last;
  @override
  Uri get uri => file.uri;
  @override
  Never get xFile => throw UnsupportedError('Fixture does not need XFile.');
  @override
  int lengthSync() => 1;
  @override
  Future<int> length() async => 1;
  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}
