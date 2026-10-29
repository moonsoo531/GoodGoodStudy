import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/quiz/quiz_models.dart';

void main() {
  test('Japanese quiz package retains target ranges and source metadata', () {
    final question = _question();
    question['prompt'] = '📖日本語を勉強する。';
    question['underlines'] = [
      {'start': 2, 'end': 5},
    ];
    final bank = QuizPackage.fromJson(_manifest(), questions: [question]);
    expect(bank.questions.single.correctChoice.text, '正答');
    expect(bank.questions.single.underlines.single.start, 2);
    expect(bank.questions.single.source, {'pdf_page': 2});
    expect(
      QuizPackage.fromJson(
        bank.manifestJson,
        questions: bank.questions.map((q) => q.toJson()).toList(),
      ).toJson(),
      bank.toJson(),
    );
  });

  test(
    'bank kind, identities, choices, and answer references are validated',
    () {
      for (final manifest in [
        {..._manifest(), 'kind': 'study'},
        {..._manifest(), 'package_id': '../escape'},
        {..._manifest(), 'content_revision': 0},
        {..._manifest(), 'language': 'en'},
      ]) {
        expect(
          () => QuizPackage.fromJson(manifest, questions: [_question()]),
          throwsFormatException,
        );
      }
      expect(
        () => QuizPackage.fromJson(_manifest(), questions: []),
        throwsFormatException,
      );
      expect(
        () => QuizPackage.fromJson(
          _manifest(),
          questions: [_question(), _question()],
        ),
        throwsFormatException,
      );
      for (final question in [
        {..._question(), 'answer_id': 'not-an-option'},
        {
          ..._question(),
          'choices': [
            {'id': 'a', 'text': 'only'},
          ],
        },
        {
          ..._question(),
          'choices': [
            {'id': 'a', 'text': 'one'},
            {'id': 'a', 'text': 'two'},
          ],
        },
        {..._question(), 'prompt': ''},
      ]) {
        expect(() => QuizQuestion.fromJson(question), throwsFormatException);
      }
    },
  );

  test('underlines reject overlaps and split surrogate pairs', () {
    for (final ranges in [
      [
        {'start': 1, 'end': 3},
      ],
      [
        {'start': 2, 'end': 4},
        {'start': 3, 'end': 5},
      ],
      [
        {'start': 2, 'end': 20},
      ],
    ]) {
      expect(
        () => QuizQuestion.fromJson({
          ..._question(),
          'prompt': '📖日本語',
          'underlines': ranges,
        }),
        throwsFormatException,
      );
    }
  });

  test('prompt and choice readings round trip independently of answers', () {
    final raw = {
      ..._question(),
      'prompt': '📖日本語を勉強する。',
      'ruby': [
        {'start': 2, 'end': 5, 'reading': 'にほんご'},
        {'start': 6, 'end': 8, 'reading': 'べんきょう'},
      ],
      'underlines': [
        {'start': 4, 'end': 7},
      ],
      'choices': [
        {
          'id': 'a',
          'text': '学校',
          'ruby': [
            {'start': 0, 'end': 2, 'reading': 'がっこう'},
          ],
        },
        {
          'id': 'b',
          'text': '駅',
          'ruby': [
            {'start': 0, 'end': 1, 'reading': 'えき'},
          ],
        },
      ],
    };
    final q = QuizQuestion.fromJson(raw);
    expect(q.ruby.first.start, 2);
    expect(q.choices.first.ruby.single.reading, 'がっこう');
    expect(q.correctChoice.text, '学校');
    expect(q.answerId, 'a');
    expect(QuizQuestion.fromJson(q.toJson()).toJson(), raw);
    final old = QuizQuestion.fromJson(_question());
    expect(old.ruby, isEmpty);
    expect(old.choices.every((c) => c.ruby.isEmpty), isTrue);
    expect(old.toJson().containsKey('ruby'), isFalse);
  });

  test('prompt and choice readings reject invalid ranges and readings', () {
    for (final ruby in [
      null,
      'not-an-array',
      [
        {'start': 1, 'end': 3, 'reading': 'にほん'},
      ],
      [
        {'start': 2, 'end': 3, 'reading': ''},
      ],
      [
        {'start': 2, 'end': 3, 'reading': 'に\nほん'},
      ],
      [
        {'start': 2, 'end': 3, 'reading': 3},
      ],
      [
        {'start': -1, 'end': 3, 'reading': 'にほん'},
      ],
      [
        {'start': 2, 'end': 9, 'reading': 'にほん'},
      ],
      [
        {'start': 2, 'end': 2, 'reading': 'にほん'},
      ],
      [
        {'start': 2.0, 'end': 3, 'reading': 'にほん'},
      ],
      [
        {'start': 2, 'end': 4, 'reading': 'にほん'},
        {'start': 3, 'end': 5, 'reading': 'ほんご'},
      ],
    ]) {
      expect(
        () => QuizQuestion.fromJson({
          ..._question(),
          'prompt': '📖日本語',
          'ruby': ruby,
        }),
        throwsFormatException,
      );
      expect(
        () => QuizChoice.fromJson({'id': 'a', 'text': '📖日本語', 'ruby': ruby}),
        throwsFormatException,
      );
    }
    expect(
      () => QuizChoice.fromJson({
        'id': 'a',
        'text': '　',
        'ruby': [
          {'start': 0, 'end': 1, 'reading': 'にほん'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('test settings validate counts, durations and named modes', () {
    for (final settings in [
      const QuizSettings(questionCount: 0),
      const QuizSettings(questionCount: 2001),
      const QuizSettings(questionCount: 1, durationMinutes: -1),
      const QuizSettings(questionCount: 1, durationMinutes: 1441),
    ]) {
      expect(settings.validate, throwsFormatException);
    }
    const value = QuizSettings(
      questionCount: 5,
      durationMinutes: 15,
      feedback: QuizFeedback.immediate,
      scope: QuizScope.wrong,
      order: QuizOrder.random,
    );
    expect(QuizSettings.fromJson(value.toJson()).toJson(), value.toJson());
    expect(
      () => QuizSettings.fromJson({...value.toJson(), 'scope': 'unknown'}),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _manifest() => {
  'schema_version': '1.0',
  'kind': 'quiz',
  'package_id': 'quiz-fixture',
  'content_revision': 1,
  'title': '测试资料',
  'language': 'ja',
  'level_tags': ['N2'],
};

Map<String, dynamic> _question() => {
  'id': 'q-1',
  'section': '文脈規定',
  'prompt': '日本語を（　）する。',
  'choices': [
    {'id': 'a', 'text': '正答'},
    {'id': 'b', 'text': '誤答'},
  ],
  'answer_id': 'a',
  'source': {'pdf_page': 2},
};
