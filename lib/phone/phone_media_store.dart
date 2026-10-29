import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../library/local_library.dart';

const phoneAudioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'aif', 'aiff', 'caf'};

class PhoneLesson {
  const PhoneLesson({
    required this.relativeAudio,
    required this.title,
    this.relativeSubtitle,
  });
  final String relativeAudio;
  final String title;
  final String? relativeSubtitle;

  PhoneLesson withSubtitle(String subtitle) => PhoneLesson(
    relativeAudio: relativeAudio,
    title: title,
    relativeSubtitle: subtitle,
  );
}

class PhoneMediaStore {
  factory PhoneMediaStore({Directory? documents}) =>
      PhoneMediaStore._(documents);
  PhoneMediaStore._(this._documents);
  Directory? _documents;
  Future<void> _pendingSave = Future.value();

  Future<Directory> get documents async =>
      _documents ??= await getApplicationDocumentsDirectory();
  Future<Directory> get mediaDirectory async {
    final folder = Directory('${(await documents).path}/Media');
    await folder.create(recursive: true);
    return folder;
  }

  Future<String> absolutePath(String relative) async {
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.contains('\\') ||
        Uri.tryParse(relative)?.hasScheme == true ||
        relative.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw ArgumentError('Invalid local media path.');
    }
    return '${(await mediaDirectory).path}/$relative';
  }

  Future<List<String>> copySelected(Iterable<String> paths) async {
    final candidates = <File>[];
    final names = <String, String>{};
    for (final path in paths.toSet()) {
      final type = extensionOf(path);
      if (!phoneAudioExtensions.contains(type) &&
          !subtitleExtensions.contains(type)) {
        continue;
      }
      final source = File(path);
      if (!source.isAbsolute || !await source.exists()) {
        throw FileSystemException('请选择本地文件。', path);
      }
      final name = fileName(path).toLowerCase();
      if (names.containsKey(name)) {
        throw FormatException('所选文件中有重名文件：${fileName(path)}。请分次导入，避免覆盖。');
      }
      names[name] = path;
      candidates.add(source);
    }
    if (candidates.isEmpty) return [];
    final media = await mediaDirectory;
    final batch = Directory(
      '${media.path}/import-${DateTime.now().microsecondsSinceEpoch}',
    );
    await batch.create();
    final copied = <String>[];
    for (final source in candidates) {
      final target = '${batch.path}/${fileName(source.path)}';
      await source.copy(target);
      copied.add(target.substring(media.path.length + 1));
    }
    return copied;
  }

  Future<List<PhoneLesson>> scan({
    Map<String, String> associations = const {},
  }) async {
    final media = await mediaDirectory;
    final paths = <String>[];
    await for (final entity in media.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          (phoneAudioExtensions.contains(extensionOf(entity.path)) ||
              subtitleExtensions.contains(extensionOf(entity.path)))) {
        paths.add(entity.path);
      }
    }
    final grouped = groupLocalFiles(paths);
    final lessons = <PhoneLesson>[];
    for (final group in grouped) {
      final audio = group.audioPath;
      if (audio == null || !phoneAudioExtensions.contains(extensionOf(audio))) {
        continue;
      }
      final relative = audio.substring(media.path.length + 1);
      final chosen = associations[relative];
      String? subtitle;
      if (chosen != null && await File(await absolutePath(chosen)).exists()) {
        subtitle = chosen;
      } else if (group.subtitlePath != null) {
        subtitle = group.subtitlePath!.substring(media.path.length + 1);
      }
      lessons.add(
        PhoneLesson(
          relativeAudio: relative,
          title: group.title,
          relativeSubtitle: subtitle,
        ),
      );
    }
    return lessons;
  }

  Future<Map<String, dynamic>> loadState() async {
    final file = File('${(await documents).path}/phone-player-state.json');
    if (!await file.exists()) return {};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> saveState(Map<String, dynamic> state) {
    final encoded = jsonEncode(state);
    final next = _pendingSave.then((_) async {
      final target = File('${(await documents).path}/phone-player-state.json');
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(target.path);
    });
    _pendingSave = next.catchError((Object _) {});
    return next;
  }

  Future<void> flush() => _pendingSave;
}
