import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_language.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/theme/app_theme.dart';

const _asset = 'assets/branding/goodgoodstudy-icon.png';
const _sections = [AppSection.study, AppSection.quiz, AppSection.player];

void main() {
  var japaneseFontLoaded = false;
  var cjkFontLoaded = false;
  var iconsLoaded = false;

  Future<void> loadRenderFonts(WidgetTester tester) async {
    await tester.runAsync(() async {
      if (!japaneseFontLoaded) {
        final folder = Directory('/System/Library/Fonts');
        final fonts = folder.existsSync()
            ? folder.listSync().whereType<File>().where(
                (file) => file.path.endsWith('W3.ttc'),
              )
            : const <File>[];
        if (fonts.isNotEmpty) {
          final bytes = await fonts.first.readAsBytes();
          await (FontLoader(
            'HomeRenderJapanese',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          japaneseFontLoaded = true;
        }
      }
      if (!cjkFontLoaded) {
        final fallbacks = [
          File('/System/Library/Fonts/Hiragino Sans GB.ttc'),
          File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
        ].where((file) => file.existsSync());
        if (fallbacks.isNotEmpty) {
          final bytes = await fallbacks.first.readAsBytes();
          await (FontLoader(
            'HomeRenderCjk',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          cjkFontLoaded = true;
        }
      }
      if (!iconsLoaded) {
        final sdk = _flutterSdk();
        final bytes = await File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        iconsLoaded = true;
      }
    });
  }

  for (final spec in [
    ('phone-zh', const Size(393, 852), 'zh', 1.0, true),
    ('desktop-zh', const Size(1100, 820), 'zh', 1.0, false),
    ('phone-en-large', const Size(393, 852), 'en', 1.5, true),
  ]) {
    testWidgets('home renders ${spec.$1} with equal module entries', (
      tester,
    ) async {
      await loadRenderFonts(tester);
      if (Platform.isMacOS) {
        expect(japaneseFontLoaded, isTrue);
        expect(cjkFontLoaded, isTrue);
      }
      tester.view.physicalSize = spec.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory temporary;
      late AppNavigationController navigation;
      late AppThemeController themeController;
      late AppLanguageController languageController;
      await tester.runAsync(() async {
        temporary = await Directory.systemTemp.createTemp('ggs-home-render-');
        navigation = AppNavigationController(
          preferences: NavigationPreferences(directory: temporary),
        );
        themeController = AppThemeController(
          preferences: ThemePreferences(directory: temporary),
        );
        languageController = AppLanguageController(
          preferences: LanguagePreferences(directory: temporary),
        );
        await navigation.load();
        await languageController.setLanguage(AppLanguage.fromCode(spec.$3));
      });
      final mounted = <AppSection>[];
      final boundaryKey = GlobalKey();
      final baseTheme = buildAppTheme(Brightness.light);
      final theme = japaneseFontLoaded
          ? baseTheme.copyWith(
              textTheme: baseTheme.textTheme.apply(
                fontFamily: 'HomeRenderJapanese',
                fontFamilyFallback: cjkFontLoaded
                    ? const ['HomeRenderCjk']
                    : null,
              ),
              primaryTextTheme: baseTheme.primaryTextTheme.apply(
                fontFamily: 'HomeRenderJapanese',
                fontFamilyFallback: cjkFontLoaded
                    ? const ['HomeRenderCjk']
                    : null,
              ),
            )
          : baseTheme;
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: AppThemeScope(
                controller: themeController,
                child: AppLanguageScope(
                  controller: languageController,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: Locale(spec.$3),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates: appLocalizationDelegates,
                    theme: theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(spec.$4)),
                      child: child!,
                    ),
                    home: GoodGoodStudyShell(
                      controller: navigation,
                      phonePlayback: spec.$5,
                      builders: {
                        for (final section in _sections)
                          section: (_) {
                            mounted.add(section);
                            return Scaffold(
                              body: Center(
                                child: Text('module-${section.name}'),
                              ),
                            );
                          },
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage(_asset),
            tester.element(find.byType(GoodGoodStudyShell)),
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('GoodGoodStudy'), findsOneWidget);
        expect(
          mounted,
          isEmpty,
          reason: 'The home page must not mount a media module.',
        );
        expect(navigation.section, AppSection.home);

        final assetImage = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == _asset,
        );
        expect(assetImage, findsOneWidget);
        final decoded = tester.widget<RawImage>(
          find.descendant(of: assetImage, matching: find.byType(RawImage)),
        );
        expect(
          decoded.image,
          isNotNull,
          reason: 'Render the actual brand icon, not its fallback.',
        );
        expect(tester.getSize(assetImage), const Size(68, 68));

        final labels = spec.$3 == 'zh'
            ? const ['学习', '测试', '本地播放']
            : const ['Study', 'Quiz', 'Local playback'];
        final materials = <Material>[];
        final sizes = <Size>[];
        final titleStyles = <TextStyle>[];
        for (var index = 0; index < _sections.length; index++) {
          final entry = find.byKey(
            ValueKey('home-entry-${_sections[index].name}'),
          );
          expect(entry, findsOneWidget);
          expect(tester.widget<InkWell>(entry).onTap, isNotNull);
          sizes.add(tester.getSize(entry));
          materials.add(
            tester.widget<Material>(
              find
                  .ancestor(
                    of: entry,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Material &&
                          widget.shape is RoundedRectangleBorder,
                    ),
                  )
                  .first,
            ),
          );
          titleStyles.add(
            tester
                .widget<Text>(
                  find.descendant(
                    of: entry,
                    matching: find.text(labels[index]),
                  ),
                )
                .style!,
          );
        }
        for (var index = 1; index < _sections.length; index++) {
          expect(sizes[index].width, closeTo(sizes.first.width, .1));
          if (!spec.$5) {
            expect(sizes[index].height, closeTo(sizes.first.height, .1));
          }
          expect(materials[index].color, materials.first.color);
          expect(materials[index].shape, materials.first.shape);
          expect(materials[index].elevation, materials.first.elevation);
          expect(titleStyles[index].fontSize, titleStyles.first.fontSize);
          expect(titleStyles[index].fontWeight, titleStyles.first.fontWeight);
        }
        expect(find.byKey(const ValueKey('app-section-menu')), findsOneWidget);
        expect(
          find.byTooltip(spec.$3 == 'zh' ? '设置' : 'Settings'),
          findsOneWidget,
        );
        await _save(tester, boundaryKey, 'home-${spec.$1}.png');

        final resources = find.text(
          spec.$3 == 'zh'
              ? '资源由你准备，所有资料保存在本机。'
              : 'Bring your own resources. Your materials stay on this device.',
        );
        expect(resources, findsOneWidget);
        await tester.ensureVisible(resources);
        await tester.pumpAndSettle();
        final resourceBounds = tester.getRect(resources);
        expect(resourceBounds.bottom, lessThanOrEqualTo(spec.$2.height + .1));
        expect(tester.takeException(), isNull);
        if (spec.$5) {
          await _save(tester, boundaryKey, 'home-${spec.$1}-resources.png');
        }

        await tester.tap(find.byKey(const ValueKey('app-section-menu')));
        await tester.pumpAndSettle();
        for (final section in AppSection.values) {
          expect(
            find.byKey(ValueKey('app-section-${section.name}')),
            findsOneWidget,
          );
        }
        expect(find.byType(SimpleDialog), findsOneWidget);
        expect(mounted, isEmpty);
        expect(tester.takeException(), isNull);
        await _save(tester, boundaryKey, 'home-${spec.$1}-menu.png');
        await tester.tap(find.text(spec.$3 == 'zh' ? '关闭' : 'Close'));
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        navigation.dispose();
        themeController.dispose();
        languageController.dispose();
        await tester.runAsync(() => temporary.delete(recursive: true));
      }
    });
  }
}

Directory _flutterSdk() {
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final sdk = Directory(configured);
    if (File(
      '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).existsSync()) {
      return sdk;
    }
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    if (File(
      '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError(
    'Could not locate Flutter MaterialIcons via FLUTTER_ROOT or the test executable.',
  );
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['HOME_SCREENSHOTS'];
  if (directory == null || directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('$directory/$name');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
