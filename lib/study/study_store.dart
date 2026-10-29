import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'study_models.dart';

class InstalledStudyPackage {
  const InstalledStudyPackage({required this.package, required this.directory});
  final StudyPackage package;
  final Directory directory;

  String audioPath(String ref) {
    for (final audio in package.media) {
      if (audio.id == ref) return '${directory.path}/${audio.path}';
    }
    throw ArgumentError.value(ref, 'ref', '音频不存在。');
  }
}

class StudyResumeLocation {
  const StudyResumeLocation({required this.packageId, required this.lessonId});
  final String packageId;
  final String lessonId;
}

class StudySyncSnapshot {
  StudySyncSnapshot({
    required List<InstalledStudyPackage> packages,
    required Map<String, Map<String, dynamic>> progress,
  }) : packages = List.unmodifiable(packages),
       progress = Map.unmodifiable({
         for (final entry in progress.entries)
           entry.key: _freezeMap(entry.value),
       });

  final List<InstalledStudyPackage> packages;
  final Map<String, Map<String, dynamic>> progress;

  static Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
      Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries) entry.key: _freeze(entry.value),
      });

  static Object? _freeze(Object? value) {
    if (value is Map<String, dynamic>) return _freezeMap(value);
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }
}

/// Imports only prepared data, without conversion or network access. Immutable
/// revision directories are committed through a small atomic current pointer.
/// Learning progress lives outside those directories and survives upgrades.
class StudyStore {
  StudyStore({this.root, this.onCommitted});
  final Directory? root;

  /// Queue synchronization work only; local commits never wait for the cloud.
  final void Function()? onCommitted;
  Directory? _root;
  Future<void> _pending = Future<void>.value();
  final List<String> _libraryWarnings = [];
  List<String> get libraryWarnings => List.unmodifiable(_libraryWarnings);

  static const maxZipBytes = 512 * 1024 * 1024;
  static const maxFileBytes = 128 * 1024 * 1024;
  static const maxExpandedBytes = 1024 * 1024 * 1024;
  static const maxJsonBytes = 8 * 1024 * 1024;
  static const maxZipEntries = 10000;
  static final _packageIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$');

