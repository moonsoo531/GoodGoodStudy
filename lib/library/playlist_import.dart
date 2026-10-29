import 'dart:io';
import 'dart:isolate';

import 'local_library.dart';

typedef LocalMediaScanner = Future<LocalMediaScan> Function(
  Iterable<String> paths, {
  MediaScanCancellation? cancellation,
  void Function(MediaScanProgress progress)? onProgress,
  required bool includeCompanions,
});

class LocalMediaScan {
  const LocalMediaScan({
    required this.lessons,
    required this.directMediaPath,
    required this.containsDirectories,
    required this.unreadablePaths,
    this.cancelled = false,
  });

  final List<LocalLesson> lessons;

  /// The first directly selected media file, retaining the user's input order.
  final String? directMediaPath;
  final bool containsDirectories;
  final List<String> unreadablePaths;
  final bool cancelled;

  bool get foldersOnly => containsDirectories && directMediaPath == null;
}

class MediaScanCancellation {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class MediaScanProgress {
  const MediaScanProgress({
    required this.files,
    required this.media,
    required this.directories,
  });
  final int files;
  final int media;
  final int directories;
}

/// Scans local folders recursively without following links or hidden folders.
/// A failed folder does not prevent other dropped files from being imported.
Future<LocalMediaScan> scanLocalMedia(
  Iterable<String> paths, {
  MediaScanCancellation? cancellation,
  void Function(MediaScanProgress progress)? onProgress,
  bool includeCompanions = false,
}) async {
  final files = <String>{};
  final visitedDirectories = <String>{};
  final unreadable = <String>{};
  final companionDirectories = <String, List<String>>{};
  String? directMediaPath;
  var containsDirectories = false;
  var scanned = 0;
  var media = 0;
  bool getCancelled() => cancellation?.cancelled ?? false;

  void progress() => onProgress?.call(
    MediaScanProgress(
      files: scanned,
      media: media,
      directories: visitedDirectories.length,
    ),
  );

  void addFile(String path) {
    if (files.add(path) &&
        (audioExtensions.contains(extensionOf(path)) ||
            videoExtensions.contains(extensionOf(path)))) {
      media++;
    }
  }

  bool supported(String path) {
    final extension = extensionOf(path);
    return audioExtensions.contains(extension) ||
        videoExtensions.contains(extension) ||
        subtitleExtensions.contains(extension);
  }

  Future<void> scanDirectory(String path) async {
    if (getCancelled()) return;
    final normalized = Directory(path).absolute.uri
        .normalizePath()
        .toFilePath();
    if (!visitedDirectories.add(normalized)) return;
    progress();
    try {
      await for (final entity in Directory(
        normalized,
      ).list(followLinks: false)) {
        if (getCancelled()) break;
        if (fileName(entity.path).startsWith('.')) continue;
        if (entity is Directory) {
          await scanDirectory(entity.path);
        } else if (entity is File && supported(entity.path)) {
          addFile(entity.path);
        }
        scanned++;
        if (scanned % 24 == 0) progress();
      }
    } on FileSystemException {
      unreadable.add(normalized);
    }
  }

  for (final path in paths.toSet()) {
    if (getCancelled()) break;
    try {
      final normalized = File(path).absolute.uri.normalizePath().toFilePath();
      final type = await FileSystemEntity.type(normalized, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        containsDirectories = true;
        await scanDirectory(normalized);
      } else if (type == FileSystemEntityType.file && supported(normalized)) {
        addFile(normalized);
        scanned++;
        final extension = extensionOf(normalized);
        if (audioExtensions.contains(extension) ||
            videoExtensions.contains(extension)) {
          directMediaPath ??= normalized;
          if (includeCompanions) {
            // A file grant may not include its parent on macOS. Only use
            // companions when the existing directory authorization permits it.
            final parent = File(normalized).parent;
            final cached = companionDirectories.containsKey(parent.path);
            final siblings = companionDirectories.putIfAbsent(
              parent.path,
              () => [],
            );
            if (!cached) {
              try {
                await for (final sibling in parent.list(followLinks: false)) {
                  if (getCancelled()) break;
                  if (sibling is File && supported(sibling.path)) {
                    siblings.add(sibling.path);
                  }
                }
              } on FileSystemException {
                // A directly selected file does not require parent access.
              }
            }
            for (final sibling in siblings) {
              if (getCancelled()) break;
              if (stemOf(sibling).toLowerCase() ==
                  stemOf(normalized).toLowerCase()) {
                addFile(sibling);
              }
            }
          }
        }
      } else if (type == FileSystemEntityType.notFound) {
        unreadable.add(normalized);
      }
    } on FileSystemException {
      unreadable.add(path);
    } on ArgumentError {
      unreadable.add(path);
    }
  }

  progress();

  return LocalMediaScan(
    lessons: files.length > 500
        ? await _groupInBackground(files.toList())
        : groupLocalFiles(files),
    directMediaPath: directMediaPath,
    containsDirectories: containsDirectories,
    unreadablePaths: unreadable.toList(),
    cancelled: getCancelled(),
  );
}

Future<List<LocalLesson>> _groupInBackground(List<String> paths) =>
    Isolate.run(() => groupLocalFiles(paths));
