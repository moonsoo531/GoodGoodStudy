import 'study_models.dart';

enum StudyMode { read, keywords, partial, dictation, translation }

/// A stable answer field in one passage. Offsets use Dart UTF-16 indices.
class PracticePrompt {
  const PracticePrompt({
    required this.id,
    required this.expected,
    required this.hint,
    required this.start,
    required this.end,
  });

  final String id;
  final String expected;
  final String hint;
  final int start;
  final int end;
}

List<PracticePrompt> practicePrompts(StudySegment segment, StudyMode mode) {
  if (mode == StudyMode.read) return const [];
  if (mode == StudyMode.dictation || mode == StudyMode.translation) {
    return [
      PracticePrompt(
        id: segment.id,
        expected: segment.text,
        hint: '',
        start: 0,
        end: segment.text.length,
      ),
    ];
  }
  return List.unmodifiable([
    for (var index = 0; index < segment.highlights.length; index++)
      _keywordPrompt(segment, index, partial: mode == StudyMode.partial),
  ]);
}

PracticePrompt _keywordPrompt(
  StudySegment segment,
  int index, {
  required bool partial,
}) {
  final highlight = segment.highlights[index];
  final expected = segment.text.substring(highlight.start, highlight.end);
  final runes = expected.runes.toList(growable: false);
  // One-character targets remain hidden; otherwise a hint would give the answer.
  final hint = partial && runes.length > 1
      ? '${String.fromCharCode(runes.first)}${'＿' * (runes.length - 1)}'
      : '＿' * runes.length;
  return PracticePrompt(
    id: '${segment.id}:$index',
    expected: expected,
    hint: hint,
    start: highlight.start,
    end: highlight.end,
  );
}
