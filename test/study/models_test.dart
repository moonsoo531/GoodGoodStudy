import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/study_models.dart';

void main() {
  test(
    'optional source ruby round trips without changing text or highlights',
    () {
      final data = _Fixture();
      expect(data.parse().lessons.single.segments.single.ruby, isEmpty);
      data.segment['ruby'] = <dynamic>[
        {
          'start': 0,
          'end': 2,
          'reading': 'そうさく',
          'source': {'pdf_page': 15},
        },
      ];
      final parsed = data.parse();
      final segment = parsed.lessons.single.segments.single;
      expect(segment.text, '創作する。');
      expect(segment.ruby.single.reading, 'そうさく');
      expect(segment.ruby.single.source, {'pdf_page': 15});
      expect(segment.toJson()['ruby'], data.segment['ruby']);
      expect(segment.highlights.single.start, 0);
    },
  );

  test(
    'rejects malformed, overlapping and surrogate-splitting ruby ranges',
    () {
      for (final ruby in [
        [
          {'start': -1, 'end': 1, 'reading': 'あ'},
        ],
        [
          {'start': 0, 'end': 100, 'reading': 'あ'},
        ],
        [
          {'start': 1, 'end': 1, 'reading': 'あ'},
        ],
        [
          {'start': 0, 'end': 1, 'reading': ''},
        ],
        [
          {'start': 0, 'end': 1, 'reading': 1},
        ],
        [
          {'start': 0.0, 'end': 1, 'reading': 'あ'},
        ],
        [
          {'start': 0, 'end': 2, 'reading': 'あ'},
          {'start': 1, 'end': 3, 'reading': 'い'},
        ],
        'そうさく',
      ]) {
        final data = _Fixture()..segment['ruby'] = ruby;
        expect(data.parse, throwsFormatException);
      }
      final data = _Fixture()
        ..segment['text'] = '𠮷田です。'
        ..segment['highlights'] = <dynamic>[]
        ..segment['ruby'] = <dynamic>[
          {'start': 0, 'end': 1, 'reading': 'よし'},
        ];
      expect(data.parse, throwsFormatException);
      data.segment['ruby'] = <dynamic>[
        {'start': 0, 'end': 3, 'reading': 'よしだ'},
      ];
      expect(
        data.parse().lessons.single.segments.single.ruby.single.reading,
        'よしだ',
      );
    },
  );

  test(
    'lesson vocabulary is optional and separate from passage highlights',
    () {
      final data = _Fixture();
      expect(data.parse().lessons.single.entryIds, isEmpty);
      data.lesson['entry_ids'] = ['sousaku'];
      data.segment['highlights'] = <dynamic>[];
      final lesson = data.parse().lessons.single;
      expect(lesson.entryIds, ['sousaku']);
      expect(lesson.toJson()['entry_ids'], ['sousaku']);
      expect(lesson.segments, hasLength(1));
      expect(lesson.segments.single.highlights, isEmpty);
      for (final invalid in [
        ['missing'],
        ['sousaku', 'sousaku'],
        [1],
        'sousaku',
      ]) {
        data.lesson['entry_ids'] = invalid;
        expect(data.parse, throwsFormatException, reason: '$invalid');
      }
      expect(
        () => StudyLesson.fromJson({...data.lesson, 'entry_ids': null}),
        throwsFormatException,
      );
    },
  );

  test(
    'round trip preserves Chinese content, attributes and source metadata',
    () {
      final data = _Fixture();
      final package = data.parse();
      expect(package.packageId, 'n2-pilot');
      expect(package.contentRevision, 1);
      expect(package.lessons.single.segments.single.translationZh, '我创作。');
      expect(package.entries.single.attributes, {'词性': '名・スル'});
      expect(package.entries.single.relations.single.meaningZh, '作品');
      expect(package.source, {'file': 'book.pdf'});
      expect(package.media.single.source, {'track_number': 1});
      expect(package.lessons.single.source, {'page': 14});
      expect(package.entries.single.source, {'page': 14, 'entry': 1});
      expect(package.lessons.single.segments.single.source, {'page': 14});
      final encoded =
          jsonDecode(jsonEncode(package.toJson())) as Map<String, dynamic>;
      final restored = StudyPackage.fromJson(
        encoded,
        lessons: encoded['lessons'] as List<dynamic>,
        entries: encoded['entries'] as List<dynamic>,
      );
      expect(restored.toJson(), package.toJson());
    },
  );

  test('rejects missing or malformed required manifest fields', () {
    for (final key in [
      'package_id',
      'content_revision',
      'title',
      'level_tags',
      'media',
    ]) {
      final data = _Fixture()..manifest.remove(key);
      expect(data.parse, throwsFormatException, reason: key);
    }
    for (final revision in [0, -1, 1.0, '1', null]) {
      final data = _Fixture()..manifest['content_revision'] = revision;
      expect(data.parse, throwsFormatException, reason: '$revision');
    }
    for (final id in ['../n2', 'N2', '/n2', 'n2.test', '', ' ']) {
      final data = _Fixture()..manifest['package_id'] = id;
      expect(data.parse, throwsFormatException, reason: id);
    }
    expect(
      (_Fixture()..manifest['level_tags'] = [2]).parse,
      throwsFormatException,
    );
  });

  test('requires the supported schema and Japanese / Chinese languages', () {
    for (final pair in [
      ('schema_version', '0.1-validation'),
      ('schema_version', 1),
      ('language', 'en'),
      ('translation_language', 'en'),
      ('translation_language', 'zh'),
    ]) {
      final data = _Fixture()..manifest[pair.$1] = pair.$2;
      expect(
        data.parse,
        throwsFormatException,
        reason: '${pair.$1}=${pair.$2}',
      );
    }
  });

  test('requires Chinese translations and well-formed entry metadata', () {
    final missing = _Fixture()..segment.remove('translation_zh');
    expect(missing.parse, throwsFormatException);
    final empty = _Fixture()..segment['translation_zh'] = '  ';
    expect(empty.parse, throwsFormatException);
    final kind = _Fixture()..entry['kind'] = 'other';
    expect(kind.parse, throwsFormatException);
    final attributes = _Fixture()..entry['attributes'] = {'词性': 1};
    expect(attributes.parse, throwsFormatException);
    final tags = _Fixture()..entry['tags'] = 'N2';
    expect(tags.parse, throwsFormatException);
    final grammar = _Fixture()..entry['kind'] = 'grammar';
    expect(grammar.parse().entries.single.kind, 'grammar');
  });

  test('rejects absent lessons, segments and dangling references', () {
    final empty = _Fixture()..lessons.clear();
    expect(empty.parse, throwsFormatException);
    final noSegments = _Fixture()..lesson['segments'] = [];
    expect(noSegments.parse, throwsFormatException);
    final audio = _Fixture()..lesson['audio_ref'] = 'missing';
    expect(audio.parse, throwsFormatException);
    final entry = _Fixture()..highlight['entry_id'] = 'missing';
    expect(entry.parse, throwsFormatException);
  });

  test(
    'rejects duplicate lesson, entry, segment, media IDs and media paths',
    () {
      final lessons = _Fixture();
      lessons.lessons.add(Map<String, dynamic>.from(lessons.lesson));
      expect(lessons.parse, throwsFormatException);
      final entries = _Fixture();
      entries.entries.add(Map<String, dynamic>.from(entries.entry));
      expect(entries.parse, throwsFormatException);
      final segments = _Fixture();
      (segments.lesson['segments'] as List).add(
        Map<String, dynamic>.from(segments.segment),
      );
      expect(segments.parse, throwsFormatException);
      final media = _Fixture();
      (media.manifest['media'] as List).add(
        Map<String, dynamic>.from(media.media),
      );
      expect(media.parse, throwsFormatException);
      final paths = _Fixture();
      (paths.manifest['media'] as List).add({...paths.media, 'id': 'second'});
      expect(paths.parse, throwsFormatException);
    },
  );

  test(
    'rejects ranges out of bounds, overlapping or splitting a surrogate pair',
    () {
      for (final range in [(-1, 1), (1, 1), (3, 2), (0, 100)]) {
        final data = _Fixture()
          ..highlight['start'] = range.$1
          ..highlight['end'] = range.$2;
        expect(data.parse, throwsFormatException, reason: '$range');
      }
      final overlap = _Fixture();
      (overlap.segment['highlights'] as List).add({
        'start': 1,
        'end': 4,
        'entry_id': 'sousaku',
      });
      expect(overlap.parse, throwsFormatException);
      for (final range in [(0, 1), (1, 3)]) {
        final data = _Fixture()
          ..segment['text'] = '𠮷田です。'
          ..highlight['start'] = range.$1
          ..highlight['end'] = range.$2;
        expect(data.parse, throwsFormatException, reason: '$range');
      }
      final complete = _Fixture()
        ..segment['text'] = '𠮷田です。'
        ..highlight['start'] = 0
        ..highlight['end'] = 3;
      expect(complete.parse().lessons.single.segments.single.text, '𠮷田です。');
    },
  );

  test('requires paired positive audio ranges and a referenced audio', () {
    for (final pair in [(-1, 100), (20, 20), (100, 20)]) {
      final data = _Fixture()
        ..segment['audio_start_ms'] = pair.$1
        ..segment['audio_end_ms'] = pair.$2;
      expect(data.parse, throwsFormatException);
    }
    for (final key in ['audio_start_ms', 'audio_end_ms']) {
      final data = _Fixture()..segment[key] = 20;
      expect(data.parse, throwsFormatException);
    }
    final noAudio = _Fixture()
      ..lesson.remove('audio_ref')
      ..segment['audio_start_ms'] = 0
      ..segment['audio_end_ms'] = 20;
    expect(noAudio.parse, throwsFormatException);
    final good = _Fixture()
      ..segment['audio_start_ms'] = 0
      ..segment['audio_end_ms'] = 100;
    expect(good.parse().lessons.single.segments.single.audioEndMs, 100);
  });

  test(
    'rejects invalid hashes, external/traversal and unsupported media paths',
    () {
      for (final hash in ['0' * 63, 'G' * 64, 'A' * 64, '']) {
        final data = _Fixture()..media['sha256'] = hash;
        expect(data.parse, throwsFormatException);
      }
      for (final path in [
        '/media/a.mp3',
        '../a.mp3',
        'media/../a.mp3',
        'media//a.mp3',
        r'media\a.mp3',
        'https://example.com/a.mp3',
        'media/a.txt',
        'audio/a.mp3',
        'media/./a.mp3',
        'media/a\u0000.mp3',
      ]) {
        final data = _Fixture()..media['path'] = path;
        expect(data.parse, throwsFormatException, reason: path);
      }
    },
  );
}

