import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_navigation.dart';
import '../navigation/app_section_menu_button.dart';
import '../theme/app_theme.dart';
import 'quiz_models.dart';
import 'quiz_ruby_text.dart';
import 'quiz_store.dart';

enum _View { library, settings, exam, result, history }

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    this.store,
    this.now,
    this.restoreLastLocation = false,
  });
  final QuizStore? store;
  final DateTime Function()? now;
  final bool restoreLastLocation;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with WidgetsBindingObserver {
  late final QuizStore _store = widget.store ?? QuizStore();
  final _count = TextEditingController(text: '10');
  final _minutes = TextEditingController(text: '15');
  final _scroll = ScrollController();
  final Map<String, QuizBookStats> _stats = {};
  final Map<String, QuizBookState> _states = {};
  List<InstalledQuizPackage> _books = [];
  InstalledQuizPackage? _book;
  QuizSession? _session;
  QuizAttempt? _attempt;
  List<QuizAttempt> _history = [];
  _View _view = _View.library;
  QuizScope _scope = QuizScope.all;
  QuizOrder _order = QuizOrder.sequential;
  QuizFeedback _feedback = QuizFeedback.onSubmit;
  bool _busy = false;
  bool _wrongOnly = false;
  bool _fromHistory = false;
  bool _showReadings = true;
  String? _message;
  Timer? _ticker;
  AppNavigationController? _navigation;
  VoidCallback? _unregisterNavigation;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  ColorScheme get _colors => Theme.of(context).colorScheme;
  QuizBookStats? get _bookStats => _stats[_book?.package.packageId];
  int get _poolCount => _scope == QuizScope.wrong
      ? (_bookStats?.wrongCount ?? 0)
      : (_book?.package.questions.length ?? 0);
  QuizSession? get _active => _states[_book?.package.packageId]?.activeSession;
  bool get _hasReadings {
    final questions = switch (_view) {
      _View.exam => _session?.questions,
      _View.result => _attempt?.session.questions,
      _ => _book?.package.questions,
    };
    return questions?.any(
          (q) => q.ruby.isNotEmpty || q.choices.any((c) => c.ruby.isNotEmpty),
        ) ??
        false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _run(() async {
        await _refresh();
        if (widget.restoreLastLocation && mounted) await _restoreLocation();
      }),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = AppNavigationScope.maybeOf(context);
    if (identical(navigation, _navigation)) return;
    _unregisterNavigation?.call();
    _navigation = navigation;
    _unregisterNavigation = navigation?.registerBeforeLeave(
      _beforeSectionLeave,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    } else if (!_busy) {
      unawaited(_rememberView());
    }
  }

  void _tick() {
    final session = _session;
    if (!mounted || _view != _View.exam || session == null) return;
    if (session.isExpired(_now)) {
      if (!_busy) unawaited(_finish(automatic: true));
    } else {
      setState(() {});
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
    } on QuizSessionExpiredException catch (error) {
      await _showResult(error.attempt, automatic: true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is FormatException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : error.toString(),
        );
      }
    } finally {
      if (mounted) await _rememberView();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _rememberView() async {
    if (!widget.restoreLastLocation) return true;
    final location = QuizNavigationLocation(
      view: _view.name,
      packageId: _view == _View.library ? null : _book?.package.packageId,
      sessionId: _view == _View.exam ? _session?.id : null,
      attemptId: _view == _View.result ? _attempt?.id : null,
      fromHistory: _fromHistory,
      wrongOnly: _wrongOnly,
    );
    try {
      await _store.saveNavigationLocation(location);
      return true;
    } catch (error) {
      if (mounted) setState(() => _message = '保存进度失败：$error');
      return false;
    }
  }

  Future<void> _restoreLocation() async {
    final saved = await _store.loadNavigationLocation();
    if (!mounted || saved == null || saved.view == 'library') return;
    final book = _books
        .where((b) => b.package.packageId == saved.packageId)
        .firstOrNull;
    if (book == null) return;
    await _openBook(book);
    if (!mounted) return;
    switch (saved.view) {
      case 'exam':
        // _openBook applies the existing expiry rule before restoration.
        if (_view == _View.result) return;
        final active = await _store.loadActiveSession(book.package.packageId);
        if (!mounted) return;
        if (active == null) {
          // Finishing is durable before the view pointer is written. Recover
          // that archive if the process stopped between those two writes.
          if (saved.sessionId != null) {
            final attempts = await _store.attempts(book.package.packageId);
            final finished = attempts
                .where((a) => a.id == saved.sessionId)
                .firstOrNull;
            if (mounted && finished != null) await _showResult(finished);
          }
          return;
        }
        if (saved.sessionId != null && active.id != saved.sessionId) {
          return;
        }
        if (active.isExpired(_now)) {
          await _showResult(
            await _store.finishSession(active.packageId, active.id, now: _now),
            automatic: true,
          );
        } else if (mounted) {
          setState(() {
            _session = active;
            _view = _View.exam;
          });
        }
        return;
      case 'history':
        _history = await _store.attempts(book.package.packageId);
        if (mounted) setState(() => _view = _View.history);
        return;
      case 'result':
        final attempts = await _store.attempts(book.package.packageId);
        if (!mounted) return;
        final attempt = attempts
            .where((a) => a.id == saved.attemptId)
            .firstOrNull;
        if (attempt != null) {
          setState(() {
            _attempt = attempt;
            _session = null;
            _view = _View.result;
            _fromHistory = saved.fromHistory;
            _wrongOnly = saved.wrongOnly;
          });
        }
        return;
      default:
        break;
    }
  }

  Future<bool> _beforeSectionLeave() async {
    if (_busy || !mounted || !await _confirmLeaveExam()) return false;
    if (!mounted || _busy || !await _rememberView()) return false;
    await _store.flush();
    return mounted && !_busy;
  }

  Future<void> _refresh() async {
    _books = await _store.packages();
    for (final book in _books) {
      await _refreshBook(book.package.packageId);
    }
    if (_store.libraryWarnings.isNotEmpty) {
      _message = _store.libraryWarnings.join('\n');
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshBook(String id) async {
    _stats[id] = await _store.stats(id);
    _states[id] = await _store.loadBookState(id);
  }

  Future<void> _import() => _run(() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: context.tr('导入选择题测试包'),
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked?.path == null) return;
    final installed = await _store.importZip(File(picked!.path!));
    await _refresh();
    if (mounted) await _openBook(installed);
  });

  Future<void> _openBook(InstalledQuizPackage book) async {
    _book = book;
    await _refreshBook(book.package.packageId);
    if (!mounted) return;
    final saved = _states[book.package.packageId]!;
    _showReadings = saved.showReadings;
    final settings = saved.lastSettings;
    _scope = settings?.scope ?? QuizScope.all;
    _order = settings?.order ?? QuizOrder.sequential;
    _feedback = settings?.feedback ?? QuizFeedback.onSubmit;
    _count.text =
        '${(settings?.questionCount ?? 10).clamp(1, _poolCount == 0 ? 1 : _poolCount)}';
    _minutes.text = '${settings?.durationMinutes ?? 15}';
    _session = null;
    _attempt = null;
    if (saved.activeSession?.isExpired(_now) ?? false) {
      final s = saved.activeSession!;
      final result = await _store.finishSession(s.packageId, s.id, now: _now);
      await _showResult(result, automatic: true);
    } else if (mounted) {
      setState(() => _view = _View.settings);
    }
  }

  Future<void> _start() => _run(() async {
    if (_active != null) throw const FormatException('请先继续或交卷当前测试。');
    final count = int.tryParse(_count.text);
    final minutes = int.tryParse(_minutes.text);
    if (count == null || count < 1 || count > _poolCount) {
      throw FormatException('测试题数需要在 1–$_poolCount 之间。');
    }
    if (minutes == null || minutes < 0 || minutes > 1440) {
      throw const FormatException('测试时间请输入 0–1440 分钟，0 表示不限时。');
    }
    _session = await _store.startSession(
      _book!.package.packageId,
      QuizSettings(
        questionCount: count,
        durationMinutes: minutes,
        feedback: _feedback,
        order: _order,
        scope: _scope,
      ),
      now: _now,
    );
    await _refreshBook(_book!.package.packageId);
    if (mounted) setState(() => _view = _View.exam);
    _top();
  });

  Future<void> _resume() => _run(() async {
    final active = await _store.loadActiveSession(_book!.package.packageId);
    if (active == null) throw const FormatException('当前没有未完成的测试。');
    _session = active;
    if (active.isExpired(_now)) {
      await _showResult(
        await _store.finishSession(active.packageId, active.id, now: _now),
        automatic: true,
      );
    } else if (mounted) {
      setState(() => _view = _View.exam);
      _top();
    }
  });

  Future<void> _choose(String choiceId) => _run(() async {
    final s = _session!;
    _session = await _store.answer(
      s.packageId,
      s.id,
      s.questions[s.currentIndex].id,
      choiceId,
      now: _now,
    );
    if (mounted) setState(() {});
  });

  Future<void> _navigate(int index) => _run(() async {
    final s = _session!;
    _session = await _store.navigate(s.packageId, s.id, index, now: _now);
    if (mounted) setState(() {});
    _top();
  });

  Future<void> _submit() async {
    if (_busy) return;
    final s = _session!;
    final missing = s.questions.length - s.answers.length;
    if (missing > 0) {
      final sessionId = s.id;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('现在交卷？')),
          content: Text(
            context.tr('还有 {count} 道题未作答，交卷后会计入错题。', {'count': missing}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('继续作答')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('确认交卷')),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          _busy ||
          _view != _View.exam ||
          _session?.id != sessionId) {
        return;
      }
    }
    await _finish();
  }

  Future<void> _finish({bool automatic = false}) => _run(() async {
    final s = _session;
    if (s == null || _view != _View.exam) return;
    if (automatic) {
      final pageRoute = ModalRoute.of(context);
      Navigator.of(context).popUntil((route) => route == pageRoute);
    }
    await _showResult(
      await _store.finishSession(s.packageId, s.id, now: _now),
      automatic: automatic,
    );
  });

  Future<void> _showResult(
    QuizAttempt attempt, {
    bool automatic = false,
  }) async {
    if (!mounted) return;
    // The completed snapshot is already durable. Switch all rendering state
    // together before refreshing derived statistics, which can be slow or fail.
    setState(() {
      _attempt = attempt;
      _session = null;
      _wrongOnly = attempt.correctCount != attempt.totalCount;
      _fromHistory = false;
      _view = _View.result;
      if (automatic) _message = '时间到，已自动交卷并保存结果。';
    });
    try {
      await _refreshBook(attempt.session.packageId);
    } catch (error) {
      // This also handles expiry raised by answer/navigate, whose caller is
      // already inside an exception handler. The saved result stays readable.
      if (mounted) {
        setState(() => _message = '成绩已保存，统计暂时无法刷新：$error');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _historyView() => _run(() async {
    _history = await _store.attempts(_book!.package.packageId);
    if (mounted) setState(() => _view = _View.history);
  });

  Future<bool> _confirmLeaveExam() async {
    if (_busy || !mounted) return false;
    if (_view != _View.exam) return true;
    final session = _session;
    if (session == null) return false;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('保存并离开测试？')),
        content: Text(
          session.deadlineAt == null
              ? context.tr('已选答案会保存在本机，可以稍后继续。')
              : context.tr('已选答案会保存在本机。计时继续，到期后按已有答案交卷。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('继续作答')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('保存并离开')),
          ),
        ],
      ),
    );
    final leave = await Navigator.of(context).push<bool>(route);
    await route.completed;
    return leave == true &&
        mounted &&
        !_busy &&
        _view == _View.exam &&
        _session?.id == session.id;
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_view == _View.library) {
      final navigation = _navigation;
      if (navigation != null) {
        await navigation.navigate(AppSection.home);
      } else {
        await Navigator.of(context).maybePop();
      }
      return;
    }
    if (_view == _View.exam) {
      if (!await _confirmLeaveExam()) return;
      await _run(() async {
        await _refreshBook(_book!.package.packageId);
        _session = null;
        if (mounted) setState(() => _view = _View.settings);
      });
      return;
    }
    setState(() {
      _message = null;
      _view = switch (_view) {
        _View.settings => _View.library,
        _View.result when _fromHistory => _View.history,
        _ => _View.settings,
      };
    });
    await _rememberView();
  }

  void _changeView(VoidCallback update) {
    setState(update);
    unawaited(_rememberView());
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unregisterNavigation?.call();
    _navigation?.trackShutdown(_store.flush());
    _ticker?.cancel();
    _count.dispose();
    _minutes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _view == _View.library && _navigation == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          _view == _View.history ? context.tr('测试记录') : context.tr('基础知识测试'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          const AppSectionMenuButton(),
          if (_view != _View.library && _view != _View.history)
            _readingToggle(),
          const ThemeMenuButton(),
          if (_view == _View.library || _view == _View.settings)
            IconButton(
              tooltip: context.tr('导入测试包'),
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.library_add_outlined),
            ),
          if (_view == _View.exam)
            IconButton(
              key: const ValueKey('quiz-submit'),
              tooltip: context.tr('交卷'),
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.task_alt),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_message != null)
              MaterialBanner(
                content: Text(context.trMessage(_message!)),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _message = null),
                    child: Text(context.tr('关闭')),
                  ),
                ],
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 932),
                  child: switch (_view) {
                    _View.library => _library(),
                    _View.settings => _settings(),
                    _View.exam => _exam(),
                    _View.result => _result(),
                    _View.history => _records(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _view == _View.exam ? _examNavigation() : null,
    ),
  );

  Widget _readingToggle() => Tooltip(
    message: _hasReadings ? context.tr('显示假名') : context.tr('本资料未提供假名标注'),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.sizeOf(context).width >= 480)
          Text(context.tr('假名'), style: const TextStyle(fontSize: 13)),
        SizedBox(
          width: 48,
          child: Semantics(
            label: context.tr('显示假名'),
            child: Switch(
              key: const ValueKey('quiz-readings-toggle'),
              value: _hasReadings && _showReadings,
              onChanged: !_hasReadings || _busy
                  ? null
                  : (value) {
                      setState(() => _showReadings = value);
                      unawaited(
                        _run(() async {
                          await _store.saveShowReadings(
                            _book!.package.packageId,
                            value,
                          );
                        }),
                      );
                    },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _scrollContent(Widget child) => SingleChildScrollView(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
    child: child,
  );

  Widget _library() {
    if (_books.isEmpty) {
      return _scrollContent(
        Column(
          children: [
            const SizedBox(height: 70),
            Icon(Icons.fact_check_outlined, size: 64, color: _colors.primary),
            const SizedBox(height: 20),
            Text(
              context.tr('选择一本资料，开始测试'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('导入准备好的选择题 ZIP 包\n测试记录和错题保存在本机'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.add),
              label: Text(context.tr('导入测试包')),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        final stats = _stats[book.package.packageId];
        final active = _states[book.package.packageId]?.activeSession;
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('quiz-book-${book.package.packageId}'),
            onTap: _busy ? null : () => _run(() => _openBook(book)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    book.package.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${context.tr('{count} 题', {'count': book.package.questions.length})}${active == null
                        ? ''
                        : active.isExpired(_now)
                        ? context.tr(' · 计时已结束，查看结果')
                        : context.tr(' · 有未完成测试')}',
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: stats?.coverage ?? 0,
                    minHeight: 5,
                  ),
                  const SizedBox(height: 10),
                  _statsLine(stats, book.package.questions.length),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.tr('进入测试  ›'),
                      style: TextStyle(
                        color: _colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statsLine(QuizBookStats? stats, int total) => Wrap(
    spacing: 18,
    runSpacing: 8,
    children: [
      Text(
        context.tr('已测 {count}/{total}', {
          'count': stats?.uniqueTestedCount ?? 0,
          'total': total,
        }),
      ),
      Text(
        context.tr('正确率 {value}', {
          'value': stats == null || stats.attemptCount == 0
              ? '—'
              : _percent(stats.accuracy),
        }),
      ),
      Text(context.tr('错题 {count}', {'count': stats?.wrongCount ?? 0})),
      Text(context.tr('测试 {count} 次', {'count': stats?.attemptCount ?? 0})),
    ],
  );

  Widget _settings() {
    final book = _book!;
    final active = _active;
    return _scrollContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            book.package.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          _statsLine(_bookStats, book.package.questions.length),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _historyView,
            icon: const Icon(Icons.history),
            label: Text(context.tr('查看测试记录')),
          ),
          if (active != null)
            Card(
              color: _colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('上次测试 · 已选 {count}/{total} 题', {
                        'count': active.answers.length,
                        'total': active.questions.length,
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (active.deadlineAt != null)
                      Text(
                        context.tr('截止 {time}', {
                          'time': _date(active.deadlineAt!),
                        }),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('quiz-resume'),
                      onPressed: _busy ? null : _resume,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(context.tr('继续上次测试')),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          _settingLabel(context.tr('出题范围')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final scope in QuizScope.values)
                ChoiceChip(
                  label: Text(
                    scope == QuizScope.all
                        ? context.tr('全部题目')
                        : context.tr('错题专项'),
                  ),
                  selected: _scope == scope,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _scope = scope;
                          if (_poolCount > 0 &&
                              (int.tryParse(_count.text) ?? 0) > _poolCount) {
                            _count.text = '$_poolCount';
                          }
                        }),
                ),
            ],
          ),
          if (_poolCount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr('暂无错题。完成测试后，错题和漏答题会自动收录。')),
            ),
          const SizedBox(height: 18),
          _settingLabel(context.tr('出题顺序')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final order in QuizOrder.values)
                ChoiceChip(
                  label: Text(
                    order == QuizOrder.sequential
                        ? context.tr('按顺序')
                        : context.tr('随机'),
                  ),
                  selected: _order == order,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _order = order),
                ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, size) {
              final fields = [
                _numberField(
                  _count,
                  context.tr('测试题数'),
                  context.tr('范围内共 {count} 题', {'count': _poolCount}),
                  'quiz-question-count',
                ),
                _numberField(
                  _minutes,
                  context.tr('测试时间（分钟）'),
                  context.tr('0 表示不限时'),
                  'quiz-duration',
                ),
              ];
              return size.maxWidth >= 480
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 16),
                        Expanded(child: fields[1]),
                      ],
                    )
                  : Column(
                      children: [
                        fields[0],
                        const SizedBox(height: 16),
                        fields[1],
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
          _settingLabel(context.tr('答案反馈')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final feedback in QuizFeedback.values)
                ChoiceChip(
                  label: Text(
                    feedback == QuizFeedback.immediate
                        ? context.tr('逐题显示答案')
                        : context.tr('交卷后统一查看'),
                  ),
                  selected: _feedback == feedback,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _feedback = feedback),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _feedback == QuizFeedback.immediate
                ? context.tr('点击选项后显示答案，该题不能再修改。')
                : context.tr('交卷前可以修改所选答案，结束后统一查看正确答案。'),
            style: TextStyle(color: _colors.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            key: const ValueKey('quiz-start'),
            onPressed: _busy || _poolCount == 0 || active != null
                ? null
                : _start,
            icon: const Icon(Icons.edit_note),
            label: Text(
              active != null ? context.tr('请先完成上次测试') : context.tr('开始测试'),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            context.tr('已测进度按完成测试覆盖的题目计算；正确率包含历次交卷中的未答题。错题之后答对，会移出错题范围。'),
            style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _settingLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    String helper,
    String key,
  ) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ],
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _exam() {
    final s = _session!;
    final q = s.questions[s.currentIndex];
    final selected = s.answers[q.id];
    final reveal =
        s.settings.feedback == QuizFeedback.immediate && selected != null;
    final remaining = s.remainingSeconds(_now);
    return _scrollContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.packageTitle, style: TextStyle(color: _colors.primary)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                context.tr('第 {index}/{total} 题 · 已选 {count} 题', {
                  'index': s.currentIndex + 1,
                  'total': s.questions.length,
                  'count': s.answers.length,
                }),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Semantics(
                liveRegion: false,
                label: remaining == null
                    ? context.tr('不限时')
                    : context.tr('剩余 {time}', {'time': _duration(remaining)}),
                child: Text(
                  remaining == null
                      ? context.tr('不限时')
                      : context.tr('剩余 {time}', {'time': _duration(remaining)}),
                  style: TextStyle(
                    color: remaining != null && remaining <= 60
                        ? _colors.error
                        : _colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: s.answers.length / s.questions.length,
            minHeight: 4,
          ),
          const SizedBox(height: 24),
          _questionHeading(q),
          const SizedBox(height: 22),
          for (final choice in q.choices) _option(q, choice, selected, reveal),
          if (reveal) _feedbackBlock(q, selected),
        ],
      ),
    );
  }

  Widget _questionHeading(QuizQuestion q) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (q.section != null && q.section!.isNotEmpty) ...[
        Text(
          q.section!,
          style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 12),
      ],
      QuizRubyText(
        text: q.prompt,
        ruby: q.ruby,
        underlines: q.underlines,
        showReadings: _showReadings,
        style: const TextStyle(fontSize: 22, height: 1.8),
      ),
    ],
  );

  Widget _choiceText(
    QuizChoice choice, {
    String prefix = '',
    TextStyle? style,
  }) => QuizRubyText(
    text: choice.text,
    ruby: choice.ruby,
    showReadings: _showReadings,
    prefix: '$prefix${choice.id}. ',
    style: style,
  );

  Widget _option(
    QuizQuestion q,
    QuizChoice choice,
    String? selected,
    bool reveal,
  ) {
    final checked = selected == choice.id;
    final correct = choice.id == q.answerId;
    final color = reveal && correct
        ? _correctColor
        : reveal && checked
        ? _colors.error
        : checked
        ? _colors.primary
        : _colors.outlineVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: checked,
        child: Material(
          color: reveal && (correct || checked) || checked
              ? color.withValues(alpha: .08)
              : _colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color, width: checked ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('quiz-choice-${choice.id}'),
            onTap: _busy || reveal ? null : () => _choose(choice.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    reveal && correct
                        ? Icons.check_circle
                        : reveal && checked
                        ? Icons.cancel
                        : checked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _choiceText(
                      choice,
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.5,
                        color: _colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _correctColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF7BDB9D)
      : const Color(0xFF13743C);

  Widget _feedbackBlock(QuizQuestion q, String? selected) {
    final correct = selected == q.answerId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                correct ? Icons.check_circle : Icons.cancel,
                color: correct ? _correctColor : _colors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: correct
                    ? Text(
                        context.tr('回答正确'),
                        style: TextStyle(
                          color: _correctColor,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      )
                    : _choiceText(
                        q.correctChoice,
                        prefix: context.tr('{status} · 正确答案：', {
                          'status': selected == null
                              ? context.tr('未作答')
                              : context.tr('回答错误'),
                        }),
                        style: TextStyle(
                          color: _colors.error,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
              ),
            ],
          ),
          if (q.explanationZh != null && q.explanationZh!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                q.explanationZh!,
                style: const TextStyle(height: 1.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _examNavigation() {
    final s = _session!;
    final last = s.currentIndex == s.questions.length - 1;
    return Material(
      color: _colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('quiz-previous'),
                      onPressed: _busy || s.currentIndex == 0
                          ? null
                          : () => _navigate(s.currentIndex - 1),
                      icon: const Icon(Icons.chevron_left),
                      label: Text(context.tr('上一题')),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: IconButton(
                      tooltip: context.tr('答题卡'),
                      onPressed: _busy ? null : _questionGrid,
                      icon: const Icon(Icons.grid_view_outlined),
                    ),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('quiz-next'),
                      onPressed: _busy
                          ? null
                          : last
                          ? _submit
                          : () => _navigate(s.currentIndex + 1),
                      icon: Icon(last ? Icons.task_alt : Icons.chevron_right),
                      label: Text(last ? context.tr('交卷') : context.tr('下一题')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _questionGrid() async {
    final s = _session!;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.tr('答题卡 · 实心表示已选答案'),
                  style: TextStyle(fontSize: 18),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 72,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: s.questions.length,
                  itemBuilder: (context, index) {
                    final answered = s.answers.containsKey(
                      s.questions[index].id,
                    );
                    return answered
                        ? FilledButton(
                            onPressed: () => Navigator.pop(context, index),
                            child: Text('${index + 1}'),
                          )
                        : OutlinedButton(
                            onPressed: () => Navigator.pop(context, index),
                            child: Text('${index + 1}'),
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted && !_busy && _view == _View.exam) {
      await _navigate(selected);
    }
  }

  Widget _result() {
    final a = _attempt!;
    final s = a.session;
    final questions = s.questions
        .where((q) => !_wrongOnly || s.answers[q.id] != q.answerId)
        .toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.packageTitle, style: TextStyle(color: _colors.primary)),
                const SizedBox(height: 14),
                Text(
                  '${a.correctCount} / ${a.totalCount}',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${context.tr('正确率 {value}', {'value': _percent(a.accuracy)})}${a.timedOut ? context.tr(' · 时间到，自动交卷') : ''}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    '已答 {answered} 题 · 未答 {unanswered} 题 · 用时 {time}',
                    {
                      'answered': a.answeredCount,
                      'unanswered': a.totalCount - a.answeredCount,
                      'time': _duration(a.elapsedSeconds),
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _changeView(() {
                              _view = _View.settings;
                              _fromHistory = false;
                            }),
                      icon: const Icon(Icons.tune),
                      label: Text(context.tr('返回测试设置')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || (_bookStats?.wrongCount ?? 0) == 0
                          ? null
                          : () => _changeView(() {
                              _scope = QuizScope.wrong;
                              _count.text =
                                  '${(_bookStats!.wrongCount).clamp(1, 10)}';
                              _view = _View.settings;
                            }),
                      icon: const Icon(Icons.replay),
                      label: Text(context.tr('错题专项')),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(context.tr('全部题目')),
                      selected: !_wrongOnly,
                      onSelected: (_) => _changeView(() => _wrongOnly = false),
                    ),
                    ChoiceChip(
                      label: Text(
                        context.tr('错题与漏答 {count}', {
                          'count': a.totalCount - a.correctCount,
                        }),
                      ),
                      selected: _wrongOnly,
                      onSelected: (_) => _changeView(() => _wrongOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final q = questions[index];
              final selected = s.answers[q.id];
              final choice = selected == null
                  ? null
                  : q.choices.firstWhere((c) => c.id == selected);
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('第 {index} 题', {
                          'index': s.questions.indexOf(q) + 1,
                        }),
                        style: TextStyle(color: _colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _questionHeading(q),
                      const SizedBox(height: 14),
                      if (choice == null)
                        Text(
                          context.tr('你的答案：未作答'),
                          style: TextStyle(color: _colors.error, height: 1.6),
                        )
                      else
                        _choiceText(
                          choice,
                          prefix: context.tr('你的答案：'),
                          style: TextStyle(
                            color: selected == q.answerId
                                ? _correctColor
                                : _colors.error,
                            height: 1.6,
                          ),
                        ),
                      if (selected == q.answerId)
                        _choiceText(
                          q.correctChoice,
                          prefix: context.tr('正确答案：'),
                          style: TextStyle(color: _correctColor, height: 1.6),
                        ),
                      _feedbackBlock(q, selected),
                      ExpansionTile(
                        title: Text(context.tr('查看全部选项')),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          for (final c in q.choices)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: _choiceText(
                                  c,
                                  style: TextStyle(
                                    color: c.id == q.answerId
                                        ? _correctColor
                                        : _colors.onSurface,
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }, childCount: questions.length),
          ),
        ),
      ],
    );
  }

  Widget _records() => _history.isEmpty
      ? Center(child: Text(context.tr('还没有测试记录。')))
      : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _history.length,
          itemBuilder: (context, index) {
            final a = _history[index];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(
                  '${a.correctCount}/${a.totalCount} · ${_percent(a.accuracy)}',
                ),
                subtitle: Text(
                  '${_date(a.session.endedAt!)}\n${context.tr('{scope} · 用时 {time}', {'scope': a.session.settings.scope == QuizScope.wrong ? context.tr('错题专项') : context.tr('全部题目'), 'time': _duration(a.elapsedSeconds)})}${a.timedOut ? context.tr(' · 超时交卷') : ''}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => _changeView(() {
                        _attempt = a;
                        _wrongOnly = a.correctCount < a.totalCount;
                        _fromHistory = true;
                        _view = _View.result;
                      }),
              ),
            );
          },
        );

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
  String _duration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
