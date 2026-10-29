import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const widgetQuizId = 'quiz-widget-sample';
const widgetQuizTitle = 'N2 选择题验证样本';

Future<File> writeWidgetQuizZip(
  Directory directory, {
  bool withReadings = false,
}) async {
  final archive = Archive();
  void add(String name, Object value) {
    final bytes = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('manifest.json', {
    'kind': 'quiz',
    'schema_version': '1.0',
    'package_id': widgetQuizId,
    'content_revision': 1,
    'title': widgetQuizTitle,
    'language': 'ja',
    'translation_language': 'zh-CN',
    'level_tags': ['N2'],
  });
  add('questions.json', [
    {
      'id': 'q1',
      'section': '語彙',
      'prompt': withReadings ? '学校では、これは（　）です。' : 'これは（　）です。',
      if (withReadings)
        'ruby': [
          {'start': 0, 'end': 2, 'reading': 'がっこう'},
        ],
      'choices': [
        {
          'id': 'a',
          'text': '本',
          if (withReadings)
            'ruby': [
              {'start': 0, 'end': 1, 'reading': 'ほん'},
            ],
        },
        {
          'id': 'b',
          'text': '読む',
          if (withReadings)
            'ruby': [
              {'start': 0, 'end': 1, 'reading': 'よ'},
            ],
        },
        {'id': 'c', 'text': '走る'},
        {'id': 'd', 'text': '書く'},
      ],
      'answer_id': 'a',
      'explanation_zh': '这是第1题的解释。',
    },
    {
      'id': 'q2',
      'section': '語彙',
      'prompt': '駅へ（　）。',
      'choices': [
        {'id': 'a', 'text': '飲みます'},
        {'id': 'b', 'text': '行きます'},
        {'id': 'c', 'text': '読みます'},
        {'id': 'd', 'text': '食べます'},
      ],
      'answer_id': 'b',
      'explanation_zh': '这是第2题的解释。',
    },
    {
      'id': 'q3',
      'section': '語彙',
      'prompt': '朝早く起きて、長い文章を読んでから、いつもの道を通って、学校へ（　）。',
      'choices': [
        {'id': 'a', 'text': 'たくさんの説明を読んで、何度も考え直します'},
        {'id': 'b', 'text': '食べて、飲んで、それから読み返します'},
        {'id': 'c', 'text': '行きます'},
        {'id': 'd', 'text': '長い文章を読んで、それから書き直します'},
      ],
      'answer_id': 'c',
      'explanation_zh': '这是第3题的解释。',
    },
  ]);
  final zip = File('${directory.path}/quiz-widget-sample.zip').absolute;
  await zip.writeAsBytes(ZipEncoder().encode(archive));
  return zip;
}
