import 'srt_parser.dart' show ParsedSubtitleCues;
import 'subtitle_cue.dart';

/// A positive [offset] delays subtitles. Cue ends are exclusive.
/// [cues] must be sorted by start; the latest active cue wins overlaps.
SubtitleCue? cueAt(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final index = _activeIndex(cues, position - offset);
  return index < 0 ? null : cues[index];
}

/// In a gap, returns the most recently started cue; otherwise the prior cue.
/// [cues] must be sorted by start. A positive [offset] delays subtitles.
SubtitleCue? previousCue(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final time = position - offset;
  final active = _activeIndex(cues, time);
  final index = active >= 0 ? active - 1 : _rightmostStarted(cues, time);
  return index < 0 ? null : cues[index];
}

/// Returns the following cue, or the first upcoming cue when in a gap.
/// [cues] must be sorted by start. A positive [offset] delays subtitles.
SubtitleCue? nextCue(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final time = position - offset;
  final active = _activeIndex(cues, time);
  final index = active >= 0 ? active + 1 : _rightmostStarted(cues, time) + 1;
  return index < cues.length ? cues[index] : null;
}

int _activeIndex(List<SubtitleCue> cues, Duration position) {
  var index = _rightmostStarted(cues, position);
  while (index >= 0) {
    if (cues is ParsedSubtitleCues &&
        !cues.hasActiveCueThrough(index, position)) {
      return -1;
    }
    if (position < cues[index].end) return index;
    index--;
  }
  return -1;
}

int _rightmostStarted(List<SubtitleCue> cues, Duration position) {
  var low = 0;
  var high = cues.length - 1;
  var rightmost = -1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    if (cues[middle].start <= position) {
      rightmost = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return rightmost;
}
