import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/widgets/player_shortcuts.dart';

void main() {
  testWidgets(
    'holding space toggles playback once, including repeated events',
    (tester) async {
      final harness = _ShortcutsHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build());
      harness.stageFocus.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      expect(harness.events, ['toggle']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(harness.events, ['toggle']);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(harness.events, ['toggle', 'toggle']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('playback keys seek, change volume, mute and open time entry', (
    tester,
  ) async {
    final harness = _ShortcutsHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.stageFocus.requestFocus();
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.escape,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(harness.events, [
      'seek:-5',
      'seek:5',
      'seek:-10',
      'seek:10',
      'volume:5.0',
      'volume:-5.0',
      'mute',
      'goToTime',
      'fullScreen',
      'escape',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alt arrows jump cues without also seeking', (tester) async {
    final harness = _ShortcutsHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.stageFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(harness.events, ['previousCue', 'nextCue']);
  });

  testWidgets('text entry retains player keys and does not trigger shortcuts', (
    tester,
  ) async {
    final harness = _ShortcutsHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '日本語 FM JL');
    await tester.pump();
    expect(harness.editorFocus.hasFocus, isTrue);

    for (final key in [
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.escape,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(harness.events, isEmpty);
    expect(harness.editorFocus.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '日本語 FM JL',
    );
    expect(tester.takeException(), isNull);

    harness.stageFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(harness.events, ['fullScreen']);
  });

  testWidgets('disabled playback accepts only fullscreen and escape', (
    tester,
  ) async {
    final harness = _ShortcutsHarness()..enabled = false;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.stageFocus.requestFocus();
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.escape,
    ]) {
      // Ignored arrow keys may legitimately move focus through MaterialApp's
      // default traversal actions. Verify each binding from the player surface.
      harness.stageFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(harness.events, ['fullScreen', 'escape']);
  });

  testWidgets('unrelated modifier chords do not toggle or change playback', (
    tester,
  ) async {
    final harness = _ShortcutsHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.stageFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(harness.events, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
    expect(harness.events, ['mute']);
  });

  testWidgets(
    'space controls playback before a focused button or list tile activates',
    (tester) async {
      final harness = _ShortcutsHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build());

      for (final focus in [
        harness.playFocus,
        harness.openFocus,
        harness.lessonFocus,
      ]) {
        harness.events.clear();
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        expect(harness.events, ['toggle']);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one-shot repeats are consumed before child shortcut fallbacks', (
    tester,
  ) async {
    final harness = _ShortcutsHarness()..probeChildShortcuts = true;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.playFocus.requestFocus();
    await tester.pump();

    for (final entry in <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.space: 'toggle',
      LogicalKeyboardKey.keyF: 'fullScreen',
      LogicalKeyboardKey.keyM: 'mute',
      LogicalKeyboardKey.keyG: 'goToTime',
      LogicalKeyboardKey.escape: 'escape',
    }.entries) {
      harness.events.clear();
      await tester.sendKeyDownEvent(entry.key);
      await tester.sendKeyRepeatEvent(entry.key);
      await tester.sendKeyRepeatEvent(entry.key);
      await tester.sendKeyUpEvent(entry.key);
      expect(harness.events, [entry.value]);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'modal route keeps its own keys and player shortcuts resume after closing',
    (tester) async {
      final harness = _ShortcutsHarness();
      final modalFocus = FocusNode();
      final modalEvents = <String>[];
      addTearDown(harness.dispose);
      addTearDown(modalFocus.dispose);
      await tester.pumpWidget(harness.build());
      unawaitedDialog(
        harness.navigatorKey.currentContext!,
        modalFocus,
        modalEvents,
      );
      await tester.pumpAndSettle();
      expect(modalFocus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      expect(modalEvents, ['activate', 'f', 'm', 'g']);
      expect(harness.events, isEmpty);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      harness.stageFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(harness.events, ['toggle']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pushed study route is not intercepted by the background player',
    (tester) async {
      final harness = _ShortcutsHarness();
      final studyEvents = <LogicalKeyboardKey>[];
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build());
      harness.navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) {
                  studyEvents.add(event.logicalKey);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const Text('学习页'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const keys = [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.escape,
      ];
      for (final key in keys) {
        await tester.sendKeyEvent(key);
      }
      expect(studyEvents, keys);
      expect(harness.events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removed player unregisters its early key handler', (
    tester,
  ) async {
    final harness = _ShortcutsHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    var replacementActivations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilledButton(
            autofocus: true,
            onPressed: () => replacementActivations++,
            child: const Text('另一个界面'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(replacementActivations, 1);
    expect(harness.events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'optional Tab traversal reports direction and preserves editor and modifier behavior',
    (tester) async {
      final harness = _ShortcutsHarness()
        ..onTraverseControls = (backwards) => true;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.build());
      harness.stageFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(harness.traversals, [false, true]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(harness.traversals, [false, true]);

      harness.editorFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(harness.traversals, [false, true]);
      expect(harness.events, isEmpty);
    },
  );

  testWidgets('declined optional Tab traversal uses normal focus traversal', (
    tester,
  ) async {
    final harness = _ShortcutsHarness()
      ..onTraverseControls = (backwards) => false;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    harness.stageFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(harness.traversals, [false]);
    expect(harness.playFocus.hasPrimaryFocus, isTrue);
    expect(harness.events, isEmpty);
  });
}

void unawaitedDialog(
  BuildContext context,
  FocusNode focus,
  List<String> events,
) {
  showDialog<void>(
    context: context,
    builder: (_) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF): () => events.add('f'),
        const SingleActivator(LogicalKeyboardKey.keyM): () => events.add('m'),
        const SingleActivator(LogicalKeyboardKey.keyG): () => events.add('g'),
      },
      child: AlertDialog(
        title: const Text('弹层'),
        actions: [
          FilledButton(
            autofocus: true,
            focusNode: focus,
            onPressed: () => events.add('activate'),
            child: const Text('弹层操作'),
          ),
        ],
      ),
    ),
  );
}

class _ShortcutsHarness {
  final navigatorKey = GlobalKey<NavigatorState>();
  final stageFocus = FocusNode();
  final editorFocus = FocusNode();
  final playFocus = FocusNode();
  final openFocus = FocusNode();
  final lessonFocus = FocusNode();
  final editor = TextEditingController();
  final events = <String>[];
  bool enabled = true;
  bool probeChildShortcuts = false;
  bool Function(bool backwards)? onTraverseControls;
  final traversals = <bool>[];

  Widget build() => MaterialApp(
    navigatorKey: navigatorKey,
    home: Scaffold(
      body: PlayerShortcuts(
        enabled: enabled,
        onToggle: () => events.add('toggle'),
        onSeek: (offset) => events.add('seek:${offset.inSeconds}'),
        onVolume: (offset) => events.add('volume:$offset'),
        onMute: () => events.add('mute'),
        onFullScreen: () => events.add('fullScreen'),
        onEscape: () => events.add('escape'),
        onPreviousCue: () => events.add('previousCue'),
        onNextCue: () => events.add('nextCue'),
        onGoToTime: () => events.add('goToTime'),
        onTraverseControls: onTraverseControls == null
            ? null
            : (backwards) {
                traversals.add(backwards);
                return onTraverseControls!(backwards);
              },
        child: Column(
          children: [
            TextField(controller: editor, focusNode: editorFocus),
            Focus(focusNode: stageFocus, child: const Text('视频画面')),
            CallbackShortcuts(
              bindings: probeChildShortcuts
                  ? {
                      for (final key in [
                        LogicalKeyboardKey.space,
                        LogicalKeyboardKey.keyF,
                        LogicalKeyboardKey.keyM,
                        LogicalKeyboardKey.keyG,
                        LogicalKeyboardKey.escape,
                      ])
                        SingleActivator(key): () =>
                            events.add('child:${key.keyLabel}'),
                    }
                  : const {},
              child: FilledButton(
                focusNode: playFocus,
                onPressed: () => events.add('activate:play'),
                child: const Text('播放'),
              ),
            ),
            TextButton(
              focusNode: openFocus,
              onPressed: () => events.add('activate:open'),
              child: const Text('打开文件'),
            ),
            ListTile(
              focusNode: lessonFocus,
              title: const Text('第2课'),
              onTap: () => events.add('activate:lesson'),
            ),
          ],
        ),
      ),
    ),
  );

  void dispose() {
    stageFocus.dispose();
    editorFocus.dispose();
    playFocus.dispose();
    openFocus.dispose();
    lessonFocus.dispose();
    editor.dispose();
  }
}
