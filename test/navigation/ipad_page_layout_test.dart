import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/phone/phone_media_store.dart';
import 'package:offline_player/phone/phone_player_page.dart';
import 'package:offline_player/playback/apple_audio_controller.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_page.dart';
import 'package:offline_player/quiz/quiz_store.dart';
import 'package:offline_player/study/study_audio.dart';
import 'package:offline_player/study/study_page.dart';
import 'package:offline_player/study/study_passage_text.dart';
import 'package:offline_player/study/study_store.dart';
import 'package:offline_player/theme/app_theme.dart';
import 'package:offline_player/widgets/ruby_subtitle_text.dart';

import '../quiz/quiz_widget_fixtures.dart';

void main() {
  var fontsLoaded = false;
  for (final language in ['zh', 'ja', 'en']) {
    for (final size in [
      const Size(834, 1194),
      const Size(1194, 834),
      const Size(320, 844),
    ]) {
      testWidgets('$language real pages fit iPad $size at 1.3 text scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (!fontsLoaded) {
          fontsLoaded = await _loadFonts(tester);
        }
        final fixture = (await tester.runAsync(_IpadFixture.create))!;
        final boundary = GlobalKey();
        final navigation = AppNavigationController(
          preferences: _MemoryPreferences(),
        );
        final themes = AppThemeController();
        try {
          await navigation.load();
          final base = buildAppTheme(Brightness.light);
          final theme = base.copyWith(
            platform: TargetPlatform.iOS,
            textTheme: fontsLoaded
                ? base.textTheme.apply(
                    fontFamily: 'IpadJapanese',
                    fontFamilyFallback: const ['IpadCjk'],
                  )
                : base.textTheme,
            primaryTextTheme: fontsLoaded
                ? base.primaryTextTheme.apply(
                    fontFamily: 'IpadJapanese',
                    fontFamilyFallback: const ['IpadCjk'],
                  )
                : base.primaryTextTheme,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: AppThemeScope(
                controller: themes,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(language),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: appLocalizationDelegates,
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.3)),
                    child: child!,
                  ),
                  home: GoodGoodStudyShell(
                    controller: navigation,
                    phonePlayback: true,
                    builders: {
                      AppSection.study: (_) => StudyPage(
                        store: fixture.study,
                        audio: fixture.studyAudio,
                      ),
                      AppSection.quiz: (_) => QuizPage(
                        store: fixture.quiz,
                        restoreLastLocation: true,
                      ),
                      AppSection.player: (_) => PhonePlayerPage(
                        store: fixture.phone,
                        audio: fixture.phoneAudio,
                      ),
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/branding/goodgoodstudy-icon.png'),
              tester.element(find.byType(GoodGoodStudyShell)),
            ),
          );
          await tester.pumpAndSettle();
          for (final section in [
            AppSection.study,
            AppSection.quiz,
            AppSection.player,
          ]) {
            expect(
              find.byKey(ValueKey('home-entry-${section.name}')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await _screenshot(
            tester,
            boundary,
            '$language-${size.width.toInt()}-home',
          );

          await _complete(tester, navigation.navigate(AppSection.study));
          await _pumpUntil(
            tester,
            () => _ready(StudyPage, Icons.library_add_outlined),
          );
          await tester.pumpAndSettle();
          expect(find.byType(StudyPassageText), findsWidgets);
          expect(find.byKey(const ValueKey('app-home-back')), findsOneWidget);
          await _screenshot(
            tester,
            boundary,
            '$language-${size.width.toInt()}-study',
          );
          expect(tester.takeException(), isNull);
          if (size.width < 600) {
            for (final control in [
              'study-playback-scope',
              'study-repeat-count',
              'study-play-pause',
              'study-playback-rate',
            ]) {
              final rect = tester.getRect(find.byKey(ValueKey(control)));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(size.width));
            }
            await tester.tap(find.byKey(const ValueKey('app-home-back')));
            await _pumpUntil(
              tester,
              () =>
                  navigation.section == AppSection.home &&
                  !navigation.isSwitching,
            );
            expect(
              find.byKey(const ValueKey('home-entry-study')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            return;
          }

          await _complete(tester, navigation.navigate(AppSection.quiz));
          await _pumpUntil(tester, () => _ready(QuizPage, Icons.task_alt));
          await tester.pumpAndSettle();
          final choice = find.byKey(const ValueKey('quiz-choice-a'));
          expect(choice, findsOneWidget);
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await _complete(tester, fixture.quiz.flush());
          await _pumpUntil(tester, () => _ready(QuizPage, Icons.task_alt));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _screenshot(
            tester,
            boundary,
            '$language-${size.width.toInt()}-quiz',
          );

          final switching = navigation.navigate(AppSection.player);
          await _pumpUntil(
            tester,
            () => find.byType(AlertDialog).evaluate().isNotEmpty,
          );
          final strings = AppLocalizations(Locale(language));
          await tester.tap(find.text(strings.text('保存并离开')));
          await _complete(tester, switching);
          await _pumpUntil(tester, () => _ready(PhonePlayerPage, Icons.add));
          await tester.pumpAndSettle();
          expect(find.byType(RubySubtitleText), findsWidgets);
          expect(find.byKey(const ValueKey('app-home-back')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _screenshot(
            tester,
            boundary,
            '$language-${size.width.toInt()}-player',
          );
          await tester.tap(find.byKey(const ValueKey('app-home-back')));
          await _pumpUntil(
            tester,
            () =>
                navigation.section == AppSection.home &&
                !navigation.isSwitching,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-entry-study')),
            findsOneWidget,
          );
          expect(fixture.phoneAudio.playing, isFalse);
          expect(tester.takeException(), isNull);
          await _complete(tester, fixture.verifyAndClose());
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await _complete(tester, fixture.close());
          navigation.dispose();
          themes.dispose();
        }
      });
    }
  }
}

bool _ready(Type page, IconData icon) {
  final control = find.descendant(
    of: find.byType(page),
    matching: find.widgetWithIcon(IconButton, icon),
  );
  return control.evaluate().length == 1 &&
      (control.evaluate().single.widget as IconButton).onPressed != null;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('iPad page did not finish loading.');
      }
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  await tester.pump();
}

Future<void> _complete(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    future.then<void>(
      (_) => done = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  await _pumpUntil(tester, () => done);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

Future<bool> _loadFonts(WidgetTester tester) async {
  final fonts = Directory('/System/Library/Fonts');
  if (!fonts.existsSync()) return false;
  await tester.runAsync(() async {
    final japanese = fonts.listSync().whereType<File>().firstWhere(
      (file) => file.path.endsWith('W3.ttc'),
    );
    final cjk = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    await (FontLoader('IpadJapanese')..addFont(
          Future.value(ByteData.sublistView(await japanese.readAsBytes())),
        ))
        .load();
    if (await cjk.exists()) {
      await (FontLoader('IpadCjk')..addFont(
            Future.value(ByteData.sublistView(await cjk.readAsBytes())),
          ))
          .load();
    }
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk != null) {
      final icons = File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            ))
            .load();
      }
    }
  });
  return true;
}

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final folder = Platform.environment['IPAD_LAYOUT_SCREENSHOTS'];
  if (folder == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$folder/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _MemoryPreferences extends NavigationPreferences {
  @override
  Future<AppSection> read() async => AppSection.home;
  @override
  Future<void> write(AppSection section) async {}
}

class _IpadFixture {
  _IpadFixture(this.root)
    : study = StudyStore(root: Directory('${root.path}/study')),
      quiz = QuizStore(root: Directory('${root.path}/quiz')),
      phone = PhoneMediaStore(documents: Directory('${root.path}/phone'));

  final Directory root;
  final StudyStore study;
  final QuizStore quiz;
  final PhoneMediaStore phone;
  final studyAudio = AppleStudyAudio(
    AppleAudioController(transport: _AudioTransport()),
    ownsController: true,
  );
  final phoneAudio = AppleAudioController(transport: _AudioTransport());
  bool _closed = false;

  static Future<_IpadFixture> create() async {
    final temporary = await Directory.systemTemp.createTemp('ggs-ipad-layout-');
    final fixture = _IpadFixture(
      Directory(await temporary.resolveSymbolicLinks()),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'schema_version': '1.0',
            'package_id': 'ipad-study',
            'content_revision': 1,
            'title': '合成学习布局样本',
            'language': 'ja',
            'translation_language': 'zh-CN',
            'level_tags': [],
            'media': [],
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'lessons.json',
          jsonEncode([
            {
              'id': 'lesson-1',
              'title': '食事',
              'topic': '食事',
              'entry_ids': ['entry-1'],
              'segments': [
                {
                  'id': 'segment-1',
                  'text': '創作料理を食べながら、今日の出来事を話します。',
                  'translation_zh': '一边吃创作料理，一边聊今天发生的事情。',
                  'highlights': [
                    {'start': 0, 'end': 2, 'entry_id': 'entry-1'},
                  ],
                  'ruby': [
                    {'start': 0, 'end': 2, 'reading': 'そうさく'},
                  ],
                },
              ],
            },
          ]),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'entries.json',
          jsonEncode([
            {
              'id': 'entry-1',
              'surface': '創作',
              'reading': 'そうさく',
              'meaning_zh': '创作',
              'kind': 'vocabulary',
              'attributes': {},
              'tags': [],
              'relations': [],
            },
          ]),
        ),
      );
    final zip = File('${fixture.root.path}/study.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    await fixture.study.importZip(zip);
    await fixture.study.saveProgress('ipad-study', {
      'lesson_id': 'lesson-1',
      'show_translation': true,
    });
    await fixture.study.saveResumeLocation(
      packageId: 'ipad-study',
      lessonId: 'lesson-1',
    );
    final quizZip = await writeWidgetQuizZip(fixture.root, withReadings: true);
    await fixture.quiz.importZip(quizZip);
    final session = await fixture.quiz.startSession(
      widgetQuizId,
      const QuizSettings(questionCount: 3),
    );
    await fixture.quiz.saveNavigationLocation(
      QuizNavigationLocation(
        view: 'exam',
        packageId: widgetQuizId,
        sessionId: session.id,
      ),
    );
    final media = await fixture.phone.mediaDirectory;
    await File('${media.path}/synthetic.mp3').writeAsBytes([0, 1, 2]);
    await File('${media.path}/synthetic.srt').writeAsString(
      '1\n00:00:00,000 --> 00:00:05,000\n一番目の文です。\n\n2\n00:00:05,000 --> 00:00:10,000\n<ruby>明日<rt>あした</rt></ruby>も勉強します。\n',
    );
    return fixture;
  }

  Future<void> verifyAndClose() async {
    final active = await quiz.loadActiveSession(widgetQuizId);
    expectSync(active?.answers, {'q1': 'a'});
    expectSync(await quiz.attempts(widgetQuizId), isEmpty);
    await phone.flush();
    expectSync(await phone.loadState(), isNotEmpty);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await studyAudio.close();
    await phoneAudio.close();
    phoneAudio.dispose();
    await study.flush();
    await quiz.flush();
    await phone.flush();
    await root.delete(recursive: true);
  }
}

class _AudioTransport implements AppleAudioTransport {
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  Map<String, Object?> _state = {
    'path': null,
    'playing': false,
    'positionMs': 0,
    'durationMs': 60000,
    'rate': 1.0,
  };
  @override
  Stream<Map<String, Object?>> get events => _events.stream;
  @override
  Future<Map<String, Object?>> invoke(
    String command, [
    Map<String, Object?> arguments = const {},
  ]) async {
    switch (command) {
      case 'snapshot':
        break;
      case 'open':
        _state = {
          ..._state,
          'path': arguments['path'],
          'title': arguments['title'],
          'positionMs': arguments['positionMs'],
          'playing': arguments['autoplay'],
          'rate': arguments['rate'],
        };
      case 'pause':
      case 'dispose':
        _state = {..._state, 'playing': false};
      case 'clearLoop':
        _state = {..._state, 'loop': null};
      case 'setRate':
        _state = {..._state, 'rate': arguments['rate']};
      case 'seek':
        _state = {..._state, 'positionMs': arguments['positionMs']};
      case 'play':
        _state = {..._state, 'playing': true};
      default:
        throw StateError('Unexpected synthetic audio command: $command');
    }
    return Map.from(_state);
  }

  @override
  Future<void> close() => _events.close();
}
