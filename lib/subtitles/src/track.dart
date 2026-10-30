import 'dart:collection';

import '../subtitle_cue.dart';

const _smallestTime = -0x8000000000000000;
const _largestTime = 0x7fffffffffffffff;

/// An internal parsing result before sorting and assigning display indices.
class CueDraft {
  CueDraft(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

/// Creates a frozen, independently indexed track, ordered stably by start.
List<SubtitleCue> finishTrack(List<CueDraft> drafts) {
  final order = List<int>.generate(drafts.length, (i) => i);
  order.sort((a, b) {
    final timeOrder = drafts[a].start.compareTo(drafts[b].start);
    return timeOrder == 0 ? a.compareTo(b) : timeOrder;
  });
  return IndexedCueList([
    for (var i = 0; i < order.length; i++)
      SubtitleCue(
        index: i,
        start: drafts[order[i]].start,
        end: drafts[order[i]].end,
        text: drafts[order[i]].text,
      ),
  ]);
}

/// A frozen list with a range-maximum tree over cue end times.
///
/// The tree permits finding the rightmost still-active cue even when many
/// later cues have ended, without walking backward through those cues.
class IndexedCueList extends UnmodifiableListView<SubtitleCue> {
  IndexedCueList(List<SubtitleCue> items)
    : _leafCount = _capacityFor(items.length),
      _latestEnd = _buildEndTree(items),
      super(List<SubtitleCue>.unmodifiable(items));

  final int _leafCount;
  final List<int> _latestEnd;

  int lastContaining(int latestStart, int time) =>
      _searchEnds(1, 0, _leafCount, latestStart, time);

  int _searchEnds(int node, int first, int span, int limit, int time) {
    if (first > limit || _latestEnd[node] <= time) return -1;
    if (span == 1) return first;
    final half = span ~/ 2;
    final fromRight = _searchEnds(
      node * 2 + 1,
      first + half,
      half,
      limit,
      time,
    );
    if (fromRight != -1) return fromRight;
    return _searchEnds(node * 2, first, half, limit, time);
  }
}

int _capacityFor(int count) {
  var size = 1;
  while (size < count) {
    size *= 2;
  }
  return size;
}

List<int> _buildEndTree(List<SubtitleCue> items) {
  final capacity = _capacityFor(items.length);
  final tree = List<int>.filled(capacity * 2, _smallestTime);
  for (var i = 0; i < items.length; i++) {
    tree[capacity + i] = items[i].end.inMicroseconds;
  }
  for (var node = capacity - 1; node > 0; node--) {
    final a = tree[node * 2];
    final b = tree[node * 2 + 1];
    tree[node] = a > b ? a : b;
  }
  return tree;
}

class CueLocation {
  const CueLocation(this.active, this.latestStart);

  final int active;
  final int latestStart;
}

/// Uses the attached tree for parser results and a correct scan for other lists.
CueLocation locate(List<SubtitleCue> cues, Duration position, Duration offset) {
  if (cues.isEmpty) return const CueLocation(-1, -1);
  final p = position.inMicroseconds;
  final o = offset.inMicroseconds;

  // A mathematical difference outside Duration's range precedes or follows
  // every representable cue; avoid wrapping native integer arithmetic.
  if (o > 0 && p < _smallestTime + o) {
    return const CueLocation(-1, -1);
  }
  if (o < 0 && p > _largestTime + o) {
    return CueLocation(-1, cues.length - 1);
  }
  final time = p - o;
  var lower = 0;
  var upper = cues.length;
  while (lower < upper) {
    final middle = lower + (upper - lower) ~/ 2;
    if (cues[middle].start.inMicroseconds <= time) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  final latest = lower - 1;
  if (latest < 0) return const CueLocation(-1, -1);
  if (cues is IndexedCueList) {
    return CueLocation(cues.lastContaining(latest, time), latest);
  }
  for (var candidate = latest; candidate >= 0; candidate--) {
    if (cues[candidate].end.inMicroseconds > time) {
      return CueLocation(candidate, latest);
    }
  }
  return CueLocation(-1, latest);
}