class _Fixture {
  final Map<String, dynamic> manifest = {
    'schema_version': '1.0',
    'package_id': 'n2-pilot',
    'content_revision': 1,
    'title': 'N2 样本',
    'language': 'ja',
    'translation_language': 'zh-CN',
    'level_tags': ['N2'],
    'source': {'file': 'book.pdf'},
    'media': <dynamic>[
      {
        'id': 'audio1',
        'path': 'media/T1.mp3',
        'sha256': '0' * 64,
        'source': {'track_number': 1},
      },
    ],
  };

  final List<dynamic> lessons = [
    {
      'id': 'lesson1',
      'title': '创作',
      'topic': '食事',
      'audio_ref': 'audio1',
      'source': {'page': 14},
      'segments': <dynamic>[
        {
          'id': 's1',
          'text': '創作する。',
          'translation_zh': '我创作。',
          'source': {'page': 14},
          'highlights': <dynamic>[
            {'start': 0, 'end': 2, 'entry_id': 'sousaku'},
          ],
        },
      ],
    },
  ];

  final List<dynamic> entries = [
    {
      'id': 'sousaku',
      'surface': '創作',
      'reading': 'そうさく',
      'meaning_zh': '创作',
      'explanation_zh': '可以接する。',
      'kind': 'vocabulary',
      'attributes': {'词性': '名・スル'},
      'tags': ['N2'],
      'relations': [
        {'label': '関連', 'text': '作品', 'meaning_zh': '作品'},
      ],
      'source': {'page': 14, 'entry': 1},
    },
  ];

  Map<String, dynamic> get media =>
      (manifest['media'] as List).single as Map<String, dynamic>;
  Map<String, dynamic> get lesson => lessons.first as Map<String, dynamic>;
  Map<String, dynamic> get segment =>
      (lesson['segments'] as List).first as Map<String, dynamic>;
  Map<String, dynamic> get highlight =>
      (segment['highlights'] as List).first as Map<String, dynamic>;
  Map<String, dynamic> get entry => entries.first as Map<String, dynamic>;

  StudyPackage parse() =>
      StudyPackage.fromJson(manifest, lessons: lessons, entries: entries);
}
