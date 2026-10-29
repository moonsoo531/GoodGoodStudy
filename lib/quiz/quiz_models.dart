/// Prepared, offline, single-choice question banks. Character offsets are UTF-16.
class QuizPackage {
  const QuizPackage({
    required this.packageId,
    required this.contentRevision,
    required this.title,
    required this.levelTags,
    required this.questions,
    this.source,
  });

  final String packageId;
  final int contentRevision;
  final String title;
  final List<String> levelTags;
  final List<QuizQuestion> questions;
  final Object? source;

  factory QuizPackage.fromJson(
    Map<String, dynamic> manifest, {
    required List<dynamic> questions,
  }) {
    if (manifest['schema_version'] != '1.0' ||
        manifest['kind'] != 'quiz' ||
        manifest['language'] != 'ja') {
      throw const FormatException('只支持 1.0 版日语测验包。');
    }
    final id = _string(manifest, 'package_id', max: 80);
    validateQuizPackageId(id);
    final revision = _integer(manifest, 'content_revision');
    if (revision < 1) throw const FormatException('测验资料修订号必须为正整数。');
    if (questions.isEmpty || questions.length > 20000) {
      throw const FormatException('测验包需要 1 至 20000 道题。');
    }
    final values = questions
        .map((q) => QuizQuestion.fromJson(_map(q, 'question')))
        .toList(growable: false);
    _unique(values.map((q) => q.id), '题目 ID');
    final tags = manifest['level_tags'] ?? <dynamic>[];
    if (tags is! List ||
        tags.length > 20 ||
        tags.any((v) => v is! String || v.trim().isEmpty || v.length > 80)) {
      throw const FormatException('level_tags 必须为级别字符串数组。');
    }
    return QuizPackage(
      packageId: id,
      contentRevision: revision,
      title: _string(manifest, 'title', max: 300),
      levelTags: List.unmodifiable(tags.cast<String>()),
      questions: List.unmodifiable(values),
      source: manifest['source'],
    );
  }

  Map<String, dynamic> get manifestJson => {
    'schema_version': '1.0',
    'kind': 'quiz',
    'package_id': packageId,
    'content_revision': contentRevision,
    'title': title,
    'language': 'ja',
    'level_tags': levelTags,
    if (source != null) 'source': source,
  };

  Map<String, dynamic> toJson() => {
    ...manifestJson,
    'questions': questions.map((q) => q.toJson()).toList(),
  };
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.answerId,
    this.section,
    this.explanationZh,
    this.underlines = const [],
    this.ruby = const [],
    this.source,
  });

  final String id;
  final String prompt;
  final List<QuizChoice> choices;
  final String answerId;
  final String? section;
  final String? explanationZh;
  final List<QuizUnderline> underlines;
  final List<QuizRuby> ruby;
  final Object? source;

  QuizChoice get correctChoice => choices.firstWhere((c) => c.id == answerId);

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final prompt = _string(json, 'prompt', max: 10000);
    final rawChoices = _list(json, 'choices', max: 8);
    if (rawChoices.length < 2) {
      throw const FormatException('每题需要 2 至 8 个选项。');
    }
    final choices = rawChoices
        .map((v) => QuizChoice.fromJson(_map(v, 'choice')))
        .toList(growable: false);
    _unique(choices.map((c) => c.id), '选项 ID');
    final answer = _string(json, 'answer_id', max: 120);
    if (!choices.any((c) => c.id == answer)) {
      throw const FormatException('正确答案必须引用本题的一个选项 ID。');
    }
    final rawRanges = json['underlines'] ?? <dynamic>[];
    if (rawRanges is! List || rawRanges.length > 100) {
      throw const FormatException('题目下划线范围必须为数组。');
    }
    var previousEnd = 0;
    final ranges = <QuizUnderline>[];
    for (final value in rawRanges) {
      final range = _map(value, 'underline');
      final start = _integer(range, 'start'), end = _integer(range, 'end');
      if (start < previousEnd ||
          start < 0 ||
          end <= start ||
          end > prompt.length ||
          !_boundary(prompt, start) ||
          !_boundary(prompt, end)) {
        throw const FormatException('题目下划线范围重叠或切断了字符。');
      }
      ranges.add(QuizUnderline(start: start, end: end));
      previousEnd = end;
    }
    return QuizQuestion(
      id: _string(json, 'id', max: 120),
      prompt: prompt,
      choices: List.unmodifiable(choices),
      answerId: answer,
      section: _optionalString(json, 'section', max: 500),
      explanationZh: _optionalString(json, 'explanation_zh', max: 10000),
      underlines: List.unmodifiable(ranges),
      ruby: _readRuby(json, prompt),
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'choices': choices.map((c) => c.toJson()).toList(),
    'answer_id': answerId,
    if (section != null) 'section': section,
    if (explanationZh != null) 'explanation_zh': explanationZh,
    if (underlines.isNotEmpty)
      'underlines': underlines.map((u) => u.toJson()).toList(),
    if (ruby.isNotEmpty) 'ruby': ruby.map((r) => r.toJson()).toList(),
    if (source != null) 'source': source,
  };
}

class QuizChoice {
  const QuizChoice({
    required this.id,
    required this.text,
    this.ruby = const [],
  });
  final String id;
  final String text;
  final List<QuizRuby> ruby;
  factory QuizChoice.fromJson(Map<String, dynamic> json) {
    final text = _string(json, 'text', max: 5000);
    return QuizChoice(
      id: _string(json, 'id', max: 120),
      text: text,
      ruby: _readRuby(json, text),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (ruby.isNotEmpty) 'ruby': ruby.map((r) => r.toJson()).toList(),
  };
}

/// Prepared readings decorate text; answer IDs and scoring never use readings.
class QuizRuby {
  const QuizRuby({
    required this.start,
    required this.end,
    required this.reading,
  });
  final int start;
  final int end;
  final String reading;
  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'reading': reading,
  };
}

List<QuizRuby> _readRuby(Map<String, dynamic> json, String text) {
  if (!json.containsKey('ruby')) return const [];
  final values = _list(json, 'ruby', max: 1000);
  final result = <QuizRuby>[];
  var previousEnd = 0;
  for (final value in values) {
    final raw = _map(value, 'ruby');
    final start = _integer(raw, 'start'), end = _integer(raw, 'end');
    final reading = _string(raw, 'reading', max: 500);
    if (start < previousEnd ||
        start < 0 ||
        end <= start ||
        end > text.length ||
        !_boundary(text, start) ||
        !_boundary(text, end) ||
        text.substring(start, end).trim().isEmpty ||
        reading.contains(RegExp(r'[\r\n\u0001-\u001f]'))) {
      throw const FormatException('假名范围重叠、切断字符或读音无效。');
    }
    result.add(QuizRuby(start: start, end: end, reading: reading));
    previousEnd = end;
  }
  return List.unmodifiable(result);
}

class QuizUnderline {
  const QuizUnderline({required this.start, required this.end});
  final int start;
  final int end;
  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

enum QuizFeedback { immediate, onSubmit }

enum QuizOrder { sequential, random }

enum QuizScope { all, wrong }

class QuizSettings {
  const QuizSettings({
    required this.questionCount,
    this.durationMinutes = 0,
    this.feedback = QuizFeedback.onSubmit,
    this.order = QuizOrder.sequential,
    this.scope = QuizScope.all,
  });

  final int questionCount;
  final int durationMinutes;
  final QuizFeedback feedback;
  final QuizOrder order;
  final QuizScope scope;

  void validate() {
    if (questionCount < 1 || questionCount > 2000) {
      throw const FormatException('每次测试题量为 1 至 2000 题。');
    }
    if (durationMinutes < 0 || durationMinutes > 1440) {
      throw const FormatException('测试时长为 0 至 1440 分钟，0 表示不限时。');
    }
  }

  factory QuizSettings.fromJson(Map<String, dynamic> json) {
    final value = QuizSettings(
      questionCount: _integer(json, 'question_count'),
      durationMinutes: _integer(json, 'duration_minutes'),
      feedback: _enum(QuizFeedback.values, json['feedback'], '答案显示方式'),
      order: _enum(QuizOrder.values, json['order'], '出题顺序'),
      scope: _enum(QuizScope.values, json['scope'], '出题范围'),
    );
    value.validate();
    return value;
  }

  Map<String, dynamic> toJson() => {
    'question_count': questionCount,
    'duration_minutes': durationMinutes,
    'feedback': feedback.name,
    'order': order.name,
    'scope': scope.name,
  };
}

/// An active test and its completed snapshot use the same immutable shape.
/// The question snapshot keeps old results correct after a bank revision.
class QuizSession {
  const QuizSession({
    required this.id,
    required this.packageId,
    required this.packageTitle,
    required this.contentRevision,
    required this.settings,
    required this.questions,
    required this.answers,
    required this.currentIndex,
    required this.startedAt,
    required this.deadlineAt,
    this.endedAt,
    this.timedOut = false,
  });

  final String id;
  final String packageId;
  final String packageTitle;
  final int contentRevision;
  final QuizSettings settings;
  final List<QuizQuestion> questions;
  final Map<String, String> answers;
  final int currentIndex;
  final DateTime startedAt;
  final DateTime? deadlineAt;
  final DateTime? endedAt;
  final bool timedOut;

  bool get isCompleted => endedAt != null;
  bool isExpired([DateTime? now]) =>
      !isCompleted &&
      deadlineAt != null &&
      !(now ?? DateTime.now()).isBefore(deadlineAt!);
  int? remainingSeconds([DateTime? now]) {
    if (deadlineAt == null) return null;
    final milliseconds = deadlineAt!
        .difference(endedAt ?? now ?? DateTime.now())
        .inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds + 999) ~/ 1000;
  }

  QuizSession copyWith({
    Map<String, String>? answers,
    int? currentIndex,
    DateTime? endedAt,
    bool? timedOut,
  }) => QuizSession(
    id: id,
    packageId: packageId,
    packageTitle: packageTitle,
    contentRevision: contentRevision,
    settings: settings,
    questions: questions,
    answers: answers == null ? this.answers : Map.unmodifiable(answers),
    currentIndex: currentIndex ?? this.currentIndex,
    startedAt: startedAt,
    deadlineAt: deadlineAt,
    endedAt: endedAt ?? this.endedAt,
    timedOut: timedOut ?? this.timedOut,
  );

  factory QuizSession.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1) throw const FormatException('测试记录版本无效。');
    final id = _string(json, 'id', max: 100);
    validateQuizSessionId(id);
    final packageId = _string(json, 'package_id', max: 80);
    validateQuizPackageId(packageId);
    final settings = QuizSettings.fromJson(_map(json['settings'], 'settings'));
    final questions = _list(json, 'questions', max: 2000)
        .map((v) => QuizQuestion.fromJson(_map(v, 'question')))
        .toList(growable: false);
    if (questions.isEmpty || questions.length > settings.questionCount) {
      throw const FormatException('测试题目快照无效。');
    }
    _unique(questions.map((q) => q.id), '测试题目 ID');
    final byId = {for (final q in questions) q.id: q};
    final answers = _map(json['answers'], 'answers');
    for (final entry in answers.entries) {
      final question = byId[entry.key];
      if (question == null ||
          entry.value is! String ||
          !question.choices.any((c) => c.id == entry.value)) {
        throw const FormatException('测试记录中含有不存在的题目或选项。');
      }
    }
    final index = _integer(json, 'current_index');
    if (index < 0 || index >= questions.length) {
      throw const FormatException('测试记录的当前题目位置无效。');
    }
    final revision = _integer(json, 'content_revision');
    if (revision < 1) throw const FormatException('测试记录的资料修订号无效。');
    final started = _date(json, 'started_at');
    final deadline = json['deadline_at'] == null
        ? null
        : _date(json, 'deadline_at');
    final ended = json['ended_at'] == null ? null : _date(json, 'ended_at');
    final expectedDeadline = settings.durationMinutes == 0
        ? null
        : started.add(Duration(minutes: settings.durationMinutes));
    if (deadline != expectedDeadline ||
        ended != null && ended.isBefore(started) ||
        json['timed_out'] is! bool ||
        json['timed_out'] == true && (ended == null || deadline == null) ||
        ended != null && deadline != null && ended.isAfter(deadline)) {
      throw const FormatException('测试记录的起止时间无效。');
    }
    return QuizSession(
      id: id,
      packageId: packageId,
      packageTitle: _string(json, 'package_title', max: 300),
      contentRevision: revision,
      settings: settings,
      questions: List.unmodifiable(questions),
      answers: Map.unmodifiable(answers.cast<String, String>()),
      currentIndex: index,
      startedAt: started,
      deadlineAt: deadline,
      endedAt: ended,
      timedOut: json['timed_out'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'id': id,
    'package_id': packageId,
    'package_title': packageTitle,
    'content_revision': contentRevision,
    'settings': settings.toJson(),
    'questions': questions.map((q) => q.toJson()).toList(),
    'answers': answers,
    'current_index': currentIndex,
    'started_at': startedAt.toUtc().toIso8601String(),
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'timed_out': timedOut,
  };
}

class QuizAttempt {
  const QuizAttempt({required this.session});
  final QuizSession session;
  String get id => session.id;
  int get totalCount => session.questions.length;
  int get answeredCount => session.answers.length;
  int get correctCount => session.questions
      .where((q) => session.answers[q.id] == q.answerId)
      .length;
  double get accuracy => totalCount == 0 ? 0 : correctCount / totalCount;
  bool get timedOut => session.timedOut;
  int get elapsedSeconds => (session.endedAt ?? session.startedAt)
      .difference(session.startedAt)
      .inSeconds;
}

class QuizQuestionStats {
  const QuizQuestionStats({
    required this.questionId,
    required this.answeredCount,
    required this.correctCount,
    required this.wrongCount,
    required this.latestCorrect,
    required this.lastAttemptedAt,
  });
  final String questionId;
  final int answeredCount;
  final int correctCount;

  /// Includes submitted tests in which this question was unanswered.
  final int wrongCount;
  final bool latestCorrect;
  final DateTime lastAttemptedAt;
}

class QuizBookStats {
  const QuizBookStats({
    required this.totalQuestions,
    required this.uniqueAnsweredCount,
    required this.uniqueTestedCount,
    required this.masteredCount,
    required this.wrongCount,
    required this.attemptCount,
    required this.totalAnswered,
    required this.totalAssigned,
    required this.totalCorrect,
    required this.wrongQuestionIds,
    required this.questionStats,
    required this.nextSequentialIndex,
  });
  final int totalQuestions;
  final int uniqueAnsweredCount;
  final int uniqueTestedCount;
  final int masteredCount;
  final int wrongCount;
  final int attemptCount;
  final int totalAnswered;
  final int totalAssigned;
  final int totalCorrect;
  final Set<String> wrongQuestionIds;
  final Map<String, QuizQuestionStats> questionStats;
  final int nextSequentialIndex;
  double get accuracy => totalAssigned == 0 ? 0 : totalCorrect / totalAssigned;
  double get coverage =>
      totalQuestions == 0 ? 0 : uniqueTestedCount / totalQuestions;
}

class QuizBookState {
  const QuizBookState({
    this.lastSettings,
    this.activeSession,
    this.showReadings = true,
  });
  final QuizSettings? lastSettings;
  final QuizSession? activeSession;
  final bool showReadings;
}

class QuizSessionExpiredException implements Exception {
  const QuizSessionExpiredException(this.attempt);
  final QuizAttempt attempt;
  @override
  String toString() => '测试时间已到，成绩已保存。';
}

void validateQuizPackageId(String id) {
  if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(id)) {
    throw const FormatException('package_id 必须是小写字母、数字或连字符。');
  }
}

void validateQuizSessionId(String id) {
  if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,99}$').hasMatch(id)) {
    throw const FormatException('测试记录 ID 无效。');
  }
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$label 必须是 JSON 对象。');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> json, String key, {int max = 10000}) {
  final value = json[key];
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      value.contains('\u0000')) {
    throw FormatException('$key 必须是非空字符串，且不能过长。');
  }
  return value;
}

String? _optionalString(
  Map<String, dynamic> json,
  String key, {
  int max = 10000,
}) => json[key] == null ? null : _string(json, key, max: max);

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key 必须是整数。');
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String key, {int max = 20000}) {
  final value = json[key];
  if (value is! List || value.length > max) {
    throw FormatException('$key 必须是数组，且不能过长。');
  }
  return value;
}

void _unique(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw FormatException('$label 重复：$value');
  }
}

bool _boundary(String text, int position) =>
    position <= 0 ||
    position >= text.length ||
    !(text.codeUnitAt(position) >= 0xdc00 &&
        text.codeUnitAt(position) <= 0xdfff);

T _enum<T extends Enum>(List<T> values, Object? value, String label) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$label 无效。');
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw FormatException('$key 必须为 ISO 日期时间。');
  return date;
}
