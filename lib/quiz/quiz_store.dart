import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../study/study_models.dart' show validateStudyRelativePath;
import 'quiz_models.dart';

class InstalledQuizPackage {
  const InstalledQuizPackage({required this.package, required this.directory});
  final QuizPackage package;
  final Directory directory;
}

/// A view pointer only. Questions, active answers and completed attempts remain
/// in their existing independent files and are never copied into navigation.
class QuizNavigationLocation {
  const QuizNavigationLocation({
    required this.view,
    this.packageId,
    this.sessionId,
    this.attemptId,
    this.fromHistory = false,
    this.wrongOnly = false,
  });
  final String view;
  final String? packageId;
  final String? sessionId;
  final String? attemptId;
  final bool fromHistory;
  final bool wrongOnly;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'view': view,
    if (packageId != null) 'package_id': packageId,
    if (sessionId != null) 'session_id': sessionId,
    if (attemptId != null) 'attempt_id': attemptId,
    'from_history': fromHistory,
    'wrong_only': wrongOnly,
  };

  factory QuizNavigationLocation.fromJson(Map<String, dynamic> json) {
    final view = json['view'];
    if (json['version'] != 1 ||
        !const [
          'library',
          'settings',
          'exam',
          'result',
          'history',
        ].contains(view)) {
      throw const FormatException('Invalid quiz navigation');
    }
    final packageId = json['package_id'];
    if (view != 'library' && packageId is! String) {
      throw const FormatException('Missing quiz navigation package');
    }
    if (packageId != null) {
      if (packageId is! String) {
        throw const FormatException('Invalid quiz package');
      }
      validateQuizPackageId(packageId);
    }
    for (final key in ['session_id', 'attempt_id']) {
      final id = json[key];
      if (id != null) {
        if (id is! String) throw const FormatException('Invalid quiz record');
        validateQuizSessionId(id);
      }
    }
    return QuizNavigationLocation(
      view: view as String,
      packageId: packageId as String?,
      sessionId: json['session_id'] as String?,
      attemptId: json['attempt_id'] as String?,
      fromHistory: json['from_history'] == true,
      wrongOnly: json['wrong_only'] == true,
    );
  }
}

/// The quiz library is separate from study content and never converts PDFs.
/// Each finished test is a durable, immutable question/answer snapshot. Statistics
/// are derived from those records, so a crash cannot apply a score twice or
/// leave the mistake list out of sync with its corresponding result.
class QuizStore {
  QuizStore({this.root, this.onCommitted});
  final Directory? root;

  /// Queue synchronization work only; local commits never wait for the cloud.
  final void Function()? onCommitted;
  Directory? _root;
  Future<void> _pending = Future<void>.value();
  final List<String> _libraryWarnings = [];
  List<String> get libraryWarnings => List.unmodifiable(_libraryWarnings);

  static const maxZipBytes = 32 * 1024 * 1024;
  static const maxJsonBytes = 8 * 1024 * 1024;
  static const maxExpandedBytes = 16 * 1024 * 1024;
  static const maxStateBytes = 16 * 1024 * 1024;

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _pending.then((_) => work());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> flush() => _pending;

