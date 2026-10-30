import 'track.dart';

/// Treat line ending variants alike while retaining payload line boundaries.
Iterable<List<String>> subtitleBlocks(String raw) sync* {
  final withoutBom = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  final normalized = withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var lines = <String>[];
  for (final line in normalized.split('\n')) {
    if (line.trim().isEmpty) {
      if (lines.isNotEmpty) {
        yield lines;
        lines = <String>[];
      }
    } else {
      lines.add(line);
    }
  }
  if (lines.isNotEmpty) yield lines;
}

final _space = RegExp(r'\s');

/// Reads only the time pair; remaining whitespace-separated settings are opaque.
CueDraft? readTimedBlock(
  List<String> block,
  int timingLine,
  Duration? Function(String) readTimestamp,
) {
  if (timingLine + 1 >= block.length) return null;
  final timing = block[timingLine].trim();
  final arrow = timing.indexOf('-->');
  if (arrow < 0) return null;
  final start = readTimestamp(timing.substring(0, arrow).trim());
  final tail = timing.substring(arrow + 3).trim();
  final separator = _space.firstMatch(tail);
  final end = readTimestamp(
    separator == null ? tail : tail.substring(0, separator.start),
  );
  if (start == null || end == null || end <= start) return null;
  final text = block.skip(timingLine + 1).join('\n').trim();
  if (text.isEmpty) return null;
  return CueDraft(start, end, text);
}

/// Bounded decimal accumulation avoids ever constructing an overflowing int.
int? readBoundedDecimal(String digits, int maximum) {
  var result = 0;
  for (final unit in digits.codeUnits) {
    final digit = unit - 0x30;
    if (digit < 0 || digit > 9 || result > (maximum - digit) ~/ 10) {
      return null;
    }
    result = result * 10 + digit;
  }
  return result;
}

Duration? assembleTimestamp(
  String hours,
  String minutes,
  String seconds,
  String fraction, {
  required int maximumHours,
}) {
  final h = readBoundedDecimal(hours, maximumHours);
  final m = readBoundedDecimal(minutes, 59);
  final s = readBoundedDecimal(seconds, 59);
  final ms = readBoundedDecimal(fraction, 999);
  if (h == null || m == null || s == null || ms == null) return null;
  final millis = h * 3600000 + m * 60000 + s * 1000 + ms;
  if (millis > 0x7fffffffffffffff ~/ Duration.microsecondsPerMillisecond) {
    return null;
  }
  return Duration(milliseconds: millis);
}
