import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/theme/app_theme.dart';
import 'package:offline_player/widgets/stable_slider.dart';

void main() {
  final binding = _RecordingThemeBinding();

  test(
    'appearance persists independently of player and study records',
    () async {
      final directory = await Directory.systemTemp.createTemp('app-theme-');
      final playerState = File('${directory.path}/offline-player-state.json');
      final studyState = File('${directory.path}/study-progress.json');
      try {
        await playerState.writeAsString('{"positionMs":12000}');
        await studyState.writeAsString('{"lesson_id":"story:0001"}');
        final preferences = ThemePreferences(directory: directory);
        expect(await preferences.read(), ThemeMode.system);
        final first = AppThemeController(preferences: preferences);
        await first.load();
        await first.setThemeMode(ThemeMode.light);
        first.dispose();

        final restored = AppThemeController(
          preferences: ThemePreferences(directory: directory),
        );
        await restored.load();
        expect(restored.themeMode, ThemeMode.light);
        expect(await playerState.readAsString(), '{"positionMs":12000}');
        expect(await studyState.readAsString(), '{"lesson_id":"story:0001"}');
        restored.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('rapid theme choices persist the last selection', () async {
    final directory = await Directory.systemTemp.createTemp('app-theme-');
    try {
      final controller = AppThemeController(
        preferences: ThemePreferences(directory: directory),
      );
      await controller.load();
      await Future.wait([
        controller.setThemeMode(ThemeMode.dark),
        controller.setThemeMode(ThemeMode.light),
        controller.setThemeMode(ThemeMode.system),
      ]);
      expect(controller.themeMode, ThemeMode.system);
      final restored = AppThemeController(
        preferences: ThemePreferences(directory: directory),
      );
      await restored.load();
      expect(restored.themeMode, ThemeMode.system);
      restored.dispose();
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'damaged preferences recover to system without affecting content',
    () async {
      final directory = await Directory.systemTemp.createTemp('app-theme-');
      try {
        final preferences = ThemePreferences(directory: directory);
        await preferences.write(ThemeMode.dark);
        final preferenceFile = (await directory.list(recursive: true).toList())
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.json'));
        await preferenceFile.writeAsString('{invalid JSON');
        expect(await preferences.read(), ThemeMode.system);
        await preferences.write(ThemeMode.light);
        expect(await preferences.read(), ThemeMode.light);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('theme menu changes all routes without resetting page state', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('app-theme-widget-'),
    );
    final controller = AppThemeController(
      preferences: ThemePreferences(directory: directory!),
    );
    try {
      await tester.pumpWidget(_ThemeHarness(controller: controller));
      await tester.tap(find.text('增加'));
      await tester.pump();
      expect(find.text('计数：1'), findsOneWidget);

      for (final choice in [
        (label: '浅色', mode: ThemeMode.light, brightness: Brightness.light),
        (label: '深色', mode: ThemeMode.dark, brightness: Brightness.dark),
      ]) {
        await tester.tap(find.byTooltip('外观主题'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, choice.label));
        await tester.pumpAndSettle();
        await _applyAndFlush(tester, controller);
        expect(controller.themeMode, choice.mode);
        expect(_brightness(tester), choice.brightness);
        expect(find.text('计数：1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      expect(find.text('详情正文'), findsOneWidget);
      expect(
        _brightness(tester, key: const ValueKey('detail-body')),
        Brightness.dark,
      );
      await tester.tap(find.byTooltip('外观主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '浅色'));
      await tester.pumpAndSettle();
      await _applyAndFlush(tester, controller);
      expect(
        _brightness(tester, key: const ValueKey('detail-body')),
        Brightness.light,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('计数：1'), findsOneWidget);
      expect(_brightness(tester), Brightness.light);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _applyAndFlush(tester, controller);
      await tester.runAsync(() => directory.delete(recursive: true));
      controller.dispose();
    }
  });

  testWidgets(
    'theme changes only after the appearance dialog exits completely',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('app-theme-transition-'),
      );
      final controller = AppThemeController(
        preferences: ThemePreferences(directory: directory!),
      );
      final semantics = tester.ensureSemantics();
      var removed = false;
      var changedBeforeRemoval = false;
      void observeTheme() {
        if (controller.themeMode == ThemeMode.light && !removed) {
          changedBeforeRemoval = true;
        }
      }

      try {
        await _applyAndFlush(tester, controller, ThemeMode.dark);
        await tester.pumpWidget(_ThemeHarness(controller: controller));
        await tester.tap(find.byTooltip('外观主题'));
        await tester.pumpAndSettle();
        final choice = find.widgetWithText(ListTile, '浅色');
        final route = ModalRoute.of(tester.element(choice))!;
        expect(route, isA<DialogRoute<Object>>());
        route.completed.then((_) => removed = true);
        controller.addListener(observeTheme);

        await tester.tap(choice);
        await tester.pump();
        expect(controller.themeMode, ThemeMode.dark);
        final halfway = Duration(
          microseconds: route.reverseTransitionDuration.inMicroseconds ~/ 2,
        );
        expect(halfway, greaterThan(Duration.zero));
        await tester.pump(halfway);
        expect(route.animation!.value, greaterThan(0));
        expect(removed, isFalse);
        expect(controller.themeMode, ThemeMode.dark);
        expect(_brightness(tester), Brightness.dark);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(removed, isTrue);
        expect(controller.themeMode, ThemeMode.light);
        expect(_brightness(tester), Brightness.light);
        expect(changedBeforeRemoval, isFalse);
        expect(find.byType(SimpleDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        controller.removeListener(observeTheme);
        await tester.pumpWidget(const SizedBox.shrink());
        await _applyAndFlush(tester, controller);
        await tester.runAsync(() => directory.delete(recursive: true));
        controller.dispose();
        semantics.dispose();
      }
    },
  );

  for (final animatesTheme in [true, false]) {
    testWidgets(
      'theme and route updates keep incremental slider semantics connected ${animatesTheme ? 'animated' : 'noAnimation'}',
      (tester) async {
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('app-theme-semantics-'),
        );
        final controller = AppThemeController(
          preferences: ThemePreferences(directory: directory!),
        );
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        try {
          await _applyAndFlush(tester, controller, ThemeMode.dark);
          binding.recorder.reset();
          await tester.pumpWidget(
            _ThemeHarness(
              controller: controller,
              withSlider: true,
              themeAnimationStyle: animatesTheme
                  ? null
                  : AnimationStyle.noAnimation,
            ),
          );
          await tester.pumpAndSettle();
          for (final stage in ['home-cold', 'home-dragged', 'detail']) {
            if (stage == 'detail') {
              await tester.tap(find.text('打开详情'));
              await tester.pumpAndSettle();
            }
            for (final label in ['浅色', '深色', '跟随系统']) {
              binding.recorder.stage = '$stage/$label';
              if (stage != 'home-cold') {
                final slider = find.byType(Slider).last;
                final gesture = await tester.startGesture(
                  tester.getCenter(slider),
                );
                await gesture.moveBy(const Offset(35, 0));
                await tester.pump(const Duration(milliseconds: 300));
                await gesture.up();
                await tester.pumpAndSettle();
              }
              await mouse.moveTo(tester.getCenter(find.byTooltip('外观主题')));
              await tester.pump(const Duration(seconds: 1));
              await mouse.down(tester.getCenter(find.byTooltip('外观主题')));
              await mouse.up();
              await tester.pumpAndSettle();
              await tester.tap(find.widgetWithText(ListTile, label));
              await tester.pumpAndSettle();
              await _applyAndFlush(tester, controller);
              expect(tester.takeException(), isNull);
              expect(binding.recorder.structuralFailures, isEmpty);
            }
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(binding.recorder.structuralFailures, isEmpty);
          expect(binding.recorder.commits, greaterThan(15));
          expect(binding.recorder.incrementalCommits, greaterThan(0));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _applyAndFlush(tester, controller);
          await tester.runAsync(() => directory.delete(recursive: true));
          controller.dispose();
          await mouse.removePointer();
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'grafted traversal child is not serialized when its traversal parent is missing',
    (tester) async {
      // Regression for Flutter PR 193372 / issue 190357. A disconnected update
      // can reach the native accessibility bridge even when root has no children.
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(const Placeholder(), phase: EnginePhase.build);
        binding.recorder.reset();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                Semantics(
                  traversalChildIdentifier: 'missing-traversal-parent',
                  child: const SizedBox.square(dimension: 10),
                ),
                const SizedBox.square(dimension: 10),
              ],
            ),
          ),
        );
        expect(binding.recorder.lastDelta.keys, [0]);
        expect(binding.recorder.lastDelta[0], isEmpty);
        expect(binding.recorder.lastHitTestDelta[0], isEmpty);
        expect(binding.recorder.structuralFailures, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'portal children are omitted with hidden anchor and reconnected when it reappears',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final opacity = ValueNotifier<double>(0);
      final controller = OverlayPortalController()..show();
      final entry = OverlayEntry(
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (_, value, _) => Opacity(
            opacity: value,
            child: OverlayPortal(
              controller: controller,
              overlayChildBuilder: (_) => Semantics(
                container: true,
                label: 'portal child',
                button: true,
                child: const SizedBox.square(dimension: 20),
              ),
              child: Semantics(
                container: true,
                label: 'anchor',
                button: true,
                child: const SizedBox.square(dimension: 20),
              ),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(const Placeholder(), phase: EnginePhase.build);
        binding.recorder.reset();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Overlay(initialEntries: [entry]),
          ),
        );
        expect(binding.recorder.lastDelta.keys, [0]);
        expect(binding.recorder.lastHitTestDelta[0], isEmpty);
        expect(binding.recorder.structuralFailures, isEmpty);

        opacity.value = 1;
        await tester.pump();
        expect(binding.recorder.children.length, greaterThanOrEqualTo(4));
        expect(binding.recorder.structuralFailures, isEmpty);

        opacity.value = 0;
        await tester.pump();
        expect(binding.recorder.lastDelta.keys, [0]);
        expect(binding.recorder.lastDelta[0], isEmpty);
        expect(binding.recorder.lastHitTestDelta[0], isEmpty);
        expect(binding.recorder.structuralFailures, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        entry.remove();
        entry.dispose();
        opacity.dispose();
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'system appearance follows brightness while explicit choice stays',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('app-theme-system-'),
      );
      final controller = AppThemeController(
        preferences: ThemePreferences(directory: directory!),
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      try {
        await tester.pumpWidget(_ThemeHarness(controller: controller));
        expect(_brightness(tester), Brightness.light);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(_brightness(tester), Brightness.dark);

        await _applyAndFlush(tester, controller, ThemeMode.light);
        expect(_brightness(tester), Brightness.light);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(_brightness(tester), Brightness.light);

        await _applyAndFlush(tester, controller, ThemeMode.system);
        expect(_brightness(tester), Brightness.dark);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(_brightness(tester), Brightness.light);
        expect(tester.takeException(), isNull);
      } finally {
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        await tester.pumpWidget(const SizedBox.shrink());
        await _applyAndFlush(tester, controller);
        await tester.runAsync(() => directory.delete(recursive: true));
        controller.dispose();
      }
    },
  );

  test('body, secondary, emphasis and selection colors remain readable', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      final colors = theme.colorScheme;
      for (final surface in [
        theme.scaffoldBackgroundColor,
        colors.surface,
        colors.surfaceContainer,
      ]) {
        for (final foreground in [
          colors.onSurface,
          colors.onSurfaceVariant,
          colors.primary,
          colors.tertiary,
        ]) {
          expect(
            _contrast(foreground, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness text $foreground on $surface',
          );
        }
      }
      expect(
        _contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

Future<void> _applyAndFlush(
  WidgetTester tester,
  AppThemeController controller, [
  ThemeMode? value,
]) async {
  await tester.runAsync(() async {
    var done = false;
    Object? error;
    StackTrace? trace;
    controller
        .setThemeMode(value ?? controller.themeMode)
        .then(
          (_) => done = true,
          onError: (Object failure, StackTrace stack) {
            error = failure;
            trace = stack;
            done = true;
          },
        );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Appearance file I/O did not settle.');
      }
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
  });
  await tester.pumpAndSettle();
}

Brightness _brightness(
  WidgetTester tester, {
  Key key = const ValueKey('page-body'),
}) => Theme.of(tester.element(find.byKey(key))).brightness;

double _contrast(Color a, Color b) {
  final aLuminance = a.computeLuminance(), bLuminance = b.computeLuminance();
  final high = aLuminance > bLuminance ? aLuminance : bLuminance;
  final low = aLuminance < bLuminance ? aLuminance : bLuminance;
  return (high + 0.05) / (low + 0.05);
}

class _ThemeHarness extends StatelessWidget {
  const _ThemeHarness({
    required this.controller,
    this.withSlider = false,
    this.themeAnimationStyle,
  });
  final AppThemeController controller;
  final bool withSlider;
  final AnimationStyle? themeAnimationStyle;

  @override
  Widget build(BuildContext context) => AppThemeScope(
    controller: controller,
    child: AnimatedBuilder(
      animation: controller,
      builder: (_, child) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: controller.themeMode,
        themeAnimationStyle: themeAnimationStyle,
        home: child,
      ),
      child: _CounterPage(withSlider: withSlider),
    ),
  );
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({this.withSlider = false});
  final bool withSlider;
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;
  double value = 0.3;
  double volume = 0.6;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(actions: const [ThemeMenuButton()]),
    body: Column(
      key: const ValueKey('page-body'),
      children: [
        Text('计数：$count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: const Text('增加'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(actions: const [ThemeMenuButton()]),
                body: Column(
                  children: [
                    const Text('详情正文', key: ValueKey('detail-body')),
                    if (widget.withSlider) const _DetailSlider(),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('打开详情'),
        ),
        if (widget.withSlider)
          StableSlider(
            value: value,
            divisions: 10,
            label: '${(value * 100).round()}',
            showValueIndicator: ShowValueIndicator.onDrag,
            onChanged: (next) => setState(() => value = next),
          ),
        if (widget.withSlider)
          StableSlider(
            value: volume,
            onChanged: (next) => setState(() => volume = next),
          ),
      ],
    ),
  );
}

class _DetailSlider extends StatefulWidget {
  const _DetailSlider();
  @override
  State<_DetailSlider> createState() => _DetailSliderState();
}

class _DetailSliderState extends State<_DetailSlider> {
  double value = 0.4;
  @override
  Widget build(BuildContext context) => StableSlider(
    value: value,
    divisions: 10,
    label: '${(value * 100).round()}',
    showValueIndicator: ShowValueIndicator.onDrag,
    onChanged: (next) => setState(() => value = next),
  );
}

class _RecordingThemeBinding extends AutomatedTestWidgetsFlutterBinding {
  final recorder = _ThemeSemanticsRecorder();
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingThemeUpdateBuilder(
        super.createSemanticsUpdateBuilder(),
        recorder,
      );
}

class _ThemeSemanticsRecorder {
  final Map<int, List<int>> children = {};
  Map<int, List<int>> lastDelta = {};
  Map<int, List<int>> lastHitTestDelta = {};
  final List<String> structuralFailures = [];
  int commits = 0;
  int incrementalCommits = 0;
  String stage = 'initial';
  void reset() {
    children.clear();
    lastDelta = {};
    lastHitTestDelta = {};
    structuralFailures.clear();
    commits = 0;
    incrementalCommits = 0;
    stage = 'initial';
  }

  void record(Map<int, List<int>> delta, Map<int, List<int>> hitTestDelta) {
    lastDelta = Map.of(delta);
    lastHitTestDelta = Map.of(hitTestDelta);
    commits++;
    if (!delta.containsKey(0)) incrementalCommits++;
    children.addAll(delta);
    final reachable = <int>{};
    final pending = <int>[0];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (reachable.add(id)) pending.addAll(children[id] ?? const []);
    }
    final orphans = delta.keys.where((id) => !reachable.contains(id)).toList();
    if (orphans.isNotEmpty) {
      structuralFailures.add(
        '$stage commit $commits orphan updates $orphans; delta=$delta',
      );
    }
    final parents = <int, int>{};
    for (final parent in reachable) {
      for (final child in children[parent] ?? const <int>[]) {
        if (!children.containsKey(child)) {
          structuralFailures.add(
            '$stage commit $commits missing child $child of $parent; delta=$delta',
          );
        }
        final previous = parents[child];
        if (previous != null && previous != parent) {
          structuralFailures.add(
            '$stage commit $commits child $child has parents $previous and $parent; delta=$delta',
          );
        }
        parents[child] = parent;
      }
    }
    children.removeWhere((id, _) => !reachable.contains(id));
  }
}

class _RecordingThemeUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingThemeUpdateBuilder(this.delegate, this.recorder);
  final ui.SemanticsUpdateBuilder delegate;
  final _ThemeSemanticsRecorder recorder;
  final Map<int, List<int>> delta = {};
  final Map<int, List<int>> hitTestDelta = {};
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final arguments = invocation.namedArguments;
      delta[arguments[#id] as int] = List<int>.of(
        arguments[#childrenInTraversalOrder] as List<int>,
      );
      hitTestDelta[arguments[#id] as int] = List<int>.of(
        arguments[#childrenInHitTestOrder] as List<int>,
      );
      Function.apply(delegate.updateNode, [], arguments);
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );
  @override
  ui.SemanticsUpdate build() {
    recorder.record(delta, hitTestDelta);
    return delegate.build();
  }
}
