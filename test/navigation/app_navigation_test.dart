import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/app_section_menu_button.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/theme/app_theme.dart';

class _MemoryPreferences extends NavigationPreferences {
  _MemoryPreferences([this.saved = AppSection.home]);
  AppSection saved;
  @override
  Future<AppSection> read() async => saved;
  @override
  Future<void> write(AppSection section) async {
    if (section != AppSection.home) saved = section;
  }
}

void main() {
  test(
    'section preferences persist only the last activity in their own file',
    () async {
      final root = await Directory.systemTemp.createTemp('ggs-navigation-');
      try {
        final unrelated = File('${root.path}/study-progress.json');
        await unrelated.writeAsString('{"lesson":"untouched"}');
        final preferences = NavigationPreferences(directory: root);
        expect(await preferences.read(), AppSection.home);
        await preferences.write(AppSection.quiz);
        expect(
          await NavigationPreferences(directory: root).read(),
          AppSection.quiz,
        );
        await preferences.write(AppSection.home);
        expect(await preferences.read(), AppSection.quiz);
        expect(await unrelated.readAsString(), '{"lesson":"untouched"}');
        final json = jsonDecode(
          await File('${root.path}/last-section.json').readAsString(),
        );
        expect(json, {'version': 1, 'section': 'quiz'});
        await File('${root.path}/last-section.json').writeAsString('{broken');
        expect(await preferences.read(), AppSection.home);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'first open has three equal entry points, menu can switch and go home',
    (tester) async {
      final preferences = _MemoryPreferences();
      final controller = AppNavigationController(preferences: preferences);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(_host(controller));
      expect(find.byKey(const ValueKey('home-entry-study')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-entry-quiz')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-entry-player')), findsOneWidget);
      expect(find.text('module-player'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-entry-study')));
      await tester.pumpAndSettle();
      expect(find.text('module-study'), findsOneWidget);
      expect(preferences.saved, AppSection.study);
      await tester.tap(find.byKey(const ValueKey('app-section-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-section-quiz')));
      await tester.pumpAndSettle();
      expect(find.text('module-quiz'), findsOneWidget);
      expect(find.text('module-study'), findsNothing);
      expect(preferences.saved, AppSection.quiz);
      unawaited(controller.navigate(AppSection.home));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-entry-study')), findsOneWidget);
      expect(preferences.saved, AppSection.quiz);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopening goes straight to the last module without mounting a player',
    (tester) async {
      final controller = AppNavigationController(
        preferences: _MemoryPreferences(AppSection.quiz),
      );
      addTearDown(controller.dispose);
      final mounted = <AppSection>[];
      await controller.load();
      await tester.pumpWidget(_host(controller, onBuild: mounted.add));
      expect(find.text('module-quiz'), findsOneWidget);
      expect(mounted, [AppSection.quiz]);
      expect(find.byKey(const ValueKey('home-entry-study')), findsNothing);
    },
  );

  testWidgets(
    'leave guard can refuse, and resource shutdown finishes before next module mounts',
    (tester) async {
      final controller = AppNavigationController(
        preferences: _MemoryPreferences(AppSection.study),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final events = <String>[];
      final shutdown = Completer<void>();
      await tester.pumpWidget(
        _host(
          controller,
          onBuild: (section) => events.add('build-${section.name}'),
          onDisposeStudy: () {
            events.add('dispose-study');
            controller.trackShutdown(
              shutdown.future.then((_) => events.add('closed-study')),
            );
          },
        ),
      );
      final unregister = controller.registerBeforeLeave(() async {
        events.add('refused');
        return false;
      });
      unawaited(controller.navigate(AppSection.player));
      await tester.pumpAndSettle();
      expect(find.text('module-study'), findsOneWidget);
      expect(events, isNot(contains('dispose-study')));
      unregister();
      controller.registerBeforeLeave(() async {
        events.add('paused-study');
        return true;
      });
      final switching = controller.navigate(AppSection.player);
      await tester.pump();
      await tester.pump();
      expect(find.text('module-study'), findsNothing);
      expect(find.text('module-player'), findsNothing);
      expect(
        events.indexOf('paused-study'),
        lessThan(events.indexOf('dispose-study')),
      );
      shutdown.complete();
      await tester.pumpAndSettle();
      await switching;
      expect(find.text('module-player'), findsOneWidget);
      expect(
        events.indexOf('closed-study'),
        lessThan(events.lastIndexOf('build-player')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['zh', 'ja', 'en']) {
    for (final size in [const Size(320, 844), const Size(1200, 850)]) {
      testWidgets('$language entry page fits $size with large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = AppNavigationController(
          preferences: _MemoryPreferences(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        await tester.pumpWidget(
          _host(controller, language: language, scale: 1.5),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-entry-player')), findsOneWidget);
      });
    }
  }

  testWidgets('section menu is absent in standalone legacy page hosts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppSectionMenuButton())),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  AppNavigationController controller, {
  String language = 'zh',
  double scale = 1,
  ValueChanged<AppSection>? onBuild,
  VoidCallback? onDisposeStudy,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationDelegates,
  theme: buildAppTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: GoodGoodStudyShell(
    controller: controller,
    iconAsset: null,
    phonePlayback: true,
    builders: {
      for (final section in [
        AppSection.study,
        AppSection.quiz,
        AppSection.player,
      ])
        section: (_) {
          onBuild?.call(section);
          return _ModulePage(
            section: section,
            onDispose: section == AppSection.study ? onDisposeStudy : null,
          );
        },
    },
  ),
);

class _ModulePage extends StatefulWidget {
  const _ModulePage({required this.section, this.onDispose});
  final AppSection section;
  final VoidCallback? onDispose;
  @override
  State<_ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<_ModulePage> {
  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('module-${widget.section.name}'),
      actions: const [AppSectionMenuButton()],
    ),
  );
}
