final class SubtitleCue {
  const SubtitleCue({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  final int index;
  final Duration start;
  final Duration end;
  final String text;

  Duration get duration => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtitleCue &&
          index == other.index &&
          start == other.start &&
          end == other.end &&
          text == other.text;

  @override
  int get hashCode => Object.hash(index, start, end, text);
}
