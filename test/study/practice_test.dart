import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/study_models.dart';
import 'package:offline_player/study/study_practice.dart';

void main() {
  group('practice prompts', () {
    final segment = StudySegment(
      id: 's1',
      text: '創作料理で勝負する。',
      translationZh: '用创作料理一决胜负。',
      highlights: [
        StudyHighlight(start: 0, end: 2, entryId: 'sousaku'),
        StudyHighlight(start: 5, end: 7, entryId: 'shoubu'),
      ],
    );

    test('read has no answers; keyword spans refer to exact text', () {
      expect(practicePrompts(segment, StudyMode.read), isEmpty);
      final prompts = practicePrompts(segment, StudyMode.keywords);
      expect(prompts.map((prompt) => prompt.expected), ['創作', '勝負']);
      expect(prompts.map((prompt) => prompt.id), ['s1:0', 's1:1']);
      expect(prompts.map((prompt) => prompt.hint), ['＿＿', '＿＿']);
      expect(prompts.last.start, 5);
      expect(prompts.last.end, 7);
    });

    test('partial hints are deterministic and retain the full target', () {
      final prompts = practicePrompts(segment, StudyMode.partial);
      expect(prompts.map((prompt) => prompt.hint), ['創＿', '勝＿']);
      expect(prompts.first.expected, '創作');
      expect(
        practicePrompts(segment, StudyMode.partial).first.hint,
        prompts.first.hint,
      );
    });

    test('dictation and translation mask the whole segment', () {
      for (final mode in [StudyMode.dictation, StudyMode.translation]) {
        final prompt = practicePrompts(segment, mode).single;
        expect(prompt.id, segment.id);
        expect(prompt.expected, segment.text);
        expect(prompt.start, 0);
        expect(prompt.end, segment.text.length);
      }
    });

    test(
      'partial masks operate on Unicode runes and hide single characters',
      () {
        final single = StudySegment(
          id: 'unicode',
          text: '𠮷田と店',
          translationZh: '吉田和店铺',
          highlights: [
            StudyHighlight(start: 0, end: 3, entryId: 'yoshida'),
            StudyHighlight(start: 4, end: 5, entryId: 'shop'),
          ],
        );
        final prompts = practicePrompts(single, StudyMode.partial);
        expect(prompts.first.hint, '𠮷＿');
        expect(prompts.first.expected, '𠮷田');
        expect(prompts.last.hint, '＿');
      },
    );
  });
}
