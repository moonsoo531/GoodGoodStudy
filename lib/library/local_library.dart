import 'dart:io';

class LocalLesson {
  const LocalLesson({
    required this.title,
    this.videoPath,
    this.audioPath,
    this.subtitlePath,
  });

  final String title;
  final String? videoPath;
  final String? audioPath;
  final String? subtitlePath;

  String get primaryPath => videoPath ?? audioPath!;
  String get identity => _groupKey(primaryPath);

  Map<String, dynamic> toJson() => {
    'title': title,
    'video': videoPath,
    'audio': audioPath,
    'subtitle': subtitlePath,
  };

  static LocalLesson fromJson(Map<String, dynamic> json) => LocalLesson(
    title: json['title'] as String,
    videoPath: json['video'] as String?,
    audioPath: json['audio'] as String?,
    subtitlePath: json['subtitle'] as String?,
  );
}

const audioExtensions = {
  'mp3',
  'm4a',
  'wav',
  'flac',
  'aac',
  'ogg',
  'opus',
  'aiff',
  'aif',
  'caf',
  'wma',
  'alac',
};
const subtitleExtensions = {'srt', 'vtt'};
const videoExtensions = {
  'mkv',
  'mp4',
  'm4v',
  'mov',
  'webm',
  'avi',
  'ts',
  'wmv',
  'mpg',
  'mpeg',
  'm2ts',
};

String fileName(String path) => path.split(Platform.pathSeparator).last;
String extensionOf(String path) {
  final name = fileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String stemOf(String path) {
  final name = fileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

String _groupKey(String path) {
  final normalized = File(path).absolute.uri.normalizePath().toFilePath();
  final extension = extensionOf(normalized);
  return (extension.isEmpty
          ? normalized
          : normalized.substring(0, normalized.length - extension.length - 1))
      .toLowerCase();
}

/// Compares numbered lesson names in reading order, e.g. lesson 2 before 10.
int compareNaturalNames(String first, String second) {
  final parts = RegExp(r'\d+|\D+');
  final a = parts.allMatches(first.toLowerCase()).map((e) => e[0]!).toList();
  final b = parts.allMatches(second.toLowerCase()).map((e) => e[0]!).toList();
  for (var index = 0; index < a.length && index < b.length; index++) {
    final left = a[index];
    final right = b[index];
    if (left == right) continue;
    final leftNumber = RegExp(r'^\d+$').hasMatch(left);
    final rightNumber = RegExp(r'^\d+$').hasMatch(right);
    if (leftNumber && rightNumber) {
      final leftValue = left.replaceFirst(RegExp(r'^0+'), '');
      final rightValue = right.replaceFirst(RegExp(r'^0+'), '');
      final lengthOrder = leftValue.length.compareTo(rightValue.length);
      if (lengthOrder != 0) return lengthOrder;
      final valueOrder = leftValue.compareTo(rightValue);
      if (valueOrder != 0) return valueOrder;
      continue;
    }
    return left.compareTo(right);
  }
  final partOrder = a.length.compareTo(b.length);
  return partOrder != 0 ? partOrder : first.compareTo(second);
}

List<LocalLesson> groupLocalFiles(Iterable<String> paths) {
  final groups = <String, Map<String, String>>{};
  for (final path in paths.toSet().toList()..sort()) {
    final extension = extensionOf(path);
    if (!audioExtensions.contains(extension) &&
        !videoExtensions.contains(extension) &&
        !subtitleExtensions.contains(extension)) {
      continue;
    }
    final key = _groupKey(path);
    final group = groups.putIfAbsent(key, () => {});
    final type = subtitleExtensions.contains(extension)
        ? 'subtitle'
        : audioExtensions.contains(extension)
        ? 'audio'
        : 'video';
    group.putIfAbsent(type, () => path);
  }
  return [
    for (final group in groups.values)
      if (group.containsKey('video') || group.containsKey('audio'))
        LocalLesson(
          title: stemOf(group['video'] ?? group['audio']!),
          videoPath: group['video'],
          audioPath: group['audio'],
          subtitlePath: group['subtitle'],
        ),
  ]..sort((a, b) {
    final titleOrder = compareNaturalNames(a.title, b.title);
    return titleOrder != 0
        ? titleOrder
        : compareNaturalNames(a.primaryPath, b.primaryPath);
  });
}

/// Adds new lessons while keeping existing queue positions and companion files.
/// When directly opening a media file, [preferredMediaPath] selects that exact
/// variant for its incoming lesson, including variants folded during grouping.
List<LocalLesson> mergePlaylist(
  Iterable<LocalLesson> existing,
  Iterable<LocalLesson> incoming, {
  String? preferredMediaPath,
}) {
  final additions = incoming.toList();
  final merged = <String, LocalLesson>{};
  for (final lesson in [...existing, ...additions]) {
    final previous = merged[lesson.identity];
    merged[lesson.identity] = previous == null
        ? lesson
        : LocalLesson(
            title: previous.title,
            videoPath: previous.videoPath ?? lesson.videoPath,
            audioPath: previous.audioPath ?? lesson.audioPath,
            subtitlePath: previous.subtitlePath ?? lesson.subtitlePath,
          );
  }
  if (preferredMediaPath != null) {
    final extension = extensionOf(preferredMediaPath);
    final isVideo = videoExtensions.contains(extension);
    final isAudio = audioExtensions.contains(extension);
    if (isVideo || isAudio) {
      final identity = _groupKey(preferredMediaPath);
      final previous = merged[identity];
      if (previous != null &&
          additions.any((lesson) => lesson.identity == identity)) {
        merged[identity] = LocalLesson(
          title: previous.title,
          videoPath: isVideo ? preferredMediaPath : previous.videoPath,
          audioPath: isAudio ? preferredMediaPath : previous.audioPath,
          subtitlePath: previous.subtitlePath,
        );
      }
    }
  }
  return merged.values.toList();
}