  Future<QuizNavigationLocation?> loadNavigationLocation() => _serial(() async {
    final file = File('${(await _location()).path}/navigation.json');
    if (!await file.exists()) return null;
    try {
      return QuizNavigationLocation.fromJson(
        await _readMap(file, 'Quiz navigation', max: 4096),
      );
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  });

  Future<void> saveNavigationLocation(QuizNavigationLocation location) =>
      _serial(() async {
        final value = location.toJson();
        QuizNavigationLocation.fromJson(value);
        await _atomicJson(
          File('${(await _location()).path}/navigation.json'),
          value,
        );
      });

  Future<Directory> _location() async {
    final directory = _root ??=
        root ??
        Directory('${(await getApplicationSupportDirectory()).path}/quiz');
    await directory.create(recursive: true);
    return directory;
  }

  Future<InstalledQuizPackage> importZip(File zip) => _serial(() async {
    if (!zip.isAbsolute || !await zip.exists()) {
      throw const FormatException('请选择已下载到本机的 ZIP 测验包。');
    }
    if (await zip.length() > maxZipBytes) {
      throw const FormatException('测验包超过 32 MB，请按资料拆分。');
    }
    final root = await _location();
    final staging = await Directory('${root.path}/staging')
        .create(recursive: true);
    final stage = await staging.createTemp('import-');
    try {
      final bytes = await zip.readAsBytes();
      if (bytes.length > maxZipBytes) {
        throw const FormatException('测验包超过 32 MB。');
      }
      final directory = ZipDirectory();
      try {
        directory.read(InputMemoryStream(bytes));
      } on Object {
        throw const FormatException('ZIP 文件损坏或无法识别。');
      }
      if (directory.fileHeaders.length != 2 ||
          directory.numberOfThisDisk != 0 ||
          directory.diskWithTheStartOfTheCentralDirectory != 0 ||
          directory.totalCentralDirectoryEntries != 2) {
        throw const FormatException(
          '测验 ZIP 根目录只能包含 manifest.json 和 questions.json。',
        );
      }
      final paths = <String>{};
      var total = 0;
      for (final header in directory.fileHeaders) {
        final name = header.filename;
        validateStudyRelativePath(name);
        if (!paths.add(name.toLowerCase())) {
          throw const FormatException('测验包包含重复或大小写冲突的路径。');
        }
        if (name != 'manifest.json' && name != 'questions.json') {
          throw FormatException('测验包含有未定义的文件：$name');
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
            (kind != 0 && kind != 0x8000) ||
            (header.compressionMethod != 0 && header.compressionMethod != 8) ||
            (header.compressionMethod == 0 &&
                header.compressedSize != header.uncompressedSize) ||
            header.diskNumberStart != 0) {
          throw const FormatException('不支持加密、链接、目录或特殊类型的 ZIP 条目。');
        }
        if (header.uncompressedSize < 0 ||
            header.uncompressedSize > maxJsonBytes) {
          throw const FormatException('测验包中的单个 JSON 不能超过 8 MB。');
        }
        total += header.uncompressedSize;
        if (total > maxExpandedBytes) {
          throw const FormatException('测验包解压后超过 16 MB。');
        }
      }
      if (!paths.containsAll({'manifest.json', 'questions.json'})) {
        throw const FormatException('测验包缺少清单或题目文件。');
      }
      // The directory records were validated before any payload is decompressed.
      // Do not use ZipDecoder, which merges duplicate filenames while decoding.
      for (final header in directory.fileHeaders) {
        final content = header.file!.getStream().toUint8List();
        if (content.length != header.uncompressedSize ||
            getCrc32(content) != header.crc32) {
          throw FormatException('ZIP 文件校验失败：${header.filename}');
        }
        await File('${stage.path}/${header.filename}')
            .writeAsBytes(content, flush: true);
      }
      final package = await _readContent(stage);
      final base = Directory('${root.path}/packages/${package.packageId}');
      await base.create(recursive: true);
      ({int revision, String folder})? pointer;
      int? installedRevision;
      try {
        pointer = await _pointer(base);
        installedRevision = pointer?.revision ?? await _highestRevision(base);
      } on FormatException {
        installedRevision = await _highestRevision(base);
      }
      if (installedRevision != null &&
          package.contentRevision < installedRevision) {
        throw const FormatException('不能用旧版测验资料覆盖新版。');
      }
      var folder = pointer?.revision == package.contentRevision
          ? pointer!.folder
          : 'revision-${package.contentRevision}';
      var target = Directory('${base.path}/$folder');
      if (await target.exists()) {
        QuizPackage? existing;
        try {
          existing = await _readContent(target);
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
          throw const FormatException('同一修订号的测验内容不同，请提高 content_revision。');
        }
      }
      if (!await target.exists()) await stage.rename(target.path);
      await _atomicJson(File('${base.path}/current.json'), {
        'content_revision': package.contentRevision,
        'directory': folder,
      });
      return InstalledQuizPackage(package: package, directory: target);
    } on FormatException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('无法导入测验包：$error');
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  Future<List<InstalledQuizPackage>> packages() => _serial(() async {
    _libraryWarnings.clear();
    final root = await _location();
    final directory = Directory('${root.path}/packages');
    if (!await directory.exists()) return [];
    final values = <InstalledQuizPackage>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final item = await _current(entity);
        if (item != null) values.add(item);
      } on FormatException {
        _warn(
          '测验资料 ${entity.path.split('/').last} 无法读取，请重新导入相同或更新版本修复。成绩记录会保留。',
        );
      } on FileSystemException {
        _warn(
          '测验资料 ${entity.path.split('/').last} 无法读取，请重新导入相同或更新版本修复。成绩记录会保留。',
        );
      }
    }
    values.sort((a, b) => a.package.title.compareTo(b.package.title));
    return values;
  });

  Future<InstalledQuizPackage?> _current(Directory base) async {
    final pointer = await _pointer(base);
    if (pointer == null) {
      if (await _highestRevision(base) != null) {
        throw const FormatException('已安装测验包缺少版本记录。');
      }
      return null;
    }
    final directory = Directory('${base.path}/${pointer.folder}');
    final package = await _readContent(directory);
    if (package.contentRevision != pointer.revision ||
        base.path.split('/').last != package.packageId) {
      throw const FormatException('测验包的资料标识或版本记录不一致。');
    }
    return InstalledQuizPackage(package: package, directory: directory);
  }

  Future<({int revision, String folder})?> _pointer(Directory base) async {
    final file = File('${base.path}/current.json');
    if (!await file.exists()) return null;
    final data = await _readMap(file, '测验版本记录');
    final revision = data['content_revision'], folder = data['directory'];
    if (revision is! int ||
        revision < 1 ||
        folder is! String ||
        !RegExp('^revision-$revision(?:-repair-[0-9]+)?\u0024')
            .hasMatch(folder)) {
      throw const FormatException('测验包的版本记录无效。');
    }
    return (revision: revision, folder: folder);
  }

  Future<int?> _highestRevision(Directory base) async {
    int? result;
    await for (final entity in base.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final match = RegExp(r'^revision-([0-9]+)(?:-repair-[0-9]+)?$')
          .firstMatch(entity.path.split('/').last);
      final revision = match == null ? null : int.tryParse(match.group(1)!);
      if (revision != null && (result == null || revision > result)) {
        result = revision;
      }
    }
    return result;
  }

  Future<QuizPackage> _readContent(Directory directory) async {
    final manifest = await _readMap(
      File('${directory.path}/manifest.json'),
      'manifest.json',
      max: maxJsonBytes,
    );
    final questionsFile = File('${directory.path}/questions.json');
    final questions = await _readJson(questionsFile, max: maxJsonBytes);
    if (questions is! List) {
      throw const FormatException('questions.json 必须为数组。');
    }
    return QuizPackage.fromJson(manifest, questions: questions);
  }

  Future<InstalledQuizPackage> _installed(String packageId) async {
    validateQuizPackageId(packageId);
    final root = await _location();
    final base = Directory('${root.path}/packages/$packageId');
    if (!await base.exists()) throw const FormatException('请先导入这本测验资料。');
    final installed = await _current(base);
    if (installed == null) throw const FormatException('请先导入这本测验资料。');
    return installed;
  }

  Future<Directory> _stateDirectory(String packageId) async {
    validateQuizPackageId(packageId);
    final root = await _location();
    return Directory('${root.path}/state/$packageId').create(recursive: true);
  }

  Future<File> _activeFile(String packageId) async =>
      File('${(await _stateDirectory(packageId)).path}/active.json');

  Future<File> _attemptFile(String packageId, String sessionId) async {
    validateQuizSessionId(sessionId);
    final state = await _stateDirectory(packageId);
    final attempts = await Directory('${state.path}/attempts')
        .create(recursive: true);
    return File('${attempts.path}/$sessionId.json');
  }

  Future<QuizSession?> loadActiveSession(String packageId) =>
      _serial(() => _active(packageId));

  Future<QuizSession?> _active(String packageId) async {
    final file = await _activeFile(packageId);
    if (!await file.exists()) return null;
    try {
      final session = QuizSession.fromJson(await _readMap(file, '未完成测试'));
      if (session.packageId != packageId || session.isCompleted) {
        throw const FormatException('未完成测试的资料标识或状态不一致。');
      }
      // A completed archive is authoritative if a crash interrupted cleanup.
      final archived = await _attemptFile(packageId, session.id);
      if (await archived.exists()) {
        try {
          final attempt = await _readAttempt(archived, packageId);
          if (attempt.id == session.id) {
            await file.delete();
            return null;
          }
        } on FormatException {
          // A corrupt completed file does not invalidate the still healthy
          // active snapshot. Preserve only that archive and allow resubmission.
          await _preserveDamaged(archived);
          _warn('一份成绩归档损坏，原文件已保留；未完成题目仍可继续或重新交卷。');
        }
      }
      return session;
    } on FormatException {
      await _preserveDamaged(file);
      _warn('这本资料的未完成测试记录损坏，原文件已保留；已保存成绩不受影响。');
      return null;
    }
  }

  Future<QuizBookState> loadBookState(String packageId) => _serial(() async {
    final directory = await _stateDirectory(packageId);
    final settingsFile = File('${directory.path}/settings.json');
    QuizSettings? settings;
    if (await settingsFile.exists()) {
      try {
        settings = QuizSettings.fromJson(await _readMap(settingsFile, '测验设置'));
      } on FormatException {
        await _preserveDamaged(settingsFile);
        _warn('这本资料的测验设置损坏，已恢复默认设置；成绩记录会保留。');
      }
    }
    final displayFile = File('${directory.path}/display.json');
    var showReadings = true;
    if (await displayFile.exists()) {
      try {
        final display = await _readMap(displayFile, '测验显示设置');
        final value = display['show_readings'];
        if (value is! bool) throw const FormatException('假名显示设置无效。');
        showReadings = value;
      } on FormatException {
        await _preserveDamaged(displayFile);
        _warn('这本资料的显示设置损坏，已恢复默认显示；成绩记录会保留。');
      }
    }
    return QuizBookState(
      lastSettings: settings,
      activeSession: await _active(packageId),
      showReadings: showReadings,
    );
  });

  Future<void> saveShowReadings(String packageId, bool value) =>
      _serial(() async {
        final directory = await _stateDirectory(packageId);
        await _atomicJson(File('${directory.path}/display.json'), {
          'show_readings': value,
        });
      });

  Future<QuizSession> startSession(
    String packageId,
    QuizSettings settings, {
    DateTime? now,
    Random? random,
  }) => _serial(() async {
    settings.validate();
    final clock = now ?? DateTime.now();
    final installed = await _installed(packageId);
    final active = await _active(packageId);
    if (active != null) {
      if (active.isExpired(clock)) {
        await _finish(packageId, active.id, clock);
      } else {
        throw StateError('这本资料已有未完成测试，请继续作答或先交卷。');
      }
    }
    final history = await _attempts(packageId);
    final stats = _statistics(installed.package, history);
    var pool = installed.package.questions
        .where(
          (q) =>
              settings.scope == QuizScope.all ||
              stats.wrongQuestionIds.contains(q.id),
        )
        .toList();
    if (pool.isEmpty) throw const FormatException('目前没有可供测试的错题。');
    if (settings.order == QuizOrder.random) {
      pool.shuffle(random ?? Random.secure());
    } else if (settings.scope == QuizScope.all &&
        stats.nextSequentialIndex > 0) {
      final offset = stats.nextSequentialIndex;
      pool = [...pool.skip(offset), ...pool.take(offset)];
    }
    final questions = pool.take(settings.questionCount).toList(growable: false);
    final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final id = 'quiz-${DateTime.now().microsecondsSinceEpoch}-$entropy';
    final session = QuizSession(
      id: id,
      packageId: packageId,
      packageTitle: installed.package.title,
      contentRevision: installed.package.contentRevision,
      settings: settings,
      questions: List.unmodifiable(questions),
      answers: const {},
      currentIndex: 0,
      startedAt: clock.toUtc(),
      deadlineAt: settings.durationMinutes == 0
          ? null
          : clock.toUtc().add(Duration(minutes: settings.durationMinutes)),
    );
    await _atomicJson(await _activeFile(packageId), session.toJson());
    final state = await _stateDirectory(packageId);
    await _atomicJson(File('${state.path}/settings.json'), settings.toJson());
    return session;
  });

  Future<QuizSession> answer(
    String packageId,
    String sessionId,
    String questionId,
    String choiceId, {
    DateTime? now,
  }) => _serial(() async {
    final session = await _requireActive(packageId, sessionId);
    final clock = now ?? DateTime.now();
    if (session.isExpired(clock)) {
      throw QuizSessionExpiredException(
        await _finish(packageId, sessionId, clock),
      );
    }
    final matching = session.questions.where((q) => q.id == questionId);
    if (matching.isEmpty ||
        !matching.first.choices.any((c) => c.id == choiceId)) {
      throw const FormatException('选项不属于本次测试中的这道题。');
    }
    if (session.settings.feedback == QuizFeedback.immediate &&
        session.answers.containsKey(questionId)) {
      if (session.answers[questionId] == choiceId) return session;
      throw StateError('这道题已核对答案，不能再次修改。');
    }
    final updated = session.copyWith(
      answers: {...session.answers, questionId: choiceId},
    );
    await _atomicJson(await _activeFile(packageId), updated.toJson());
    return updated;
  });

  Future<QuizSession> navigate(
    String packageId,
    String sessionId,
    int index, {
    DateTime? now,
  }) => _serial(() async {
    final session = await _requireActive(packageId, sessionId);
    final clock = now ?? DateTime.now();
    if (session.isExpired(clock)) {
      throw QuizSessionExpiredException(
        await _finish(packageId, sessionId, clock),
      );
    }
    if (index < 0 || index >= session.questions.length) {
      throw RangeError.index(index, session.questions, 'index');
    }
    final updated = session.copyWith(currentIndex: index);
    await _atomicJson(await _activeFile(packageId), updated.toJson());
    return updated;
  });

  Future<QuizSession> _requireActive(String packageId, String sessionId) async {
    validateQuizSessionId(sessionId);
    final current = await _active(packageId);
    if (current == null || current.id != sessionId) {
      throw StateError('这次测试已结束或不存在，请返回资料列表。');
    }
    return current;
  }

  Future<QuizAttempt> finishSession(
    String packageId,
    String sessionId, {
    DateTime? now,
  }) => _serial(() => _finish(packageId, sessionId, now ?? DateTime.now()));

  Future<QuizAttempt> _finish(
    String packageId,
    String sessionId,
    DateTime now,
  ) async {
    final archive = await _attemptFile(packageId, sessionId);
    if (await archive.exists()) {
      try {
        final result = await _readAttempt(archive, packageId);
        final active = await _active(packageId);
        if (active?.id == sessionId) {
          await (await _activeFile(packageId)).delete();
        }
        return result;
      } on FormatException {
        // _active preserves the corrupt archive if its live snapshot is valid.
        // Without that snapshot there is no reliable basis to recompute a score.
        final active = await _active(packageId);
        if (active?.id != sessionId) rethrow;
      }
    }
    final session = await _requireActive(packageId, sessionId);
    final timedOut = session.isExpired(now);
    final ended = timedOut
        ? session.deadlineAt!
        : now.isBefore(session.startedAt)
        ? session.startedAt
        : now.toUtc();
    final result = QuizAttempt(
      session: session.copyWith(endedAt: ended, timedOut: timedOut),
    );
    // Commit the result first. Recovery treats this immutable archive as final,
    // even if the process stops before deleting active.json.
    await _atomicJson(archive, result.session.toJson());
    final file = await _activeFile(packageId);
    if (await file.exists()) await file.delete();
    return result;
  }

  Future<List<QuizAttempt>> attempts(String packageId) =>
      _serial(() => _attempts(packageId));

  Future<QuizAttempt> _readAttempt(File file, String packageId) async {
    final session = QuizSession.fromJson(await _readMap(file, '测试成绩'));
    if (!session.isCompleted ||
        session.packageId != packageId ||
        file.path.split('/').last != '${session.id}.json') {
      throw const FormatException('测试成绩的资料标识或状态无效。');
    }
    return QuizAttempt(session: session);
  }

  Future<List<QuizAttempt>> _attempts(String packageId) async {
    final state = await _stateDirectory(packageId);
    final folder = Directory('${state.path}/attempts');
    if (!await folder.exists()) return [];
    final values = <QuizAttempt>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        values.add(await _readAttempt(entity, packageId));
      } on FormatException {
        _warn('一份测试成绩无法读取，原文件已保留，统计暂不包含该记录。');
      } on FileSystemException {
        _warn('一份测试成绩无法读取，原文件已保留，统计暂不包含该记录。');
      }
    }
    values.sort((a, b) {
      final time = b.session.endedAt!.compareTo(a.session.endedAt!);
      return time == 0 ? b.id.compareTo(a.id) : time;
    });
    return values;
  }

  Future<QuizBookStats> stats(String packageId) => _serial(() async {
    final installed = await _installed(packageId);
    return _statistics(installed.package, await _attempts(packageId));
  });

  QuizBookStats _statistics(QuizPackage package, List<QuizAttempt> history) {
    final questionIds = package.questions.map((q) => q.id).toSet();
    final questionStats = <String, QuizQuestionStats>{};
    final selected = <String>{};
    var totalAnswered = 0,
        totalCorrect = 0,
        totalAssigned = 0,
        nextSequentialIndex = 0;
    for (final attempt in history.reversed) {
      totalAnswered += attempt.answeredCount;
      totalCorrect += attempt.correctCount;
      totalAssigned += attempt.totalCount;
      final session = attempt.session;
      for (final q in session.questions) {
        final answer = session.answers[q.id];
        final correct = answer == q.answerId;
        final previous = questionStats[q.id];
        if (answer != null) selected.add(q.id);
        questionStats[q.id] = QuizQuestionStats(
          questionId: q.id,
          answeredCount:
              (previous?.answeredCount ?? 0) + (answer == null ? 0 : 1),
          correctCount: (previous?.correctCount ?? 0) + (correct ? 1 : 0),
          wrongCount: (previous?.wrongCount ?? 0) + (correct ? 0 : 1),
          latestCorrect: correct,
          lastAttemptedAt: session.endedAt!,
        );
      }
      if (session.settings.scope == QuizScope.all &&
          session.settings.order == QuizOrder.sequential) {
        final last = package.questions.indexWhere(
          (q) => q.id == session.questions.last.id,
        );
        if (last >= 0) {
          nextSequentialIndex = (last + 1) % package.questions.length;
        }
      }
    }
    final wrong = questionStats.entries
        .where(
          (entry) =>
              questionIds.contains(entry.key) && !entry.value.latestCorrect,
        )
        .map((entry) => entry.key)
        .toSet();
    return QuizBookStats(
      totalQuestions: package.questions.length,
      uniqueAnsweredCount: selected.intersection(questionIds).length,
      uniqueTestedCount: questionStats.keys.where(questionIds.contains).length,
      masteredCount: questionStats.entries
          .where(
            (entry) =>
                questionIds.contains(entry.key) && entry.value.latestCorrect,
          )
          .length,
      wrongCount: wrong.length,
      attemptCount: history.length,
      totalAnswered: totalAnswered,
      totalAssigned: totalAssigned,
      totalCorrect: totalCorrect,
      wrongQuestionIds: Set.unmodifiable(wrong),
      questionStats: Map.unmodifiable(questionStats),
      nextSequentialIndex: nextSequentialIndex,
    );
  }

  Future<Object?> _readJson(File file, {int max = maxStateBytes}) async {
    if (!await file.exists()) {
      throw FormatException('缺少文件 ${file.path.split('/').last}。');
    }
    if (await file.length() > max) throw const FormatException('JSON 记录过大。');
    return jsonDecode(utf8.decode(await file.readAsBytes()));
  }

  Future<Map<String, dynamic>> _readMap(
    File file,
    String label, {
    int max = maxStateBytes,
  }) async {
    final value = await _readJson(file, max: max);
    if (value is! Map<String, dynamic>) {
      throw FormatException('$label 必须为 JSON 对象。');
    }
    return value;
  }

  Future<void> _atomicJson(File file, Object value) async {
    final text = jsonEncode(value);
    if (utf8.encode(text).length > maxStateBytes) {
      throw const FormatException('本机测试记录过大，无法保存。');
    }
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

  Future<void> _preserveDamaged(File file) async {
    if (await file.exists()) {
      await file.rename(
        '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
  }

  void _warn(String message) {
    if (!_libraryWarnings.contains(message)) _libraryWarnings.add(message);
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
