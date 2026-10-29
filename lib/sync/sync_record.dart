import 'dart:convert';

import 'package:crypto/crypto.dart';

Object? canonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalValue(value[key])};
  }
  if (value is List) return value.map(canonicalValue).toList();
  return value;
}

String canonicalJson(Object? value) => jsonEncode(canonicalValue(value));
String jsonHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

final syncFilePattern = RegExp(r'^[mb]_[a-f0-9]{64}\.(?:ggsync|ggpack)$');
final syncPackagePattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$');

class SyncRecord {
  SyncRecord(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
  String get kind => data['kind'] as String;
  String get packageId => data['package_id'] as String;
  String get title => data['title'] as String;
  String get fingerprint => data['fingerprint'] as String;
  int get revision => data['revision'] as int? ?? 0;
  String? get blob => data['blob'] as String?;
  List<String> get parents =>
      (data['parents'] as List? ?? const []).cast<String>();
  Map<String, dynamic> get progress =>
      Map<String, dynamic>.from(data['progress'] as Map);
  int get created => data['created_ms'] as int;

  static SyncRecord parse(String name, String content) {
    if (!RegExp(r'^m_[a-f0-9]{64}\.ggsync$').hasMatch(name) ||
        utf8.encode(content).length > 9 * 1024 * 1024) {
      throw const FormatException('Invalid sync record');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        name != 'm_${jsonHash(decoded)}.ggsync' ||
        decoded['schema'] != 1 ||
        !const [
          'studyPackage',
          'quizPackage',
          'studyProgress',
        ].contains(decoded['kind']) ||
        decoded['package_id'] is! String ||
        !syncPackagePattern.hasMatch(decoded['package_id'] as String) ||
        decoded['title'] is! String ||
        (decoded['title'] as String).length > 100000 ||
        decoded['created_ms'] is! int ||
        decoded['device'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(decoded['device'] as String) ||
        decoded['fingerprint'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(decoded['fingerprint'] as String)) {
      throw const FormatException('Invalid sync metadata');
    }
    final record = SyncRecord(name, decoded);
    if (record.kind == 'studyProgress') {
      final parents = decoded['parents'];
      if (decoded['progress'] is! Map<String, dynamic> ||
          decoded['resource_revision'] is! int ||
          (decoded['resource_revision'] as int) < 1 ||
          decoded['resource_fingerprint'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(decoded['resource_fingerprint'] as String) ||
          jsonHash(decoded['progress']) != record.fingerprint ||
          parents is! List ||
          parents.length > 1024 ||
          parents.any(
            (p) =>
                p is! String ||
                !RegExp(r'^m_[a-f0-9]{64}\.ggsync$').hasMatch(p),
          ) ||
          parents.contains(name)) {
        throw const FormatException('Invalid progress metadata');
      }
    } else if (decoded['revision'] is! int ||
        record.revision < 1 ||
        decoded['blob'] is! String ||
        !RegExp(r'^b_[a-f0-9]{64}\.ggpack$').hasMatch(record.blob!)) {
      throw const FormatException('Invalid package metadata');
    }
    return record;
  }
}

/// Notes/attributes merge by key. Playback position and lesson form one value,
/// so concurrent changes cannot splice a segment into the wrong lesson.
({Map<String, dynamic> progress, List<String> conflicts}) mergeStudyProgress(
  Map<String, dynamic> base,
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final conflicts = <String>[];
  final absent = Object();
  Object? merge(Object? b, Object? l, Object? r, String path) {
    bool same(Object? a, Object? b) =>
        identical(a, absent) || identical(b, absent)
        ? identical(a, b)
        : canonicalJson(a) == canonicalJson(b);
    if (same(l, r) || same(r, b)) return l;
    if (same(l, b)) return r;
    if (l is Map && r is Map && (b is Map || identical(b, absent))) {
      final before = b is Map ? b : const <String, dynamic>{};
      final keys = {...before.keys, ...l.keys, ...r.keys}.cast<String>();
      final result = <String, dynamic>{};
      for (final key in keys) {
        final value = merge(
          before.containsKey(key) ? before[key] : absent,
          l.containsKey(key) ? l[key] : absent,
          r.containsKey(key) ? r[key] : absent,
          path.isEmpty ? key : '$path.$key',
        );
        if (!identical(value, absent)) result[key] = value;
      }
      return result;
    }
    conflicts.add(path);
    return l;
  }

  final result = <String, dynamic>{};
  for (final field in ['entry_notes', 'entry_attributes']) {
    final value = merge(
      base.containsKey(field) ? base[field] : absent,
      local.containsKey(field) ? local[field] : absent,
      remote.containsKey(field) ? remote[field] : absent,
      field,
    );
    if (!identical(value, absent)) result[field] = value;
  }
  Map<String, dynamic> location(Map<String, dynamic> value) => {
    for (final entry in value.entries)
      if (entry.key != 'entry_notes' && entry.key != 'entry_attributes')
        entry.key: entry.value,
  };
  final b = location(base), l = location(local), r = location(remote);
  if (canonicalJson(l) == canonicalJson(r) ||
      canonicalJson(r) == canonicalJson(b)) {
    result.addAll(l);
  } else if (canonicalJson(l) == canonicalJson(b)) {
    result.addAll(r);
  } else {
    result.addAll(l);
    conflicts.add('learning_position');
  }
  return (progress: result, conflicts: conflicts);
}
