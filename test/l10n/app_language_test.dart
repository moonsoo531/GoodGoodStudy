import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_language.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/theme/app_theme.dart';

void main() {
  test(
    'language defaults to Chinese and persists without changing records',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'interface-language-',
      );
      try {
        final media = File('${directory.path}/offline-player-state.json');
        final study = File('${directory.path}/study-progress.json');
        final appearance = File('${directory.path}/appearance.json');
        await media.writeAsString('{"positionMs":977550}');
        await study.writeAsString('{"lesson_id":"story:0001"}');
        await appearance.writeAsString('{"theme_mode":"dark"}');
        final first = AppLanguageController(
          preferences: LanguagePreferences(directory: directory),
        );
        await first.load();
        expect(first.language, AppLanguage.chinese);
        await first.setLanguage(AppLanguage.japanese);
        final restored = AppLanguageController(
          preferences: LanguagePreferences(directory: directory),
        );
        await restored.load();
        expect(restored.locale.languageCode, 'ja');
        expect(await media.readAsString(), '{"positionMs":977550}');
        expect(await study.readAsString(), '{"lesson_id":"story:0001"}');
        expect(await appearance.readAsString(), '{"theme_mode":"dark"}');
        first.dispose();
        restored.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('rapid choices persist the last language', () async {
    final directory = await Directory.systemTemp.createTemp(
      'interface-language-',
    );
    try {
      final controller = AppLanguageController(
        preferences: LanguagePreferences(directory: directory),
      );
      await Future.wait([
        controller.setLanguage(AppLanguage.japanese),
        controller.setLanguage(AppLanguage.english),
        controller.setLanguage(AppLanguage.chinese),
      ]);
      expect(
        await LanguagePreferences(directory: directory).read(),
        AppLanguage.chinese,
      );
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('a late load cannot overwrite a manual language choice', () async {
    final preferences = _DelayedPreferences();
    final controller = AppLanguageController(preferences: preferences);
    final load = controller.load();
    await controller.setLanguage(AppLanguage.english);
    preferences.value.complete(AppLanguage.japanese);
    await load;
    expect(controller.language, AppLanguage.english);
    controller.dispose();
  });

  test('bad and unsupported preferences fall back to Chinese', () async {
    final directory = await Directory.systemTemp.createTemp(
      'interface-language-',
    );
    try {
      final file = File('${directory.path}/interface-language.json');
      final preferences = LanguagePreferences(directory: directory);
      for (final value in ['{broken', '{"language":"xx"}', '[]']) {
        await file.writeAsString(value);
        expect(await preferences.read(), AppLanguage.chinese);
      }
      await preferences.write(AppLanguage.english);
      expect(await preferences.read(), AppLanguage.english);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('catalog translations preserve placeholders and all three variants', () {
    final placeholders = RegExp(r'\{\w+\}');
    for (final entry in interfaceTranslations.entries) {
      expect(entry.value, hasLength(2), reason: entry.key);
      final expected = placeholders
          .allMatches(entry.key)
          .map((m) => m[0])
          .toSet();
      for (final variant in entry.value) {
        expect(variant.trim(), isNotEmpty, reason: entry.key);
        expect(
          placeholders.allMatches(variant).map((m) => m[0]).toSet(),
          expected,
          reason: entry.key,
        );
      }
    }
    const english = AppLocalizations(Locale('en'));
    expect(
      english.text('已添加 {p0} 项到播放列表', {'p0': 3}),
      'Added 3 items to the playlist',
    );
    expect(
      english.message('保存进度失败：字幕文件中没有有效条目。'),
      'Could not save progress: The subtitle file has no valid cues.',
    );
    expect(english.message('未知用户文件名.mp4'), '未知用户文件名.mp4');
    expect(
      english.message('字幕文件中没有有效条目。\n这些媒体已在播放列表中'),
      'The subtitle file has no valid cues.\nThese files are already in the playlist',
    );
  });

  testWidgets(
    'settings switches all UI immediately after dismissal and survives reopening',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('language-settings-'),
      );
      final languages = AppLanguageController(
        preferences: LanguagePreferences(directory: directory),
      );
      final themes = AppThemeController(
        preferences: ThemePreferences(directory: directory),
      );
      final key = GlobalKey<_ContentState>();
      try {
        await tester.pumpWidget(
          AppThemeScope(
            controller: themes,
            child: AppLanguageScope(
              controller: languages,
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: AppLanguageScope.of(context).locale,
                  theme: buildAppTheme(Brightness.light),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: appLocalizationDelegates,
                  home: _Content(key: key),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = key.currentState;
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        expect(find.text('界面语言'), findsOneWidget);
        expect(find.text('中文'), findsOneWidget);
        expect(find.text('日本語'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('interface-language-ja')));
        await tester.pumpAndSettle();
        await _flushLanguage(tester, languages);
        expect(find.text('基礎知識の学習'), findsOneWidget);
        expect(find.text('教材：日本語の本文'), findsOneWidget);
        expect(key.currentState, same(state));
        expect(
          Localizations.localeOf(tester.element(find.byType(_Content)))
              .languageCode,
          'ja',
        );
        await tester.tap(find.byTooltip('設定'));
        await tester.pumpAndSettle();
        expect(find.text('表示言語'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('interface-language-en')));
        await tester.pumpAndSettle();
        await _flushLanguage(tester, languages);
        expect(find.text('Study'), findsOneWidget);
        expect(find.text('教材：日本語の本文'), findsOneWidget);
        expect(key.currentState, same(state));
        expect(
          await tester.runAsync(
            () => LanguagePreferences(directory: directory).read(),
          ),
          AppLanguage.english,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _flushLanguage(tester, languages);
        languages.dispose();
        themes.dispose();
        await tester.runAsync(() => directory!.delete(recursive: true));
      }
    },
  );
}

class _DelayedPreferences extends LanguagePreferences {
  final value = Completer<AppLanguage>();
  @override
  Future<AppLanguage> read() => value.future;
  @override
  Future<void> write(AppLanguage value) async {}
}

class _Content extends StatefulWidget {
  const _Content({super.key});
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.tr('基础知识学习')),
      actions: const [ThemeMenuButton()],
    ),
    body: const Text('教材：日本語の本文'),
  );
}

Future<void> _flushLanguage(
  WidgetTester tester,
  AppLanguageController controller,
) async {
  var done = false;
  controller.flush().then((_) => done = true);
  for (var i = 0; i < 60 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'Language preference writes must finish.');
  await tester.pumpAndSettle();
}
