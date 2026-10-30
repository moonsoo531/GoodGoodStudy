import 'src/parser_support.dart';
import 'src/track.dart';
import 'subtitle_cue.dart';

final _srtTimestamp = RegExp(
  r'^([0-9]{1,2}):([0-9]{2}):([0-9]{2})[,.]([0-9]{3})$',
);
final _sequenceNumber = RegExp(r'^[0-9]+$');

/// Parses complete SRT blocks, retaining each accepted payload as text.
List<SubtitleCue> parseSrt(String raw) {
  final drafts = <CueDraft>[];
  for (final block in subtitleBlocks(raw)) {
    final hasNumber = _sequenceNumber.hasMatch(block.first.trim());
    final draft = readTimedBlock(block, hasNumber ? 1 : 0, _readSrtTime);
    if (draft != null) drafts.add(draft);
  }
  return finishTrack(drafts);
}

Duration? _readSrtTime(String token) {
  final match = _srtTimestamp.firstMatch(token);
  if (match == null) return null;
  return assembleTimestamp(
    match[1]!,
    match[2]!,
    match[3]!,
    match[4]!,
    maximumHours: 99,
  );
}
