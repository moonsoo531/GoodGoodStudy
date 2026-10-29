import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../navigation/app_navigation.dart';
import '../navigation/app_section_menu_button.dart';

import '../widgets/stable_slider.dart';
import 'study_audio.dart';
import 'answer_input.dart';
import 'study_models.dart';
import 'study_passage_text.dart';
import 'study_practice.dart';
import 'study_playback_controller.dart';
import 'study_store.dart';

const _modeLabels = {StudyMode.keywords: '关键词遮蔽', StudyMode.dictation: '全文遮蔽'};

const _omittedDefaultAttributes = {'词汇编号', '动词组'};
const _sideLessonNavigationWidth = 1040.0;

/// Learning and self study. Formal single-choice tests have a separate page.
class StudyPage extends StatefulWidget {
  const StudyPage({super.key, this.store, this.audio});
  final StudyStore? store;
  final StudyAudio? audio;

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
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
    if (_loading || _playback.busy) return false;
    await _audio.pause();
    await _saveProgress();
    return true;
  }

  ColorScheme get _colors => Theme.of(context).colorScheme;

  late final StudyStore _store = widget.store ?? StudyStore();
  late final StudyAudio _audio = widget.audio ?? StudyAudio.platform();
  late final StudyPlaybackController _playback = StudyPlaybackController(
    audio: _audio,
  );
  List<InstalledStudyPackage> _packages = [];
  InstalledStudyPackage? _installed;
  StudyLesson? _lesson;
  InstalledStudyPackage? _selectionPackage;
  StudyLesson? _selectionLesson;
  Map<String, dynamic> _progress = {};
  final Map<String, StudyAnswerController> _drafts = {};
  final Set<String> _focusedAnswers = {};
  final FocusNode _pageFocus = FocusNode(debugLabel: 'Study page');
  final ScrollController _studyScroll = ScrollController(
    keepScrollOffset: false,
  );
  StudyMode _mode = StudyMode.read;
  bool _loading = true;
  bool _audioReady = false;
  bool _showTranslation = false;
  bool _showReadings = true;
  bool _reveal = false;
  double _rate = 1;
  double? _drag;
  String? _message;

  @override
  void initState() {
    super.initState();
    _audio.addListener(_audioChanged);
    _playback.addListener(_audioChanged);
    unawaited(
      _run(() async {
        _packages = await _store.packages();
        final resume = await _store.loadResumeLocation(_packages);
        if (!mounted) return;
        if (resume != null) {
          await _openPackage(
            _packages.firstWhere(
              (package) => package.package.packageId == resume.packageId,
            ),
            lessonId: resume.lessonId,
          );
        }
        _libraryWarnings();
      }),
    );
  }

  void _audioChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _audioAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  void _clearDrafts() {
    for (final controller in _drafts.values) {
      controller.dispose();
    }
    _drafts.clear();
    _focusedAnswers.clear();
    _reveal = false;
  }

  Future<void> _import() => _run(() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: context.tr('导入日语学习包'),
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked?.path == null) return;
    await _audio.pause();
    if (!mounted) return;
    final imported = await _store.importZip(File(picked!.path!));
    if (!mounted) return;
    _packages = await _store.packages();
    if (!mounted) return;
    if (_lesson == null) {
      setState(() {
        _selectionPackage = imported;
        _selectionLesson = null;
      });
    } else {
      final lessonId = await _pickLesson(imported);
      if (!mounted) return;
      if (lessonId != null) {
        await _openPackage(imported, lessonId: lessonId);
      }
    }
    _libraryWarnings();
  });

  void _libraryWarnings() {
    if (_store.libraryWarnings.isNotEmpty) {
      _message = _store.libraryWarnings.join('\n');
    }
  }

  Future<void> _openPackage(
    InstalledStudyPackage installed, {
    required String lessonId,
  }) async {
    if (!mounted) return;
    final lesson = installed.package.lessons.firstWhere(
      (lesson) => lesson.id == lessonId,
    );
    await _audio.pause();
    if (!mounted) return;
    final saved = await _store.loadProgress(installed.package.packageId);
    if (!mounted) return;
    _installed = installed;
    _progress = Map<String, dynamic>.from(saved);
    _migrateAttributeDefaults();
    _showTranslation = saved['show_translation'] == true;
    _showReadings = saved['show_readings'] != false;
    _rate = (saved['rate'] is num ? (saved['rate'] as num).toDouble() : 1);
    if (![0.5, 0.75, 1.0, 1.25, 1.5, 2.0].contains(_rate)) _rate = 1;
    _mode = switch (saved['mode']) {
      'keywords' => StudyMode.keywords,
      'dictation' => StudyMode.dictation,
      _ => StudyMode.read,
    };
    await _openLesson(lesson);
    _libraryWarnings();
  }

  Future<void> _openLesson(StudyLesson lesson) async {
    final installed = _installed;
    if (installed == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _playback.setLesson(null);
    if (!mounted) return;
    _clearDrafts();
    _lesson = lesson;
    _audioReady = false;
    _drag = null;
    if (_studyScroll.hasClients) _studyScroll.jumpTo(0);
    setState(() {});
    _pageFocus.requestFocus();
    try {
      await _loadAudio();
    } finally {
      if (mounted && _installed == installed && _lesson == lesson) {
        await _saveProgress();
        if (mounted && _installed == installed && _lesson == lesson) {
          await _store.saveResumeLocation(
            packageId: installed.package.packageId,
            lessonId: lesson.id,
          );
        }
      }
    }
  }

  Future<void> _loadAudio() async {
    final lesson = _lesson;
    final installed = _installed;
    if (!mounted || lesson == null || installed == null) return;
    if (lesson.audioRef != null) {
      await _audio.open(installed.audioPath(lesson.audioRef!), lesson.title);
      if (!mounted) return;
      await _audio.setRate(_rate);
    }
    if (!mounted) return;
    final savedCount = _progress['repeat_count'];
    final count = savedCount is int && [0, 1, 2, 3, 5, 10].contains(savedCount)
        ? savedCount
        : 1;
    final selectedId = _progress['audio_segment_id'];
    final selectedIndex = lesson.segments.indexWhere(
      (segment) => segment.id == selectedId,
    );
    await _playback.setLesson(
      lesson,
      scope: _progress['playback_scope'] == 'sentence'
          ? StudyPlaybackScope.sentence
          : StudyPlaybackScope.passage,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      repeatCount: count == 0 ? null : count,
    );
    if (mounted) setState(() => _audioReady = lesson.audioRef != null);
  }

  Future<void> _saveProgress() async {
    final installed = _installed;
    if (installed == null) return;
    _progress.addAll({
      'lesson_id': _lesson?.id,
      'mode': _mode.name,
      'rate': _rate,
      'show_translation': _showTranslation,
      'show_readings': _showReadings,
      if (_playback.lesson != null) ...{
        'playback_scope': _playback.scope.name,
        'repeat_count': _playback.repeatCount ?? 0,
        'audio_segment_id': _playback.selectedSegment?.id,
      },
    });
    await _store.saveProgress(installed.package.packageId, _progress);
  }

  void _remember() => unawaited(_audioAction(_saveProgress));

  bool get _canControlAudio =>
      _audioReady && !_loading && !_playback.busy && _playback.hasPlayableUnit;

  void _toggleAudioShortcut() {
    if (_canControlAudio) unawaited(_audioAction(_playback.toggle));
  }

  Future<void> _changePlayback(Future<void> Function() change) =>
      _audioAction(() async {
        if (mounted) setState(() => _drag = null);
        await change();
        await _saveProgress();
      });

  Future<void> _chooseRepeatCount() async {
    final route = DialogRoute<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('循环次数')),
        children: [
          for (final count in [1, 2, 3, 5, 10, 0])
            ListTile(
              leading: Icon(
                (_playback.repeatCount ?? 0) == count
                    ? Icons.check_rounded
                    : Icons.circle_outlined,
              ),
              title: Text(
                count == 0
                    ? context.tr('无限')
                    : context.tr('{count} 遍', {'count': count}),
              ),
              onTap: () => Navigator.of(dialogContext).pop(count),
            ),
        ],
      ),
    );
    final count = await Navigator.of(context).push<int>(route);
    // Remove the chooser before updating the playback controls and semantics.
    await route.completed;
    if (!mounted || count == null || !_canControlAudio) return;
    final resume = _audio.playing;
    await _changePlayback(
      () =>
          _playback.setRepeatCount(count == 0 ? null : count, autoplay: resume),
    );
  }

  void _answerFocus(String id, bool focused) {
    if (!mounted) return;
    setState(() {
      if (focused) {
        _focusedAnswers.add(id);
      } else {
        _focusedAnswers.remove(id);
      }
    });
  }

  void _setMode(StudyMode mode) {
    setState(() {
      _clearDrafts();
      _mode = mode;
    });
    _remember();
  }

  void _migrateAttributeDefaults() {
    if (_progress['entry_attribute_defaults_version'] == 1) return;
    final overrides = _progress['entry_attributes'];
    if (overrides is Map) {
      _progress['entry_attributes'] = {
        for (final entry in overrides.entries)
          entry.key: entry.value is Map
              ? {
                  for (final attr in (entry.value as Map).entries)
                    if (!_omittedDefaultAttributes.contains(attr.key))
                      attr.key: attr.value,
                }
              : entry.value,
      };
    }
    _progress['entry_attribute_defaults_version'] = 1;
  }

  Map<String, String> _attributes(StudyEntry entry) {
    final overrides = _progress['entry_attributes'];
    final value = overrides is Map ? overrides[entry.id] : null;
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value.toString()))
        : {
            for (final attr in entry.attributes.entries)
              if (!_omittedDefaultAttributes.contains(attr.key))
                attr.key: attr.value,
          };
  }

  String _note(StudyEntry entry) {
    final notes = _progress['entry_notes'];
    return notes is Map ? notes[entry.id]?.toString() ?? '' : '';
  }

  Future<void> _entryDetails(StudyEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.kind == 'grammar' ? context.tr('语法') : context.tr('词汇'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  entry.surface,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (entry.reading.isNotEmpty)
                  Text(
                    entry.reading,
                    style: TextStyle(
                      fontSize: 18,
                      color: _colors.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  entry.meaningZh,
                  style: const TextStyle(fontSize: 20, height: 1.6),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final attr in _attributes(entry).entries)
                      Chip(label: Text('${attr.key} · ${attr.value}')),
                    for (final tag in entry.tags) Chip(label: Text(tag)),
                  ],
                ),
                if (entry.explanationZh?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    entry.explanationZh!,
                    style: const TextStyle(fontSize: 16, height: 1.8),
                  ),
                ],
                for (final relation in entry.relations)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${relation.label}：${relation.text}${relation.meaningZh == null ? '' : ' · ${relation.meaningZh}'}',
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                if (_note(entry).isNotEmpty) ...[
                  const Divider(height: 28),
                  Text(
                    context.tr('我的笔记'),
                    style: TextStyle(color: _colors.onSurfaceVariant),
                  ),
                  Text(_note(entry), style: const TextStyle(height: 1.8)),
                ],
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_editEntry(entry));
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.tr('编辑属性与笔记')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editEntry(StudyEntry entry) async {
    final edited = await showDialog<_EntryEdits>(
      context: context,
      builder: (_) =>
          _EntryEditor(attributes: _attributes(entry), note: _note(entry)),
    );
    if (edited == null || !mounted) return;
    final attributes = Map<String, dynamic>.from(
      _progress['entry_attributes'] as Map? ?? {},
    );
    final notes = Map<String, dynamic>.from(
      _progress['entry_notes'] as Map? ?? {},
    );
    attributes[entry.id] = edited.attributes;
    notes[entry.id] = edited.note;
    setState(() {
      _progress['entry_attributes'] = attributes;
      _progress['entry_notes'] = notes;
    });
    await _audioAction(_saveProgress);
  }

  @override
  void dispose() {
    _unregisterNavigation?.call();
    _audio.removeListener(_audioChanged);
    _playback.removeListener(_audioChanged);
    _playback.dispose();
    _pageFocus.dispose();
    _studyScroll.dispose();
    _clearDrafts();
    final shutdown = _audio.close().whenComplete(_audio.dispose);
    _navigation?.trackShutdown(shutdown);
    unawaited(shutdown.catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    return CallbackShortcuts(
      bindings: {
        if (_focusedAnswers.isEmpty)
          const SingleActivator(
            LogicalKeyboardKey.space,
            includeRepeats: false,
          ): _toggleAudioShortcut,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          includeRepeats: false,
        ): _toggleAudioShortcut,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          includeRepeats: false,
        ): _toggleAudioShortcut,
      },
      child: FocusScope(
        autofocus: true,
        child: Focus(
          focusNode: _pageFocus,
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.tr('基础知识学习')),
              actions: [
                const AppSectionMenuButton(),
                const ThemeMenuButton(),
                IconButton(
                  tooltip: context.tr('导入学习包'),
                  onPressed: _loading ? null : _import,
                  icon: const Icon(Icons.library_add_outlined),
                ),
              ],
              bottom: lesson == null
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(52),
                      child: _studyNavigationBar(),
                    ),
            ),
            body: _loading && lesson == null
                ? const Center(child: CircularProgressIndicator())
                : _withLessonNavigation(
                    AbsorbPointer(
                      absorbing: _loading,
                      child: SingleChildScrollView(
                        key: const PageStorageKey('study-scroll'),
                        controller: _studyScroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              key: ValueKey((
                                _installed?.package.packageId,
                                _installed?.package.contentRevision,
                                lesson?.id,
                              )),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_message != null) _errorBanner(_message!),
                                if (lesson == null)
                                  if (_packages.isEmpty)
                                    _emptyLibrary()
                                  else
                                    _startSelection(),
                                if (lesson != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    lesson.topic,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                  Text(
                                    lesson.title,
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w600,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _learningToolbar(),
                                  if (_mode != StudyMode.read)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            setState(() => _reveal = !_reveal),
                                        icon: Icon(
                                          _reveal
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                        label: Text(
                                          _reveal
                                              ? context.tr('重新遮蔽')
                                              : context.tr('对照原文'),
                                        ),
                                      ),
                                    ),
                                  for (
                                    var index = 0;
                                    index < lesson.segments.length;
                                    index++
                                  )
                                    _segmentCard(lesson.segments[index], index),
                                  if (_mode == StudyMode.read || _reveal)
                                    _glossary(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            bottomNavigationBar: lesson == null ? null : _audioBar(),
          ),
        ),
      ),
    );
  }

  Widget _learningToolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final modes = Wrap(
        key: const ValueKey('study-mode-buttons'),
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final mode in _modeLabels.keys)
            ChoiceChip(
              label: Text(context.tr(_modeLabels[mode]!)),
              selected: mode == _mode,
              onSelected: (selected) =>
                  _setMode(selected ? mode : StudyMode.read),
            ),
        ],
      );
      final options = _textDisplayOptions();
      return constraints.maxWidth >= 760
          ? Row(
              key: const ValueKey('study-learning-toolbar'),
              children: [
                Expanded(child: modes),
                const SizedBox(width: 12),
                options,
              ],
            )
          : Column(
              key: const ValueKey('study-learning-toolbar'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                modes,
                Align(alignment: Alignment.centerRight, child: options),
              ],
            );
    },
  );

  Widget _textDisplayOptions() {
    final hasReadings = _lesson!.segments.any((s) => s.ruby.isNotEmpty);
    return Wrap(
      key: const ValueKey('study-display-options'),
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_mode != StudyMode.translation) ...[
          _displayToggle(
            key: const ValueKey('study-translation-toggle'),
            label: context.tr('译文'),
            tooltip: context.tr('显示中文译文'),
            value: _showTranslation,
            onChanged: (value) {
              setState(() => _showTranslation = value);
              _remember();
            },
          ),
        ],
        _displayToggle(
          key: const ValueKey('study-readings-toggle'),
          label: context.tr('假名'),
          tooltip: !hasReadings ? context.tr('本篇未提供假名标注') : context.tr('显示假名'),
          value: hasReadings && _showReadings,
          onChanged: !hasReadings
              ? null
              : (value) {
                  setState(() => _showReadings = value);
                  _remember();
                },
        ),
      ],
    );
  }

  Widget _displayToggle({
    required Key key,
    required String label,
    required String tooltip,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => Tooltip(
    message: tooltip,
    child: MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Switch.adaptive(
            key: key,
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );

  Widget _errorBanner(String message) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        context.trMessage(message),
        style: TextStyle(color: _colors.onErrorContainer),
      ),
    ),
  );

  Widget _emptyLibrary() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      children: [
        Icon(
          Icons.menu_book_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(context.tr('把材料变成自己的学习课'), style: TextStyle(fontSize: 23)),
        const SizedBox(height: 12),
        Text(
          context.tr('导入准备好的日语学习 ZIP 包\n包含日文、中文讲解、重点词和配套音频'),
          textAlign: TextAlign.center,
          style: TextStyle(color: _colors.onSurfaceVariant, height: 1.8),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.add),
          label: Text(context.tr('导入学习包')),
        ),
      ],
    ),
  );

  Future<String?> _pickStudyItem({
    required String title,
    required String? selectedId,
    required List<({String id, String label})> items,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    final route = ModalBottomSheetRoute<String>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final selected = item.id == selectedId;
                    return ListTile(
                      key: ValueKey('study-choice-${item.id}'),
                      selected: selected,
                      title: Text(item.label),
                      trailing: selected
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(item.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final selected = await navigator.push<String>(route);
    // A popped result arrives before the closing animation removes its scroll
    // tree. Keep that tree stable until the route has fully finished.
    await route.completed;
    return selected;
  }

  Future<String?> _pickLesson(
    InstalledStudyPackage installed, {
    String? selectedId,
  }) => _pickStudyItem(
    title: context.tr('选择篇目'),
    selectedId: selectedId,
    items: [
      for (final lesson in installed.package.lessons)
        (id: lesson.id, label: '${lesson.topic} · ${lesson.title}'),
    ],
  );

  Future<void> _selectPackage() async {
    final id = await _pickStudyItem(
      title: context.tr('选择学习资料'),
      selectedId: _installed?.package.packageId,
      items: [
        for (final package in _packages)
          (id: package.package.packageId, label: package.package.title),
      ],
    );
    if (!mounted || id == null || id == _installed?.package.packageId) return;
    final installed = _packages.firstWhere(
      (package) => package.package.packageId == id,
    );
    final lessonId = await _pickLesson(installed);
    if (!mounted || lessonId == null) return;
    await _run(() => _openPackage(installed, lessonId: lessonId));
  }

  Future<void> _selectLesson() async {
    final installed = _installed;
    if (installed == null) return;
    final id = await _pickLesson(installed, selectedId: _lesson?.id);
    if (!mounted || id == null || id == _lesson?.id) return;
    await _run(
      () => _openLesson(
        installed.package.lessons.firstWhere((lesson) => lesson.id == id),
      ),
    );
  }

  StudyLesson? _adjacentLesson(int offset) {
    final lessons = _installed?.package.lessons;
    if (lessons == null || _lesson == null) return null;
    final index = lessons.indexWhere((lesson) => lesson.id == _lesson!.id);
    final target = index + offset;
    return index < 0 || target < 0 || target >= lessons.length
        ? null
        : lessons[target];
  }

  void _stepLesson(int offset) {
    if (_loading) return;
    final lesson = _adjacentLesson(offset);
    if (lesson == null) return;
    unawaited(_run(() => _openLesson(lesson)));
  }

  Widget _lessonArrow(int offset, {bool side = false}) {
    final previous = offset < 0;
    final onPressed = _loading || _adjacentLesson(offset) == null
        ? null
        : () => _stepLesson(offset);
    final key = ValueKey(
      previous ? 'study-previous-lesson' : 'study-next-lesson',
    );
    final icon = Icon(
      previous ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      size: side ? 36 : 26,
    );
    final tooltip = previous ? context.tr('上一篇') : context.tr('下一篇');
    if (side) {
      return IconButton.filledTonal(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        constraints: const BoxConstraints.tightFor(width: 48, height: 64),
      );
    }
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    );
  }

  Widget _withLessonNavigation(Widget content) => LayoutBuilder(
    builder: (context, constraints) {
      if (_lesson == null ||
          constraints.maxWidth < _sideLessonNavigationWidth) {
        return content;
      }
      final inset = (constraints.maxWidth - 900) / 4 - 24;
      return Stack(
        key: const ValueKey('study-side-lesson-navigation'),
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            left: inset,
            top: 0,
            bottom: 0,
            child: Center(child: _lessonArrow(-1, side: true)),
          ),
          Positioned(
            right: inset,
            top: 0,
            bottom: 0,
            child: Center(child: _lessonArrow(1, side: true)),
          ),
        ],
      );
    },
  );

  Future<void> _selectStartPackage() async {
    final id = await _pickStudyItem(
      title: context.tr('选择学习资料'),
      selectedId: _selectionPackage?.package.packageId,
      items: [
        for (final package in _packages)
          (id: package.package.packageId, label: package.package.title),
      ],
    );
    if (!mounted || id == null || id == _selectionPackage?.package.packageId) {
      return;
    }
    setState(() {
      _selectionPackage = _packages.firstWhere(
        (package) => package.package.packageId == id,
      );
      _selectionLesson = null;
    });
  }

  Future<void> _selectStartLesson() async {
    final installed = _selectionPackage;
    if (installed == null) return;
    final id = await _pickLesson(installed, selectedId: _selectionLesson?.id);
    if (!mounted || id == null) return;
    setState(() {
      _selectionLesson = installed.package.lessons.firstWhere(
        (lesson) => lesson.id == id,
      );
    });
  }

  Future<void> _startLearning() async {
    final installed = _selectionPackage;
    final lesson = _selectionLesson;
    if (_loading || installed == null || lesson == null) return;
    await _run(() => _openPackage(installed, lessonId: lesson.id));
  }

  Widget _startSelection() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('选择学习内容'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('先选择学习资料和篇目，再开始学习。'),
          style: TextStyle(color: _colors.onSurfaceVariant, height: 1.6),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('study-start-package-picker'),
                title: Text(context.tr('学习资料')),
                subtitle: Text(
                  _selectionPackage?.package.title ?? context.tr('请选择学习资料'),
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: _loading ? null : _selectStartPackage,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('study-start-lesson-picker'),
                title: Text(context.tr('篇目')),
                subtitle: Text(
                  _selectionLesson == null
                      ? context.tr('请选择篇目')
                      : '${_selectionLesson!.topic} · ${_selectionLesson!.title}',
                ),
                trailing: const Icon(Icons.expand_more),
                enabled: !_loading && _selectionPackage != null,
                onTap: _selectStartLesson,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('study-start-button'),
            onPressed:
                !_loading &&
                    _selectionPackage != null &&
                    _selectionLesson != null
                ? _startLearning
                : null,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(context.tr('开始学习')),
          ),
        ),
      ],
    ),
  );

  Widget _studyNavigationBar() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 932),
      child: Padding(
        key: const ValueKey('study-navigation'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              if (MediaQuery.sizeOf(context).width < _sideLessonNavigationWidth)
                _lessonArrow(-1),
              Expanded(
                child: _navigationButton(
                  key: const ValueKey('study-package-picker'),
                  label: _installed!.package.title,
                  tooltip: context.tr('学习资料：{title}', {
                    'title': _installed!.package.title,
                  }),
                  onPressed: _selectPackage,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: _colors.outline),
              Expanded(
                child: _navigationButton(
                  key: const ValueKey('study-lesson-picker'),
                  label: '${_lesson!.topic} · ${_lesson!.title}',
                  tooltip: context.tr('篇目：{topic} · {title}', {
                    'topic': _lesson!.topic,
                    'title': _lesson!.title,
                  }),
                  onPressed: _selectLesson,
                ),
              ),
              if (MediaQuery.sizeOf(context).width < _sideLessonNavigationWidth)
                _lessonArrow(1),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _navigationButton({
    required Key key,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) => Tooltip(
    message: tooltip,
    child: TextButton(
      key: key,
      onPressed: _loading ? null : onPressed,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    ),
  );

  Widget _segmentCard(StudySegment segment, int index) {
    final showOriginal = _mode == StudyMode.read || _reveal;
    final prompts = practicePrompts(segment, _mode);
    return Card(
      shape:
          _playback.scope == StudyPlaybackScope.sentence &&
              _playback.selectedIndex == index
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _colors.primary),
            )
          : null,
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}${segment.speaker == null ? '' : ' · ${segment.speaker}'}',
                    style: TextStyle(
                      color: _colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_playback.timedSegmentIndexes.contains(index))
                  IconButton(
                    key: ValueKey('study-segment-play-${segment.id}'),
                    tooltip: context.tr('播放这一句'),
                    onPressed: !_audioReady || _loading
                        ? null
                        : () => _changePlayback(
                            () =>
                                _playback.selectSegment(index, autoplay: true),
                          ),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
              ],
            ),
            if (showOriginal)
              _originalText(segment)
            else if (_mode == StudyMode.keywords || _mode == StudyMode.partial)
              _maskedText(segment, prompts)
            else if (_mode == StudyMode.dictation)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  context.tr('原文已全部遮蔽'),
                  style: TextStyle(
                    color: _colors.onSurfaceVariant,
                    fontSize: 20,
                  ),
                ),
              ),
            if (_showTranslation || _mode == StudyMode.translation) ...[
              const SizedBox(height: 10),
              Text(
                segment.translationZh,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  color: _colors.onSurfaceVariant,
                ),
              ),
            ],
            if (_mode != StudyMode.read) ...[
              const SizedBox(height: 14),
              for (var i = 0; i < prompts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Focus(
                    onFocusChange: (focused) =>
                        _answerFocus(prompts[i].id, focused),
                    child: StudyAnswerInput(
                      key: ValueKey('draft-${prompts[i].id}'),
                      controller: _drafts.putIfAbsent(
                        prompts[i].id,
                        StudyAnswerController.new,
                      ),
                      expected: prompts[i].expected,
                      maxLines:
                          _mode == StudyMode.keywords ||
                              _mode == StudyMode.partial
                          ? 2
                          : 5,
                      labelText:
                          _mode == StudyMode.keywords ||
                              _mode == StudyMode.partial
                          ? context.tr('重点词 {number}（选填）', {'number': i + 1})
                          : context.tr('写下日文（选填）'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _originalText(StudySegment segment) => StudyPassageText(
    segment: segment,
    entries: {for (final entry in _installed!.package.entries) entry.id: entry},
    showReadings: _showReadings,
    onEntryTap: _entryDetails,
  );

  Widget _maskedText(StudySegment segment, List<PracticePrompt> prompts) {
    final spans = <InlineSpan>[];
    var offset = 0;
    for (var i = 0; i < prompts.length; i++) {
      final prompt = prompts[i];
      spans.add(TextSpan(text: segment.text.substring(offset, prompt.start)));
      spans.add(
        TextSpan(
          text: _mode == StudyMode.partial
              ? '〔${i + 1}: ${prompt.hint}〕'
              : '〔${i + 1}〕',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      offset = prompt.end;
    }
    spans.add(TextSpan(text: segment.text.substring(offset)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 23, height: 1.8),
    );
  }

  Widget _glossary() {
    final ids = {
      ..._lesson!.entryIds,
      ..._lesson!.segments.expand((s) => s.highlights).map((h) => h.entryId),
    };
    final entries = _installed!.package.entries.where(
      (e) => ids.contains(e.id),
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('本篇重点'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                ActionChip(
                  label: Text('${entry.surface} · ${entry.reading}'),
                  onPressed: () => _entryDetails(entry),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioBar() {
    final available = _canControlAudio;
    final sentence = _playback.scope == StudyPlaybackScope.sentence;
    final start = _audioReady && sentence ? _playback.unitStart : Duration.zero;
    final end = !_audioReady
        ? Duration.zero
        : sentence
        ? _playback.unitEnd
        : _audio.duration;
    final minimum = start.inMilliseconds.toDouble();
    final maximum = end.inMilliseconds.toDouble();
    final value =
        (_drag ??
                (_audioReady ? _audio.position.inMilliseconds.toDouble() : 0.0))
            .clamp(minimum, maximum > minimum ? maximum : minimum + 1);
    final indexes = _playback.timedSegmentIndexes;
    final selectedPosition = indexes.indexOf(_playback.selectedIndex);
    final count = _playback.repeatCount;
    final status = !_audioReady
        ? _lesson?.audioRef == null
              ? context.tr('本篇无配套音频')
              : context.tr('音频尚未就绪')
        : '${sentence ? context.tr('第 {current} / {total} 句', {'current': _playback.selectedIndex + 1, 'total': _lesson!.segments.length}) : context.tr('整段音频')} · '
              '${_playback.completed ? context.tr('已完成 {count} 遍', {'count': _playback.completedPasses}) : context.tr('已播 {completed}/{count} 遍', {'completed': _playback.completedPasses, 'count': count ?? '∞'})}';
    void changeScope(StudyPlaybackScope scope) {
      final resume = _audio.playing;
      unawaited(
        _changePlayback(() => _playback.setScope(scope, autoplay: resume)),
      );
    }

    final scopeHint = _audioReady && !_playback.canPlaySentence
        ? context.tr('未提供逐句时间点，可用快捷键播放／暂停。')
        : context.tr('整段／逐句播放');
    final restart = available ? () => _audioAction(_playback.restart) : null;
    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('study-audio-bar'),
        color: _colors.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_audio.error != null)
                Text(
                  context.trMessage(_audio.error!),
                  style: TextStyle(color: _colors.error),
                  maxLines: 2,
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  return Row(
                    key: const ValueKey('study-audio-controls'),
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (compact)
                              SizedBox(
                                width: 32,
                                child: PopupMenuButton<String>(
                                  key: const ValueKey('study-playback-scope'),
                                  tooltip: context.tr('播放范围 · {scope}', {
                                    'scope': sentence
                                        ? context.tr('逐句')
                                        : context.tr('整段'),
                                  }),
                                  padding: EdgeInsets.zero,
                                  initialValue: _playback.scope.name,
                                  enabled: available,
                                  icon: Icon(
                                    sentence ? Icons.short_text : Icons.subject,
                                    size: 20,
                                  ),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'passage',
                                      enabled: _audioReady,
                                      child: Text(context.tr('整段')),
                                    ),
                                    PopupMenuItem(
                                      value: 'sentence',
                                      enabled:
                                          _audioReady &&
                                          _playback.canPlaySentence,
                                      child: Text(context.tr('逐句')),
                                    ),
                                    const PopupMenuDivider(),
                                    PopupMenuItem(
                                      value: 'restart',
                                      enabled: available,
                                      child: Text(context.tr('从头播放')),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'restart') {
                                      unawaited(
                                        _audioAction(_playback.restart),
                                      );
                                    } else {
                                      changeScope(
                                        StudyPlaybackScope.values.byName(value),
                                      );
                                    }
                                  },
                                ),
                              )
                            else
                              Tooltip(
                                message: scopeHint,
                                child: SegmentedButton<StudyPlaybackScope>(
                                  key: const ValueKey('study-playback-scope'),
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: [
                                    ButtonSegment(
                                      value: StudyPlaybackScope.passage,
                                      label: Text(context.tr('整段')),
                                      icon: const Icon(Icons.subject, size: 17),
                                      enabled: _audioReady,
                                    ),
                                    ButtonSegment(
                                      value: StudyPlaybackScope.sentence,
                                      label: Text(context.tr('逐句')),
                                      icon: const Icon(
                                        Icons.short_text,
                                        size: 17,
                                      ),
                                      enabled:
                                          _audioReady &&
                                          _playback.canPlaySentence,
                                    ),
                                  ],
                                  selected: {_playback.scope},
                                  onSelectionChanged: !available
                                      ? null
                                      : (selection) =>
                                            changeScope(selection.single),
                                ),
                              ),
                            SizedBox(width: compact ? 0 : 12),
                            Tooltip(
                              message: context.tr('循环次数 · {status}', {
                                'status': status,
                              }),
                              child: OutlinedButton.icon(
                                key: const ValueKey('study-repeat-count'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size(compact ? 56 : 0, 36),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 4 : 12,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 12),
                                  visualDensity: VisualDensity.compact,
                                  iconSize: compact ? 15 : 18,
                                ),
                                onPressed: available
                                    ? _chooseRepeatCount
                                    : null,
                                icon: const Icon(Icons.repeat_rounded),
                                label: Text(
                                  compact
                                      ? '${count ?? '∞'}'
                                      : count == null
                                      ? context.tr('无限')
                                      : context.tr('{count} 遍', {
                                          'count': count,
                                        }),
                                ),
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 36,
                                child: IconButton(
                                  tooltip: context.tr('从头播放'),
                                  onPressed: restart,
                                  icon: const Icon(Icons.replay_rounded),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Semantics(
                        label: status,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: context.tr('上一句'),
                                onPressed:
                                    available &&
                                        sentence &&
                                        selectedPosition > 0
                                    ? () {
                                        final resume = _audio.playing;
                                        unawaited(
                                          _changePlayback(
                                            () => _playback.previous(
                                              autoplay: resume,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: IconButton.filled(
                                key: const ValueKey('study-play-pause'),
                                tooltip: _audio.playing
                                    ? context.tr('暂停学习音频')
                                    : context.tr('播放学习音频'),
                                onPressed: available
                                    ? () => _audioAction(_playback.toggle)
                                    : null,
                                icon: Icon(
                                  _audio.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 32,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: context.tr('下一句'),
                                onPressed:
                                    available &&
                                        sentence &&
                                        selectedPosition >= 0 &&
                                        selectedPosition < indexes.length - 1
                                    ? () {
                                        final resume = _audio.playing;
                                        unawaited(
                                          _changePlayback(
                                            () => _playback.next(
                                              autoplay: resume,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!_audioReady &&
                                !_loading &&
                                _lesson?.audioRef != null)
                              SizedBox(
                                width: 32,
                                child: IconButton(
                                  tooltip: context.tr('重新载入音频'),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _run(_loadAudio),
                                  icon: const Icon(Icons.refresh, size: 20),
                                ),
                              ),
                            DropdownButton<double>(
                              key: const ValueKey('study-playback-rate'),
                              value: _rate,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final rate in [
                                  0.5,
                                  0.75,
                                  1.0,
                                  1.25,
                                  1.5,
                                  2.0,
                                ])
                                  DropdownMenuItem(
                                    value: rate,
                                    child: Text(
                                      '$rate×',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                              ],
                              onChanged: !available
                                  ? null
                                  : (value) => _audioAction(() async {
                                      if (value == null) return;
                                      await _audio.setRate(value);
                                      if (!mounted) return;
                                      setState(() => _rate = value);
                                      await _saveProgress();
                                    }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              Row(
                children: [
                  Text(
                    _time(Duration(milliseconds: (value - minimum).round())),
                    style: const TextStyle(fontSize: 11),
                  ),
                  Expanded(
                    child: StableSlider(
                      value: value,
                      min: minimum,
                      max: maximum > minimum ? maximum : minimum + 1,
                      onChanged: available && maximum > minimum
                          ? (value) => setState(() => _drag = value)
                          : null,
                      onChangeEnd: (value) => _changePlayback(() async {
                        await _playback.seek(
                          Duration(milliseconds: value.round()),
                        );
                      }),
                    ),
                  ),
                  Text(
                    _time(end - start),
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _time(Duration time) =>
    '${time.inMinutes.toString().padLeft(2, '0')}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

class _EntryEdits {
  const _EntryEdits(this.attributes, this.note);
  final Map<String, String> attributes;
  final String note;
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.attributes, required this.note});
  final Map<String, String> attributes;
  final String note;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _rows = [
    for (final entry in widget.attributes.entries)
      (
        TextEditingController(text: entry.key),
        TextEditingController(text: entry.value),
      ),
  ];
  final _retiredRows = <(TextEditingController, TextEditingController)>[];
  late final _note = TextEditingController(text: widget.note);
  String? _error;

  void _removeAttribute((TextEditingController, TextEditingController) row) {
    setState(() {
      if (!_rows.remove(row)) return;
      // Keep controllers alive until their TextFields have left the route.
      _retiredRows.add(row);
      _error = null;
    });
  }

  @override
  void dispose() {
    for (final row in [..._rows, ..._retiredRows]) {
      row.$1.dispose();
      row.$2.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('属性与笔记')),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in _rows)
              Padding(
                key: ObjectKey(row.$1),
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: row.$1,
                        decoration: InputDecoration(
                          labelText: context.tr('属性名'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: row.$2,
                        decoration: InputDecoration(
                          labelText: context.tr('内容'),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('删除属性'),
                      onPressed: () => _removeAttribute(row),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => _rows.add((
                    TextEditingController(),
                    TextEditingController(),
                  )),
                ),
                icon: const Icon(Icons.add),
                label: Text(context.tr('添加属性')),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr('我的笔记'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                context.trMessage(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('取消')),
      ),
      FilledButton(
        onPressed: () {
          final attributes = <String, String>{};
          for (final row in _rows) {
            final key = row.$1.text.trim(), value = row.$2.text.trim();
            if (key.isEmpty && value.isEmpty) continue;
            if (key.isEmpty || value.isEmpty || attributes.containsKey(key)) {
              setState(() => _error = '请填写完整属性，且属性名不能重复。');
              return;
            }
            attributes[key] = value;
          }
          Navigator.pop(context, _EntryEdits(attributes, _note.text.trim()));
        },
        child: Text(context.tr('保存')),
      ),
    ],
  );
}
