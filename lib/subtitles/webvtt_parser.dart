import 'srt_parser.dart' show ParsedSubtitleCues;
import 'subtitle_cue.dart';

final _webVttHeader = RegExp(r'^WEBVTT(?:[ \t].*)?$');
final _webVttMetadata = RegExp(r'^(?:NOTE|STYLE|REGION)(?:[ \t]|$)');
final _webVttArrow = RegExp(
  r'^\s*((?:\d{2,}:)?\d{2}:\d{2}\.\d{3})\s*-->\s*'
  r'((?:\d{2,}:)?\d{2}:\d{2}\.\d{3})(?:[ \t]+.*)?[ \t]*$',
);

/// Keeps cue markup unchanged; inline entities are decoded by parseRubyText.
List<SubtitleCue> parseWebVtt(String raw) {
  var normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.startsWith('\uFEFF')) normalized = normalized.substring(1);
  final lines = normalized.split('\n');
  final cues = <SubtitleCue>[];
  var cursor = 0;
  while (cursor < lines.length) {
    while (cursor < lines.length && lines[cursor].trim().isEmpty) {
      cursor++;
    }
    final blockStart = cursor;
    while (cursor < lines.length && lines[cursor].trim().isNotEmpty) {
      cursor++;
    }
    if (blockStart == cursor) continue;
    final block = lines.sublist(blockStart, cursor);
    final first = block.first.trim();
    if (_webVttHeader.hasMatch(first) || _webVttMetadata.hasMatch(first)) {
      continue;
    }
    var timestampLine = 0;
    var match = _webVttArrow.firstMatch(block.first);
    if (match == null && block.length > 1) {
      timestampLine = 1;
      match = _webVttArrow.firstMatch(block[1]);
    }
    if (match == null) continue;
    final start = _parseTimestamp(match.group(1)!);
    final end = _parseTimestamp(match.group(2)!);
    final text = block.skip(timestampLine + 1).join('\n').trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    cues.add(
      SubtitleCue(index: cues.length, start: start, end: end, text: text),
    );
  }
  cues.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart == 0 ? a.index.compareTo(b.index) : byStart;
  });
  return ParsedSubtitleCues([
    for (var index = 0; index < cues.length; index++)
      SubtitleCue(
        index: index,
        start: cues[index].start,
        end: cues[index].end,
        text: cues[index].text,
      ),
  ]);
}

Duration? _parseTimestamp(String timestamp) {
  final parts = timestamp.split(':');
  final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
  final minutes = int.parse(parts[parts.length - 2]);
  final secondsAndMillis = parts.last.split('.');
  final seconds = int.parse(secondsAndMillis[0]);
  final millis = int.parse(secondsAndMillis[1]);
  if (hours == null || hours > 2562047787 || minutes > 59 || seconds > 59) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
