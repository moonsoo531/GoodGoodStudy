import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_store.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late QuizStore store;
  var zipCounter = 0;
  final clock = DateTime.utc(2026, 10, 26, 12);
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('quiz-store-');
    root = Directory('${temporary.path}/library');
    store = QuizStore(root: root);
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<File> zip(Archive archive) =>
      File('${temporary.path}/input-${zipCounter++}.zip')
          .writeAsBytes(ZipEncoder().encode(archive));
  Future<void> install() async => store.importZip(await zip(_bank()));

  test(
    'reimport, upgrades and immutable attempt snapshots survive restarts',
    () async {
      final file = await zip(_bank());
      final first = await store.importZip(file);
      expect(
        (await store.importZip(file)).directory.path,
        first.directory.path,
      );
      final active = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 2),
        now: clock,
      );
      await store.answer('quiz-fixture', active.id, 'q-1', 'a', now: clock);
      await store.importZip(await zip(_bank(revision: 2, answer: 'b')));
      await expectLater(store.importZip(file), throwsFormatException);
      await expectLater(
        store.importZip(await zip(_bank(revision: 2, answer: 'a'))),
        throwsFormatException,
      );
      final reopened = QuizStore(root: root);
      final resume = await reopened.loadActiveSession('quiz-fixture');
      expect(resume!.contentRevision, 1);
      expect(resume.questions.first.answerId, 'a');
      final completed = await reopened.finishSession(
        'quiz-fixture',
        active.id,
        now: clock.add(const Duration(seconds: 20)),
      );
      expect(completed.correctCount, 1);
      expect((await reopened.packages()).single.package.contentRevision, 2);
      expect(
        (await reopened.attempts('quiz-fixture'))
            .single
            .session
            .contentRevision,
        1,
      );
    },
  );

  test(
    'deferred feedback permits edits and concurrent answers do not get lost',
    () async {
      await install();
      final s = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 3),
        now: clock,
      );
      await Future.wait([
        store.answer('quiz-fixture', s.id, 'q-1', 'b', now: clock),
        store.answer('quiz-fixture', s.id, 'q-2', 'a', now: clock),
      ]);
      await store.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock);
      final state = await store.loadBookState('quiz-fixture');
      expect(state.activeSession!.answers, {'q-1': 'a', 'q-2': 'a'});
      expect(state.lastSettings!.questionCount, 3);
      expect((await store.stats('quiz-fixture')).attemptCount, 0);
      expect((await store.stats('quiz-fixture')).coverage, 0);
      final completed = await store.finishSession(
        'quiz-fixture',
        s.id,
        now: clock,
      );
      expect(completed.correctCount, 2);
      expect(completed.accuracy, closeTo(2 / 3, 0.00001));
      final stats = await store.stats('quiz-fixture');
      expect(stats.totalAssigned, 3);
      expect(stats.totalAnswered, 2);
      expect(stats.uniqueTestedCount, 3);
      expect(stats.uniqueAnsweredCount, 2);
      expect(stats.coverage, .75);
      expect(stats.accuracy, completed.accuracy);
      expect(stats.wrongQuestionIds, {'q-3'});
    },
  );

  test('readings survive active and archived snapshots and display preferences stay separate', () async {
    final original = await store.importZip(await zip(_bank(reading: 'にほんご')));
    expect(original.package.questions.first.ruby.single.reading, 'にほんご');
    expect((await store.loadBookState('quiz-fixture')).showReadings, isTrue);
    final s = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 1, durationMinutes: 15),
      now: clock,
    );
    await store.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock);
    await store.saveShowReadings('quiz-fixture', false);
    var restarted = QuizStore(root: root);
    final state = await restarted.loadBookState('quiz-fixture');
    expect(state.showReadings, isFalse);
    expect(state.activeSession!.deadlineAt, s.deadlineAt);
    expect(state.activeSession!.answers, {'q-1': 'a'});
    expect(state.activeSession!.questions.first.ruby.single.reading, 'にほんご');
    expect(
      state.activeSession!.questions.first.choices.first.ruby.single.reading,
      'せいとう',
    );
    await restarted.importZip(await zip(_bank(revision: 2, reading: 'ニホンゴ')));
    final a = await restarted.finishSession('quiz-fixture', s.id, now: clock);
    expect(a.correctCount, 1);
    restarted = QuizStore(root: root);
    final history = (await restarted.attempts('quiz-fixture')).single;
    expect(history.session.questions.first.ruby.single.reading, 'にほんご');
    expect(
      (await restarted.packages())
          .single
          .package
          .questions
          .first
          .ruby
          .single
          .reading,
      'ニホンゴ',
    );
    expect(
      (await restarted.loadBookState('quiz-fixture')).showReadings,
      isFalse,
    );
    await restarted.saveShowReadings('quiz-fixture', true);
    expect(
      (await restarted.loadBookState('quiz-fixture')).showReadings,
      isTrue,
    );
    expect((await restarted.attempts('quiz-fixture')).single.correctCount, 1);
  });

  test(
    'immediate feedback locks an answer durably and rejects foreign options',
    () async {
      await install();
      final s = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 2, feedback: QuizFeedback.immediate),
        now: clock,
      );
      await store.answer('quiz-fixture', s.id, 'q-1', 'b', now: clock);
      final reopened = QuizStore(root: root);
      await expectLater(
        reopened.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock),
        throwsStateError,
      );
      expect(
        (await reopened.answer(
          'quiz-fixture',
          s.id,
          'q-1',
          'b',
          now: clock,
        )).answers['q-1'],
        'b',
      );
      await expectLater(
        reopened.answer('quiz-fixture', s.id, 'q-2', 'foreign', now: clock),
        throwsFormatException,
      );
      await expectLater(
        reopened.answer('quiz-fixture', s.id, 'q-4', 'a', now: clock),
        throwsFormatException,
      );
      await expectLater(
        reopened.startSession(
          'quiz-fixture',
          const QuizSettings(questionCount: 1),
          now: clock,
        ),
        throwsStateError,
      );
      expect((await reopened.loadActiveSession('quiz-fixture'))!.answers, {
        'q-1': 'b',
      });
    },
  );

  test(
    'deadline persists across restarts and late selection cannot earn credit',
    () async {
      await install();
      final s = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 3, durationMinutes: 1),
        now: clock,
      );
      await store.answer(
        'quiz-fixture',
        s.id,
        'q-1',
        'a',
        now: clock.add(const Duration(seconds: 59)),
      );
      final reopened = QuizStore(root: root);
      final resume = (await reopened.loadActiveSession('quiz-fixture'))!;
      expect(resume.deadlineAt, clock.add(const Duration(minutes: 1)));
      expect(
        resume.remainingSeconds(clock.add(const Duration(milliseconds: 59500))),
        1,
      );
      expect(resume.isExpired(clock.add(const Duration(minutes: 1))), isTrue);
      await expectLater(
        reopened.answer(
          'quiz-fixture',
          s.id,
          'q-2',
          'a',
          now: clock.add(const Duration(minutes: 2)),
        ),
        throwsA(
          isA<QuizSessionExpiredException>().having(
            (e) => e.attempt.correctCount,
            'saved score',
            1,
          ),
        ),
      );
      final completed = (await reopened.attempts('quiz-fixture')).single;
      expect(completed.elapsedSeconds, 60);
      expect(completed.timedOut, isTrue);
      expect(completed.answeredCount, 1);
      expect((await reopened.stats('quiz-fixture')).wrongQuestionIds, {
        'q-2',
        'q-3',
      });
      expect(
        (await reopened.stats('quiz-fixture')).accuracy,
        closeTo(1 / 3, .00001),
      );
      expect(await reopened.loadActiveSession('quiz-fixture'), isNull);
    },
  );

  test('targeted correction clears current mistakes without erasing cumulative errors', () async {
    await install();
    await expectLater(
      store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 2, scope: QuizScope.wrong),
        now: clock,
      ),
      throwsFormatException,
    );
    final s = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 3),
      now: clock,
    );
    await store.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock);
    await store.answer('quiz-fixture', s.id, 'q-2', 'b', now: clock);
    await store.finishSession(
      'quiz-fixture',
      s.id,
      now: clock.add(const Duration(seconds: 1)),
    );
    final retry = await store.startSession(
      'quiz-fixture',
      const QuizSettings(
        questionCount: 10,
        scope: QuizScope.wrong,
        order: QuizOrder.random,
      ),
      now: clock.add(const Duration(seconds: 2)),
      random: Random(4),
    );
    expect(retry.questions.map((q) => q.id).toSet(), {'q-2', 'q-3'});
    for (final q in retry.questions) {
      await store.answer(
        'quiz-fixture',
        retry.id,
        q.id,
        q.answerId,
        now: clock.add(const Duration(seconds: 3)),
      );
    }
    await store.finishSession(
      'quiz-fixture',
      retry.id,
      now: clock.add(const Duration(seconds: 4)),
    );
    final stats = await QuizStore(root: root).stats('quiz-fixture');
    expect(stats.wrongCount, 0);
    expect(stats.masteredCount, 3);
    expect(stats.questionStats['q-2']!.wrongCount, 1);
    expect(stats.questionStats['q-3']!.wrongCount, 1);
    expect(stats.questionStats['q-3']!.answeredCount, 1);
    expect(stats.attemptCount, 2);
  });

  test('sequential tests continue around the bank and random draws never repeat a question', () async {
    await install();
    final s = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 3),
      now: clock,
    );
    expect(s.questions.map((q) => q.id), ['q-1', 'q-2', 'q-3']);
    await store.finishSession('quiz-fixture', s.id, now: clock);
    expect((await store.stats('quiz-fixture')).nextSequentialIndex, 3);
    final next = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 2),
      now: clock.add(const Duration(seconds: 1)),
    );
    expect(next.questions.map((q) => q.id), ['q-4', 'q-1']);
    await store.finishSession(
      'quiz-fixture',
      next.id,
      now: clock.add(const Duration(seconds: 2)),
    );
    final random = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 3, order: QuizOrder.random),
      now: clock.add(const Duration(seconds: 3)),
      random: Random(12),
    );
    expect(random.questions.map((q) => q.id).toSet(), hasLength(3));
    expect(
      random.questions.every(
        (q) => ['q-1', 'q-2', 'q-3', 'q-4'].contains(q.id),
      ),
      isTrue,
    );
  });

  test('finishing twice or recovering an already archived active record applies one score', () async {
    await install();
    final s = await store.startSession(
      'quiz-fixture',
      const QuizSettings(questionCount: 1),
      now: clock,
    );
    await store.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock);
    final activeFile = File('${root.path}/state/quiz-fixture/active.json');
    final activeBytes = await activeFile.readAsBytes();
    final completed = await store.finishSession(
      'quiz-fixture',
      s.id,
      now: clock,
    );
    await activeFile.writeAsBytes(activeBytes);
    final reopened = QuizStore(root: root);
    expect(await reopened.loadActiveSession('quiz-fixture'), isNull);
    final again = await reopened.finishSession(
      'quiz-fixture',
      s.id,
      now: clock.add(const Duration(minutes: 2)),
    );
    expect(again.session.toJson(), completed.session.toJson());
    expect((await reopened.stats('quiz-fixture')).attemptCount, 1);
    expect((await reopened.stats('quiz-fixture')).totalAssigned, 1);
  });

  test(
    'damaged active records are preserved, completed records remain usable',
    () async {
      await install();
      final s = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 1),
        now: clock,
      );
      await store.finishSession('quiz-fixture', s.id, now: clock);
      await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 1),
        now: clock,
      );
      await File('${root.path}/state/quiz-fixture/active.json')
          .writeAsString('{bad');
      final reopened = QuizStore(root: root);
      expect(await reopened.loadActiveSession('quiz-fixture'), isNull);
      expect((await reopened.attempts('quiz-fixture')), hasLength(1));
      expect(reopened.libraryWarnings.single, contains('原文件已保留'));
      expect(
        await Directory('${root.path}/state/quiz-fixture')
            .list()
            .where((f) => f.path.contains('.damaged-'))
            .length,
        1,
      );
    },
  );

  test(
    'a damaged archive cannot discard the healthy active snapshot',
    () async {
      await install();
      final s = await store.startSession(
        'quiz-fixture',
        const QuizSettings(questionCount: 1),
        now: clock,
      );
      await store.answer('quiz-fixture', s.id, 'q-1', 'a', now: clock);
      final activeFile = File('${root.path}/state/quiz-fixture/active.json');
      final bytes = await activeFile.readAsBytes();
      await store.finishSession('quiz-fixture', s.id, now: clock);
      await activeFile.writeAsBytes(bytes);
      final archive = File(
        '${root.path}/state/quiz-fixture/attempts/${s.id}.json',
      );
      await archive.writeAsString('{damaged');
      final reopened = QuizStore(root: root);
      final restored = await reopened.loadActiveSession('quiz-fixture');
      expect(restored!.answers, {'q-1': 'a'});
      expect(await archive.exists(), isFalse);
      final retried = await reopened.finishSession(
        'quiz-fixture',
        s.id,
        now: clock,
      );
      expect(retried.correctCount, 1);
      expect((await reopened.attempts('quiz-fixture')), hasLength(1));
      expect(reopened.libraryWarnings.single, contains('归档损坏'));
    },
  );

  test('unsafe ZIP paths, symlinks, malformed answers and encrypted headers never install', () async {
    final unsafe = _bank();
    unsafe.removeFile(unsafe.find('questions.json')!);
    unsafe.addFile(ArchiveFile.string('../outside.json', 'bad'));
    final linked = _bank();
    linked.removeFile(linked.find('questions.json')!);
    linked.addFile(ArchiveFile.string('questions.json', '[]')..mode = 0xa1ff);
    final invalidAnswer = _bank(answer: 'missing');
    final nested = _bank()..addFile(ArchiveFile.string('unused.json', '{}'));
    for (final bank in [unsafe, linked, invalidAnswer, nested]) {
      await expectLater(
        store.importZip(await zip(bank)),
        throwsFormatException,
      );
      expect(await store.packages(), isEmpty);
    }
    final bytes = List<int>.from(ZipEncoder().encode(_bank()));
    for (var i = 0; i + 4 < bytes.length; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 1 &&
          bytes[i + 3] == 2) {
        bytes[i + 8] |= 1;
        break;
      }
    }
    final crafted = await File('${temporary.path}/encrypted.zip')
        .writeAsBytes(bytes);
    await expectLater(store.importZip(crafted), throwsFormatException);
    expect(await store.packages(), isEmpty);
    expect(await File('${temporary.path}/outside.json').exists(), isFalse);
    expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
  });
}

Archive _bank({int revision = 1, String answer = 'a', String? reading}) =>
    Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'schema_version': '1.0',
            'kind': 'quiz',
            'package_id': 'quiz-fixture',
            'content_revision': revision,
            'title': 'N2 测验样本',
            'language': 'ja',
            'level_tags': ['N2'],
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'questions.json',
          jsonEncode([
            for (var i = 1; i <= 4; i++)
              {
                'id': 'q-$i',
                'prompt': '第 $i 問：日本語を（　）する。',
                if (reading != null)
                  'ruby': [
                    {'start': 6, 'end': 9, 'reading': reading},
                  ],
                'choices': [
                  {
                    'id': 'a',
                    'text': '正答',
                    if (reading != null)
                      'ruby': [
                        {'start': 0, 'end': 2, 'reading': 'せいとう'},
                      ],
                  },
                  {'id': 'b', 'text': '誤答'},
                ],
                'answer_id': answer,
              },
          ]),
        ),
      );
