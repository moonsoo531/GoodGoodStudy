import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_page.dart';
import 'package:offline_player/quiz/quiz_store.dart';
import 'package:offline_player/theme/app_theme.dart';

import 'quiz_widget_fixtures.dart';

void main() {
  for (final language in ['en', 'ja']) {
    testWidgets(
      '$language quiz settings, validation, answers and history fit narrow large-text screens',
      (tester) async {
        final h = await _Harness.create(tester, withReadings: true);
        final locale = ValueNotifier(Locale(language));
        final strings = AppLocalizations(locale.value);
        try {
          await h.open(
            tester,
            size: const Size(320, 900),
            textScale: 1.5,
            locale: locale,
          );
          expect(find.text(strings.text('基础知识测试')), findsOneWidget);
          expect(find.text(widgetQuizTitle), findsOneWidget);
          expect(
            find.text(
              strings.text('已测 {count}/{total}', {'count': 0, 'total': 3}),
            ),
            findsOneWidget,
          );
          await h.enterBook(tester);
          expect(find.text(strings.text('测试题数')), findsOneWidget);
          expect(find.text(strings.text('答案反馈')), findsOneWidget);
          expect(find.text('基础知识测试'), findsNothing);
          final count = find.byKey(const ValueKey('quiz-question-count'));
          await tester.ensureVisible(count);
          await tester.enterText(count, '0');
          final start = find.byKey(const ValueKey('quiz-start'));
          await tester.ensureVisible(start);
          await tester.tap(start);
          await h.flush(tester);
          expect(
            find.text(strings.text('测试题数需要在 1–{count} 之间。', {'count': 3})),
            findsOneWidget,
          );
          expect(await h.active(tester), isNull);
          await tester.ensureVisible(count);
          await tester.enterText(count, '3');
          await h.start(tester, feedback: QuizFeedback.immediate, minutes: 15);
          expect(find.text('がっこう'), findsOneWidget);
          await h.choose(tester, 'b');
          expect(find.textContaining(strings.text('回答错误')), findsOneWidget);
          expect(find.text('这是第1题的解释。'), findsOneWidget);
          await h.next(tester);
          await h.choose(tester, 'b');
          await h.next(tester);
          await h.choose(tester, 'c');
          await h.next(tester);
          expect(find.text('2 / 3'), findsOneWidget);
          expect(find.text(strings.text('返回测试设置')), findsOneWidget);
          expect(find.text('这是第1题的解释。'), findsOneWidget);
          final back = find.text(strings.text('返回测试设置'));
          await tester.ensureVisible(back);
          await tester.tap(back);
          await h.flush(tester);
          final history = find.text(strings.text('查看测试记录'));
          await tester.ensureVisible(history);
          await tester.tap(history);
          await h.flush(tester);
          expect(find.text(strings.text('测试记录')), findsOneWidget);
          expect(find.text('2/3 · 66.7%'), findsOneWidget);
          final attempt = (await h.attempts(tester)).single;
          expect(attempt.session.answers, {'q1': 'b', 'q2': 'b', 'q3': 'c'});
          expect(attempt.session.questions.first.prompt, '学校では、これは（　）です。');
          expect(attempt.session.questions.first.explanationZh, '这是第1题的解释。');
          _expectNoError(tester);
        } finally {
          await h.close(tester);
          locale.dispose();
        }
      },
    );
  }

  testWidgets(
    'live interface language updates active quiz and modal sheets without changing the session',
    (tester) async {
      final h = await _Harness.create(tester, withReadings: true);
      final locale = ValueNotifier(const Locale('zh'));
      final japanese = AppLocalizations(const Locale('ja'));
      final english = AppLocalizations(const Locale('en'));
      try {
        await h.open(tester, locale: locale);
        await h.enterBook(tester);
        await h.start(tester, minutes: 15);
        await h.choose(tester, 'a');
        final before = (await h.active(tester))!;
        locale.value = const Locale('ja');
        await tester.pumpAndSettle();
        expect(find.text(japanese.text('基础知识测试')), findsOneWidget);
        expect(find.text('がっこう'), findsOneWidget);
        await tester.tap(find.byTooltip(japanese.text('答题卡')));
        await tester.pumpAndSettle();
        expect(find.text(japanese.text('答题卡 · 实心表示已选答案')), findsOneWidget);
        locale.value = const Locale('en');
        await tester.pumpAndSettle();
        final sheetHeading = find.text(english.text('答题卡 · 实心表示已选答案'));
        expect(sheetHeading, findsOneWidget);
        Navigator.of(tester.element(sheetHeading)).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('quiz-submit')));
        await tester.pumpAndSettle();
        expect(find.text(english.text('现在交卷？')), findsOneWidget);
        expect(
          find.text(english.text('还有 {count} 道题未作答，交卷后会计入错题。', {'count': 2})),
          findsOneWidget,
        );
        locale.value = const Locale('ja');
        await tester.pumpAndSettle();
        expect(find.text(japanese.text('现在交卷？')), findsOneWidget);
        expect(
          find.text(japanese.text('还有 {count} 道题未作答，交卷后会计入错题。', {'count': 2})),
          findsOneWidget,
        );
        await tester.tap(find.text(japanese.text('继续作答')));
        await tester.pumpAndSettle();
        final after = (await h.active(tester))!;
        expect(after.id, before.id);
        expect(after.answers, before.answers);
        expect(after.currentIndex, before.currentIndex);
        expect(after.startedAt, before.startedAt);
        expect(after.deadlineAt, before.deadlineAt);
        expect(after.questions.first.prompt, before.questions.first.prompt);
        expect(after.questions.first.choices.first.text, '本');
        expect(await h.attempts(tester), isEmpty);
        _expectNoError(tester);
      } finally {
        await h.close(tester);
        locale.dispose();
      }
    },
  );

  testWidgets(
    'readings toggle decorates exam and feedback, persists and never alters answers or deadline',
    (tester) async {
      final h = await _Harness.create(tester, withReadings: true);
      try {
        await h.open(tester, size: const Size(320, 900), textScale: 1.3);
        await h.enterBook(tester);
        expect(
          tester
              .widget<Switch>(
                find.byKey(const ValueKey('quiz-readings-toggle')),
              )
              .value,
          isTrue,
        );
        await h.start(tester, feedback: QuizFeedback.immediate, minutes: 15);
        expect(find.text('がっこう'), findsOneWidget);
        expect(find.text('ほん'), findsOneWidget);
        await h.choose(tester, 'b');
        final before = (await h.active(tester))!;
        expect(before.answers, {'q1': 'b'});
        expect(find.text('ほん'), findsNWidgets(2));
        final toggle = find.byKey(const ValueKey('quiz-readings-toggle'));
        await tester.tap(toggle);
        await h.flush(tester);
        expect(find.text('がっこう'), findsNothing);
        expect(find.text('ほん'), findsNothing);
        final after = (await h.active(tester))!;
        expect(after.answers, before.answers);
        expect(after.deadlineAt, before.deadlineAt);
        expect(after.startedAt, before.startedAt);
        await h.open(tester);
        await h.enterBook(tester);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        await tester.tap(find.byKey(const ValueKey('quiz-resume')));
        await h.flush(tester);
        expect(find.text('がっこう'), findsNothing);
        await tester.tap(toggle);
        await h.flush(tester);
        expect(find.text('がっこう'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quiz-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认交卷'));
        await h.flush(tester);
        expect(find.text('0 / 3'), findsOneWidget);
        final prompt = find.text('がっこう');
        await tester.ensureVisible(prompt);
        expect(prompt, findsOneWidget);
        expect(find.text('ほん'), findsOneWidget);
        expect(
          (await h.attempts(tester))
              .single
              .session
              .questions
              .first
              .ruby
              .single
              .reading,
          'がっこう',
        );
        _expectNoError(tester);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('old banks keep their plain text and disable readings control', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    try {
      await h.open(tester);
      await h.enterBook(tester);
      final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('quiz-readings-toggle')),
      );
      expect(toggle.onChanged, isNull);
      await h.start(tester);
      expect(find.text('a. 本'), findsOneWidget);
      _expectNoError(tester);
    } finally {
      await h.close(tester);
    }
  });
  testWidgets(
    'submit feedback stays hidden, permits edits and saves one result',
    (tester) async {
      final h = await _Harness.create(tester);
      try {
        await h.open(tester);
        await h.enterBook(tester);
        await h.start(tester);
        await h.choose(tester, 'b');
        expect(find.text('这是第1题的解释。'), findsNothing);
        expect(find.textContaining('正确答案：'), findsNothing);
        await h.choose(tester, 'a');
        expect((await h.active(tester))!.answers['q1'], 'a');
        await h.next(tester);
        await h.choose(tester, 'b');
        await h.previous(tester);
        expect(find.text('这是第1题的解释。'), findsNothing);
        expect((await h.active(tester))!.answers['q1'], 'a');
        await h.next(tester);
        await h.next(tester);
        await h.choose(tester, 'c');
        await h.next(tester);
        expect(find.text('3 / 3'), findsOneWidget);
        final attempts = await h.attempts(tester);
        expect(attempts, hasLength(1));
        expect(attempts.single.correctCount, 3);
        expect(await h.active(tester), isNull);
        await h.open(tester);
        expect(find.text('已测 3/3'), findsOneWidget);
        expect(find.text('正确率 100.0%'), findsOneWidget);
        expect(find.text('错题 0'), findsOneWidget);
        _expectNoError(tester);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('immediate feedback locks the first answer across navigation', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    try {
      await h.open(tester);
      await h.enterBook(tester);
      await h.start(tester, feedback: QuizFeedback.immediate);
      await h.choose(tester, 'b');
      expect(find.text('这是第1题的解释。'), findsOneWidget);
      expect(find.textContaining('回答错误 · 正确答案：a. 本'), findsOneWidget);
      final correct = tester.widget<InkWell>(
        find.byKey(const ValueKey('quiz-choice-a')),
      );
      expect(correct.onTap, isNull);
      await h.next(tester);
      await h.choose(tester, 'b');
      expect(find.text('回答正确'), findsOneWidget);
      await h.previous(tester);
      expect(find.text('这是第1题的解释。'), findsOneWidget);
      expect((await h.active(tester))!.answers['q1'], 'b');
      await tester.tap(find.byKey(const ValueKey('quiz-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认交卷'));
      await h.flush(tester);
      final attempt = (await h.attempts(tester)).single;
      expect(attempt.correctCount, 1);
      expect(attempt.answeredCount, 2);
      final stats = await tester.runAsync(() => h.store.stats(widgetQuizId));
      expect(stats!.wrongQuestionIds, {'q1', 'q3'});
      _expectNoError(tester);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'expired test is finalized once on reopening with unanswered errors',
    (tester) async {
      final h = await _Harness.create(tester);
      try {
        await tester.runAsync(() async {
          final session = await h.store.startSession(
            widgetQuizId,
            const QuizSettings(questionCount: 3, durationMinutes: 1),
            now: h.clock,
          );
          await h.store.answer(
            widgetQuizId,
            session.id,
            'q1',
            'a',
            now: h.clock,
          );
        });
        h.clock = h.clock.add(const Duration(minutes: 2));
        await h.open(tester);
        await h.enterBook(tester);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.textContaining('时间到，自动交卷'), findsOneWidget);
        expect(find.byKey(const ValueKey('quiz-resume')), findsNothing);
        expect(await h.active(tester), isNull);
        final attempt = (await h.attempts(tester)).single;
        expect(attempt.timedOut, isTrue);
        expect(attempt.answeredCount, 1);
        expect(attempt.correctCount, 1);
        expect(attempt.elapsedSeconds, 60);
        await h.open(tester);
        expect(find.text('已测 3/3'), findsOneWidget);
        expect((await h.attempts(tester)), hasLength(1));
        final stats = await tester.runAsync(() => h.store.stats(widgetQuizId));
        expect(stats!.wrongQuestionIds, {'q2', 'q3'});
        _expectNoError(tester);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('archived result renders while statistics are still loading', (
    tester,
  ) async {
    late _ControlledStatsStore controlled;
    final h = await _Harness.create(
      tester,
      storeFactory: (directory) {
        return controlled = _ControlledStatsStore(directory);
      },
    );
    try {
      await h.open(tester);
      await h.enterBook(tester);
      await h.start(tester);
      await h.choose(tester, 'a');
      await h.next(tester);
      await h.choose(tester, 'b');
      await h.next(tester);
      await h.choose(tester, 'c');
      controlled.blockStats();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('quiz-next')));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!controlled.statsRequested!.isCompleted) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Completion did not request statistics.');
          }
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz-next')), findsNothing);
      expect((await h.attempts(tester)), hasLength(1));
      _expectNoError(tester);
      controlled.releaseStats();
      await h.flush(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      _expectNoError(tester);
    } finally {
      controlled.releaseStats();
      await h.close(tester);
    }
  });

  testWidgets('statistics error cannot discard the archived score page', (
    tester,
  ) async {
    late _ControlledStatsStore controlled;
    final h = await _Harness.create(
      tester,
      storeFactory: (directory) {
        return controlled = _ControlledStatsStore(directory);
      },
    );
    try {
      await h.open(tester);
      await h.enterBook(tester);
      await h.start(tester);
      await h.choose(tester, 'a');
      await h.next(tester);
      await h.choose(tester, 'b');
      await h.next(tester);
      await h.choose(tester, 'c');
      controlled.failStats = true;
      await h.next(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.textContaining('统计暂时无法读取'), findsOneWidget);
      expect(await h.active(tester), isNull);
      final attempts = await h.attempts(tester);
      expect(attempts, hasLength(1));
      expect(attempts.single.correctCount, 3);
      _expectNoError(tester);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'late answer expiry still displays saved score when statistics fail',
    (tester) async {
      late _ControlledStatsStore controlled;
      final h = await _Harness.create(
        tester,
        storeFactory: (directory) {
          return controlled = _ControlledStatsStore(directory);
        },
      );
      try {
        await h.open(tester);
        await h.enterBook(tester);
        await h.start(tester, minutes: 1);
        controlled.failStats = true;
        h.clock = h.clock.add(const Duration(seconds: 61));
        // Do not pump the ticker: the answer operation itself must discover expiry.
        await tester.tap(find.byKey(const ValueKey('quiz-choice-a')));
        await h.flush(tester);
        expect(controlled.expiredAnswerCount, 1);
        expect(find.text('0 / 3'), findsOneWidget);
        expect(find.textContaining('统计暂时无法读取'), findsOneWidget);
        expect(find.byKey(const ValueKey('quiz-next')), findsNothing);
        expect(await h.active(tester), isNull);
        final attempts = await h.attempts(tester);
        expect(attempts, hasLength(1));
        expect(attempts.single.timedOut, isTrue);
        expect(attempts.single.answeredCount, 0);
        expect(attempts.single.correctCount, 0);
        expect(attempts.single.elapsedSeconds, 60);
        _expectNoError(tester);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('leaving and resuming retains answers, question and deadline', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    try {
      await h.open(tester);
      await h.enterBook(tester);
      await h.start(tester, minutes: 1);
      await h.choose(tester, 'b');
      await h.next(tester);
      final before = (await h.active(tester))!;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('保存并离开测试？'), findsOneWidget);
      await tester.tap(find.text('保存并离开'));
      await h.flush(tester);
      h.clock = h.clock.add(const Duration(seconds: 15));
      final resume = find.byKey(const ValueKey('quiz-resume'));
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await h.flush(tester);
      final restored = (await h.active(tester))!;
      expect(restored.id, before.id);
      expect(restored.currentIndex, 1);
      expect(restored.answers, {'q1': 'b'});
      expect(restored.deadlineAt, before.deadlineAt);
      expect(find.text('剩余 0:45'), findsOneWidget);
      await h.previous(tester);
      await h.choose(tester, 'a');
      expect((await h.active(tester))!.answers['q1'], 'a');
      expect(await h.attempts(tester), isEmpty);
      _expectNoError(tester);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('timeout closes a pending submit dialog and saves only once', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    try {
      await h.open(tester);
      await h.enterBook(tester);
      await h.start(tester, minutes: 1);
      await h.choose(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('quiz-submit')));
      await tester.pumpAndSettle();
      expect(find.text('现在交卷？'), findsOneWidget);
      h.clock = h.clock.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await h.flush(tester);
      expect(find.text('现在交卷？'), findsNothing);
      expect(find.text('1 / 3'), findsOneWidget);
      expect((await h.attempts(tester)), hasLength(1));
      expect(await h.active(tester), isNull);
      _expectNoError(tester);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    '320px large text keeps settings, long choices and navigation usable',
    (tester) async {
      final h = await _Harness.create(tester);
      try {
        await h.open(tester, size: const Size(320, 568), textScale: 1.5);
        await h.enterBook(tester);
        await h.start(tester);
        await h.next(tester);
        await h.next(tester);
        final choice = find.byKey(const ValueKey('quiz-choice-c'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await h.flush(tester);
        expect((await h.active(tester))!.answers['q3'], 'c');
        final navigation = find.byKey(const ValueKey('quiz-next'));
        expect(tester.getBottomRight(navigation).dx, lessThanOrEqualTo(320));
        expect(tester.getBottomRight(navigation).dy, lessThanOrEqualTo(568));
        _expectNoError(tester);
      } finally {
        await h.close(tester);
      }
    },
  );
}

void _expectNoError(WidgetTester tester) {
  final errors = <Object>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error!);
  }
  expect(errors, isEmpty);
}

class _Harness {
  _Harness(this.directory, this.store);
  final Directory directory;
  final QuizStore store;
  DateTime clock = DateTime.utc(2026, 10, 26, 10);

  static Future<_Harness> create(
    WidgetTester tester, {
    QuizStore Function(Directory root)? storeFactory,
    bool withReadings = false,
  }) async {
    late _Harness harness;
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('quiz-widget-');
      final root = Directory('${directory.path}/library');
      final store = storeFactory?.call(root) ?? QuizStore(root: root);
      await store.importZip(
        await writeWidgetQuizZip(directory, withReadings: withReadings),
      );
      harness = _Harness(directory, store);
    });
    return harness;
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    double textScale = 1,
    ValueNotifier<Locale>? locale,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    Widget app(Locale? selected) => MaterialApp(
      locale: selected,
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: QuizPage(store: store, now: () => clock),
    );
    await tester.pumpWidget(
      locale == null
          ? app(const Locale('zh'))
          : ValueListenableBuilder<Locale>(
              valueListenable: locale,
              builder: (context, selected, child) => app(selected),
            ),
    );
    await flush(tester);
  }

  Future<void> enterBook(WidgetTester tester) async {
    final book = find.byKey(const ValueKey('quiz-book-$widgetQuizId'));
    await tester.ensureVisible(book);
    await tester.tap(book);
    await flush(tester);
  }

  Future<void> start(
    WidgetTester tester, {
    QuizFeedback feedback = QuizFeedback.onSubmit,
    int minutes = 0,
  }) async {
    final time = find.byKey(const ValueKey('quiz-duration'));
    await tester.ensureVisible(time);
    await tester.enterText(time, '$minutes');
    if (feedback == QuizFeedback.immediate) {
      final immediate = find.widgetWithText(
        ChoiceChip,
        AppLocalizations.of(tester.element(find.byType(QuizPage)))
            .text('逐题显示答案'),
      );
      await tester.ensureVisible(immediate);
      await tester.tap(immediate);
      await tester.pumpAndSettle();
    }
    final button = find.byKey(const ValueKey('quiz-start'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await flush(tester);
  }

  Future<void> choose(WidgetTester tester, String id) async {
    final choice = find.byKey(ValueKey('quiz-choice-$id'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await flush(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('quiz-next')));
    await flush(tester);
  }

  Future<void> previous(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('quiz-previous')));
    await flush(tester);
  }

  Future<QuizSession?> active(WidgetTester tester) async {
    QuizSession? result;
    await tester.runAsync(() async {
      result = await store.loadActiveSession(widgetQuizId);
    });
    return result;
  }

  Future<List<QuizAttempt>> attempts(WidgetTester tester) async =>
      (await tester.runAsync(() => store.attempts(widgetQuizId)))!;

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var stable = 0;
      while (stable < 3) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Quiz page I/O did not settle.');
        }
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final busy = find.byWidgetPredicate(
          (w) => w is LinearProgressIndicator && w.value == null,
        );
        stable = busy.evaluate().isEmpty ? stable + 1 : 0;
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await store.loadBookState(widgetQuizId);
      await directory.delete(recursive: true);
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class _ControlledStatsStore extends QuizStore {
  _ControlledStatsStore(Directory root) : super(root: root);
  Completer<void>? statsRequested;
  Completer<void>? _statsGate;
  bool failStats = false;
  int expiredAnswerCount = 0;

  void blockStats() {
    statsRequested = Completer<void>();
    _statsGate = Completer<void>();
  }

  void releaseStats() {
    final gate = _statsGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<QuizSession> answer(
    String packageId,
    String sessionId,
    String questionId,
    String choiceId, {
    DateTime? now,
  }) async {
    try {
      return await super.answer(
        packageId,
        sessionId,
        questionId,
        choiceId,
        now: now,
      );
    } on QuizSessionExpiredException {
      expiredAnswerCount++;
      rethrow;
    }
  }

  @override
  Future<QuizBookStats> stats(String packageId) async {
    final gate = _statsGate;
    if (gate != null) {
      if (!statsRequested!.isCompleted) statsRequested!.complete();
      await gate.future;
    }
    if (failStats) {
      throw const FileSystemException('统计暂时无法读取');
    }
    return super.stats(packageId);
  }
}
