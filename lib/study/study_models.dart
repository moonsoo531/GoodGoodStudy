/// Versioned, offline Japanese learning material. Character ranges use Dart's
/// UTF-16 offsets and are validated against the exact imported source text.
class StudyPackage {
  const StudyPackage({
    required this.packageId,
    required this.contentRevision,
    required this.title,
    required this.levelTags,
    required this.media,
    required this.lessons,
    required this.entries,
    this.source,
  });

  final String packageId;
  final int contentRevision;
  final String title;
  final List<String> levelTags;
  final List<StudyMedia> media;
  final List<StudyLesson> lessons;
  final List<StudyEntry> entries;
  final Object? source;

  factory StudyPackage.fromJson(
    Map<String, dynamic> manifest, {
    required List<dynamic> lessons,
    required List<dynamic> entries,
  }) {
    if (manifest['schema_version'] != '1.0' ||
        manifest['language'] != 'ja' ||
        manifest['translation_language'] != 'zh-CN') {
      throw const FormatException('只支持 1.0 版日语 / 简体中文学习包。');
    }
    final id = _string(manifest, 'package_id');
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(id)) {
      throw const FormatException('package_id 必须是小写字母、数字或连字符。');
    }
    final revision = _integer(manifest, 'content_revision');
    if (revision < 1) throw const FormatException('资料版本必须为正整数。');
    final result = StudyPackage(
      packageId: id,
      contentRevision: revision,
      title: _string(manifest, 'title'),
      levelTags: _strings(manifest, 'level_tags'),
      media: _list(manifest, 'media')
          .map((e) => StudyMedia.fromJson(_map(e, 'media')))
          .toList(growable: false),
      lessons: lessons
          .map((e) => StudyLesson.fromJson(_map(e, 'lesson')))
          .toList(growable: false),
      entries: entries
          .map((e) => StudyEntry.fromJson(_map(e, 'entry')))
          .toList(growable: false),
      source: manifest['source'],
    );
    result._validateReferences();
    return result;
  }

  Map<String, dynamic> get manifestJson => {
    'schema_version': '1.0',
    'package_id': packageId,
    'content_revision': contentRevision,
    'title': title,
    'language': 'ja',
    'translation_language': 'zh-CN',
    'level_tags': levelTags,
    'media': media.map((m) => m.toJson()).toList(),
    if (source != null) 'source': source,
  };

  Map<String, dynamic> toJson() => {
    ...manifestJson,
    'lessons': lessons.map((e) => e.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  void _validateReferences() {
    if (lessons.isEmpty) throw const FormatException('学习包没有课程。');
    _unique(media.map((e) => e.id), '音频 ID');
    _unique(media.map((e) => e.path.toLowerCase()), '音频路径');
    _unique(lessons.map((e) => e.id), '课程 ID');
    _unique(lessons.expand((e) => e.segments.map((s) => s.id)), '段落 ID');
    _unique(entries.map((e) => e.id), '词条 ID');
    final audioIds = media.map((e) => e.id).toSet();
    final entryIds = entries.map((e) => e.id).toSet();
    for (final lesson in lessons) {
      if (lesson.audioRef != null && !audioIds.contains(lesson.audioRef)) {
        throw FormatException('课程 ${lesson.id} 引用了不存在的音频。');
      }
      _unique(lesson.segments.map((e) => e.id), '段落 ID');
      _unique(lesson.entryIds, '课程词条 ID');
      if (lesson.entryIds.any((id) => !entryIds.contains(id))) {
        throw FormatException('课程 ${lesson.id} 引用了不存在的词条。');
      }
      for (final segment in lesson.segments) {
        if (segment.audioStartMs != null && lesson.audioRef == null) {
          throw const FormatException('时间轴必须关联课程音频。');
        }
        var previousEnd = 0;
        for (final highlight in segment.highlights) {
          if (!entryIds.contains(highlight.entryId)) {
            throw FormatException('段落 ${segment.id} 引用了不存在的词条。');
          }
          if (highlight.start < previousEnd ||
              highlight.start < 0 ||
              highlight.end <= highlight.start ||
              highlight.end > segment.text.length ||
              !_characterBoundary(segment.text, highlight.start) ||
              !_characterBoundary(segment.text, highlight.end)) {
            throw FormatException('段落 ${segment.id} 的强调范围重叠或无效。');
          }
          previousEnd = highlight.end;
        }
        previousEnd = 0;
        for (final ruby in segment.ruby) {
          if (ruby.start < previousEnd ||
              ruby.start < 0 ||
              ruby.end <= ruby.start ||
              ruby.end > segment.text.length ||
              !_characterBoundary(segment.text, ruby.start) ||
              !_characterBoundary(segment.text, ruby.end)) {
            throw FormatException('段落 ${segment.id} 的假名范围重叠或无效。');
          }
          previousEnd = ruby.end;
        }
      }
    }
  }
}

class StudyMedia {
  const StudyMedia({
    required this.id,
    required this.path,
    required this.sha256,
    this.source,
  });
  final String id;
  final String path;
  final String sha256;
  final Object? source;

  factory StudyMedia.fromJson(Map<String, dynamic> json) {
    final path = _string(json, 'path');
    validateStudyRelativePath(path);
    if (!path.startsWith('media/') ||
        !{
          'mp3',
          'm4a',
          'aac',
          'wav',
          'caf',
          'aiff',
          'aif',
        }.contains(path.split('.').last.toLowerCase())) {
      throw const FormatException('音频必须位于 media/ 且为支持的本地音频格式。');
    }
    final hash = _string(json, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('音频 SHA-256 必须为 64 位小写十六进制。');
    }
    return StudyMedia(
      id: _string(json, 'id'),
      path: path,
      sha256: hash,
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'sha256': sha256,
    if (source != null) 'source': source,
  };
}

class StudyLesson {
  const StudyLesson({
    required this.id,
    required this.title,
    required this.topic,
    required this.segments,
    this.entryIds = const [],
    this.audioRef,
    this.source,
  });
  final String id;
  final String title;
  final String topic;
  final String? audioRef;
  final List<StudySegment> segments;

  /// Lesson vocabulary, including related terms absent from the passage.
  final List<String> entryIds;
  final Object? source;

  factory StudyLesson.fromJson(Map<String, dynamic> json) {
    final segments = _list(json, 'segments')
        .map((e) => StudySegment.fromJson(_map(e, 'segment')))
        .toList(growable: false);
    if (segments.isEmpty) throw const FormatException('课程没有段落。');
    return StudyLesson(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      topic: _string(json, 'topic'),
      audioRef: _optionalString(json, 'audio_ref'),
      segments: segments,
      entryIds: json.containsKey('entry_ids')
          ? _strings(json, 'entry_ids')
          : const [],
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'topic': topic,
    if (audioRef != null) 'audio_ref': audioRef,
    'segments': segments.map((s) => s.toJson()).toList(),
    if (entryIds.isNotEmpty) 'entry_ids': entryIds,
    if (source != null) 'source': source,
  };
}

class StudySegment {
  const StudySegment({
    required this.id,
    required this.text,
    required this.translationZh,
    required this.highlights,
    this.ruby = const [],
    this.speaker,
    this.audioStartMs,
    this.audioEndMs,
    this.source,
  });
  final String id;
  final String text;
  final String translationZh;
  final String? speaker;
  final List<StudyHighlight> highlights;
  final List<StudyRuby> ruby;
  final int? audioStartMs;
  final int? audioEndMs;
  final Object? source;

  factory StudySegment.fromJson(Map<String, dynamic> json) {
    final hasStart = json['audio_start_ms'] != null;
    final hasEnd = json['audio_end_ms'] != null;
    if (hasStart != hasEnd) {
      throw const FormatException('音频时间必须同时给出起点和终点。');
    }
    final start = hasStart ? _integer(json, 'audio_start_ms') : null;
    final end = hasEnd ? _integer(json, 'audio_end_ms') : null;
    if (start != null && (start < 0 || end! <= start)) {
      throw const FormatException('音频时间范围无效。');
    }
    return StudySegment(
      id: _string(json, 'id'),
      text: _string(json, 'text'),
      translationZh: _string(json, 'translation_zh'),
      speaker: _optionalString(json, 'speaker'),
      highlights: _list(json, 'highlights')
          .map((e) => StudyHighlight.fromJson(_map(e, 'highlight')))
          .toList(growable: false),
      ruby: json.containsKey('ruby')
          ? _list(json, 'ruby')
                .map((e) => StudyRuby.fromJson(_map(e, 'ruby')))
                .toList(growable: false)
          : const [],
      audioStartMs: start,
      audioEndMs: end,
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'translation_zh': translationZh,
    if (speaker != null) 'speaker': speaker,
    'highlights': highlights.map((e) => e.toJson()).toList(),
    if (ruby.isNotEmpty) 'ruby': ruby.map((e) => e.toJson()).toList(),
    if (audioStartMs != null) 'audio_start_ms': audioStartMs,
    if (audioEndMs != null) 'audio_end_ms': audioEndMs,
    if (source != null) 'source': source,
  };
}

class StudyRuby {
  const StudyRuby({
    required this.start,
    required this.end,
    required this.reading,
    this.source,
  });

  final int start;
  final int end;
  final String reading;
  final Object? source;

  factory StudyRuby.fromJson(Map<String, dynamic> json) => StudyRuby(
    start: _integer(json, 'start'),
    end: _integer(json, 'end'),
    reading: _string(json, 'reading'),
    source: json['source'],
  );

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'reading': reading,
    if (source != null) 'source': source,
  };
}

class StudyHighlight {
  const StudyHighlight({
    required this.start,
    required this.end,
    required this.entryId,
  });
  final int start;
  final int end;
  final String entryId;

  factory StudyHighlight.fromJson(Map<String, dynamic> json) => StudyHighlight(
    start: _integer(json, 'start'),
    end: _integer(json, 'end'),
    entryId: _string(json, 'entry_id'),
  );
  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'entry_id': entryId,
  };
}

class StudyEntry {
  const StudyEntry({
    required this.id,
    required this.surface,
    required this.reading,
    required this.meaningZh,
    required this.kind,
    required this.attributes,
    required this.tags,
    required this.relations,
    this.explanationZh,
    this.source,
  });
  final String id;
  final String surface;
  final String reading;
  final String meaningZh;
  final String? explanationZh;
  final String kind;
  final Map<String, String> attributes;
  final List<String> tags;
  final List<StudyRelation> relations;
  final Object? source;

  factory StudyEntry.fromJson(Map<String, dynamic> json) {
    final kind = _string(json, 'kind');
    if (kind != 'vocabulary' && kind != 'grammar') {
      throw const FormatException('词条类型必须是 vocabulary 或 grammar。');
    }
    final attributes = _map(json['attributes'], 'attributes');
    if (attributes.values.any((v) => v is! String)) {
      throw const FormatException('词条属性必须是字符串。');
    }
    return StudyEntry(
      id: _string(json, 'id'),
      surface: _string(json, 'surface'),
      reading: _string(json, 'reading'),
      meaningZh: _string(json, 'meaning_zh'),
      explanationZh: _optionalString(json, 'explanation_zh'),
      kind: kind,
      attributes: attributes.map(
        (key, value) => MapEntry(key, value as String),
      ),
      tags: _strings(json, 'tags'),
      relations: _list(json, 'relations')
          .map((e) => StudyRelation.fromJson(_map(e, 'relation')))
          .toList(growable: false),
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'surface': surface,
    'reading': reading,
    'meaning_zh': meaningZh,
    if (explanationZh != null) 'explanation_zh': explanationZh,
    'kind': kind,
    'attributes': attributes,
    'tags': tags,
    'relations': relations.map((e) => e.toJson()).toList(),
    if (source != null) 'source': source,
  };
}

class StudyRelation {
  const StudyRelation({
    required this.label,
    required this.text,
    this.meaningZh,
  });
  final String label;
  final String text;
  final String? meaningZh;
  factory StudyRelation.fromJson(Map<String, dynamic> json) => StudyRelation(
    label: _string(json, 'label'),
    text: _string(json, 'text'),
    meaningZh: _optionalString(json, 'meaning_zh'),
  );
  Map<String, dynamic> toJson() => {
    'label': label,
    'text': text,
    if (meaningZh != null) 'meaning_zh': meaningZh,
  };
}

void validateStudyRelativePath(String path) {
  if (path.isEmpty ||
      path.length > 240 ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('\u0000') ||
      path.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
      path.codeUnits.any((c) => c < 32)) {
    throw const FormatException('学习包中包含无效的相对路径。');
  }
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    throw FormatException('$label 必须为 JSON 对象。');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 100000) {
    throw FormatException('$key 必须为非空字符串。');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _string(json, key);
int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key 必须为整数。');
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key 必须为数组。');
  if (value.length > 50000) throw FormatException('$key 条目过多。');
  return value;
}

List<String> _strings(Map<String, dynamic> json, String key) {
  final values = _list(json, key);
  if (values.any((e) => e is! String || e.trim().isEmpty)) {
    throw FormatException('$key 必须是非空字符串数组。');
  }
  return List<String>.from(values);
}

void _unique(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw FormatException('$label 重复：$value');
  }
}

bool _characterBoundary(String text, int position) =>
    position <= 0 ||
    position >= text.length ||
    !(text.codeUnitAt(position) >= 0xdc00 &&
        text.codeUnitAt(position) <= 0xdfff);
