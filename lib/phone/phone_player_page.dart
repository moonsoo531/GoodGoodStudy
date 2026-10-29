import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_home_back_button.dart';
import '../navigation/app_navigation.dart';
import '../navigation/app_section_menu_button.dart';

import '../theme/app_theme.dart';

import '../library/local_library.dart';
import '../playback/apple_audio_controller.dart';
import '../quiz/quiz_page.dart';
import '../subtitles/subtitles.dart';
import '../study/study_audio.dart';
import '../study/study_page.dart';
import '../widgets/ruby_subtitle_text.dart';
import '../widgets/stable_slider.dart';
import 'phone_media_store.dart';

class PhonePlayerPage extends StatefulWidget {
  const PhonePlayerPage({super.key, this.audio, this.store});
  final AppleAudioController? audio;
  final PhoneMediaStore? store;

  @override
  State<PhonePlayerPage> createState() => _PhonePlayerPageState();
}

class _PhonePlayerPageState extends State<PhonePlayerPage>
    with WidgetsBindingObserver {
  AppNavigationController? _navigation;
  VoidCallback? _unregisterNavigation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = AppNavigationScope.maybeOf(context);
    if (identical(navigation, _navigation)) return;
    _unregisterNavigation?.call();
    _navigation = navigation;
    _unregisterNavigation = navigation?.registerBeforeLeave(_leaveSection);
  }

  Future<bool> _leaveSection() async {
    if (_loading || _studying) return false;
    await _audio.pause();
    _save();
    await _store.flush();
    return true;
  }

  ColorScheme get _colors => Theme.of(context).colorScheme;

  late final AppleAudioController _audio =
      widget.audio ?? AppleAudioController();
  late final PhoneMediaStore _store = widget.store ?? PhoneMediaStore();
  final _scroll = ScrollController();
  List<PhoneLesson> _lessons = [];
  List<SubtitleCue> _cues = [];
  PhoneLesson? _lesson;
  final Map<String, String> _associations = {};
  bool _loading = true;
  bool _studying = false;
  bool _visible = true;
  bool _readings = true;
  bool _follow = true;
  double _fontSize = 25;
  double? _drag;
  Duration _offset = Duration.zero;
  int? _passes;
  int? _lastCue;
  Duration? _pointA;
  String? _message;
  Timer? _saveTimer;

  bool get _ready =>
      _lesson != null && _audio.path != null && !_loading && !_audio.busy;
  SubtitleCue? get _current => cueAt(_cues, _audio.position, offset: _offset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio.addListener(_changed);
    unawaited(_run(_initialize));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _initialize() async {
    try {
      final saved = await _store.loadState();
      final associations = saved['associations'] as Map?;
      if (associations != null) {
        _associations.addAll(
          associations.map(
            (key, value) => MapEntry(key as String, value as String),
          ),
        );
      }
      _visible = saved['visible'] as bool? ?? true;
      _readings = saved['readings'] as bool? ?? true;
      _fontSize = (saved['fontSize'] as num? ?? 25).toDouble().clamp(16, 36);
      _offset = Duration(milliseconds: saved['offsetMs'] as int? ?? 0);
      _lessons = await _store.scan(associations: _associations);
      await _audio.refresh();
      final current = saved['current'] as String?;
      PhoneLesson? target;
      for (final lesson in _lessons) {
        if (lesson.relativeAudio == current) target = lesson;
      }
      target ??= _lessons.isEmpty ? null : _lessons.first;
      if (target != null) {
        await _open(
          target,
          position: target.relativeAudio == current
              ? Duration(milliseconds: saved['positionMs'] as int? ?? 0)
              : Duration.zero,
        );
        final savedRate = (saved['rate'] as num? ?? 1).toDouble();
        if ([0.5, 0.75, 1.0, 1.25, 1.5, 2.0].contains(savedRate)) {
          await _audio.setRate(savedRate);
        }
      }
    } finally {
      _loading = false;
    }
  }

  void _save() {
    if (_loading || _studying) return;
    unawaited(
      _store
          .saveState({
            'associations': _associations,
            'current': _lesson?.relativeAudio,
            'positionMs': _audio.position.inMilliseconds,
            'rate': _audio.rate,
            'visible': _visible,
            'readings': _readings,
            'fontSize': _fontSize,
            'offsetMs': _offset.inMilliseconds,
          })
          .catchError((Object error) {
            if (mounted) setState(() => _message = '保存进度失败：$error');
          }),
    );
  }

  void _changed() {
    if (!mounted || _studying) return;
    final current = _current?.index;
    if (current != _lastCue) {
      _lastCue = current;
      if (_follow && current != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              (current * 96.0 - 48).clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
    setState(() {});
  }

  Future<void> _study() => _run(() async {
    if (_navigation case final navigation?) {
      await navigation.navigate(AppSection.study);
      return;
    }
    final original = _lesson;
    final position = _audio.position;
    final rate = _audio.rate;
    await _audio.pause();
    _save();
    if (!mounted) return;
    _studying = true;
    final studyAudio = AppleStudyAudio(_audio);
    final route = MaterialPageRoute<void>(
      builder: (_) => StudyPage(audio: studyAudio),
    );
    try {
      await Navigator.of(context).push<void>(route);
      // The popped result arrives before StudyPage is disposed. Its outstanding
      // commands must finish before reopening the original shared session.
      await route.completed;
    } finally {
      try {
        await studyAudio.close();
      } finally {
        _studying = false;
        if (mounted && original != null) {
          await _open(original, position: position);
          await _audio.setRate(rate);
        }
      }
    }
  });

  Future<void> _quiz() => _run(() async {
    if (_navigation case final navigation?) {
      await navigation.navigate(AppSection.quiz);
      return;
    }
    await _audio.pause();
    _save();
    if (!mounted) return;
    _studying = true;
    try {
      final route = MaterialPageRoute<void>(builder: (_) => const QuizPage());
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } finally {
      _studying = false;
      if (mounted) await _audio.refresh();
    }
  });

  Future<void> _open(
    PhoneLesson lesson, {
    Duration position = Duration.zero,
  }) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await _audio.openLocal(
        await _store.absolutePath(lesson.relativeAudio),
        title: lesson.title,
        position: position,
        autoplay: false,
      );
      _lesson = lesson;
      _pointA = null;
      _lastCue = null;
      await _loadSubtitle(lesson.relativeSubtitle);
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
    _save();
  }

  Future<void> _loadSubtitle(String? relative) async {
    _cues = [];
    if (relative != null) {
      final path = await _store.absolutePath(relative);
      final raw = await File(path).readAsString();
      _cues = extensionOf(path) == 'vtt' ? parseWebVtt(raw) : parseSrt(raw);
      if (_cues.isEmpty) throw const FormatException('字幕中没有有效条目。');
    }
    if (mounted) setState(() {});
  }

  Future<void> _import() => _run(() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: context.tr('导入本地音频，可同时选择同名字幕'),
      type: FileType.custom,
      allowedExtensions: [...phoneAudioExtensions, ...subtitleExtensions],
    );
    if (result.isEmpty) return;
    setState(() => _loading = true);
    try {
      final copied = await _store.copySelected(
        result.map((file) => file.path).whereType<String>(),
      );
      _lessons = await _store.scan(associations: _associations);
      PhoneLesson? added;
      for (final lesson in _lessons) {
        if (copied.contains(lesson.relativeAudio)) {
          added = lesson;
          break;
        }
      }
      if (added != null) {
        await _open(added);
      } else {
        _message = '请先导入MP3等音频，再用“载入字幕”选择SRT或VTT。';
      }
    } finally {
      _loading = false;
    }
    _save();
  });

  Future<void> _pickSubtitle() => _run(() async {
    final lesson = _lesson;
    if (lesson == null) return;
    final selected = await FilePicker.pickFile(
      dialogTitle: context.tr('选择SRT或VTT字幕'),
      type: FileType.custom,
      allowedExtensions: subtitleExtensions.toList(),
    );
    if (selected?.path == null) return;
    final copied = await _store.copySelected([selected!.path!]);
    if (copied.isEmpty) return;
    await _loadSubtitle(copied.single);
    final updated = lesson.withSubtitle(copied.single);
    _associations[updated.relativeAudio] = copied.single;
    final index = _lessons.indexOf(lesson);
    if (index >= 0) _lessons[index] = updated;
    _lesson = updated;
    _save();
  });

  Future<void> _reload() => _run(() async {
    _lessons = await _store.scan(associations: _associations);
    if (_lesson == null && _lessons.isNotEmpty) await _open(_lessons.first);
  });

  Duration _start(SubtitleCue cue) =>
      cue.start + _offset < Duration.zero ? Duration.zero : cue.start + _offset;

  Future<void> _jump(SubtitleCue? cue) => _run(() async {
    if (!_ready || cue == null) return;
    await _audio.clearLoop();
    await _audio.seek(_start(cue));
    _pointA = null;
    _save();
  });

  Future<void> _repeat() => _run(() async {
    final cue = _current;
    if (!_ready || cue == null) return;
    await _audio.setLoop(_start(cue), cue.end + _offset, repeatCount: _passes);
    await _audio.play();
  });

  Future<void> _chooseLesson() async {
    final picked = await showModalBottomSheet<PhoneLesson>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final lesson in _lessons)
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(
                  lesson.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: lesson.relativeAudio == _lesson?.relativeAudio
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, lesson),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _run(() => _open(picked));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_studying) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _run(() async {
          await _audio.refresh();
          await _reload();
        }),
      );
    } else {
      _save();
    }
  }

  @override
  void dispose() {
    _unregisterNavigation?.call();
    _save();
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _audio.removeListener(_changed);
    if (widget.audio == null) {
      final shutdown = Future.wait<void>([
        _audio.close().whenComplete(_audio.dispose),
        _store.flush(),
      ]).then<void>((_) {});
      _navigation?.trackShutdown(shutdown);
      unawaited(shutdown.catchError((Object _) {}));
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _message ?? _audio.error;
    return Scaffold(
      appBar: AppBar(
        leading: _navigation == null ? null : const AppHomeBackButton(),
        title: Text(
          context.tr('本地播放'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          const AppSectionMenuButton(),
          const ThemeMenuButton(),
          IconButton(
            tooltip: context.tr('刷新本地资料'),
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.tr('导入音频'),
            onPressed: _loading ? null : _import,
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: _navigation != null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: context.tr('基础知识学习'),
                          child: TextButton.icon(
                            onPressed: _loading || _studying ? null : _study,
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 20,
                            ),
                            label: Text(context.tr('基础知识学习')),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: context.tr('基础知识测试'),
                          child: TextButton.icon(
                            onPressed: _loading || _studying ? null : _quiz,
                            icon: const Icon(
                              Icons.fact_check_outlined,
                              size: 20,
                            ),
                            label: Text(context.tr('基础知识测试')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (error != null)
              MaterialBanner(
                content: Text(
                  context.trMessage(error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _audio.clearError();
                      setState(() => _message = null);
                    },
                    child: Text(context.tr('关闭')),
                  ),
                ],
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) {
                  final sections = <Widget>[
                    _lessonHeader(),
                    if (_lesson == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _subtitleStage(),
                      )
                    else
                      SizedBox(
                        height: (size.maxHeight * 0.22).clamp(80, 175),
                        child: _subtitleStage(),
                      ),
                    _timeline(),
                    _playControls(),
                    _options(),
                    _subtitleHeader(),
                  ];
                  if (size.maxHeight < 440 || size.maxWidth < 360) {
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          ...sections,
                          if (_cues.isEmpty)
                            _subtitleList()
                          else
                            SizedBox(height: 180, child: _subtitleList()),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      ...sections,
                      Expanded(child: _subtitleList()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lessonHeader() => SizedBox(
    height: 46,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: _lessons.isEmpty || _loading ? null : _chooseLesson,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Icon(Icons.headphones_rounded, color: _colors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _lesson?.title ?? context.tr('导入音频，开始练习'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _colors.onSurfaceVariant),
              ),
            ),
            if (_lessons.isNotEmpty) const Icon(Icons.expand_more, size: 20),
          ],
        ),
      ),
    ),
  );

  Widget _subtitleStage() {
    if (_loading || _audio.buffering) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lesson == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('选择本地MP3或M4A音频'), style: TextStyle(fontSize: 17)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _import,
                icon: const Icon(Icons.folder_open),
                label: Text(context.tr('导入音频与字幕')),
              ),
            ],
          ),
        ),
      );
    }
    final cue = _current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: SingleChildScrollView(
          child: _visible && cue != null
              ? RubySubtitleText(
                  text: cue.text,
                  showReadings: _readings,
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: 1.4,
                    color: _colors.onSurface,
                  ),
                )
              : Text(
                  !_visible
                      ? context.tr('字幕已遮挡')
                      : _cues.isEmpty
                      ? context.tr('可载入SRT或VTT字幕')
                      : context.tr('听一听，等待下一句'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _colors.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _timeline() {
    final total = _audio.duration.inMilliseconds.toDouble();
    final position = (_drag ?? _audio.position.inMilliseconds.toDouble()).clamp(
      0.0,
      total > 0 ? total : 1.0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            _clock(Duration(milliseconds: position.round())),
            style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
          ),
          Expanded(
            child: StableSlider(
              value: position,
              max: total > 0 ? total : 1,
              onChanged: _ready
                  ? (value) => setState(() => _drag = value)
                  : null,
              onChangeEnd: (value) {
                setState(() => _drag = null);
                unawaited(
                  _run(
                    () => _audio.seek(Duration(milliseconds: value.round())),
                  ),
                );
              },
            ),
          ),
          Text(
            _clock(_audio.duration),
            style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _playControls() => SizedBox(
    height: 60,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: context.tr('上一句'),
          onPressed: _ready
              ? () =>
                    _jump(previousCue(_cues, _audio.position, offset: _offset))
              : null,
          icon: const Icon(Icons.skip_previous_rounded, size: 27),
        ),
        FilledButton(
          onPressed: _ready ? () => _run(_audio.toggle) : null,
          child: Icon(
            _audio.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 32,
            semanticLabel: _audio.playing ? context.tr('暂停') : context.tr('播放'),
          ),
        ),
        IconButton(
          tooltip: context.tr('下一句'),
          onPressed: _ready
              ? () => _jump(nextCue(_cues, _audio.position, offset: _offset))
              : null,
          icon: const Icon(Icons.skip_next_rounded, size: 27),
        ),
        IconButton(
          tooltip: _audio.loop == null
              ? context.tr('循环当前句')
              : context.tr('取消循环'),
          isSelected: _audio.loop != null,
          onPressed: !_ready
              ? null
              : () => _audio.loop == null ? _repeat() : _run(_audio.clearLoop),
          icon: const Icon(Icons.repeat_one_rounded),
        ),
      ],
    ),
  );

  Widget _options() => SizedBox(
    height: 44,
    child: Row(
      children: [
        SizedBox(
          width: 94,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              isExpanded: true,
              value: _audio.rate,
              items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (rate) => DropdownMenuItem(
                      value: rate,
                      child: Text(
                        '$rate×',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: !_ready
                  ? null
                  : (rate) {
                      if (rate != null) {
                        unawaited(
                          _run(() async {
                            await _audio.setRate(rate);
                            _save();
                          }),
                        );
                      }
                    },
            ),
          ),
        ),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: (MediaQuery.sizeOf(context).width - 24)
                  .clamp(200, 400)
                  .toDouble(),
              value: _passes ?? 0,
              selectedItemBuilder: (context) => [
                for (final choice in [(0, '无限循环'), (1, '1遍后停'), (3, '3遍后停')])
                  Tooltip(
                    message: context.tr(choice.$2),
                    excludeFromSemantics: true,
                    child: Text(
                      choice.$1 == 0 ? '∞' : '${choice.$1}×',
                      semanticsLabel: context.tr(choice.$2),
                    ),
                  ),
              ],
              items: [
                DropdownMenuItem(value: 0, child: Text(context.tr('无限循环'))),
                DropdownMenuItem(value: 1, child: Text(context.tr('1遍后停'))),
                DropdownMenuItem(value: 3, child: Text(context.tr('3遍后停'))),
              ],
              style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
              onChanged: (value) =>
                  setState(() => _passes = value == 0 ? null : value),
            ),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: context.tr('定时停止'),
          enabled: _ready,
          icon: Icon(
            Icons.bedtime_outlined,
            size: 20,
            color: _audio.stopAt == null
                ? _colors.onSurfaceVariant
                : _colors.primary,
          ),
          onSelected: (minutes) => _run(
            () => _audio.setStopAt(
              minutes == 0
                  ? null
                  : DateTime.now().add(Duration(minutes: minutes)),
            ),
          ),
          itemBuilder: (_) => [
            for (final minutes in [0, 5, 15, 30, 60])
              PopupMenuItem(
                value: minutes,
                child: Text(
                  minutes == 0
                      ? context.tr('关闭定时停止')
                      : context.tr('{minutes}分钟后停止', {'minutes': minutes}),
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: context.tr('字幕和循环设置'),
          onPressed: _settings,
          icon: const Icon(Icons.tune, size: 20),
        ),
      ],
    ),
  );

  Widget _subtitleHeader() => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('字幕  {count}', {'count': _cues.length}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: context.tr('跟随当前句'),
            isSelected: _follow,
            onPressed: () => setState(() => _follow = !_follow),
            icon: const Icon(Icons.my_location, size: 18),
          ),
          IconButton(
            tooltip: _visible ? context.tr('遮挡字幕') : context.tr('显示字幕'),
            onPressed: () {
              setState(() => _visible = !_visible);
              _save();
            },
            icon: Icon(
              _visible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
          ),
          if (constraints.maxWidth < 400)
            IconButton(
              tooltip: context.tr('载入字幕'),
              onPressed: _lesson == null ? null : _pickSubtitle,
              icon: const Icon(Icons.file_open_outlined, size: 18),
            )
          else
            TextButton(
              onPressed: _lesson == null ? null : _pickSubtitle,
              child: Text(
                context.tr('载入字幕'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _subtitleList() => _cues.isEmpty
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              context.tr('音频可在后台继续播放\n音量可用手机侧键调整'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _colors.onSurfaceVariant, height: 1.8),
            ),
          ),
        )
      : ListView.builder(
          controller: _scroll,
          itemExtent: 96,
          itemCount: _cues.length,
          itemBuilder: (context, index) {
            final cue = _cues[index];
            final selected = _current?.index == cue.index;
            return Material(
              color: selected ? _colors.primaryContainer : Colors.transparent,
              child: InkWell(
                onTap: _ready ? () => _jump(cue) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}    ${_clock(cue.start + _offset)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? _colors.onPrimaryContainer
                              : _colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          _visible
                              ? plainSubtitleText(cue.text)
                              : context.tr('字幕已遮挡'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            color: selected
                                ? _colors.onPrimaryContainer
                                : _colors.onSurface,
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

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('字幕与循环'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Text(context.tr('字号 {size}', {'size': _fontSize.round()})),
                  StableSlider(
                    value: _fontSize,
                    min: 16,
                    max: 36,
                    divisions: 20,
                    onChanged: (value) {
                      setState(() => _fontSize = value);
                      refresh(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('显示已有假名')),
                    value: _readings,
                    onChanged: (value) {
                      setState(() => _readings = value);
                      refresh(() {});
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('字幕偏移 {offset} ms', {
                            'offset': _offset.inMilliseconds,
                          }),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => _offset -= const Duration(milliseconds: 100),
                          );
                          refresh(() {});
                        },
                        child: const Text('−100'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => _offset += const Duration(milliseconds: 100),
                          );
                          refresh(() {});
                        },
                        child: const Text('+100'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: !_ready
                            ? null
                            : () {
                                setState(() => _pointA = _audio.position);
                                refresh(() {});
                              },
                        child: Text(
                          _pointA == null
                              ? context.tr('设置A点')
                              : 'A ${_clock(_pointA!)}',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: !_ready || _pointA == null
                            ? null
                            : () => _run(() async {
                                await _audio.setLoop(
                                  _pointA!,
                                  _audio.position,
                                  repeatCount: _passes,
                                );
                                await _audio.play();
                                if (context.mounted) Navigator.pop(context);
                              }),
                        child: Text(context.tr('设置B点并播放')),
                      ),
                      TextButton(
                        onPressed: _audio.loop == null
                            ? null
                            : () => _run(() async {
                                await _audio.clearLoop();
                                refresh(() {});
                              }),
                        child: Text(context.tr('清除循环')),
                      ),
                    ],
                  ),
                  if (_audio.loop != null)
                    Text(
                      context.tr('循环 {start}—{end}　{completed}/{count}', {
                        'start': _clock(_audio.loop!.start),
                        'end': _clock(_audio.loop!.end),
                        'completed': _audio.loop!.completedPasses,
                        'count': _audio.loop!.repeatCount ?? '∞',
                      }),
                      style: TextStyle(
                        fontSize: 12,
                        color: _colors.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        _save();
                        Navigator.pop(context);
                      },
                      child: Text(context.tr('完成')),
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

  String _clock(Duration value) {
    final seconds = value.inSeconds.clamp(0, 999999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
