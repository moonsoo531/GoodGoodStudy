import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_page.dart';
import 'package:offline_player/quiz/quiz_store.dart';
import 'package:offline_player/theme/app_theme.dart';

import 'quiz_widget_fixtures.dart';

final _clock = DateTime.utc(2026, 10, 29, 10);

void main() {
  test('quiz view pointer is independent and preserves active answers on corrupt pointer', () async {
    final root = await Directory.systemTemp.createTemp('ggs-quiz-navigation-');
    try {
      final store = await _seed(root);
      var session = await store.startSession(
        widgetQuizId,
        const QuizSettings(questionCount: 3),
        now: _clock,
      );
      session = await store.answer(
        widgetQuizId,
        session.id,
        session.questions.first.id,
        'a',
        now: _clock,
      );
      session = await store.navigate(widgetQuizId, session.id, 1, now: _clock);
      await store.saveNavigationLocation(
        QuizNavigationLocation(
          view: 'exam',
          packageId: widgetQuizId,
          sessionId: session.id,
        ),
      );
      await store.flush();
      final reopened = QuizStore(root: Directory('${root.path}/library'));
      final pointer = await reopened.loadNavigationLocation();
      expect(pointer!.view, 'exam');
      expect(pointer.sessionId, session.id);
      expect(
        (await reopened.loadActiveSession(widgetQuizId))!.toJson(),
        session.toJson(),
      );
      expect(await reopened.attempts(widgetQuizId), isEmpty);
      await File('${root.path}/library/navigation.json')
          .writeAsString('{broken');
      expect(await reopened.loadNavigationLocation(), isNull);
      expect((await reopened.loadActiveSession(widgetQuizId))!.answers, {
        session.questions.first.id: 'a',
      });
    } finally {
      await root.delete(recursive: true);
    }
  });

  testWidgets(
    'restore exam, settings, history and exact completed attempt without creating a test',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ggs-quiz-view-'),
      );
      late QuizStore store;
      late QuizSession session;
      await tester.runAsync(() async {
        store = await _seed(root!);
        session = await store.startSession(
          widgetQuizId,
          const QuizSettings(questionCount: 3),
          now: _clock,
        );
        session = await store.answer(
          widgetQuizId,
          session.id,
          session.questions.first.id,
          'a',
          now: _clock,
        );
        session = await store.navigate(
          widgetQuizId,
          session.id,
          1,
          now: _clock,
        );
        await store.saveNavigationLocation(
          QuizNavigationLocation(
            view: 'exam',
            packageId: widgetQuizId,
            sessionId: session.id,
          ),
        );
      });
      try {
        await _open(tester, store);
        expect(find.byKey(const ValueKey('quiz-next')), findsOneWidget);
        expect(find.text('駅へ（　）。'), findsOneWidget);
        final active = await tester.runAsync(
          () => store.loadActiveSession(widgetQuizId),
        );
        expect(active!.id, session.id);
        expect(active.currentIndex, 1);
        expect(active.answers, session.answers);
        expect(
          await tester.runAsync(() => store.attempts(widgetQuizId)),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => store.saveNavigationLocation(
            const QuizNavigationLocation(
              view: 'settings',
              packageId: widgetQuizId,
            ),
          ),
        );
        await _open(tester, store);
        expect(
          find.byKey(const ValueKey('quiz-question-count')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('quiz-next')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        late QuizAttempt result;
        await tester.runAsync(() async {
          result = await store.finishSession(
            widgetQuizId,
            session.id,
            now: _clock,
          );
          await store.saveNavigationLocation(
            QuizNavigationLocation(
              view: 'result',
              packageId: widgetQuizId,
              attemptId: result.id,
              wrongOnly: false,
            ),
          );
        });
        await _open(tester, store);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.text('返回测试设置'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => store.saveNavigationLocation(
            const QuizNavigationLocation(
              view: 'history',
              packageId: widgetQuizId,
            ),
          ),
        );
        await _open(tester, store);
        expect(find.text('测试记录'), findsOneWidget);
        expect(find.textContaining('1/3'), findsOneWidget);
        expect(
          (await tester.runAsync(() => store.attempts(widgetQuizId)))!,
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await store.flush();
          await root!.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'menu cancellation keeps exam and accepted switch preserves unsubmitted answers',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ggs-quiz-switch-'),
      );
      late _MenuQuizStore store;
      late QuizSession session;
      final navigation = AppNavigationController(
        preferences: _QuizPreferences(),
      );
      await navigation.load();
      await tester.runAsync(() async {
        final seeded = await _seed(root!);
        session = await seeded.startSession(
          widgetQuizId,
          const QuizSettings(questionCount: 3),
          now: _clock,
        );
        session = await seeded.answer(
          widgetQuizId,
          session.id,
          session.questions.first.id,
          'a',
          now: _clock,
        );
        store = _MenuQuizStore(Directory('${root.path}/library'), session);
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: GoodGoodStudyShell(
              controller: navigation,
              iconAsset: null,
              builders: {
                AppSection.quiz: (_) => QuizPage(
                  store: store,
                  now: () => _clock,
                  restoreLastLocation: true,
                ),
                AppSection.player: (_) =>
                    const Scaffold(body: Text('playback module')),
              },
            ),
          ),
        );
        await _flush(tester);
        await tester.tap(find.byKey(const ValueKey('app-section-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('app-section-player')));
        await tester.pumpAndSettle();
        expect(find.text('保存并离开测试？'), findsOneWidget);
        await tester.tap(find.text('继续作答'));
        await tester.pumpAndSettle();
        expect(navigation.section, AppSection.quiz);
        expect(find.byKey(const ValueKey('quiz-next')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('app-section-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('app-section-player')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存并离开'));
        await tester.pumpAndSettle();
        expect(navigation.section, AppSection.player);
        expect(find.text('playback module'), findsOneWidget);
        expect(store.active.id, session.id);
        expect(store.active.answers, session.answers);
        expect(store.submissionCalls, 0);
        expect(store.location.view, 'exam');
        unawaited(navigation.navigate(AppSection.quiz));
        await _flush(tester, navigation: navigation);
        expect(find.byKey(const ValueKey('quiz-next')), findsOneWidget);
        expect(store.active.id, session.id);
        expect(store.active.answers, session.answers);
        expect(store.submissionCalls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await root!.delete(recursive: true);
        });
        navigation.dispose();
      }
    },
  );
}

Future<QuizStore> _seed(Directory root) async {
  final store = QuizStore(root: Directory('${root.path}/library'));
  await store.importZip(await writeWidgetQuizZip(root));
  return store;
}

Future<void> _open(WidgetTester tester, QuizStore store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: QuizPage(
        store: store,
        now: () => _clock,
        restoreLastLocation: true,
      ),
    ),
  );
  await _flush(tester);
}

Future<void> _flush(
  WidgetTester tester, {
  AppNavigationController? navigation,
}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var stable = 0;
    while (stable < 3) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Quiz navigation did not settle');
      }
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final busy = find.byWidgetPredicate(
        (widget) => widget is LinearProgressIndicator && widget.value == null,
      );
      stable = busy.evaluate().isEmpty && navigation?.isSwitching != true
          ? stable + 1
          : 0;
    }
  });
  await tester.pumpAndSettle();
}

class _QuizPreferences extends NavigationPreferences {
  @override
  Future<AppSection> read() async => AppSection.quiz;
  @override
  Future<void> write(AppSection section) async {}
}

class _MenuQuizStore extends QuizStore {
  _MenuQuizStore(Directory root, this.active) : super(root: root) {
    location = QuizNavigationLocation(
      view: 'exam',
      packageId: widgetQuizId,
      sessionId: active.id,
    );
  }
  final QuizSession active;
  late QuizNavigationLocation location;
  int submissionCalls = 0;
  @override
  Future<QuizSession?> loadActiveSession(String packageId) async => active;
  @override
  Future<QuizNavigationLocation?> loadNavigationLocation() async => location;
  @override
  Future<void> saveNavigationLocation(QuizNavigationLocation value) async {
    location = value;
  }

  @override
  Future<void> flush() async {}
  @override
  Future<QuizAttempt> finishSession(
    String packageId,
    String sessionId, {
    DateTime? now,
  }) async {
    submissionCalls++;
    throw StateError('Switching modules must not submit an exam.');
  }
}
