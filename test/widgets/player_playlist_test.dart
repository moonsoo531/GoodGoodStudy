import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/playlist_mode.dart';
import 'package:offline_player/widgets/player_playlist.dart';

const _lessons = [
  LocalLesson(title: '第一课', videoPath: '/lessons/01.mp4'),
  LocalLesson(title: '第二课', audioPath: '/lessons/02.mp3'),
  LocalLesson(title: '第三课', videoPath: '/lessons/03.mp4'),
];

void main() {
  testWidgets('current media remains identifiable while playback changes', (
    tester,
  ) async {
    final harness = _PlaylistHarness();
    harness.current = LocalLesson.fromJson(_lessons[1].toJson());
    harness.playing = true;
    await tester.pumpWidget(harness.build());

    expect(find.text('共 3 项'), findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第二课')).selected,
      isTrue,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第一课')).selected,
      isFalse,
    );
    expect(find.text('1 · 视频'), findsOneWidget);
    expect(find.text('3 · 视频'), findsOneWidget);

    harness.playing = false;
    await tester.pumpWidget(harness.build());
    expect(find.text('正在播放'), findsNothing);
    expect(find.text('当前媒体 · 已暂停'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第二课')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting a row supplies that lesson and updates current media',
    (tester) async {
      final harness = _PlaylistHarness();
      await tester.pumpWidget(harness.build());
      expect(find.text('2 · 音频'), findsOneWidget);

      await tester.tap(find.text('第二课'));
      await tester.pumpAndSettle();

      expect(harness.selected, [_lessons[1]]);
      expect(harness.removed, isEmpty);
      expect(find.text('当前媒体 · 已暂停'), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '第二课')).selected,
        isTrue,
      );
    },
  );

  testWidgets('removing one row does not also select it or affect other rows', (
    tester,
  ) async {
    final harness = _PlaylistHarness();
    harness.current = _lessons.first;
    await tester.pumpWidget(harness.build());

    final remove = find.descendant(
      of: find.widgetWithText(ListTile, '第二课'),
      matching: find.byTooltip('从播放列表移除'),
    );
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(harness.removed, [_lessons[1]]);
    expect(harness.selected, isEmpty);
    expect(find.text('第二课'), findsNothing);
    expect(find.text('第一课'), findsOneWidget);
    expect(find.text('第三课'), findsOneWidget);
    expect(find.text('共 2 项'), findsOneWidget);
    expect(find.text('当前媒体 · 已暂停'), findsOneWidget);
  });

  testWidgets('clearing the list displays drop guidance and disables clear', (
    tester,
  ) async {
    final harness = _PlaylistHarness();
    await tester.pumpWidget(harness.build());
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(harness.clearCount, 1);
    expect(harness.selected, isEmpty);
    expect(find.text('共 0 项'), findsOneWidget);
    expect(find.textContaining('播放列表为空'), findsOneWidget);
    expect(find.textContaining('拖入视频即可播放'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '清空'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(harness.clearCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'auto advance can be switched off and on without selecting media',
    (tester) async {
      final harness = _PlaylistHarness();
      await tester.pumpWidget(harness.build());
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );

      await tester.tap(find.text('自动播放下一项'));
      await tester.pumpAndSettle();
      expect(harness.autoAdvanceChanges, [false]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      await tester.tap(find.text('自动播放下一项'));
      await tester.pumpAndSettle();
      expect(harness.autoAdvanceChanges, [false, true]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(harness.selected, isEmpty);
      expect(harness.removed, isEmpty);
    },
  );

  testWidgets(
    'disabled list blocks selection, removal, clearing, settings and drag',
    (tester) async {
      final harness = _PlaylistHarness()..enabled = false;
      await tester.pumpWidget(harness.build());

      await tester.tap(find.text('第二课'));
      await tester.tap(find.byTooltip('从播放列表移除').first);
      await tester.tap(find.text('清空'));
      await tester.tap(find.text('自动播放下一项'));
      await tester.drag(
        find.byIcon(Icons.drag_indicator).first,
        const Offset(0, 130),
      );
      await tester.pumpAndSettle();

      expect(harness.selected, isEmpty);
      expect(harness.removed, isEmpty);
      expect(harness.clearCount, 0);
      expect(harness.autoAdvanceChanges, isEmpty);
      expect(harness.reorders, isEmpty);
      expect(find.text('共 3 项'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag handle reorders media without changing the current lesson',
    (tester) async {
      final harness = _PlaylistHarness()..current = _lessons.first;
      await tester.pumpWidget(harness.build());

      final firstHandle = find.byIcon(Icons.drag_indicator).first;
      final destination = Offset(
        tester.getCenter(firstHandle).dx,
        tester.getBottomLeft(find.byType(ReorderableListView)).dy - 45,
      );
      final gesture = await tester.startGesture(tester.getCenter(firstHandle));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(harness.reorders, [(0, 2)]);
      expect(harness.lessons, [_lessons[1], _lessons[2], _lessons[0]]);
      expect(harness.selected, isEmpty);
      expect(harness.current, _lessons.first);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '第一课')).selected,
        isTrue,
      );
      expect(find.text('当前媒体 · 已暂停'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters by folder and disables reordering filtered rows',
    (tester) async {
      final harness = _PlaylistHarness();
      await tester.pumpWidget(harness.build());
      await tester.enterText(find.byType(TextField), '02.MP3');
      await tester.pumpAndSettle();
      expect(find.text('找到 1 / 3 项'), findsOneWidget);
      expect(find.text('第二课'), findsOneWidget);
      expect(find.text('第一课'), findsNothing);
      expect(find.byTooltip('清除搜索后可排序'), findsOneWidget);
      expect(
        tester
            .widget<ReorderableDragStartListener>(
              find.byType(ReorderableDragStartListener),
            )
            .enabled,
        isFalse,
      );
      await tester.drag(
        find.byIcon(Icons.drag_indicator),
        const Offset(0, 130),
      );
      await tester.pumpAndSettle();
      expect(harness.reorders, isEmpty);
      await tester.tap(find.text('第二课'));
      await tester.pumpAndSettle();
      expect(harness.selected, [_lessons[1]]);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('共 3 项'), findsOneWidget);
      expect(find.text('第一课'), findsOneWidget);
    },
  );

  testWidgets(
    'locate current clears a query and reveals a distant current item',
    (tester) async {
      final harness = _PlaylistHarness();
      harness.lessons = [
        for (var i = 0; i < 45; i++)
          LocalLesson(title: '第${i + 1}课', videoPath: '/lessons/$i.mp4'),
      ];
      harness.current = harness.lessons[38];
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      expect(find.text('第39课'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '第1课');
      await tester.pumpAndSettle();
      expect(find.text('第39课'), findsNothing);
      await tester.tap(find.byTooltip('定位当前项'));
      await tester.pumpAndSettle();
      expect(find.text('共 45 项'), findsOneWidget);
      expect(find.text('第39课'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('item status shows progress, completion and unavailable files', (
    tester,
  ) async {
    final harness = _PlaylistHarness();
    harness.statusOf = (lesson) => switch (lesson.title) {
      '第一课' => const PlaylistItemStatus(
        position: Duration(minutes: 3),
        duration: Duration(minutes: 10),
      ),
      '第二课' => const PlaylistItemStatus(
        duration: Duration(hours: 1, minutes: 2),
        completed: true,
      ),
      _ => const PlaylistItemStatus(error: 'missing'),
    };
    await tester.pumpWidget(harness.build());
    expect(find.text('03:00 / 10:00'), findsOneWidget);
    expect(find.text('已播完 · 1:02:00'), findsOneWidget);
    expect(find.text('文件不可用'), findsOneWidget);
    final values = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .map((widget) => widget.value)
        .toList();
    expect(values, [0.3, 1.0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('media menu supplies the correct lesson without selecting it', (
    tester,
  ) async {
    final harness = _PlaylistHarness()..withMenus = true;
    await tester.pumpWidget(harness.build());
    final secondRow = find.widgetWithText(ListTile, '第二课');
    await tester.tap(
      find.descendant(of: secondRow, matching: find.byTooltip('媒体操作')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('从头播放'));
    await tester.pumpAndSettle();
    expect(harness.replayed, [_lessons[1]]);
    expect(harness.selected, isEmpty);
    await tester.tap(
      find.descendant(of: secondRow, matching: find.byTooltip('媒体操作')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新定位文件'));
    await tester.pumpAndSettle();
    expect(harness.relocated, [_lessons[1]]);
    expect(harness.selected, isEmpty);
  });

  testWidgets(
    'explicit playback modes replace the legacy auto advance switch',
    (tester) async {
      final harness = _PlaylistHarness()..mode = PlaylistMode.sequential;
      await tester.pumpWidget(harness.build());
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('顺序播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('单项循环').last);
      await tester.pumpAndSettle();
      expect(harness.mode, PlaylistMode.repeatOne);
      expect(harness.modeChanges, [PlaylistMode.repeatOne]);
      expect(harness.autoAdvanceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('media actions wait until the actual menu route is removed', (
    tester,
  ) async {
    final observer = _MenuObserver();
    final harness = _PlaylistHarness()
      ..withMenus = true
      ..menuObserver = observer;
    await tester.pumpWidget(harness.build());
    for (final label in ['从头播放', '重新定位文件']) {
      await tester.tap(find.byTooltip('媒体操作').first);
      await tester.pumpAndSettle();
      harness.playing = !harness.playing;
      await tester.pumpWidget(harness.build());
      await tester.pump();
      final count = harness.menuCompletion.length;
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(observer.route!.reverseTransitionDuration ~/ 2);
      expect(observer.completed, isFalse);
      expect(harness.menuCompletion.length, count);
      await tester.pumpAndSettle();
      expect(observer.completed, isTrue);
      expect(harness.menuCompletion.last.$2, isTrue);
    }
    expect(harness.menuCompletion, [('replay', true), ('relocate', true)]);
    expect(harness.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode selection waits for the dropdown route to complete', (
    tester,
  ) async {
    final observer = _MenuObserver();
    final harness = _PlaylistHarness()
      ..mode = PlaylistMode.sequential
      ..menuObserver = observer;
    await tester.pumpWidget(harness.build());
    await tester.tap(find.text('顺序播放'));
    await tester.pumpAndSettle();
    harness.playing = true;
    await tester.pumpWidget(harness.build());
    await tester.pump();
    await tester.tap(find.text('单项循环').last);
    await tester.pump();
    await tester.pump(observer.route!.reverseTransitionDuration ~/ 2);
    expect(observer.completed, isFalse);
    expect(harness.modeChanges, isEmpty);
    await tester.pumpAndSettle();
    expect(harness.modeChanges, [PlaylistMode.repeatOne]);
    expect(harness.menuCompletion, [('mode', true)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'menu-close notifications follow actions and wait after cancellation',
    (tester) async {
      final observer = _MenuObserver();
      final harness = _PlaylistHarness()
        ..mode = PlaylistMode.sequential
        ..withMenus = true
        ..notifyMenuClosed = true
        ..menuObserver = observer;
      await tester.pumpWidget(harness.build());
      await tester.tap(find.text('顺序播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('列表循环').last);
      await tester.pumpAndSettle();
      expect(harness.menuCompletion, [('mode', true), ('closed', true)]);

      await tester.tap(find.text('列表循环'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(observer.route!.reverseTransitionDuration ~/ 2);
      expect(harness.menuCompletion.length, 2);
      await tester.pumpAndSettle();
      expect(harness.menuCompletion.last, ('closed', true));
      expect(harness.modeChanges, [PlaylistMode.repeatAll]);

      await tester.tap(find.byTooltip('媒体操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('从头播放'));
      await tester.pumpAndSettle();
      expect(harness.menuCompletion.sublist(3), [
        ('replay', true),
        ('closed', true),
      ]);
      await tester.tap(find.byTooltip('媒体操作').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(observer.route!.reverseTransitionDuration ~/ 2);
      expect(harness.menuCompletion.length, 5);
      await tester.pumpAndSettle();
      expect(harness.menuCompletion.last, ('closed', true));
      expect(harness.replayed, [_lessons.first]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PlaylistHarness {
  List<LocalLesson> lessons = List.of(_lessons);
  LocalLesson? current;
  bool playing = false;
  bool enabled = true;
  bool autoAdvance = true;
  bool withMenus = false;
  bool notifyMenuClosed = false;
  PlaylistMode? mode;
  PlaylistItemStatus Function(LocalLesson)? statusOf;
  final selected = <LocalLesson>[];
  final removed = <LocalLesson>[];
  final autoAdvanceChanges = <bool>[];
  final reorders = <(int, int)>[];
  final replayed = <LocalLesson>[];
  final relocated = <LocalLesson>[];
  final modeChanges = <PlaylistMode>[];
  _MenuObserver? menuObserver;
  final menuCompletion = <(String, bool)>[];
  int clearCount = 0;

  Widget build() => MaterialApp(
    navigatorObservers: [?menuObserver],
    home: Scaffold(
      body: SizedBox(
        width: 320,
        height: 450,
        child: StatefulBuilder(
          builder: (context, setState) => PlayerPlaylist(
            lessons: lessons,
            current: current,
            playing: playing,
            enabled: enabled,
            autoAdvance: autoAdvance,
            onSelect: (lesson) => setState(() {
              selected.add(lesson);
              current = lesson;
            }),
            onRemove: (lesson) => setState(() {
              removed.add(lesson);
              lessons.remove(lesson);
            }),
            onReorder: (oldIndex, newIndex) => setState(() {
              reorders.add((oldIndex, newIndex));
              lessons.insert(newIndex, lessons.removeAt(oldIndex));
            }),
            onClear: () => setState(() {
              clearCount++;
              lessons.clear();
            }),
            onAutoAdvanceChanged: (value) => setState(() {
              autoAdvanceChanges.add(value);
              autoAdvance = value;
            }),
            statusOf: statusOf,
            mode: mode,
            onModeChanged: (value) => setState(() {
              modeChanges.add(value);
              mode = value;
              if (menuObserver != null) {
                menuCompletion.add(('mode', menuObserver!.completed));
              }
            }),
            onReplay: withMenus
                ? (lesson) {
                    replayed.add(lesson);
                    if (menuObserver != null) {
                      menuCompletion.add(('replay', menuObserver!.completed));
                    }
                  }
                : null,
            onRelocate: withMenus
                ? (lesson) {
                    relocated.add(lesson);
                    if (menuObserver != null) {
                      menuCompletion.add(('relocate', menuObserver!.completed));
                    }
                  }
                : null,
            onMenuClosed: notifyMenuClosed
                ? () {
                    menuCompletion.add((
                      'closed',
                      menuObserver?.completed ?? false,
                    ));
                  }
                : null,
          ),
        ),
      ),
    ),
  );
}

class _MenuObserver extends NavigatorObserver {
  PopupRoute<dynamic>? route;
  bool completed = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) {
      this.route = route;
      completed = false;
      route.completed.then((_) => completed = true);
    }
    super.didPush(route, previousRoute);
  }
}