  Future<Directory> _location() async {
    final root = _root ??=
        this.root ??
        Directory('${(await getApplicationSupportDirectory()).path}/study');
    await root.create(recursive: true);
    return root;
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _pending.then((_) => work());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> flush() => _pending;

  Future<InstalledStudyPackage> importZip(File zip) => _serial(() async {
    if (!zip.isAbsolute || !await zip.exists()) {
      throw const FormatException('请选择已下载到本机的 ZIP 学习包。');
    }
    if (await zip.length() > maxZipBytes) {
      throw const FormatException('学习包超过 512 MB，请按主题拆分。');
    }
    final root = await _location();
    final staging = await Directory('${root.path}/staging')
        .create(recursive: true);
    final stage = await staging.createTemp('import-');
    try {
      final bytes = await zip.readAsBytes();
      if (bytes.length > maxZipBytes) {
        throw const FormatException('学习包超过 512 MB，请按主题拆分。');
      }
      final directory = ZipDirectory();
      try {
        directory.read(InputMemoryStream(bytes));
      } on Object {
        throw const FormatException('ZIP 文件损坏或无法识别。');
      }
      if (directory.fileHeaders.isEmpty ||
          directory.fileHeaders.length > maxZipEntries ||
          directory.numberOfThisDisk != 0 ||
          directory.diskWithTheStartOfTheCentralDirectory != 0 ||
          directory.fileHeaders.length !=
              directory.totalCentralDirectoryEntries) {
        throw const FormatException('ZIP 条目数量无效或使用了不支持的分卷格式。');
      }
      final paths = <String>{};
      var total = 0;
      for (final header in directory.fileHeaders) {
        final name = header.filename;
        final isDirectory = name.endsWith('/');
        validateStudyRelativePath(
          isDirectory ? name.substring(0, name.length - 1) : name,
        );
        if (!paths.add(name.toLowerCase())) {
          throw const FormatException('ZIP 包含重复或大小写冲突的路径。');
        }
        final file = header.file;
        final kind = (header.externalFileAttributes >> 16) & 0xf000;
        if (file == null ||
            file.filename != name ||
            file.uncompressedSize != header.uncompressedSize ||
            file.compressedSize != header.compressedSize ||
            file.compressionMethod !=
                (header.compressionMethod == 0
                    ? CompressionType.none
                    : CompressionType.deflate) ||
            (header.generalPurposeBitFlag & 1) != 0 ||
            (file.flags & 1) != 0 ||
            (kind != 0 && kind != 0x8000 && kind != 0x4000) ||
            (header.compressionMethod != 0 && header.compressionMethod != 8) ||
            (header.compressionMethod == 0 &&
                header.compressedSize != header.uncompressedSize) ||
            header.diskNumberStart != 0) {
          throw const FormatException('不支持加密、链接或特殊类型的 ZIP 条目。');
        }
        if ((kind == 0x4000) != isDirectory && kind != 0) {
          throw const FormatException('ZIP 条目类型与路径不一致。');
        }
        final size = header.uncompressedSize;
        if (size < 0 ||
            size > maxFileBytes ||
            (name.endsWith('.json') && size > maxJsonBytes)) {
          throw const FormatException('学习包内的文件过大。');
        }
        total += size;
        if (total > maxExpandedBytes) {
          throw const FormatException('学习包解压后超过 1 GB。');
        }
        if (isDirectory) continue;
        if (name != 'manifest.json' &&
            name != 'lessons.json' &&
            name != 'entries.json' &&
            !name.startsWith('media/')) {
          throw FormatException('学习包中含有未定义的内容文件：$name');
        }
      }

      // Use validated central-directory records directly: ZipDecoder otherwise
      // merges duplicate filenames and may decompress symlinks while decoding.
      final extracted = <String>{};
      for (final header in directory.fileHeaders) {
        if (header.filename.endsWith('/')) continue;
        final content = header.file!.getStream().toUint8List();
        if (content.length != header.uncompressedSize ||
            getCrc32(content) != header.crc32) {
          throw FormatException('ZIP 文件校验失败：${header.filename}');
        }
        final target = File('${stage.path}/${header.filename}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(content, flush: true);
        extracted.add(header.filename);
      }
      final package = await _readContent(stage);
      final expected = {
        'manifest.json',
        'lessons.json',
        'entries.json',
        ...package.media.map((e) => e.path),
      };
      if (extracted.length != expected.length ||
          !extracted.containsAll(expected)) {
        throw const FormatException('学习包的音频清单与实际文件不一致。');
      }
      await _verifyAudio(package, stage);

      final base = Directory('${root.path}/packages/${package.packageId}');
      await base.create(recursive: true);
      ({int revision, String folder})? current;
      int? installedRevision;
      try {
        current = await _pointer(base);
        installedRevision = current?.revision ?? await _highestRevision(base);
      } on FormatException {
        // A damaged pointer can be repaired by reimporting the same or a newer
        // revision. Retain all old content and prevent accidental downgrades.
        installedRevision = await _highestRevision(base);
      }
      if (installedRevision != null &&
          package.contentRevision < installedRevision) {
        throw const FormatException('不能用旧版资料覆盖已导入的新版。');
      }
      var folder = current?.revision == package.contentRevision
          ? current!.folder
          : 'revision-${package.contentRevision}';
      var target = Directory('${base.path}/$folder');
      if (await target.exists()) {
        StudyPackage? existing;
        try {
          existing = await _readContent(target);
          await _verifyAudio(existing, target);
        } on FormatException {
          existing = null;
        } on FileSystemException {
          existing = null;
        }
        if (existing == null) {
          folder =
              'revision-${package.contentRevision}-repair-${DateTime.now().microsecondsSinceEpoch}';
          target = Directory('${base.path}/$folder');
        } else if (_canonical(existing.toJson()) !=
            _canonical(package.toJson())) {
          throw const FormatException('同一版本的资料内容不同，请提高 content_revision。');
        }
      }
      if (!await target.exists()) {
        await stage.rename(target.path);
      }
      await _atomicJson(File('${base.path}/current.json'), {
        'content_revision': package.contentRevision,
        'directory': folder,
      });
      return InstalledStudyPackage(package: package, directory: target);
    } on FormatException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('无法导入学习包：$error');
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  Future<List<InstalledStudyPackage>> packages() => _serial(_packages);

  Future<List<InstalledStudyPackage>> _packages() async {
    _libraryWarnings.clear();
    final root = await _location();
    final folder = Directory('${root.path}/packages');
    if (!await folder.exists()) return [];
    final result = <InstalledStudyPackage>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final item = await _current(entity);
        if (item != null) result.add(item);
      } on FormatException {
        _damagedPackage(entity);
      } on FileSystemException {
        _damagedPackage(entity);
      }
    }
    result.sort((a, b) => a.package.title.compareTo(b.package.title));
    return result;
  }

  /// Read committed content and its progress through the same local write queue.
  /// Resume locations remain device-specific and are not included.
  Future<StudySyncSnapshot> captureSyncSnapshot() => _serial(() async {
    final installed = await _packages();
    final progress = <String, Map<String, dynamic>>{};
    for (final item in installed) {
      progress[item.package.packageId] = await _loadProgress(
        item.package.packageId,
      );
    }
    return StudySyncSnapshot(packages: installed, progress: progress);
  });

  Future<InstalledStudyPackage?> _current(Directory base) async {
    final pointer = await _pointer(base);
    if (pointer == null) {
      if (await _highestRevision(base) != null) {
        throw const FormatException('已安装学习包缺少版本记录。');
      }
      return null;
    }
    final directory = Directory('${base.path}/${pointer.folder}');
    final package = await _readContent(directory);
    if (package.contentRevision != pointer.revision ||
        !base.path.endsWith('/${package.packageId}')) {
      throw const FormatException('已安装学习包的标识与版本记录不一致。');
    }
    return InstalledStudyPackage(package: package, directory: directory);
  }

  void _damagedPackage(Directory base) {
    final id = base.path.split('/').last;
    _libraryWarnings.add('资料包 $id 无法读取。请重新导入相同或更新版本修复，学习笔记会保留。');
  }

  Future<({int revision, String folder})?> _pointer(Directory base) async {
    final pointer = File('${base.path}/current.json');
    if (!await pointer.exists()) return null;
    final data = _jsonMap(await pointer.readAsString(), 'current.json');
    final revision = data['content_revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('已安装学习包的版本记录损坏。');
    }
    final folder = data['directory'] ?? 'revision-$revision';
    if (folder is! String ||
        !RegExp('^revision-$revision(?:-repair-[0-9]+)?\u0024')
            .hasMatch(folder)) {
      throw const FormatException('已安装学习包的内容路径损坏。');
    }
    return (revision: revision, folder: folder);
  }

  Future<int?> _highestRevision(Directory base) async {
    int? highest;
    await for (final entity in base.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      final match = RegExp(r'^revision-([0-9]+)(?:-repair-[0-9]+)?$')
          .firstMatch(name);
      final revision = match == null ? null : int.tryParse(match.group(1)!);
      if (revision != null && (highest == null || revision > highest)) {
        highest = revision;
      }
    }
    return highest;
  }

  Future<StudyPackage> _readContent(Directory directory) async {
    Future<Object?> read(String name) async {
      final file = File('${directory.path}/$name');
      if (!await file.exists()) throw FormatException('学习包缺少 $name。');
      if (await file.length() > maxJsonBytes) {
        throw FormatException('$name 超过 8 MB。');
      }
      return jsonDecode(await file.readAsString());
    }

    final manifest = await read('manifest.json');
    final lessons = await read('lessons.json');
    final entries = await read('entries.json');
    if (manifest is! Map<String, dynamic> ||
        lessons is! List ||
        entries is! List) {
      throw const FormatException('manifest 必须为对象，lessons 和 entries 必须为数组。');
    }
    return StudyPackage.fromJson(manifest, lessons: lessons, entries: entries);
  }

  Future<void> _verifyAudio(StudyPackage package, Directory directory) async {
    for (final media in package.media) {
      final file = File('${directory.path}/${media.path}');
      if (!await file.exists()) throw FormatException('学习包缺少音频 ${media.path}。');
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != media.sha256) {
        throw FormatException('音频 SHA-256 校验失败：${media.path}');
      }
    }
  }

  Future<Map<String, dynamic>> loadProgress(String packageId) =>
      _serial(() => _loadProgress(packageId));

  Future<Map<String, dynamic>> _loadProgress(String packageId) async {
    final file = await _stateFile(packageId, 'progress');
    if (!await file.exists()) return {};
    try {
      return _jsonMap(utf8.decode(await file.readAsBytes()), '学习进度');
    } on FormatException {
      await file.rename(
        '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
      );
      _libraryWarnings.add('资料包 $packageId 的学习进度损坏，原文件已保留备份；本次从默认设置开始。');
      return {};
    }
  }

  /// Only records an explicitly entered lesson. Importing alone creates no
  /// resume record. The caller saves that lesson's progress before this pointer.
  Future<void> saveResumeLocation({
    required String packageId,
    required String lessonId,
  }) => _serial(() async {
    if (!_packageIdPattern.hasMatch(packageId)) {
      throw ArgumentError.value(packageId, 'packageId');
    }
    if (!_validLessonId(lessonId)) {
      throw ArgumentError.value(lessonId, 'lessonId');
    }
    await _atomicJson(await _stateFile('learning', 'resume'), {
      'schema_version': 1,
      'package_id': packageId,
      'lesson_id': lessonId,
    });
  });

  /// Resolve only currently installed, valid content. An existing global
  /// pointer is authoritative even when stale: never replace it with an
  /// unrelated package or the first lesson. Legacy progress is consulted only
  /// once, when no global pointer exists yet.
  Future<StudyResumeLocation?> loadResumeLocation(
    List<InstalledStudyPackage> packages,
  ) => _serial(() async {
    final file = await _stateFile('learning', 'resume');
    if (await file.exists()) {
      try {
        if (await file.length() > maxJsonBytes) {
          throw const FormatException('学习位置记录过大。');
        }
        final data = _jsonMap(utf8.decode(await file.readAsBytes()), '上次学习位置');
        if (data['schema_version'] != 1) {
          throw const FormatException('学习位置记录版本无效。');
        }
        if (data['selection_required'] == true) return null;
        final packageId = data['package_id'], lessonId = data['lesson_id'];
        if (packageId is! String ||
            !_packageIdPattern.hasMatch(packageId) ||
            lessonId is! String ||
            !_validLessonId(lessonId)) {
          throw const FormatException('学习位置记录无效。');
        }
        return _resolveResume(packages, packageId, lessonId);
      } on FormatException {
        await file.rename(
          '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
        // Keep the invalid record backed up, and retain an explicit selection
        // marker so a later launch cannot accidentally fall back to history.
        await _atomicJson(file, {
          'schema_version': 1,
          'selection_required': true,
        });
        _libraryWarnings.add('上次学习位置损坏，原文件已保留备份；请重新选择资料和篇目，个人笔记会保留。');
        return null;
      }
    }

    StudyResumeLocation? latest;
    DateTime? latestModified;
    for (final installed in packages) {
      final packageId = installed.package.packageId;
      final progressFile = await _stateFile(packageId, 'progress');
      if (!await progressFile.exists()) continue;
      final modified = await progressFile.lastModified();
      final progress = await _loadProgress(packageId);
      final lessonId = progress['lesson_id'];
      if (lessonId is! String) continue;
      final exists = installed.package.lessons.any(
        (lesson) => lesson.id == lessonId,
      );
      if (exists &&
          (latestModified == null || modified.isAfter(latestModified))) {
        latest = StudyResumeLocation(packageId: packageId, lessonId: lessonId);
        latestModified = modified;
      }
    }
    if (latest != null) {
      await _atomicJson(file, {
        'schema_version': 1,
        'package_id': latest.packageId,
        'lesson_id': latest.lessonId,
      });
    }
    return latest;
  });

  bool _validLessonId(String id) => id.trim().isNotEmpty && id.length <= 100000;

  StudyResumeLocation? _resolveResume(
    List<InstalledStudyPackage> packages,
    String packageId,
    String lessonId,
  ) {
    for (final installed in packages) {
      if (installed.package.packageId == packageId &&
          installed.package.lessons.any((lesson) => lesson.id == lessonId)) {
        return StudyResumeLocation(packageId: packageId, lessonId: lessonId);
      }
    }
    return null;
  }

  Future<void> saveProgress(String packageId, Map<String, dynamic> progress) {
    final snapshot = jsonEncode(progress);
    return _serial(() async {
      await _atomicText(await _stateFile(packageId, 'progress'), snapshot);
    });
  }

  /// Apply only while the caller has suspended the corresponding learning page.
  /// Compare the entire document so a newer local note cannot be overwritten.
  Future<bool> applySyncedProgress(
    String packageId, {
    required Map<String, dynamic> expectedLocal,
    required Map<String, dynamic> progress,
  }) {
    if (!_packageIdPattern.hasMatch(packageId)) {
      throw ArgumentError.value(packageId, 'packageId');
    }
    // Capture caller-owned maps before waiting for earlier local writes.
    final expected = _canonical(expectedLocal);
    _validateSyncJson(progress);
    final snapshot = jsonEncode(progress);
    if (utf8.encode(snapshot).length > maxJsonBytes) {
      throw const FormatException('同步学习进度超过 8 MB，未覆盖本机记录。');
    }
    return _serial(() async {
      final local = await _loadProgress(packageId);
      if (_canonical(local) != expected) return false;
      final decoded = _jsonMap(snapshot, '同步学习进度');
      _validateSyncedProgress(decoded);
      await _atomicText(await _stateFile(packageId, 'progress'), snapshot);
      await _updateSyncedResume(packageId, decoded);
      return true;
    });
  }

  Future<void> _updateSyncedResume(
    String packageId,
    Map<String, dynamic> progress,
  ) async {
    final lessonId = progress['lesson_id'];
    if (lessonId is! String || !_validLessonId(lessonId)) return;
    final root = await _location();
    final file = File('${root.path}/state/learning-resume.json');
    Map<String, dynamic> resume;
    try {
      // Do not create a pointer or migrate another package's local history.
      if (!await file.exists() || await file.length() > maxJsonBytes) return;
      resume = _jsonMap(utf8.decode(await file.readAsBytes()), '上次学习位置');
      final previousLesson = resume['lesson_id'];
      if (resume['schema_version'] != 1 ||
          resume['selection_required'] == true ||
          resume['package_id'] != packageId ||
          previousLesson is! String ||
          !_validLessonId(previousLesson) ||
          previousLesson == lessonId) {
        return;
      }
      final base = Directory('${root.path}/packages/$packageId');
      if (!await base.exists()) return;
      final installed = await _current(base);
      if (installed == null ||
          !installed.package.lessons.any((lesson) => lesson.id == lessonId)) {
        return;
      }
    } on FormatException {
      // Preserve malformed pointers for the existing recovery path.
      return;
    } on FileSystemException {
      return;
    }
    await _atomicJson(file, {...resume, 'lesson_id': lessonId});
  }

  void _validateSyncedProgress(Map<String, dynamic> progress) {
    void invalid(String field) {
      throw FormatException('同步学习进度的 $field 无效，未覆盖本机记录。');
    }

    for (final key in ['lesson_id', 'audio_segment_id']) {
      if (!progress.containsKey(key) || progress[key] == null) continue;
      final value = progress[key];
      if (value is! String || !_validLessonId(value)) invalid(key);
    }
    for (final key in ['show_translation', 'show_readings']) {
      if (progress.containsKey(key) && progress[key] is! bool) invalid(key);
    }
    if (progress.containsKey('mode') &&
        !['read', 'keywords', 'dictation'].contains(progress['mode'])) {
      invalid('mode');
    }
    if (progress.containsKey('playback_scope') &&
        !['passage', 'sentence'].contains(progress['playback_scope'])) {
      invalid('playback_scope');
    }
    if (progress.containsKey('rate')) {
      final value = progress['rate'];
      if (value is! num || ![0.5, 0.75, 1.0, 1.25, 1.5, 2.0].contains(value)) {
        invalid('rate');
      }
    }
    if (progress.containsKey('repeat_count')) {
      final value = progress['repeat_count'];
      if (value is! int || ![0, 1, 2, 3, 5, 10].contains(value)) {
        invalid('repeat_count');
      }
    }
    if (progress.containsKey('entry_attribute_defaults_version')) {
      final value = progress['entry_attribute_defaults_version'];
      if (value is! int || value < 0) {
        invalid('entry_attribute_defaults_version');
      }
    }
    if (progress.containsKey('entry_notes')) {
      final notes = progress['entry_notes'];
      if (notes is! Map<String, dynamic> ||
          notes.values.any((value) => value is! String)) {
        invalid('entry_notes');
      }
    }
    if (progress.containsKey('entry_attributes')) {
      final attributes = progress['entry_attributes'];
      if (attributes is! Map<String, dynamic> ||
          attributes.values.any(
            (value) =>
                value is! Map<String, dynamic> ||
                value.values.any((attribute) => attribute is! String),
          )) {
        invalid('entry_attributes');
      }
    }
  }

  // Preserve unknown fields for newer clients, but accept only bounded JSON
  // values rather than arbitrary objects with custom encoders or cyclic maps.
  void _validateSyncJson(Object? value, [int depth = 0]) {
    if (depth > 64) {
      throw const FormatException('同步学习进度的嵌套层级过深。');
    }
    if (value == null || value is String || value is bool) return;
    if (value is num && value.isFinite) return;
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('同步学习进度的字段名必须是字符串。');
        }
        _validateSyncJson(entry.value, depth + 1);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _validateSyncJson(item, depth + 1);
      }
      return;
    }
    throw const FormatException('同步学习进度包含无效的 JSON 值。');
  }

  Future<File> _stateFile(String id, String kind) async {
    if (!_packageIdPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'packageId');
    }
    final root = await _location();
    final state = Directory('${root.path}/state');
    await state.create(recursive: true);
    return File('${state.path}/$id-$kind.json');
  }

  Future<void> _atomicJson(File file, Object value) =>
      _atomicText(file, jsonEncode(value));

  Future<void> _atomicText(File file, String text) async {
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
      _notifyCommitted();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void _notifyCommitted() {
    try {
      onCommitted?.call();
    } on Object {
      // A synchronization scheduling failure must not undo a local commit.
    }
  }

  Map<String, dynamic> _jsonMap(String input, String label) {
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$label 必须为对象。');
    }
    return decoded;
  }

  String _canonical(Object? value) {
    Object? sorted(Object? value) {
      if (value is Map<String, dynamic>) {
        final keys = value.keys.toList()..sort();
        return {for (final key in keys) key: sorted(value[key])};
      }
      if (value is List) return value.map(sorted).toList();
      return value;
    }

    return jsonEncode(sorted(value));
  }
}
