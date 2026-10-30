import 'src/track.dart';
import 'subtitle_cue.dart';

/// Finds the last containing cue in start order; end times are exclusive.
SubtitleCue? cueAt(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final found = locate(cues, position, offset).active;
  return found < 0 ? null : cues[found];
}

/// Returns the active cue's predecessor, or the latest start in a gap.
SubtitleCue? previousCue(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final found = locate(cues, position, offset);
  final index = found.active < 0 ? found.latestStart : found.active - 1;
  return index < 0 ? null : cues[index];
}

/// Returns the active cue's successor, or the first upcoming start in a gap.
SubtitleCue? nextCue(
  List<SubtitleCue> cues,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final found = locate(cues, position, offset);
  final index = (found.active < 0 ? found.latestStart : found.active) + 1;
  return index >= cues.length ? null : cues[index];
}
