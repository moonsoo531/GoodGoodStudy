String formatPlaybackTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 99999999);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final tail =
      '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:$tail' : tail;
}

/// Accepts seconds, minutes:seconds, or hours:minutes:seconds.
Duration? parsePlaybackTime(String input) {
  final parts = input.trim().split(':');
  if (parts.isEmpty ||
      parts.length > 3 ||
      parts.any((part) => !RegExp(r'^\d+$').hasMatch(part))) {
    return null;
  }
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((number) => number == null)) return null;
  if (parts.length > 1 && numbers.last! >= 60) return null;
  if (parts.length == 3 && numbers[1]! >= 60) return null;
  var seconds = 0;
  for (final number in numbers) {
    seconds = seconds * 60 + number!;
    if (seconds > 99999999) return null;
  }
  return Duration(seconds: seconds);
}
