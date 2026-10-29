import 'dart:collection';

import 'subtitle_cue.dart';

final RegExp _srtArrow = RegExp(
  r'^\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*'
  r'(\d{1,2}:\d{2}:\d{2}[,.]\d{3})(?:\s+.*)?\s*$',
);

/// Returns immutable, chronologically sorted cues with zero-based indices.
List<SubtitleCue> parseSrt(String raw) {
  final content = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  final lines = _splitLines(content);
  final cues = <SubtitleCue>[];
  var i = 0;
  while (i < lines.length) {
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    if (i >= lines.length) break;
    if (_isAllDigits(lines[i].trim())) i++;
    if (i >= lines.length) break;

    final match = _srtArrow.firstMatch(lines[i]);
    if (match == null) {
      i++;
      continue;
    }
    final start = _parseTimestamp(match.group(1)!);
    final end = _parseTimestamp(match.group(2)!);
    i++;
    final text = StringBuffer();
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      if (text.isNotEmpty) text.writeln();
      text.write(lines[i]);
      i++;
    }
    final cueText = text.toString().trim();
    if (start != null && end != null && end > start && cueText.isNotEmpty) {
      cues.add(
        SubtitleCue(index: cues.length, start: start, end: end, text: cueText),
      );
    }
  }
  cues.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart == 0 ? a.index.compareTo(b.index) : byStart;
  });
  return ParsedSubtitleCues([
    for (var i = 0; i < cues.length; i++)
      SubtitleCue(
        index: i,
        start: cues[i].start,
        end: cues[i].end,
        text: cues[i].text,
      ),
  ]);
}

final class ParsedSubtitleCues extends UnmodifiableListView<SubtitleCue> {
  ParsedSubtitleCues(super.cues) : _latestEndThrough = _prefixLatestEnds(cues);

  final List<Duration> _latestEndThrough;

  bool hasActiveCueThrough(int index, Duration position) =>
      _latestEndThrough[index] > position;

  static List<Duration> _prefixLatestEnds(Iterable<SubtitleCue> cues) {
    var latestEnd = Duration.zero;
    return [
      for (final cue in cues)
        latestEnd = cue.end > latestEnd ? cue.end : latestEnd,
    ];
  }
}

List<String> _splitLines(String content) {
  if (!content.contains('\r')) return content.split('\n');
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final carriageReturn = line.indexOf('\r');
    if (carriageReturn < 0) continue;
    if (carriageReturn != line.length - 1) return _splitLegacyLines(content);
    final stripped = line.substring(0, carriageReturn);
    if (stripped.contains('\r')) return _splitLegacyLines(content);
    lines[i] = stripped;
  }
  return lines;
}

List<String> _splitLegacyLines(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

bool _isAllDigits(String line) {
  if (line.isEmpty) return false;
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit < 48 || unit > 57) return false;
  }
  return true;
}

int _digitsToInt(String source, int start, int end) {
  var value = 0;
  for (var i = start; i < end; i++) {
    value = value * 10 + (source.codeUnitAt(i) - 48);
  }
  return value;
}

Duration? _parseTimestamp(String raw) {
  final firstColon = raw.indexOf(':');
  final secondColon = raw.indexOf(':', firstColon + 1);
  final hours = _digitsToInt(raw, 0, firstColon);
  final minutes = _digitsToInt(raw, firstColon + 1, secondColon);
  final seconds = _digitsToInt(raw, secondColon + 1, secondColon + 3);
  final millis = _digitsToInt(raw, secondColon + 4, raw.length);
  if (minutes > 59 || seconds > 59) return null;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
