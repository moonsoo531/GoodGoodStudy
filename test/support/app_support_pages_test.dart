import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_language.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/support/app_info_gateway.dart';
import 'package:offline_player/support/support_pages.dart';
import 'package:offline_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(AppInfoGateway.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'build info uses the installed version and links stay within this project',
    () async {
      final opened = <String>[];
      messenger.setMockMethodCallHandler(AppInfoGateway.channel, (call) async {
        if (call.method == 'getInfo') {
          return {'version': '2.3.4', 'buildNumber': '57'};
        }
        opened.add((call.arguments as Map)['url'] as String);
        return true;
      });
      const gateway = AppInfoGateway();
      final info = await gateway.getInfo();
      expect(info?.version, '2.3.4');
      expect(info?.buildNumber, '57');
      expect(await gateway.openLink(AppSupportLinks.privacy), isTrue);
      for (final url in [
        'https://github.com/moonsoo531/AnotherProject',
        'https://github.com/moonsoo531/GoodGoodStudy-other',
        'https://github.com/moonsoo531/GoodGoodStudy/blob/main/unlisted.md',
        '${AppSupportLinks.privacy}?raw=1',
        '${AppSupportLinks.privacy}#section',
        'https://example.com/moonsoo531/GoodGoodStudy',
        'file:///private/user-document',
      ]) {
        expect(await gateway.openLink(Uri.parse(url)), isFalse);
      }
      expect(opened, [AppSupportLinks.privacy.toString()]);
    },
  );

  for (final language in ['zh', 'ja', 'en']) {
    for (final size in [const Size(320, 844), const Size(834, 1194)]) {
      testWidgets('$language help and about remain usable at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opened = <String>[];
        messenger.setMockMethodCallHandler(AppInfoGateway.channel, (
          call,
        ) async {
          if (call.method == 'getInfo') {
            return {'version': '2.3.4', 'buildNumber': '57'};
          }
          opened.add((call.arguments as Map)['url'] as String);
          return true;
        });
        final scale = size.width < 400 ? 1.5 : 1.0;
        await tester.pumpWidget(_host(language, const ImportHelpPage(), scale));
        await tester.pumpAndSettle();
        final title = switch (language) {
          'ja' => '読み込みガイド',
          'en' => 'Import help',
          _ => '导入帮助',
        };
        expect(find.text(title), findsOneWidget);
        expect(find.text('manifest.json'), findsNWidgets(2));
        expect(find.text('lessons.json'), findsOneWidget);
        expect(find.text('entries.json'), findsOneWidget);
        expect(find.text('questions.json'), findsOneWidget);
        expect(find.textContaining('512 MiB'), findsOneWidget);
        expect(find.textContaining('32 MiB'), findsOneWidget);
        final quizDocs = find.byKey(const ValueKey('quiz-format-link'));
        await tester.ensureVisible(quizDocs);
        await tester.pumpAndSettle();
        await tester.tap(quizDocs);
        await tester.pumpAndSettle();
        expect(opened, [AppSupportLinks.quizFormat.toString()]);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _host(
            language,
            const AppAboutPage(),
            scale,
            key: const ValueKey('about-host'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('GoodGoodStudy'), findsOneWidget);
        expect(find.textContaining('2.3.4'), findsOneWidget);
        final privacy = find.byKey(const ValueKey('privacy-policy-link'));
        await tester.ensureVisible(privacy);
        await tester.pumpAndSettle();
        await tester.tap(privacy);
        await tester.pumpAndSettle();
        expect(opened.last, AppSupportLinks.privacy.toString());
        expect(find.byType(AlertDialog), findsNothing);
        final components = find.byKey(const ValueKey('component-licenses'));
        await tester.ensureVisible(components);
        await tester.pumpAndSettle();
        expect(tester.getRect(components).right, lessThanOrEqualTo(size.width));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('settings dismisses its dialog before opening help or about', (
    tester,
  ) async {
    final themes = AppThemeController();
    final languages = AppLanguageController();
    messenger.setMockMethodCallHandler(
      AppInfoGateway.channel,
      (call) async => call.method == 'getInfo'
          ? {'version': '2.3.4', 'buildNumber': '57'}
          : true,
    );
    try {
      await tester.pumpWidget(
        AppThemeScope(
          controller: themes,
          child: AppLanguageScope(
            controller: languages,
            child: _host(
              'zh',
              Scaffold(appBar: AppBar(actions: const [ThemeMenuButton()])),
              1,
            ),
          ),
        ),
      );
      for (final destination in [
        (key: 'import-help-settings', type: ImportHelpPage),
        (key: 'about-app-settings', type: AppAboutPage),
      ]) {
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        final entry = find.byKey(ValueKey(destination.key));
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        final route = ModalRoute.of(tester.element(entry))!;
        var removed = false;
        route.completed.then((_) => removed = true);
        await tester.tap(entry);
        await tester.pump();
        await tester.pump(
          Duration(
            microseconds: route.reverseTransitionDuration.inMicroseconds ~/ 2,
          ),
        );
        expect(find.byType(destination.type), findsNothing);
        await tester.pumpAndSettle();
        expect(removed, isTrue);
        expect(find.byType(SimpleDialog), findsNothing);
        expect(find.byType(destination.type), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      themes.dispose();
      languages.dispose();
    }
  });

  for (final platformError in [false, true]) {
    testWidgets(
      '${platformError ? 'platform exception' : 'unavailable browser'} retains a copyable privacy link',
      (tester) async {
        String? copied;
        messenger.setMockMethodCallHandler(AppInfoGateway.channel, (
          call,
        ) async {
          if (platformError) {
            throw PlatformException(
              code: 'unavailable',
              message: 'native-detail-not-for-display',
            );
          }
          return call.method == 'getInfo' ? null : false;
        });
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        await tester.pumpWidget(_host('en', const AppAboutPage(), 1));
        await tester.pumpAndSettle();
        expect(find.text('Version information is unavailable'), findsOneWidget);
        final privacy = find.byKey(const ValueKey('privacy-policy-link'));
        await tester.ensureVisible(privacy);
        await tester.pumpAndSettle();
        await tester.tap(privacy);
        await tester.pumpAndSettle();
        expect(find.text('Could not open the link'), findsOneWidget);
        expect(
          find.textContaining('native-detail-not-for-display'),
          findsNothing,
        );
        expect(find.text(AppSupportLinks.privacy.toString()), findsOneWidget);
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(copied, AppSupportLinks.privacy.toString());
        expect(find.text('Link copied'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _host(String language, Widget home, double scale, {Key? key}) =>
    MaterialApp(
      key: key,
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: appLocalizationDelegates,
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );
