import 'src/parser_support.dart';
import 'src/track.dart';
import 'subtitle_cue.dart';

final _vttTimestamp = RegExp(
  r'^(?:([0-9]{2,}):)?([0-9]{2}):([0-9]{2})\.([0-9]{3})$',
);
final _vttHeader = RegExp(r'^WEBVTT(?:[ \t].*)?$');
final _vttComment = RegExp(r'^NOTE(?:\s|$)');

/// Reads the text-cue subset of WebVTT without interpreting its markup.
List<SubtitleCue> parseWebVtt(String raw) {
  final drafts = <CueDraft>[];
  var firstBlock = true;
  for (final block in subtitleBlocks(raw)) {
    final leader = block.first.trim();
    final isHeader = firstBlock && _vttHeader.hasMatch(leader);
    firstBlock = false;
    if (isHeader ||
        _vttComment.hasMatch(leader) ||
        leader == 'STYLE' ||
        leader == 'REGION') {
      continue;
    }
    final timingLine = leader.contains('-->') ? 0 : 1;
    final draft = readTimedBlock(block, timingLine, _readVttTime);
    if (draft != null) drafts.add(draft);
  }
  return finishTrack(drafts);
}

Duration? _readVttTime(String token) {
  final match = _vttTimestamp.firstMatch(token);
  if (match == null) return null;
  return assembleTimestamp(
    match[1] ?? '0',
    match[2]!,
    match[3]!,
    match[4]!,
    maximumHours: 2562047787,
  );
}
