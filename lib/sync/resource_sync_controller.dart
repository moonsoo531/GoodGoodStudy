import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../quiz/quiz_models.dart';
import '../quiz/quiz_store.dart';
import '../study/study_models.dart';
import '../study/study_store.dart';
import 'icloud_transport.dart';
import 'sync_record.dart';

Future<void> _encodePackage((String, List<String>, String) request) async {
  final encoder = ZipFileEncoder();
  encoder.create(request.$3);
  try {
    for (final relative in request.$2) {
      validateStudyRelativePath(relative);
      final source = File('${request.$1}/$relative');
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Unsupported local package file');
      }
      await encoder.addFile(source, relative);
    }
  } finally {
    await encoder.close();
  }
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.packageId,
    required this.title,
    required this.kind,
    this.paths = const [],
  });
  final String id, packageId, title, kind;
  final List<String> paths;
  bool get canUseRemote => kind == 'studyProgress';
}

class _Cancelled implements Exception {}

/// Local stores remain authoritative and usable without iCloud. Cloud objects
/// are immutable and content addressed; no deletion propagates between devices.
class ResourceSyncController extends ChangeNotifier
    with WidgetsBindingObserver {
  ResourceSyncController({
    required this.study,
    required this.quiz,
    required this.canApplyRemote,
    ICloudTransport? transport,
  }) : _transport = transport ?? ICloudTransport();

  final StudyStore study;
  final QuizStore quiz;
  final bool Function() canApplyRemote;
  final ICloudTransport _transport;
  late Directory _root;
  Directory? _accountRoot;
  bool _enabled = false, _disposed = false, _busy = false;
  bool _changingSettings = false;
  bool _pendingRemote = false, _accountChanged = false;
  String _availability = 'unchecked', _phase = 'off';
  String? _boundAccount, _device, _lastError;
  DateTime? _lastCheckedAt;
  int _epoch = 0, _queuedUploads = 0, _pendingDownloads = 0;
  Timer? _timer, _debounce;
  Future<void>? _running;
  Future<void> _saves = Future.value();
  final Map<String, SyncRecord> _records = {};
  final Map<String, List<String>> _tips = {};
  final Set<String> _ignored = {};
  final Map<String, bool> _decisions = {};
  final Map<String, SyncConflict> _conflicts = {};
  final Map<String, String> _localPackageHashes = {};
  final Map<String, int> _localPackageVersions = {};
  final Map<String, String> _localProgressHashes = {};

  bool get enabled => _enabled;
  bool get busy => _busy || _changingSettings;
  bool get pendingRemote => _pendingRemote;
  bool get accountChanged => _accountChanged;
  bool get available => _availability == 'available';
  String get availability => _availability;
  String get phase => _phase;
  String? get lastError => _lastError;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  int get queuedUploads => _queuedUploads;
  int get pendingDownloads => _pendingDownloads;
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts.values);

  Future<void> initialize() async {
    try {
      await _initialize();
    } catch (_) {
      _enabled = false;
      _availability = 'unavailable';
      _phase = 'error';
      _lastError = 'invalidLocalSettings';
      _notify();
    }
  }

  Future<void> _initialize() async {
    _root = Directory(
      '${(await getApplicationSupportDirectory()).path}/cloud-sync',
    );
    await _root.create(recursive: true);
    final preferenceFile = File('${_root.path}/preferences.json');
    Map<String, dynamic> prefs;
    try {
      prefs = await _readMap(preferenceFile, 16384);
    } catch (_) {
      if (await preferenceFile.exists()) {
        await preferenceFile.rename(
          '${preferenceFile.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      prefs = {};
      _lastError = 'invalidLocalSettings';
    }
    _enabled = prefs['enabled'] == true;
    final savedAccount = prefs['account'];
    _boundAccount =
        savedAccount is String &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(savedAccount)
        ? savedAccount
        : null;
    _device = prefs['device'] is String ? prefs['device'] as String : null;
    if (_device == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(_device!)) {
      final random = Random.secure();
      _device = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    _transport.onChanged = (event) {
      if (event == 'accountChanged') {
        _epoch++;
        _availability = 'unchecked';
      }
      _schedule();
    };
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _schedule());
    _schedule();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    if (_disposed || _debounce?.isActive == true) return;
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(synchronize());
    });
  }

  /// Called only after a successful local atomic commit. Never waits for iCloud.
  void localChanged() => _schedule();
  void navigationChanged() {
    if (_enabled && canApplyRemote()) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
    if (_enabled && state == AppLifecycleState.inactive) {
      unawaited(synchronize());
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || _changingSettings) return;
    _changingSettings = true;
    _epoch++;
    _enabled = false;
    _lastError = null;
    _notify();
    try {
      // Drain the old account's operation before replacing any account paths.
      if (_running != null) await _running;
      if (!value) {
        _phase = 'off';
        await _savePreferences();
        await _transport.stop();
        return;
      }
      final status = await _transport.call('status');
      _availability = _reason(status);
      final account = status['accountID'];
      if (account is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(account)) {
        if (_boundAccount != null &&
            _boundAccount != account &&
            !_accountChanged) {
          _accountChanged = true;
          _phase = 'off';
          await _savePreferences();
          await _transport.stop();
          return;
        }
        _boundAccount = account;
        _accountChanged = false;
        await _loadAccount(account);
      }
      _enabled = true;
      await _savePreferences();
    } catch (_) {
      _lastError = 'syncFailed';
      _phase = 'error';
    } finally {
      _changingSettings = false;
      _notify();
    }
    if (_enabled) await synchronize();
  }

  Future<void> synchronize() {
    if (_disposed || _changingSettings) return Future.value();
    if (_running != null) return _running!;
    final future = _synchronize();
    _running = future.whenComplete(() => _running = null);
    return _running!;
  }

  void _check(int epoch) {
    if (_disposed || !_enabled || epoch != _epoch) throw _Cancelled();
  }

  Future<void> _synchronize() async {
    final epoch = _epoch;
    _busy = true;
    _lastError = null;
    _phase = _enabled ? 'checking' : 'off';
    _notify();
    try {
      final status = await _transport.call('status');
      _availability = _reason(status);
      final account = status['accountID'];
      if (_boundAccount != null &&
          account is String &&
          account != _boundAccount) {
        _enabled = false;
        _accountChanged = true;
        _epoch++;
        _phase = 'off';
        await _savePreferences();
        await _transport.stop();
        return;
      }
      if (!_enabled || !available) {
        _phase = _enabled ? 'waiting' : 'off';
        return;
      }
      _check(epoch);
      if (account is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(account)) {
        throw const FormatException('Missing local account identity');
      }
      _boundAccount ??= account;
      await _loadAccount(account);
      await _savePreferences();
      await _transport.call('start', {'expectedAccountID': _boundAccount});
      _check(epoch);
      final listing = await _transport.call('list', {
        'expectedAccountID': _boundAccount,
      });
      _check(epoch);
      if (listing['available'] == false) {
        _availability = _reason(listing);
        _phase = 'waiting';
        return;
      }
      if (listing['gathering'] == true) {
        _phase = 'waiting';
        return;
      }
      final files = <String, Map<String, dynamic>>{};
      for (final item in listing['files'] as List? ?? const []) {
        if (item is! Map) continue;
        final file = Map<String, dynamic>.from(item);
        final name = file['name'];
        if (name is String && syncFilePattern.hasMatch(name)) {
          files[name] = file;
        }
      }
      _pendingDownloads = 0;
      _phase = 'downloading';
      _notify();
      await _receiveMetadata(files, epoch);
      _check(epoch);
      // Freeze the current local state before considering incoming branches.
      await _publishLocal(epoch);
      await _prefetchPackages(epoch);
      if (canApplyRemote()) {
        await _applyRemote(epoch);
      } else {
        _pendingRemote = _hasIncoming();
      }
      _check(epoch);
      _phase = 'uploading';
      _notify();
      await _uploadOutbox(files, epoch);
      await _saveAccount();
      _lastCheckedAt = DateTime.now();
      _phase = _lastError != null
          ? 'error'
          : _conflicts.isNotEmpty
          ? 'conflict'
          : _queuedUploads > 0 || _pendingDownloads > 0 || _pendingRemote
          ? 'waiting'
          : 'ready';
    } on _Cancelled {
      _phase = _enabled ? 'waiting' : 'off';
    } catch (_) {
      _lastError = 'syncFailed';
      _phase = _enabled ? 'error' : 'off';
    } finally {
      _busy = false;
      _notify();
    }
  }

  String _reason(Map<String, dynamic> status) {
    if (status['available'] == true) return 'available';
    if (status['supported'] == false) return 'unsupported';
    if (status['configured'] == false) return 'notConfigured';
    return status['reason'] == 'notSignedIn' ? 'notSignedIn' : 'unavailable';
  }

  Future<void> _loadAccount(String account) async {
    final directory = Directory('${_root.path}/accounts/$account');
    if (_accountRoot?.path == directory.path) return;
    await directory.create(recursive: true);
    for (final child in ['records', 'outbox', 'blobs', 'recovery']) {
      await Directory('${directory.path}/$child').create(recursive: true);
    }
    _accountRoot = directory;
    _records.clear();
    _tips.clear();
    _ignored.clear();
    _decisions.clear();
    _conflicts.clear();
    final stateFile = File('${directory.path}/state.json');
    Map<String, dynamic> state;
    try {
      state = await _readMap(stateFile, 4 * 1024 * 1024);
    } catch (_) {
      if (await stateFile.exists()) {
        await stateFile.rename(
          '${stateFile.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      state = {};
      _lastError = 'invalidLocalSettings';
    }
    final tips = state['tips'];
    if (tips is Map) {
      for (final entry in tips.entries) {
        if (entry.key is String &&
            entry.value is List &&
            syncPackagePattern.hasMatch(entry.key as String)) {
          _tips[entry.key as String] = (entry.value as List)
              .whereType<String>()
              .where(syncFilePattern.hasMatch)
              .toList();
        }
      }
    }
    _ignored.addAll(
      (state['ignored'] as List? ?? const []).whereType<String>(),
    );
    final decisions = state['decisions'];
    if (decisions is Map) {
      for (final entry in decisions.entries) {
        if (entry.key is String && entry.value is bool) {
          _decisions[entry.key as String] = entry.value as bool;
        }
      }
    }
    final journalFiles = <File>[];
    for (final folder in ['records', 'outbox']) {
      await for (final file in Directory(
        '${directory.path}/$folder',
      ).list(followLinks: false)) {
        if (file is File && file.path.endsWith('.ggsync')) {
          journalFiles.add(file);
        }
      }
    }
    for (final file in journalFiles) {
      try {
        if (await file.length() > 9 * 1024 * 1024) continue;
        final record = SyncRecord.parse(
          file.uri.pathSegments.last,
          await file.readAsString(),
        );
        _records[record.name] = record;
        final cached = File('${directory.path}/records/${record.name}');
        if (!await cached.exists()) {
          await _atomic(cached, canonicalJson(record.data));
        }
      } catch (_) {
        _lastError = 'invalidCloudData';
      }
    }
  }

  Future<void> _receiveMetadata(
    Map<String, Map<String, dynamic>> files,
    int epoch,
  ) async {
    for (final entry in files.entries) {
      _check(epoch);
      if (!entry.key.endsWith('.ggsync')) continue;
      if ((entry.value['bytes'] as num? ?? 0) > 9 * 1024 * 1024 ||
          entry.value['error'] != null) {
        _lastError = 'invalidCloudData';
        continue;
      }
      if (_records.containsKey(entry.key)) continue;
      final local = await _download(entry.key, epoch);
      if (local == null) continue;
      try {
        if (await local.length() > 9 * 1024 * 1024) {
          throw const FormatException('Record too large');
        }
        final text = await local.readAsString();
        final record = SyncRecord.parse(entry.key, text);
        await _atomic(File('${_accountRoot!.path}/records/${entry.key}'), text);
        _records[record.name] = record;
      } catch (_) {
        _lastError = 'invalidCloudData';
      } finally {
        await _transport.call('release', {'path': local.path});
      }
    }
  }

  Future<File?> _download(String name, int epoch) async {
    _check(epoch);
    final result = await _transport.call('download', {
      'name': name,
      'expectedAccountID': _boundAccount,
    });
    _check(epoch);
    if (result['ready'] != true || result['path'] is! String) {
      _pendingDownloads++;
      return null;
    }
    return File(result['path'] as String);
  }

  Future<void> _publishLocal(int epoch) async {
    final snapshot = await study.captureSyncSnapshot();
    final books = await quiz.packages();
    _localPackageHashes.clear();
    _localPackageVersions.clear();
    _localProgressHashes.clear();
    for (final book in snapshot.packages) {
      _check(epoch);
      _localPackageHashes['studyPackage/${book.package.packageId}'] = jsonHash(
        book.package.toJson(),
      );
      _localPackageVersions['studyPackage/${book.package.packageId}'] =
          book.package.contentRevision;
      await _publishPackage(
        'studyPackage',
        book.package.packageId,
        book.package.title,
        book.package.contentRevision,
        book.package.toJson(),
        book.directory,
        [
          'manifest.json',
          'lessons.json',
          'entries.json',
          ...book.package.media.map((m) => m.path),
        ],
        epoch,
      );
    }
    for (final book in books) {
      _check(epoch);
      _localPackageHashes['quizPackage/${book.package.packageId}'] = jsonHash(
        book.package.toJson(),
      );
      _localPackageVersions['quizPackage/${book.package.packageId}'] =
          book.package.contentRevision;
      await _publishPackage(
        'quizPackage',
        book.package.packageId,
        book.package.title,
        book.package.contentRevision,
        book.package.toJson(),
        book.directory,
        ['manifest.json', 'questions.json'],
        epoch,
      );
    }
    for (final entry in snapshot.progress.entries) {
      _check(epoch);
      final fingerprint = jsonHash(entry.value);
      _localProgressHashes[entry.key] = fingerprint;
      if (entry.value.isEmpty) continue;
      final tips = _tips[entry.key] ?? const <String>[];
      if (tips.any((name) => _records[name]?.fingerprint == fingerprint)) {
        continue;
      }
      final title =
          snapshot.packages
              .where((p) => p.package.packageId == entry.key)
              .firstOrNull
              ?.package
              .title ??
          entry.key;
      await _publishProgress(
        entry.key,
        title,
        entry.value,
        tips,
        resourceRevision: _localPackageVersions['studyPackage/${entry.key}']!,
        resourceFingerprint: _localPackageHashes['studyPackage/${entry.key}']!,
      );
    }
  }

  Future<void> _publishPackage(
    String kind,
    String id,
    String title,
    int revision,
    Map<String, dynamic> content,
    Directory directory,
    List<String> paths,
    int epoch,
  ) async {
    final fingerprint = jsonHash(content);
    if (_records.values.any(
      (r) =>
          r.kind == kind && r.packageId == id && r.fingerprint == fingerprint,
    )) {
      return;
    }
    final temporary = File('${_accountRoot!.path}/outbox/packing.tmp');
    final request = (
      directory.path,
      List<String>.of(paths)..sort(),
      temporary.path,
    );
    await Isolate.run(() => _encodePackage(request));
    _check(epoch);
    final max = kind == 'studyPackage'
        ? StudyStore.maxZipBytes
        : QuizStore.maxZipBytes;
    if (await temporary.length() > max) {
      throw const FormatException('Package exceeds sync limit');
    }
    final digest = (await sha256.bind(temporary.openRead()).first).toString();
    final blob = 'b_$digest.ggpack';
    await temporary.rename('${temporary.parent.path}/$blob');
    await _writeRecord({
      'schema': 1,
      'kind': kind,
      'package_id': id,
      'title': title,
      'revision': revision,
      'fingerprint': fingerprint,
      'blob': blob,
      'device': _device,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<SyncRecord> _publishProgress(
    String id,
    String title,
    Map<String, dynamic> progress,
    List<String> parents, {
    required int resourceRevision,
    required String resourceFingerprint,
  }) async {
    final record = await _writeRecord({
      'schema': 1,
      'kind': 'studyProgress',
      'package_id': id,
      'title': title,
      'fingerprint': jsonHash(progress),
      'parents': parents.toSet().toList()..sort(),
      'progress': progress,
      'resource_revision': resourceRevision,
      'resource_fingerprint': resourceFingerprint,
      'device': _device,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _tips[id] = [record.name];
    await _saveAccount();
    return record;
  }

  Future<SyncRecord> _writeRecord(Map<String, dynamic> data) async {
    final name = 'm_${jsonHash(data)}.ggsync';
    final text = canonicalJson(data);
    final record = SyncRecord.parse(name, text);
    await _atomic(File('${_accountRoot!.path}/outbox/$name'), text);
    await _atomic(File('${_accountRoot!.path}/records/$name'), text);
    _records[name] = record;
    return record;
  }

  Future<void> _uploadOutbox(
    Map<String, Map<String, dynamic>> files,
    int epoch,
  ) async {
    final outbox = Directory('${_accountRoot!.path}/outbox');
    // Repair the durable local-commit / upload-marker crash window.
    for (final record in _records.values) {
      if (record.data['device'] == _device && !files.containsKey(record.name)) {
        final pending = File('${outbox.path}/${record.name}');
        if (!await pending.exists()) {
          await _atomic(pending, canonicalJson(record.data));
        }
      }
    }
    final pending = await outbox
        .list(followLinks: false)
        .where(
          (f) => f is File && syncFilePattern.hasMatch(f.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    pending.sort(
      (a, b) => a.path.compareTo(b.path),
    ); // b_ blobs before m_ metadata.
    _queuedUploads = 0;
    for (final file in pending) {
      _check(epoch);
      final name = file.uri.pathSegments.last;
      if (files[name]?['uploaded'] == true) {
        await file.delete();
        continue;
      }
      await _transport.call('upload', {
        'name': name,
        'sourcePath': file.path,
        'expectedAccountID': _boundAccount,
      });
      _check(epoch);
      _queuedUploads++;
    }
  }

  bool _hasIncoming() {
    final progress = <String, List<SyncRecord>>{};
    for (final record in _records.values) {
      if (_ignored.contains(record.name)) continue;
      if (record.kind == 'studyProgress') {
        progress.putIfAbsent(record.packageId, () => []).add(record);
      } else {
        final key = '${record.kind}/${record.packageId}';
        if (record.fingerprint != _localPackageHashes[key] &&
            record.revision >= (_localPackageVersions[key] ?? 0)) {
          return true;
        }
      }
    }
    return progress.entries.any((entry) {
      final heads = _heads(entry.value);
      return heads.length > 1 ||
          heads.any((r) => r.fingerprint != _localProgressHashes[entry.key]);
    });
  }

  Future<void> _prefetchPackages(int epoch) async {
    for (final record in _resourceHeads()) {
      if (record.kind == 'studyProgress' || _ignored.contains(record.name)) {
        continue;
      }
      final key = '${record.kind}/${record.packageId}';
      if (record.fingerprint == _localPackageHashes[key] ||
          record.revision <= (_localPackageVersions[key] ?? 0)) {
        continue;
      }
      try {
        await _blob(record, epoch, localOnly: false);
      } on _Cancelled {
        rethrow;
      } catch (_) {
        _lastError = 'invalidCloudData';
      }
    }
  }

  List<SyncRecord> _resourceHeads() {
    final groups = <String, List<SyncRecord>>{};
    for (final record in _records.values) {
      if (record.kind == 'studyProgress') continue;
      groups
          .putIfAbsent('${record.kind}/${record.packageId}', () => [])
          .add(record);
    }
    return [
      for (final group in groups.values)
        ...(() {
          final revision = group.map((r) => r.revision).reduce(max);
          final unique = <String, SyncRecord>{};
          for (final record in group.where((r) => r.revision == revision)) {
            unique.putIfAbsent(record.fingerprint, () => record);
          }
          return unique.values;
        })(),
    ];
  }

  /// Runs while the old module is unmounted. Never waits for iCloud/network;
  /// only already-downloaded blobs and metadata are considered here.
  Future<void> applyPending() {
    if (!_enabled ||
        busy ||
        _running != null ||
        _accountRoot == null ||
        !available ||
        !canApplyRemote()) {
      return Future.value();
    }
    final future = _applyPending();
    _running = future.whenComplete(() => _running = null);
    return _running!;
  }

  Future<void> _applyPending() async {
    _busy = true;
    final epoch = _epoch;
    try {
      await _publishLocal(epoch);
      await _applyRemote(epoch, localOnly: true);
      await _saveAccount();
      _phase = _lastError != null
          ? 'error'
          : _conflicts.isNotEmpty
          ? 'conflict'
          : 'waiting';
    } on _Cancelled {
      // A settings/account change cancels this pass without changing local data.
    } catch (_) {
      _lastError = 'syncFailed';
    } finally {
      _busy = false;
      _notify();
      _schedule();
    }
  }

  Future<void> _applyRemote(int epoch, {bool localOnly = false}) async {
    if (!canApplyRemote()) {
      _pendingRemote = true;
      return;
    }
    _pendingRemote = false;
    _conflicts.clear();
    final packages = _resourceHeads();
    for (final record in packages) {
      _check(epoch);
      try {
        if (_ignored.contains(record.name)) continue;
        final studyBooks = record.kind == 'studyPackage'
            ? (await study.captureSyncSnapshot()).packages
            : const <InstalledStudyPackage>[];
        final quizBooks = record.kind == 'quizPackage'
            ? await quiz.packages()
            : const <InstalledQuizPackage>[];
        final ownStudy = studyBooks
            .where((p) => p.package.packageId == record.packageId)
            .firstOrNull;
        final ownQuiz = quizBooks
            .where((p) => p.package.packageId == record.packageId)
            .firstOrNull;
        final ownRevision =
            ownStudy?.package.contentRevision ??
            ownQuiz?.package.contentRevision ??
            0;
        final ownHash = ownStudy != null
            ? jsonHash(ownStudy.package.toJson())
            : ownQuiz != null
            ? jsonHash(ownQuiz.package.toJson())
            : null;
        final alternatives = packages
            .where(
              (r) =>
                  r.kind == record.kind &&
                  r.packageId == record.packageId &&
                  !_ignored.contains(r.name),
            )
            .toList();
        if (alternatives.length > 1 &&
            !alternatives.any((r) => r.fingerprint == ownHash)) {
          _conflicts[record.name] = SyncConflict(
            id: record.name,
            packageId: record.packageId,
            title: record.title,
            kind: record.kind,
          );
          continue;
        }
        if (ownHash == record.fingerprint || ownRevision > record.revision) {
          continue;
        }
        if (ownRevision == record.revision) {
          _conflicts[record.name] = SyncConflict(
            id: record.name,
            packageId: record.packageId,
            title: record.title,
            kind: record.kind,
          );
          continue;
        }
        final blob = await _blob(record, epoch, localOnly: localOnly);
        if (blob == null) {
          _pendingRemote = true;
          continue;
        }
        await _validatePackage(blob, record);
        _check(epoch);
        if (!canApplyRemote()) {
          _pendingRemote = true;
          return;
        }
        if (record.kind == 'studyPackage') {
          await study.importZip(blob);
        } else {
          await quiz.importZip(blob);
        }
        await blob.delete();
      } on _Cancelled {
        rethrow;
      } catch (_) {
        _lastError = 'invalidCloudData';
      }
    }
    final progressByPackage = <String, List<SyncRecord>>{};
    for (final record in _records.values) {
      if (record.kind == 'studyProgress') {
        progressByPackage.putIfAbsent(record.packageId, () => []).add(record);
      }
    }
    for (final entry in progressByPackage.entries) {
      _check(epoch);
      try {
        await _applyProgress(entry.key, entry.value, epoch);
      } on _Cancelled {
        rethrow;
      } catch (_) {
        _lastError = 'invalidCloudData';
      }
    }
  }

  Future<File?> _blob(
    SyncRecord record,
    int epoch, {
    required bool localOnly,
  }) async {
    final name = record.blob!;
    final local = File('${_accountRoot!.path}/blobs/$name');
    final max = record.kind == 'studyPackage'
        ? StudyStore.maxZipBytes
        : QuizStore.maxZipBytes;
    Future<bool> valid(File file) async =>
        await file.length() <= max &&
        (await sha256.bind(file.openRead()).first).toString() ==
            name.substring(2, 66);
    if (await local.exists()) {
      if (await valid(local)) return local;
      await local.rename(
        '${local.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    if (localOnly) return null;
    final received = await _download(name, epoch);
    if (received == null) return null;
    try {
      if (!await valid(received)) {
        throw const FormatException('Invalid resource checksum');
      }
      final temporary = File('${local.path}.tmp');
      await received.copy(temporary.path);
      _check(epoch);
      await temporary.rename(local.path);
      return local;
    } finally {
      await _transport.call('release', {'path': received.path});
    }
  }

  Future<void> _validatePackage(File file, SyncRecord record) async {
    final stream = InputFileStream(file.path);
    try {
      final zip = ZipDirectory()..read(stream);
      if (zip.fileHeaders.length > StudyStore.maxZipEntries) {
        throw const FormatException('Too many package files');
      }
      Object? read(String name) {
        final headers = zip.fileHeaders
            .where((h) => h.filename == name)
            .toList();
        if (headers.length != 1 ||
            headers.single.uncompressedSize > StudyStore.maxJsonBytes) {
          throw const FormatException('Invalid package JSON');
        }
        return jsonDecode(
          utf8.decode(headers.single.file!.getStream().toUint8List()),
        );
      }

      final manifest = Map<String, dynamic>.from(read('manifest.json') as Map);
      final content = record.kind == 'studyPackage'
          ? StudyPackage.fromJson(
              manifest,
              lessons: read('lessons.json') as List,
              entries: read('entries.json') as List,
            ).toJson()
          : QuizPackage.fromJson(
              manifest,
              questions: read('questions.json') as List,
            ).toJson();
      if (content['package_id'] != record.packageId ||
          content['content_revision'] != record.revision ||
          jsonHash(content) != record.fingerprint) {
        throw const FormatException('Resource identity differs from metadata');
      }
    } finally {
      await stream.close();
    }
  }

  List<SyncRecord> _heads(List<SyncRecord> records) {
    final parents = records.expand((r) => r.parents).toSet();
    return records.where((r) => !parents.contains(r.name)).toList();
  }

  Set<String> _ancestors(SyncRecord record) {
    final found = <String>{};
    final queue = <String>[record.name];
    while (queue.isNotEmpty && found.length < 20000) {
      final name = queue.removeLast();
      if (found.add(name)) queue.addAll(_records[name]?.parents ?? const []);
    }
    return found;
  }

  Future<void> _applyProgress(
    String id,
    List<SyncRecord> records,
    int epoch,
  ) async {
    final snapshot = await study.captureSyncSnapshot();
    final book = snapshot.packages
        .where((p) => p.package.packageId == id)
        .firstOrNull;
    if (book == null) {
      _pendingRemote = true;
      return;
    }
    final local = snapshot.progress[id] ?? <String, dynamic>{};
    // An earlier upload snapshot may predate a note saved while the module was
    // still active. Register the current value before it can be overwritten.
    final tips = _tips[id] ?? const <String>[];
    if (local.isNotEmpty &&
        !tips.any((name) => _records[name]?.fingerprint == jsonHash(local))) {
      _check(epoch);
      await _publishProgress(
        id,
        book.package.title,
        local,
        tips,
        resourceRevision: book.package.contentRevision,
        resourceFingerprint: jsonHash(book.package.toJson()),
      );
      records = _records.values
          .where((r) => r.kind == 'studyProgress' && r.packageId == id)
          .toList();
    }
    // A metadata query may discover descendants before their parent JSON is
    // downloaded. Defer until the causal graph is complete for this package.
    for (final record in records) {
      for (final parent in record.parents) {
        final value = _records[parent];
        if (value == null) {
          _pendingRemote = true;
          return;
        }
        if (value.kind != 'studyProgress' || value.packageId != id) {
          _lastError = 'invalidCloudData';
          return;
        }
      }
    }
    final heads = _heads(records)
      ..sort((a, b) => a.created.compareTo(b.created));
    if (heads.isEmpty) return;
    final resourceHash = jsonHash(book.package.toJson());
    if (heads.any(
      (r) =>
          (r.data['resource_revision'] as int) > book.package.contentRevision ||
          ((r.data['resource_revision'] as int) ==
                  book.package.contentRevision &&
              r.data['resource_fingerprint'] != resourceHash),
    )) {
      _pendingRemote = true;
      return;
    }
    final headNames = heads.map((r) => r.name).toList()..sort();
    if (heads.length == 1) {
      final head = heads.single;
      if (jsonHash(local) != head.fingerprint) {
        _check(epoch);
        if (!canApplyRemote() ||
            !await study.applySyncedProgress(
              id,
              expectedLocal: local,
              progress: head.progress,
            )) {
          _pendingRemote = true;
          return;
        }
      }
      _tips[id] = [head.name];
      return;
    }
    final conflictId = 'p_${jsonHash(headNames)}';
    Map<String, dynamic> merged = local;
    final common = _ancestors(heads.first);
    for (final head in heads.skip(1)) {
      common.retainAll(_ancestors(head));
    }
    final candidates =
        common
            .map((n) => _records[n])
            .whereType<SyncRecord>()
            .where((r) => r.kind == 'studyProgress' && r.packageId == id)
            .toList()
          ..sort(
            (a, b) => _ancestors(a).length.compareTo(_ancestors(b).length),
          );
    final base = candidates.lastOrNull?.progress ?? <String, dynamic>{};
    final paths = <String>{};
    for (final head in heads) {
      if (jsonHash(merged) == head.fingerprint) continue;
      final result = mergeStudyProgress(base, merged, head.progress);
      merged = result.progress;
      paths.addAll(result.conflicts);
    }
    final decision = _decisions[conflictId];
    if (paths.isNotEmpty && decision == null) {
      _conflicts[conflictId] = SyncConflict(
        id: conflictId,
        packageId: id,
        title: book.package.title,
        kind: 'studyProgress',
        paths: paths.toList(),
      );
      return;
    }
    if (decision != null) {
      // Preserve the exact local and remote alternatives before applying a choice.
      await _atomic(
        File('${_accountRoot!.path}/recovery/${conflictId}_local.json'),
        canonicalJson(local),
      );
      for (final head in heads) {
        await _atomic(
          File(
            '${_accountRoot!.path}/recovery/${conflictId}_${head.name}.json',
          ),
          canonicalJson(head.progress),
        );
      }
      final remote =
          heads.where((h) => h.data['device'] != _device).lastOrNull ??
          heads.last;
      merged = decision ? remote.progress : local;
    }
    _check(epoch);
    if (!canApplyRemote() ||
        !await study.applySyncedProgress(
          id,
          expectedLocal: local,
          progress: merged,
        )) {
      _pendingRemote = true;
      return;
    }
    await _publishProgress(
      id,
      book.package.title,
      merged,
      headNames,
      resourceRevision: book.package.contentRevision,
      resourceFingerprint: resourceHash,
    );
    _decisions.remove(conflictId);
  }

  Future<void> resolveConflict(String id, {required bool useRemote}) async {
    final conflict = _conflicts[id];
    if (conflict == null || (useRemote && !conflict.canUseRemote)) return;
    if (conflict.canUseRemote) {
      _decisions[id] = useRemote;
      _pendingRemote = true;
    } else {
      _ignored.add(
        id,
      ); // The cloud artifact and the local resource both remain.
      _conflicts.remove(id);
    }
    await _saveAccount();
    if (canApplyRemote()) await applyPending();
    _notify();
    _schedule();
  }

  Future<Map<String, dynamic>> _readMap(File file, int max) async {
    if (!await file.exists()) return {};
    if (await file.length() > max) {
      throw const FormatException('Local sync settings too large');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid local sync settings');
    }
    return value;
  }

  Future<void> _savePreferences() => _atomic(
    File('${_root.path}/preferences.json'),
    canonicalJson({
      'schema': 1,
      'enabled': _enabled,
      'account': _boundAccount,
      'device': _device,
    }),
  );

  Future<void> _saveAccount() async {
    if (_accountRoot == null) return;
    await _atomic(
      File('${_accountRoot!.path}/state.json'),
      canonicalJson({
        'schema': 1,
        'tips': _tips,
        'ignored': _ignored.toList(),
        'decisions': _decisions,
      }),
    );
  }

  Future<void> _atomic(File file, String value) {
    final next = _saves.then((_) async {
      final temporary = File('${file.path}.tmp');
      await temporary.parent.create(recursive: true);
      try {
        await temporary.writeAsString(value, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _saves = next.catchError((Object _) {});
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _transport.dispose();
    super.dispose();
  }
}

class ResourceSyncScope extends InheritedNotifier<ResourceSyncController> {
  const ResourceSyncScope({
    super.key,
    required ResourceSyncController controller,
    required super.child,
  }) : super(notifier: controller);
  static ResourceSyncController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResourceSyncScope>()?.notifier;
}
