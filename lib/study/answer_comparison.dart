import 'dart:typed_data';

/// Bounds the quadratic alignment while accommodating normal study passages.
const maxStudyComparisonCharacters = 2000;
const _maxRawCodeUnits = 16000;

class ComparisonSpan {
  const ComparisonSpan({required this.text, required this.different});

  final String text;
  final bool different;
}

class AnswerComparison {
  AnswerComparison({
    required List<ComparisonSpan> actualSpans,
    required List<ComparisonSpan> expectedSpans,
    required this.matches,
    required this.hasContent,
    this.tooLong = false,
  }) : actualSpans = List.unmodifiable(actualSpans),
       expectedSpans = List.unmodifiable(expectedSpans);

  /// Wrong and extra input characters are marked as different.
  final List<ComparisonSpan> actualSpans;

  /// Wrong and missing answer characters are marked as different.
  final List<ComparisonSpan> expectedSpans;

  /// Matching punctuation-only or blank strings never count as an answer.
  final bool matches;
  final bool hasContent;

  /// No comparison was attempted; both span lists remain neutral.
  final bool tooLong;
}

/// Aligns an input with the prepared source text for self-correction, without
/// assigning a score or judging synonyms. Ignores spacing and common sentence
/// punctuation; folds ASCII width only. Original spelling is always preserved.
AnswerComparison compareStudyAnswer(String actual, String expected) {
  if (actual.length > _maxRawCodeUnits || expected.length > _maxRawCodeUnits) {
    return _tooLong(actual, expected);
  }
  final input = _prepare(actual);
  final answer = _prepare(expected);
  final n = input.keys.length;
  final m = answer.keys.length;
  if (n > maxStudyComparisonCharacters || m > maxStudyComparisonCharacters) {
    return _tooLong(actual, expected);
  }

  final width = m + 1;
  final distances = Uint16List((n + 1) * width);
  for (var i = n; i >= 0; i--) {
    for (var j = m; j >= 0; j--) {
      final cell = i * width + j;
      if (i == n) {
        distances[cell] = m - j;
      } else if (j == m) {
        distances[cell] = n - i;
      } else if (input.keys[i] == answer.keys[j]) {
        distances[cell] = distances[(i + 1) * width + j + 1];
      } else {
        final substitution = distances[(i + 1) * width + j + 1];
        final extra = distances[(i + 1) * width + j];
        final missing = distances[i * width + j + 1];
        final best = substitution < extra ? substitution : extra;
        distances[cell] = 1 + (best < missing ? best : missing);
      }
    }
  }

  final inputErrors = List<bool>.filled(n, false);
  final answerErrors = List<bool>.filled(m, false);
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && input.keys[i] == answer.keys[j]) {
      i++;
      j++;
    } else if (i < n &&
        j < m &&
        distances[i * width + j] == 1 + distances[(i + 1) * width + j + 1]) {
      // Prefer a replacement when equally optimal, keeping alignment stable.
      inputErrors[i++] = true;
      answerErrors[j++] = true;
    } else if (i < n &&
        (j == m ||
            distances[i * width + j] == 1 + distances[(i + 1) * width + j])) {
      inputErrors[i++] = true;
    } else {
      answerErrors[j++] = true;
    }
  }
  return AnswerComparison(
    actualSpans: _spans(input.units, inputErrors),
    expectedSpans: _spans(answer.units, answerErrors),
    matches: n > 0 && m > 0 && distances.first == 0,
    hasContent: n > 0,
  );
}

AnswerComparison _tooLong(String actual, String expected) => AnswerComparison(
  actualSpans: actual.isEmpty
      ? const []
      : [ComparisonSpan(text: actual, different: false)],
  expectedSpans: expected.isEmpty
      ? const []
      : [ComparisonSpan(text: expected, different: false)],
  matches: false,
  hasContent: actual.runes.any((rune) => !_ignored(_foldWidth(rune))),
  tooLong: true,
);

class _Unit {
  const _Unit(this.text, this.index);
  final String text;
  final int? index;
}

class _Prepared {
  const _Prepared(this.units, this.keys);
  final List<_Unit> units;
  final List<int> keys;
}

_Prepared _prepare(String text) {
  final units = <_Unit>[];
  final keys = <int>[];
  for (final rune in text.runes) {
    final normalized = _foldWidth(rune);
    final ignored = _ignored(normalized);
    units.add(_Unit(String.fromCharCode(rune), ignored ? null : keys.length));
    if (!ignored) keys.add(normalized);
  }
  return _Prepared(units, keys);
}

List<ComparisonSpan> _spans(List<_Unit> units, List<bool> errors) {
  final spans = <ComparisonSpan>[];
  var buffer = StringBuffer();
  bool? previous;
  for (final unit in units) {
    final different = unit.index != null && errors[unit.index!];
    if (previous != null && previous != different) {
      spans.add(ComparisonSpan(text: buffer.toString(), different: previous));
      buffer = StringBuffer();
    }
    previous = different;
    buffer.write(unit.text);
  }
  if (previous != null) {
    spans.add(ComparisonSpan(text: buffer.toString(), different: previous));
  }
  return spans;
}

int _foldWidth(int rune) =>
    rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune;

bool _ignored(int rune) =>
    (rune >= 0x09 && rune <= 0x0d) ||
    rune == 0x20 ||
    rune == 0x85 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000 ||
    rune == 0xfeff ||
    _sentencePunctuation.contains(rune);

const _sentencePunctuation = <int>{
  0x21,
  0x22,
  0x27,
  0x28,
  0x29,
  0x2c,
  0x2e,
  0x3a,
  0x3b,
  0x3f,
  0x5b,
  0x5d,
  0x7b,
  0x7d,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2025,
  0x2026,
  0x3001,
  0x3002,
  0x3008,
  0x3009,
  0x300a,
  0x300b,
  0x300c,
  0x300d,
  0x300e,
  0x300f,
  0x3010,
  0x3011,
};
