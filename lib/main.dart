import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide PlaylistMode;
import 'package:media_kit_video/media_kit_video.dart';

import 'accessibility/stable_semantics_binding.dart';
import 'library/local_library.dart';
import 'library/local_state.dart';
import 'library/media_history.dart';
import 'library/playlist_import.dart';
import 'library/playlist_mode.dart';
import 'l10n/app_language.dart';
import 'l10n/app_localizations.dart';
import 'navigation/app_home_back_button.dart';
import 'navigation/app_navigation.dart';
import 'navigation/app_section_menu_button.dart';
import 'navigation/good_good_study_shell.dart';
import 'phone/phone_player_page.dart';
import 'playback/offline_playback.dart';
import 'playback/media_metadata.dart';
import 'playback/media_tracks.dart';
import 'playback/player_time.dart';
import 'quiz/quiz_page.dart';
import 'quiz/quiz_store.dart';
import 'subtitles/subtitles.dart';
import 'subtitles/subtitle_visibility.dart';
import 'study/study_page.dart';
import 'study/study_store.dart';
import 'support/project_licenses.dart';
import 'sync/resource_sync_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/stable_slider.dart';
import 'widgets/player_subtitles.dart';
import 'widgets/player_playlist.dart';
import 'widgets/player_shortcuts.dart';
import 'widgets/player_track_sheet.dart';

Future<void> main() async {
  StableSemanticsBinding.ensureInitialized();
  registerProjectLicense();
  final themeController = AppThemeController();
  final languageController = AppLanguageController();
  late final ResourceSyncController syncController;
  final navigationController = AppNavigationController(
    beforeEnter: () => syncController.applyPending(),
  );
  final studyStore = StudyStore(
    onCommitted: () => syncController.localChanged(),
  );
  final quizStore = QuizStore(onCommitted: () => syncController.localChanged());
  syncController = ResourceSyncController(
    study: studyStore,
    quiz: quizStore,
    canApplyRemote: () =>
        !navigationController.isModuleMounted ||
        navigationController.section == AppSection.home,
  );
  await syncController.initialize();
  navigationController.addListener(syncController.navigationChanged);
  await themeController.load();
  await languageController.load();
  await navigationController.load();
  if (!Platform.isIOS) MediaKit.ensureInitialized();
  runApp(
    OfflinePlayerApp(
      themeController: themeController,
      languageController: languageController,
      navigationController: navigationController,
      studyStore: studyStore,
      quizStore: quizStore,
      syncController: syncController,
    ),
  );
}

class OfflinePlayerApp extends StatelessWidget {
  const OfflinePlayerApp({
    super.key,
    required this.themeController,
    required this.languageController,
    required this.navigationController,
    required this.studyStore,
    required this.quizStore,
    required this.syncController,
  });
  final AppThemeController themeController;
  final AppLanguageController languageController;
  final AppNavigationController navigationController;
  final StudyStore studyStore;
  final QuizStore quizStore;
  final ResourceSyncController syncController;

  @override
  Widget build(BuildContext context) => ResourceSyncScope(
    controller: syncController,
    child: AppThemeScope(
      controller: themeController,
      child: AppLanguageScope(
        controller: languageController,
        child: Builder(
          builder: (context) => MaterialApp(
            title: 'GoodGoodStudy',
            locale: AppLanguageScope.of(context).locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationDelegates,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: AppThemeScope.of(context).themeMode,
            home: GoodGoodStudyShell(
              controller: navigationController,
              phonePlayback: Platform.isIOS,
              builders: {
                AppSection.study: (_) => StudyPage(store: studyStore),
                AppSection.quiz: (_) =>
                    QuizPage(store: quizStore, restoreLastLocation: true),
                AppSection.player: (_) => Platform.isIOS
                    ? const PhonePlayerPage()
                    : const PlayerPage(),
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    this.playback,
    this.stateStore,
    this.videoSurface,
    this.trackController,
    this.scanMedia,
  });
  final OfflinePlayback? playback;
  final LocalStateStore? stateStore;
  final Widget? videoSurface;
  final MediaTracksController? trackController;
  final LocalMediaScanner? scanMedia;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
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
    if (_loading || _importing || _exiting) return false;
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    _scanCancellation?.cancel();
    await _mediaOperations;
    if (_fullScreen) await _setFullScreen(false);
    await _playback.pause();
    _save();
    await _store.flush();
    return true;
  }

  static const _files = MethodChannel('offline_player/local_files');
  late final _playback = widget.playback ?? OfflinePlayback();
  late final _store = widget.stateStore ?? LocalStateStore();
  late final MediaTracksController? _tracks =
      widget.trackController ??
      (widget.playback == null
          ? MediaTracksController(_playback.player)
          : null);
  MediaHistory _history = MediaHistory();
  late final MediaMetadataReader? _metadata = widget.playback == null
      ? MediaMetadataReader(onDuration: _receivedDuration)
      : null;
  final Map<String, String> _invalidMedia = {};
  final Map<String, MediaTrackPreferences> _trackPreferencesByPath = {};
  bool _stateReady = false;
  bool _exiting = false;
  Future<AppExitResponse>? _exitRequest;
  String? _stateWarning;
  String? _restoreCurrentPath;
  Duration _restorePosition = Duration.zero;
  final _subtitleScroll = ScrollController();
  final _stageKey = const ValueKey('player-stage');
  late final VideoController _video = VideoController(_playback.player);
  List<LocalLesson> _lessons = [];
  List<SubtitleCue> _cues = [];
  LocalLesson? _lesson;
  String? _subtitlePath;
  String? _message;
  bool _loading = false;
  bool _importing = false;
  MediaScanCancellation? _scanCancellation;
  MediaScanProgress? _scanProgress;
  bool _draggingFiles = false;
  bool _fullScreen = false;
  bool _fullScreenChanging = false;
  bool? _pendingFullScreen;
  bool _showPlaylist = true;
  PlaylistMode _playlistMode = PlaylistMode.sequential;
  bool _muted = false;
  double _lastAudibleVolume = 65;
  String? _completedIdentity;
  bool _chromeVisible = true;
  bool _hoveringChrome = false;
  bool _keyboardChrome = false;
  int _overlayDepth = 0;
  TransitionRoute<dynamic>? _speedMenuRoute;
  PopupRoute<dynamic>? _passesMenuRoute;
  PopupRoute<dynamic>? _sleepMenuRoute;
  Timer? _chromeTimer;
  Object? _lastPlaybackSignature;
  int _lastCompletion = 0;
  String? _pendingCompletionFor;
  int _autoplayEpoch = 0;
  Timer? _fullScreenSyncTimer;
  Future<void> _mediaOperations = Future.value();
  SubtitleVisibility _subtitleVisibility = const SubtitleVisibility();
  bool _showReadings = true;
  bool _hasReadings = false;
  bool _follow = true;
  bool _audioMode = false;
  double _fontSize = 27;
  double _subtitleBottom = 0.1;
  double _volume = 65;
  double? _dragPosition;
  Duration _offset = Duration.zero;
  Duration? _pointA;
  int? _passes;
  int? _lastCueIndex;
  Timer? _saveTimer;
  Timer? _stopTimer;
  DateTime? _stopAt;

  bool get _ready =>
      _lesson != null &&
      _playback.localPath != null &&
      !_exiting &&
      !_loading &&
      !_playback.busy;
  int get _playlistIndex => _lessons.indexWhere(
    (lesson) => lesson.primaryPath == _lesson?.primaryPath,
  );
  SubtitleCue? get _current =>
      cueAt(_cues, _playback.position, offset: _offset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.addListener(_changed);
    _tracks?.addListener(_tracksChanged);
    _files.setMethodCallHandler(_handleNativeCall);
    unawaited(_enqueueMedia(_restore));
    if (Platform.isMacOS) unawaited(_readFullScreen());
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _save();
      _advanceAfterCompletion();
    });
  }

  Future<void> _applyVolume() async {
    if (widget.playback == null) {
      await _playback.player.setVolume(_muted ? 0 : _volume);
    }
  }

  void _recordHistory({bool? completed}) {
    final lesson = _lesson;
    final path = _playback.localPath;
    if (lesson == null ||
        path == null ||
        (path != lesson.videoPath && path != lesson.audioPath)) {
      return;
    }
    final tracks = _tracks?.preferences;
    if (tracks != null) _trackPreferencesByPath[path] = tracks;
    _history.record(
      lesson,
      position: _playback.position,
      duration: _playback.duration,
      completed:
          completed ??
          (_completedIdentity == lesson.identity && !_playback.playing
              ? true
              : null),
      subtitlePath: _subtitlePath,
      offset: _offset,
      audioTrackId: tracks?.audioId,
      subtitleTrackId: tracks?.subtitleId,
      subtitleSource: tracks?.subtitleSource.name,
    );
  }

  void _tracksChanged() {
    if (!mounted || _exiting) return;
    if (!_loading) _save();
    setState(() {});
  }

  void _suspendMetadata() => _metadata?.setSuspended(
    _exiting || !_stateReady || _playback.playing || _loading || _importing,
  );

  void _syncMetadataQueue() {
    _suspendMetadata();
    _metadata?.updateQueue(
      _lessons.where(
        (lesson) => !(_history.getForLesson(lesson)?.hasDuration ?? false),
      ),
    );
  }

  void _receivedDuration(LocalLesson lesson, Duration duration) {
    if (!mounted ||
        _exiting ||
        !_lessons.any(
          (item) =>
              item.identity == lesson.identity &&
              item.primaryPath == lesson.primaryPath,
        )) {
      return;
    }
    final saved = _history.getForLesson(lesson);
    if (saved?.hasDuration ?? false) return;
    _history.record(
      lesson,
      position: saved?.position ?? Duration.zero,
      duration: duration,
      completed: saved?.completed ?? false,
    );
    setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_exiting) return;
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _enqueueMedia(Future<void> Function() action) {
    if (_exiting) return Future.value();
    final next = _mediaOperations.then((_) async {
      if (!mounted || _exiting) return;
      try {
        await action();
      } finally {
        if (mounted) {
          _syncMetadataQueue();
          _save();
          _advanceAfterCompletion();
        }
      }
    });
    _mediaOperations = _run(() => next);
    return _mediaOperations;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted || _exiting) return;
    switch (call.method) {
      case 'filesDropped':
        setState(() => _draggingFiles = false);
        if (ModalRoute.of(context)?.isCurrent != true) return;
        final arguments = call.arguments;
        final paths = arguments is Map ? arguments['paths'] : arguments;
        if (paths is List) {
          await _importPaths(
            paths.whereType<String>().toList(),
            fromDrop: true,
          );
        }
      case 'dragStateChanged':
        setState(() => _draggingFiles = call.arguments == true);
      case 'fullScreenChanged':
        _fullScreenSyncTimer?.cancel();
        _pendingFullScreen = call.arguments == true;
        _fullScreenChanging = false;
        _commitPendingFullScreen();
      case 'dropFailed':
        setState(() {
          _draggingFiles = false;
          _message = '无法读取拖入的文件：${call.arguments}';
        });
    }
  }

  Future<void> _readFullScreen() => _run(() async {
    final fullScreen = await _files.invokeMethod<bool>('getFullScreen');
    if (mounted) {
      _pendingFullScreen = fullScreen ?? false;
      _commitPendingFullScreen();
    }
  });

  void _commitPendingFullScreen() {
    if (!mounted ||
        _pendingFullScreen == null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final enabled = _pendingFullScreen!;
    _pendingFullScreen = null;
    setState(() {
      _fullScreen = enabled;
      _fullScreenChanging = false;
      _chromeVisible = true;
      _hoveringChrome = false;
      _keyboardChrome = false;
    });
    _armChromeTimer();
  }

  Future<void> _setFullScreen(bool enabled) => _run(() async {
    if (_fullScreenChanging || _fullScreen == enabled) return;
    if (Tooltip.dismissAllToolTips()) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    setState(() => _fullScreenChanging = true);
    try {
      await _files.invokeMethod<void>('setFullScreen', {'enabled': enabled});
      _fullScreenSyncTimer?.cancel();
      _fullScreenSyncTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _fullScreenChanging = false);
        unawaited(_readFullScreen());
      });
    } catch (_) {
      if (mounted) setState(() => _fullScreenChanging = false);
      rethrow;
    }
  });

  Future<void> _study() => _run(() async {
    if (_navigation case final navigation?) {
      await navigation.navigate(AppSection.study);
      return;
    }
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    await _playback.pause();
    _save();
    if (!mounted) return;
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const StudyPage()));
  });

  Future<void> _quiz() => _run(() async {
    if (_navigation case final navigation?) {
      await navigation.navigate(AppSection.quiz);
      return;
    }
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    await _playback.pause();
    _save();
    if (!mounted) return;
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const QuizPage()));
  });

  Future<void> _remember(List<String> paths) async {
    if (Platform.isMacOS) {
      await _files.invokeMethod<void>('rememberPaths', paths);
    }
  }

  Future<void> _restore() async {
    _stateReady = false;
    Map<String, dynamic>? data;
    try {
      data = await _store.read();
      if (!mounted) return;
      _history = MediaHistory.fromJson(data);
      if (data != null) {
        _lessons = mergePlaylist(
          const [],
          (data['lessons'] as List<dynamic>? ?? []).map(
            (e) => LocalLesson.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );
        _fontSize = (data['fontSize'] as num? ?? 27).toDouble();
        _subtitleBottom = (data['subtitleBottom'] as num? ?? 0.1).toDouble();
        _offset = Duration(milliseconds: data['offsetMs'] as int? ?? 0);
        _subtitleVisibility = SubtitleVisibility.fromJson(data);
        _showReadings = data['showReadings'] as bool? ?? true;
        _audioMode = data['audioMode'] as bool? ?? false;
        _showPlaylist = data['showPlaylist'] as bool? ?? true;
        _playlistMode = PlaylistMode.fromJson(
          data['playlistMode'],
          legacyAutoAdvance: data['autoAdvance'] as bool? ?? true,
        );
        _volume = (data['volume'] as num? ?? 65).toDouble();
        if (_volume > 0) _lastAudibleVolume = _volume;
        _muted = data['muted'] == true;
        _restoreCurrentPath = data['current'] as String?;
        _restorePosition = Duration(
          milliseconds: data['positionMs'] as int? ?? 0,
        );
        final preferences = data['mediaTrackPreferences'];
        if (preferences is Map) {
          for (final entry in preferences.entries) {
            if (entry.key is String && entry.value is Map) {
              _trackPreferencesByPath[entry.key
                  as String] = MediaTrackPreferences.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            }
          }
        }
      }
      _stateReady = _store.canWrite;
      _stateWarning = _store.recoveryMessage;
    } catch (error) {
      if (mounted) setState(() => _stateWarning = '$error');
      return;
    }
    try {
      if (Platform.isMacOS) {
        await _files.invokeMethod<List<dynamic>>('restorePaths');
      }
      await _applyVolume();
      await _playback.setRate((data?['rate'] as num? ?? 1).toDouble());
      for (final lesson in _lessons) {
        if (lesson.primaryPath == _restoreCurrentPath ||
            lesson.audioPath == _restoreCurrentPath) {
          await _openLesson(
            lesson,
            position: _history.resumePosition(lesson),
            subtitleOverride: data?['subtitlePath'] as String?,
          );
          break;
        }
      }
    } catch (error) {
      _message = '媒体暂时无法恢复，可在列表中重新定位：$error';
    }
    if (mounted) setState(() {});
  }

  void _save() {
    if (_loading || !_stateReady || !_store.canWrite) return;
    _recordHistory();
    unawaited(
      _store
          .write({
            'lessons': _lessons.map((e) => e.toJson()).toList(),
            'current': _lesson?.primaryPath ?? _restoreCurrentPath,
            'subtitlePath': _subtitlePath,
            'positionMs':
                (_lesson == null ? _restorePosition : _playback.position)
                    .inMilliseconds,
            'durationMs': _playback.duration.inMilliseconds,
            'rate': _playback.rate,
            'offsetMs': _offset.inMilliseconds,
            'fontSize': _fontSize,
            'subtitleBottom': _subtitleBottom,
            ..._subtitleVisibility.toJson(),
            'showReadings': _showReadings,
            'audioMode': _audioMode,
            'showPlaylist': _showPlaylist,
            'autoAdvance': _playlistMode.autoAdvance,
            'playlistMode': _playlistMode.name,
            'volume': _volume,
            'muted': _muted,
            'mediaHistory': _history.toJson(),
            'mediaTrackPreferences': {
              for (final entry in _trackPreferencesByPath.entries)
                entry.key: entry.value.toJson(),
            },
          })
          .catchError((Object error) {
            if (mounted) setState(() => _message = '保存进度失败：$error');
          }),
    );
  }

  void _setSubtitleVisibility(SubtitleVisibility value) {
    setState(() => _subtitleVisibility = value);
    _save();
  }

  void _changed() {
    if (!mounted || _exiting) return;
    _suspendMetadata();
    if (_lastCompletion != _playback.completedCount) {
      _lastCompletion = _playback.completedCount;
      _completedIdentity = _lesson?.identity;
      _recordHistory(completed: true);
      _save();
      _pendingCompletionFor = _lesson?.identity;
      _advanceAfterCompletion();
    }
    if (_playback.playing &&
        _completedIdentity == _lesson?.identity &&
        _playback.position < _playback.duration) {
      _completedIdentity = null;
    }
    final index = _current?.index;
    final cueChanged = index != _lastCueIndex;
    if (cueChanged) {
      _lastCueIndex = index;
      if (_follow && index != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _subtitleScroll.hasClients) {
            _subtitleScroll.animateTo(
              (index * 104.0 - 104).clamp(
                0,
                _subtitleScroll.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
    final signature = (
      _playback.playing,
      _playback.buffering,
      _playback.busy,
      _playback.error,
      _playback.duration,
      _playback.localPath,
      _playback.rate,
      _playback.loop?.completedPasses,
      _playback.loop?.start,
      _playback.loop?.end,
    );
    if (cueChanged || signature != _lastPlaybackSignature) {
      _lastPlaybackSignature = signature;
      if (!_playback.playing) {
        _revealChrome();
      } else {
        _armChromeTimer();
      }
      setState(() {});
    }
  }

  void _beginImport() {
    _scanCancellation = MediaScanCancellation();
    setState(() {
      _importing = true;
      _scanProgress = null;
    });
    _suspendMetadata();
    _revealChrome();
  }

  void _finishImport() {
    _scanCancellation = null;
    if (mounted) {
      setState(() {
        _importing = false;
        _scanProgress = null;
      });
    }
    _armChromeTimer();
    _syncMetadataQueue();
  }

  Future<void> _openFolder() => _run(() async {
    if (_importing) return;
    _beginImport();
    try {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: context.tr("选择包含音视频和字幕的文件夹"),
      );
      if (directory == null || !mounted) return;
      await _remember([directory]);
      await _scanAndImport([directory]);
    } finally {
      _finishImport();
    }
  });

  Future<void> _openFiles() => _run(() async {
    if (_importing) return;
    _beginImport();
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: context.tr("选择音视频及同名 SRT / VTT，可多选"),
        type: FileType.custom,
        allowedExtensions: [
          ...audioExtensions,
          ...videoExtensions,
          ...subtitleExtensions,
        ],
      );
      if (result.isEmpty || !mounted) return;
      final paths = result
          .map((file) => file.path)
          .whereType<String>()
          .toList();
      await _remember(paths);
      await _scanAndImport(paths);
    } finally {
      _finishImport();
    }
  });

  Future<void> _importPaths(List<String> paths, {bool fromDrop = false}) =>
      _run(() async {
        if (_importing) {
          setState(() => _message = '正在导入文件，可先完成或取消本次扫描。');
          return;
        }
        _beginImport();
        try {
          await _scanAndImport(paths, fromDrop: fromDrop);
        } finally {
          _finishImport();
        }
      });

  Future<void> _scanAndImport(
    List<String> paths, {
    bool fromDrop = false,
  }) async {
    final autoplayEpoch = _autoplayEpoch;
    final cancellation = _scanCancellation;
    final scan = await (widget.scanMedia ?? scanLocalMedia)(
      paths,
      cancellation: cancellation,
      includeCompanions: true,
      onProgress: (progress) {
        if (mounted) setState(() => _scanProgress = progress);
      },
    );
    if (!mounted || scan.cancelled || cancellation?.cancelled == true) return;
    if (scan.lessons.isEmpty) {
      setState(() => _message = '没有找到可播放的音视频。字幕请在打开媒体后通过“载入字幕”选择。');
      return;
    }
    await _enqueueMedia(() async {
      if (cancellation?.cancelled == true) return;
      final previousLength = _lessons.length;
      setState(() {
        _lessons = mergePlaylist(
          _lessons,
          scan.lessons,
          preferredMediaPath: fromDrop ? scan.directMediaPath : null,
        );
        final current = _lesson;
        if (current != null) {
          _lesson = _lessons.firstWhere(
            (lesson) => lesson.identity == current.identity,
          );
        }
        _showPlaylist = true;
        _message = scan.unreadablePaths.isEmpty
            ? null
            : '已添加可读取的媒体，${scan.unreadablePaths.length} 个路径无法读取。';
      });
      if (fromDrop &&
          scan.directMediaPath != null &&
          autoplayEpoch == _autoplayEpoch) {
        final path = scan.directMediaPath!;
        final identity = MediaHistory.keyForPath(path);
        final lesson = _lessons.firstWhere(
          (lesson) => lesson.identity == identity,
        );
        await _openLesson(
          lesson,
          autoplay: true,
          preferAudio: lesson.audioPath == path,
          autoplayEpoch: autoplayEpoch,
        );
      } else if (!fromDrop && _lesson == null) {
        await _openLesson(
          _lessons.firstWhere(
            (lesson) => lesson.identity == scan.lessons.first.identity,
          ),
        );
      }
      if (mounted) {
        final added = _lessons.length - previousLength;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Builder(
              builder: (context) => Text(
                added > 0
                    ? context.tr("已添加 {p0} 项到播放列表", {'p0': added})
                    : context.tr("这些媒体已在播放列表中"),
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _selectAdjacent(int offset, {bool? autoplay}) async {
    final index = _playlistIndex;
    final target = index + offset;
    if (_loading || index < 0 || target < 0 || target >= _lessons.length) {
      return;
    }
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    final lesson = _lessons[target];
    final shouldPlay = autoplay ?? _playback.playing;
    final epoch = _autoplayEpoch;
    await _enqueueMedia(
      () => _openLesson(lesson, autoplay: shouldPlay, autoplayEpoch: epoch),
    );
  }

  void _advanceAfterCompletion() {
    if (_exiting) return;
    _commitPendingFullScreen();
    if (_loading || _pendingCompletionFor == null) return;
    final identity = _pendingCompletionFor;
    if (_lesson?.identity != identity) {
      _pendingCompletionFor = null;
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _pendingCompletionFor = null;
    final index = _playlistIndex;
    final target = _playlistMode.nextIndex(index, _lessons.length);
    if (target == null) return;
    final epoch = _autoplayEpoch;
    unawaited(
      _enqueueMedia(() async {
        var candidate = target;
        final visited = <int>{};
        final failed = <String>[];
        while (mounted && visited.add(candidate) && epoch == _autoplayEpoch) {
          final lesson = _lessons[candidate];
          try {
            await _openLesson(
              lesson,
              autoplay: true,
              autoplayEpoch: epoch,
              restart: candidate == index,
            );
            if (failed.isNotEmpty && mounted) {
              setState(
                () => _message = '已跳过 ${failed.length} 项无法播放的媒体，可在列表中重新定位。',
              );
            }
            return;
          } catch (_) {
            failed.add(lesson.title);
            if (_playlistMode == PlaylistMode.repeatOne) break;
            final next = _playlistMode.nextIndex(candidate, _lessons.length);
            if (next == null) break;
            candidate = next;
          }
        }
        if (mounted && failed.isNotEmpty) {
          setState(() => _message = '无法继续连播：${failed.join('、')}。可在列表中重新定位或移除。');
        }
      }),
    );
  }

  void _setPlaylistMode(PlaylistMode mode) {
    setState(() {
      _playlistMode = mode;
    });
    _save();
    _advanceAfterCompletion();
  }

  Future<void> _selectLesson(LocalLesson lesson, {bool restart = false}) {
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    final epoch = _autoplayEpoch;
    return _enqueueMedia(
      () => _openLesson(
        lesson,
        autoplay: true,
        restart: restart,
        autoplayEpoch: epoch,
      ),
    );
  }

  Future<void> _afterSpeedMenu(Future<void> Function() action) async {
    final route = _speedMenuRoute;
    if (route != null) await route.completed;
    if (!mounted) return;
    _overlayDepth--;
    await _run(action);
    _armChromeTimer();
    _advanceAfterCompletion();
  }

  void _watchMenuCancellation(PopupRoute<dynamic> route) {
    unawaited(() async {
      final value = await route.popped;
      await route.completed;
      if (mounted && value == null) _advanceAfterCompletion();
    }());
  }

  Future<void> _setPassesAfterMenu(int? value) async {
    final route = _passesMenuRoute;
    if (route != null) await route.completed;
    if (!mounted) return;
    setState(() => _passes = value == 0 ? null : value);
    _advanceAfterCompletion();
  }

  Future<void> _setStopAfterMenu(int minutes) async {
    final route = _sleepMenuRoute;
    if (route != null) await route.completed;
    if (!mounted) return;
    _setStopTimer(minutes);
    _advanceAfterCompletion();
  }

  PlaylistItemStatus _playlistStatus(LocalLesson lesson) {
    final saved = _history.getForLesson(lesson);
    final active =
        _lesson?.identity == lesson.identity &&
        _playback.localPath != null &&
        (_playback.localPath == lesson.videoPath ||
            _playback.localPath == lesson.audioPath);
    return PlaylistItemStatus(
      position: active ? _playback.position : saved?.position ?? Duration.zero,
      duration: active ? _playback.duration : saved?.duration ?? Duration.zero,
      completed: saved?.completed ?? false,
      error: _invalidMedia[lesson.identity],
    );
  }

  Future<void> _removeLesson(LocalLesson lesson) {
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    return _enqueueMedia(() async {
      final index = _lessons.indexWhere(
        (item) => item.identity == lesson.identity,
      );
      if (index < 0) return;
      final current = lesson.primaryPath == _lesson?.primaryPath;
      final wasPlaying = _playback.playing;
      if (current && _lessons.length == 1) {
        _recordHistory();
        await _playback.clearMedia();
        if (!mounted) return;
        _lessons = [];
        _clearCurrent();
        return;
      }
      if (current) await _playback.pause();
      if (!mounted) return;
      setState(() {
        _lessons = [..._lessons]..removeAt(index);
      });
      if (!current) return;
      if (_lessons.isNotEmpty) {
        await _openLesson(
          _lessons[index.clamp(0, _lessons.length - 1)],
          autoplay: wasPlaying,
        );
      }
    });
  }

  Future<void> _clearPlaylist() {
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    return _enqueueMedia(() async {
      _recordHistory();
      await _playback.clearMedia();
      if (!mounted) return;
      setState(() => _lessons = []);
      _clearCurrent();
    });
  }

  void _clearCurrent() {
    _recordHistory();
    _completedIdentity = null;
    _pendingCompletionFor = null;
    _restoreCurrentPath = null;
    _restorePosition = Duration.zero;
    _playback.clearLoop();
    setState(() {
      _lesson = null;
      _cues = [];
      _subtitlePath = null;
      _hasReadings = false;
      _pointA = null;
      _dragPosition = null;
    });
  }

  void _reorderPlaylist(int oldIndex, int newIndex) {
    setState(() {
      final reordered = [..._lessons];
      reordered.insert(newIndex, reordered.removeAt(oldIndex));
      _lessons = reordered;
    });
    _save();
  }

  Future<void> _openLesson(
    LocalLesson lesson, {
    Duration? position,
    String? subtitleOverride,
    bool autoplay = false,
    bool? preferAudio,
    int? autoplayEpoch,
    bool restart = false,
  }) async {
    final epoch = autoplayEpoch ?? _autoplayEpoch;
    final useAudio =
        (preferAudio ?? _audioMode) && lesson.audioPath != null ||
        lesson.videoPath == null;
    final path = useAudio ? lesson.audioPath! : lesson.videoPath!;
    _pendingCompletionFor = null;
    if (!restart &&
        position == null &&
        _lesson?.identity == lesson.identity &&
        _playback.localPath == path) {
      if (autoplay && epoch == _autoplayEpoch && !_playback.playing) {
        await _playback.play();
      }
      _save();
      return;
    }
    _recordHistory();
    _completedIdentity = null;
    final saved = _history.getForLesson(lesson);
    final target =
        position ?? (restart ? Duration.zero : _history.resumePosition(lesson));
    setState(() {
      _loading = true;
      _message = null;
    });
    _suspendMetadata();
    _revealChrome();
    try {
      await _playback.openLocal(path, position: target, autoplay: false);
      if (!mounted) return;
      await _applyVolume();
      _lesson = lesson;
      _restoreCurrentPath = lesson.primaryPath;
      _restorePosition = target;
      _audioMode = useAudio;
      _pointA = null;
      _dragPosition = null;
      _lastCueIndex = null;
      _offset = saved?.offset ?? Duration.zero;
      _cues = [];
      _hasReadings = false;
      _subtitlePath = null;
      try {
        await _loadSubtitle(
          subtitleOverride ?? saved?.subtitlePath ?? lesson.subtitlePath,
        );
      } catch (error) {
        _message = '媒体已打开，字幕载入失败：$error';
      }
      if (!mounted) return;
      final tracks = _tracks;
      if (tracks != null) {
        final savedPreferences = _trackPreferencesByPath[path];
        await tracks.applyPreferences(
          savedPreferences ??
              tracks.defaults(hasExternalSubtitles: _cues.isNotEmpty),
          hasExternalSubtitles: _cues.isNotEmpty,
        );
      }
      await _applyNativeSubtitleOffset();
      _invalidMedia.remove(lesson.identity);
      _history.record(
        lesson,
        position: _playback.position,
        duration: _playback.duration,
        completed: false,
      );
      if (autoplay && epoch == _autoplayEpoch) await _playback.play();
    } catch (error) {
      _invalidMedia[lesson.identity] = '无法读取或解码，可重新定位';
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _save();
    _armChromeTimer();
  }

  Future<void> _loadSubtitle(String? path) async {
    List<SubtitleCue> cues = [];
    var hasReadings = false;
    if (path != null) {
      final raw = await File(path).readAsString();
      final parsed = extensionOf(path) == 'vtt'
          ? parseWebVtt(raw)
          : parseSrt(raw);
      if (parsed.isEmpty) throw const FormatException('字幕文件中没有有效条目。');
      cues = parsed;
      hasReadings = parsed.any(
        (cue) =>
            parseRubyText(cue.text).any((segment) => segment.reading != null),
      );
    }
    if (!mounted) return;
    setState(() {
      _cues = cues;
      _hasReadings = hasReadings;
      _subtitlePath = path;
    });
  }

  Future<void> _pickSubtitle() => _enqueueMedia(() async {
    final result = await FilePicker.pickFile(
      dialogTitle: context.tr("载入字幕"),
      type: FileType.custom,
      allowedExtensions: subtitleExtensions.toList(),
    );
    final path = result?.path;
    if (path == null) return;
    await _remember([path]);
    await _loadSubtitle(path);
    if (_tracks != null) {
      _tracks.setExternalSubtitlesAvailable(_cues.isNotEmpty);
      await _tracks.selectExternalSubtitles();
    }
    final previous = _lesson;
    if (previous != null) {
      final updated = LocalLesson(
        title: previous.title,
        videoPath: previous.videoPath,
        audioPath: previous.audioPath,
        subtitlePath: path,
      );
      final index = _lessons.indexOf(previous);
      if (index >= 0) _lessons[index] = updated;
      _lesson = updated;
      setState(() {});
    }
    _save();
  });

  Future<void> _switchMode(bool audio) => _enqueueMedia(() async {
    final lesson = _lesson;
    if (lesson == null || audio == _audioMode) return;
    final path = audio ? lesson.audioPath : lesson.videoPath;
    if (path == null) return;
    setState(() => _loading = true);
    _suspendMetadata();
    final position = _playback.position;
    final playing = _playback.playing;
    final autoplayEpoch = _autoplayEpoch;
    final loop = _playback.loop;
    try {
      await _playback.openLocal(path, position: position, autoplay: false);
      await _applyVolume();
      if (_tracks != null) {
        await _tracks.applyPreferences(
          _trackPreferencesByPath[path] ??
              _tracks.defaults(hasExternalSubtitles: _cues.isNotEmpty),
          hasExternalSubtitles: _cues.isNotEmpty,
        );
      }
      await _applyNativeSubtitleOffset();
      if (loop != null && !loop.completed) {
        await _playback.setLoop(
          loop.start,
          loop.end,
          repeatCount: loop.repeatCount,
          completedPasses: loop.completedPasses,
        );
        await _playback.seek(position);
      }
      if (playing && autoplayEpoch == _autoplayEpoch) await _playback.play();
      _audioMode = audio;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _save();
  });

  void _revealChrome() {
    if (!mounted) return;
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _armChromeTimer();
  }

  void _armChromeTimer() {
    _chromeTimer?.cancel();
    if (!mounted) return;
    if (!_fullScreen ||
        !_playback.playing ||
        _hoveringChrome ||
        _keyboardChrome ||
        MediaQuery.accessibleNavigationOf(context) ||
        _overlayDepth > 0 ||
        _importing ||
        _loading) {
      return;
    }
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _fullScreen &&
          _playback.playing &&
          !_hoveringChrome &&
          _overlayDepth == 0) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  Future<void> _seekTo(Duration target) => _run(() async {
    if (!_ready) return;
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    _completedIdentity = null;
    final bounded = target < Duration.zero
        ? Duration.zero
        : target > _playback.duration
        ? _playback.duration
        : target;
    await _playback.seek(bounded);
    _keyboardChrome = false;
    _save();
    _revealChrome();
  });

  Future<void> _seekRelative(Duration delta) =>
      _seekTo(_playback.position + delta);

  Future<void> _togglePlayback() => _run(() async {
    if (!_ready) return;
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    _completedIdentity = null;
    await _playback.toggle();
    _keyboardChrome = false;
    _save();
    _revealChrome();
  });

  Future<void> _setVolume(double value) => _run(() async {
    final volume = value.clamp(0.0, 100.0);
    setState(() {
      _volume = volume;
      _muted = false;
      if (volume > 0) _lastAudibleVolume = volume;
    });
    await _applyVolume();
    _save();
    _revealChrome();
  });

  Future<void> _toggleMute() => _run(() async {
    setState(() {
      if (_muted || _volume == 0) {
        _muted = false;
        if (_volume == 0) _volume = _lastAudibleVolume;
      } else {
        _muted = true;
      }
    });
    await _applyVolume();
    _save();
    _revealChrome();
  });

  Future<void> _applyNativeSubtitleOffset() async {
    if (widget.playback != null) return;
    final platform = _playback.player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(
        'sub-delay',
        (_offset.inMilliseconds / 1000).toString(),
      );
    }
  }

  Future<void> _showTracks() => _run(() async {
    final tracks = _tracks;
    if (!_ready || tracks == null) return;
    var pickExternal = false;
    _overlayDepth++;
    _revealChrome();
    final navigator = Navigator.of(context);
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      modalBarrierColor: Colors.black54,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      builder: (sheetContext) => PlayerTrackSheet(
        controller: tracks,
        enabled: !_loading,
        onPickExternal: () {
          pickExternal = true;
          Navigator.pop(sheetContext);
        },
        onChanged: () {
          unawaited(_run(_applyNativeSubtitleOffset));
          _save();
        },
      ),
    );
    try {
      await navigator.push(route);
      await route.completed;
    } finally {
      _overlayDepth--;
      if (mounted) {
        _armChromeTimer();
        _advanceAfterCompletion();
      }
    }
    if (pickExternal && mounted) await _pickSubtitle();
  });

  Future<void> _relocateLesson(LocalLesson lesson) => _run(() async {
    if (_importing) return;
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    _beginImport();
    try {
      final result = await FilePicker.pickFile(
        dialogTitle: context.tr("重新定位 {p0}", {'p0': lesson.title}),
        type: FileType.custom,
        allowedExtensions:
            (lesson.videoPath != null ? videoExtensions : audioExtensions)
                .toList(),
      );
      final path = result?.path;
      if (path == null || !mounted || _scanCancellation?.cancelled == true) {
        return;
      }
      await _remember([path]);
      final scan = await (widget.scanMedia ?? scanLocalMedia)(
        [path],
        includeCompanions: true,
        cancellation: _scanCancellation,
      );
      if (!mounted || scan.cancelled || scan.lessons.isEmpty) return;
      final scanned = mergePlaylist(
        const [],
        scan.lessons,
        preferredMediaPath: path,
      ).firstWhere((item) => item.identity == MediaHistory.keyForPath(path));
      Future<String?> existing(String? candidate) async =>
          candidate != null && await File(candidate).exists()
          ? candidate
          : null;
      final replacement = LocalLesson(
        title: scanned.title,
        videoPath: scanned.videoPath ?? await existing(lesson.videoPath),
        audioPath: scanned.audioPath ?? await existing(lesson.audioPath),
        subtitlePath:
            scanned.subtitlePath ?? await existing(lesson.subtitlePath),
      );
      await _enqueueMedia(() async {
        if (_scanCancellation?.cancelled == true) return;
        final index = _lessons.indexWhere(
          (item) => item.identity == lesson.identity,
        );
        if (index < 0) return;
        _recordHistory();
        final previous = _history.getForLesson(lesson);
        final current =
            _lesson?.identity == lesson.identity ||
            (_lesson == null &&
                _restoreCurrentPath != null &&
                MediaHistory.keyForPath(_restoreCurrentPath!) ==
                    lesson.identity);
        final playing = _playback.playing;
        for (final pair in [
          (lesson.videoPath, replacement.videoPath),
          (lesson.audioPath, replacement.audioPath),
        ]) {
          final preferences = _trackPreferencesByPath[pair.$1];
          if (pair.$2 != null && preferences != null) {
            _trackPreferencesByPath[pair.$2!] = preferences;
          }
        }
        if (previous != null) {
          _history.record(
            replacement,
            position: previous.position,
            duration: previous.duration,
            completed: previous.completed,
            subtitlePath: replacement.subtitlePath ?? previous.subtitlePath,
            offset: previous.offset,
          );
        }
        setState(() {
          final updated = [..._lessons];
          updated[index] = replacement;
          _lessons = mergePlaylist(const [], updated);
          _invalidMedia.remove(lesson.identity);
          _invalidMedia.remove(replacement.identity);
        });
        if (current) {
          await _openLesson(
            replacement,
            position: previous?.resumePosition,
            autoplay: playing,
          );
        }
      });
    } finally {
      _finishImport();
    }
  });

  Future<void> _goToTime() => _run(() async {
    if (!_ready) return;
    final identity = _lesson?.identity;
    final input = TextEditingController(text: _clock(_playback.position));
    final form = GlobalKey<FormState>();
    _overlayDepth++;
    _revealChrome();
    final route = DialogRoute<Duration>(
      context: context,
      builder: (context) {
        void submit() {
          if (form.currentState!.validate()) {
            Navigator.pop(context, parsePlaybackTime(input.text));
          }
        }

        return AlertDialog(
          title: Text(context.tr("跳转到时间")),
          content: Form(
            key: form,
            child: TextFormField(
              controller: input,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr("分:秒 或 时:分:秒"),
                helperText: context.tr("总时长 {p0}", {
                  'p0': _clock(_playback.duration),
                }),
              ),
              validator: (value) {
                final parsed = parsePlaybackTime(value ?? '');
                if (parsed == null) {
                  return context.tr("请输入有效时间，例如 12:30 或 1:02:30");
                }
                if (parsed > _playback.duration) return context.tr("时间不能超过总时长");
                return null;
              },
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("取消")),
            ),
            FilledButton(onPressed: submit, child: Text(context.tr("跳转"))),
          ],
        );
      },
    );
    try {
      final target = await Navigator.of(context).push(route);
      await route.completed;
      if (mounted && target != null && _lesson?.identity == identity) {
        await _seekTo(target);
      }
    } finally {
      input.dispose();
      _overlayDepth--;
      if (mounted) {
        _armChromeTimer();
        _advanceAfterCompletion();
      }
    }
  });

  Duration _cueStart(SubtitleCue cue) =>
      cue.start + _offset < Duration.zero ? Duration.zero : cue.start + _offset;

  Future<void> _jump(SubtitleCue? cue) => _run(() async {
    if (!_ready || cue == null) return;
    _completedIdentity = null;
    _playback.clearLoop();
    _pointA = null;
    await _playback.seek(_cueStart(cue));
    _save();
  });

  Future<void> _loopCue() => _run(() async {
    final cue = _current;
    if (!_ready || cue == null) return;
    await _playback.setLoop(
      _cueStart(cue),
      cue.end + _offset,
      repeatCount: _passes,
    );
    await _playback.play();
  });

  void _setStopTimer(int minutes) {
    _stopTimer?.cancel();
    _stopAt = minutes == 0
        ? null
        : DateTime.now().add(Duration(minutes: minutes));
    if (minutes > 0) {
      _stopTimer = Timer(Duration(minutes: minutes), () {
        _autoplayEpoch++;
        _pendingCompletionFor = null;
        unawaited(_run(_playback.pause));
        if (mounted) setState(() => _stopAt = null);
      });
    }
    setState(() {});
  }

  @override
  Future<AppExitResponse> didRequestAppExit() =>
      _exitRequest ??= _prepareExit();

  Future<AppExitResponse> _prepareExit() async {
    _exiting = true;
    _autoplayEpoch++;
    _pendingCompletionFor = null;
    _scanCancellation?.cancel();
    _saveTimer?.cancel();
    _stopTimer?.cancel();
    _chromeTimer?.cancel();
    _fullScreenSyncTimer?.cancel();
    _metadata?.setSuspended(true);
    Future<void> finish(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stack) {
        debugPrint('Player shutdown: $error\n$stack');
      }
    }

    await finish(() => _mediaOperations);
    await finish(_playback.pause);
    _save();
    await finish(() async => _metadata?.close());
    await finish(OfflinePlayback.closeAll);
    await finish(_store.flush);
    if (mounted) {
      await finish(() async => AppLanguageScope.maybeOf(context)?.flush());
    }
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_exiting &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      _save();
    }
  }

  @override
  void dispose() {
    _unregisterNavigation?.call();
    if (!_exiting) _save();
    _saveTimer?.cancel();
    _stopTimer?.cancel();
    _fullScreenSyncTimer?.cancel();
    _chromeTimer?.cancel();
    _scanCancellation?.cancel();
    _metadata?.dispose();
    _tracks?.removeListener(_tracksChanged);
    _tracks?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _playback.removeListener(_changed);
    _files.setMethodCallHandler(null);
    final shutdown = Future.wait<void>([
      _playback.close(),
      if (_metadata != null) _metadata.close(),
      _store.flush(),
    ]).then<void>((_) {});
    _navigation?.trackShutdown(shutdown);
    unawaited(shutdown.catchError((Object _) {}));
    _playback.dispose();
    _subtitleScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final errors = [
      ?_stateWarning,
      if ((_message ?? _playback.error) != null) (_message ?? _playback.error)!,
    ];
    final width = MediaQuery.sizeOf(context).width;
    final expandedActions =
        width >=
        (AppLocalizations.of(context).locale.languageCode == 'zh'
            ? 1100
            : 1320);
    return PlayerShortcuts(
      enabled: _ready,
      onToggle: _togglePlayback,
      onSeek: _seekRelative,
      onVolume: (delta) => _setVolume(_volume + delta),
      onMute: _toggleMute,
      onFullScreen: () => _setFullScreen(!_fullScreen),
      onEscape: () {
        if (_fullScreen) unawaited(_setFullScreen(false));
      },
      onPreviousCue: () =>
          _jump(previousCue(_cues, _playback.position, offset: _offset)),
      onNextCue: () =>
          _jump(nextCue(_cues, _playback.position, offset: _offset)),
      onGoToTime: _goToTime,
      onTraverseControls: _traverseFullScreenControls,
      child: Scaffold(
        backgroundColor: _fullScreen ? Colors.black : null,
        appBar: _fullScreen
            ? null
            : AppBar(
                leading: _navigation == null ? null : const AppHomeBackButton(),
                title: Row(
                  children: [
                    Icon(Icons.headphones_rounded, size: 23),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr("本地播放"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  const AppSectionMenuButton(),
                  const ThemeMenuButton(),
                  if (expandedActions) ...[
                    TextButton.icon(
                      onPressed: _loading ? null : _study,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(context.tr("基础知识学习")),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : _quiz,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(context.tr("基础知识测试")),
                    ),
                    Chip(
                      avatar: Icon(Icons.offline_bolt_outlined, size: 16),
                      label: Text(
                        context.tr("本地播放"),
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: context.tr("基础知识学习"),
                      onPressed: _loading ? null : _study,
                      icon: const Icon(Icons.menu_book_outlined),
                    ),
                    IconButton(
                      tooltip: context.tr("基础知识测试"),
                      onPressed: _loading ? null : _quiz,
                      icon: const Icon(Icons.fact_check_outlined),
                    ),
                  ],
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: _importing ? null : _openFiles,
                    icon: const Icon(Icons.add),
                    label: Text(context.tr("打开文件")),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    onPressed: _importing ? null : _openFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(context.tr("打开文件夹")),
                  ),
                  const SizedBox(width: 18),
                ],
              ),
        body: MouseRegion(
          cursor: _fullScreen && !_chromeVisible
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          onHover: (_) {
            if (_fullScreen) {
              _keyboardChrome = false;
              _revealChrome();
            }
          },
          child: Stack(
            children: [
              Column(
                children: [
                  Visibility(
                    visible: errors.isNotEmpty,
                    child: MaterialBanner(
                      content: Text(
                        errors.map(context.trMessage).join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: const Icon(Icons.info_outline),
                      actions: [
                        if (_stateWarning != null)
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => _enqueueMedia(_restore),
                            child: Text(context.tr("重试恢复")),
                          ),
                        if (_stateReady ||
                            _message != null ||
                            _playback.error != null)
                          TextButton(
                            onPressed: () {
                              _playback.clearError();
                              setState(() {
                                _message = null;
                                if (_stateReady) _stateWarning = null;
                              });
                            },
                            child: Text(context.tr("关闭")),
                          ),
                      ],
                    ),
                  ),
                  Visibility(visible: _importing, child: _importProgressBar()),
                  Visibility(visible: !_fullScreen, child: _lessonBar()),
                  Expanded(
                    child: Padding(
                      padding: _fullScreen
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(18, 6, 18, 0),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _stage(current)),
                            SizedBox(width: _fullScreen ? 0 : 14),
                            Visibility(
                              visible:
                                  !_fullScreen && constraints.maxWidth >= 760,
                              child: SizedBox(
                                width: 320,
                                child: constraints.maxHeight < 280
                                    ? SingleChildScrollView(
                                        child: SizedBox(
                                          height: 360,
                                          child: _sidePanel(current),
                                        ),
                                      )
                                    : _sidePanel(current),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Visibility(
                    visible: !_fullScreen,
                    child: ListenableBuilder(
                      listenable: _playback,
                      builder: (context, _) => _controls(context),
                    ),
                  ),
                  Visibility(
                    visible: !_fullScreen,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        context.tr(
                          "空格：播放 / 暂停    ← →：±5秒    Alt + ← →：逐句    M：静音    F：全屏    G：跳转时间",
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_fullScreen) _fullScreenChrome(),
              if (_draggingFiles)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(36),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.playlist_add, size: 52),
                              SizedBox(height: 16),
                              Text(
                                context.tr("松开以导入"),
                                style: TextStyle(fontSize: 24),
                              ),
                              SizedBox(height: 10),
                              Text(context.tr("视频直接播放 · 文件夹加入播放列表")),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importProgressBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _scanProgress == null
                  ? context.tr("选择要导入的文件…")
                  : context.tr("已扫描 {p0} 项，发现 {p1} 个媒体文件", {
                      'p0': _scanProgress!.files,
                      'p1': _scanProgress!.media,
                    }),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => _scanCancellation?.cancel(),
            child: Text(context.tr("取消导入")),
          ),
        ],
      ),
    ),
  );

  Widget _chromeRegion(Widget child) => MouseRegion(
    onEnter: (_) {
      _hoveringChrome = true;
      _chromeTimer?.cancel();
    },
    onExit: (_) {
      _hoveringChrome = false;
      _armChromeTimer();
    },
    child: child,
  );

  bool _traverseFullScreenControls(bool backwards) {
    if (!_fullScreen) return false;
    _keyboardChrome = true;
    final wasHidden = !_chromeVisible;
    _revealChrome();
    if (!wasHidden) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_fullScreen) return;
      if (backwards) {
        FocusScope.of(context).previousFocus();
      } else {
        FocusScope.of(context).nextFocus();
      }
    });
    return true;
  }

  Widget _chromeVisibility(Widget child) => IgnorePointer(
    ignoring: !_chromeVisible,
    child: ExcludeFocus(
      excluding: !_chromeVisible,
      child: ExcludeSemantics(
        excluding: !_chromeVisible,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: _chromeRegion(child),
        ),
      ),
    ),
  );

  Widget _fullScreenChrome() => Positioned.fill(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: Theme(
        data: buildAppTheme(Brightness.dark),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Builder(
            builder: (context) => Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _chromeVisibility(
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 14, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xD9000000), Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lesson?.title ?? context.tr("离线播放器"),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _setSubtitleVisibility(
                              _subtitleVisibility.copyWith(
                                video: !_subtitleVisibility.video,
                              ),
                            ),
                            icon: Icon(
                              _subtitleVisibility.video
                                  ? Icons.subtitles_outlined
                                  : Icons.subtitles_off_outlined,
                            ),
                            label: Text(context.tr("字幕")),
                          ),
                          IconButton(
                            tooltip: context.tr("音轨与字幕"),
                            onPressed: _lesson == null ? null : _showTracks,
                            icon: const Icon(Icons.tune),
                          ),
                          IconButton(
                            tooltip: context.tr("退出全屏 (Esc)"),
                            onPressed: () => _setFullScreen(false),
                            icon: const Icon(Icons.fullscreen_exit),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _chromeVisibility(
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xEB000000)],
                        ),
                      ),
                      padding: const EdgeInsets.only(top: 28, bottom: 12),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1150),
                          child: ListenableBuilder(
                            listenable: _playback,
                            builder: (context, _) =>
                                _controls(context, compact: true),
                          ),
                        ),
                      ),
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

  Widget _lessonBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 3, 20, 10),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: _lesson?.primaryPath ?? context.tr("在右侧播放列表中选择媒体"),
                child: Text(
                  _lesson?.title ?? context.tr("导入音视频，开始播放"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_playlistIndex < 0 ? 0 : _playlistIndex + 1} / ${_lessons.length}',
              style: const TextStyle(fontSize: 12),
            ),
            TextButton.icon(
              onPressed: !_loading && _playlistIndex > 0
                  ? () => _selectAdjacent(-1)
                  : null,
              icon: const Icon(Icons.skip_previous_outlined, size: 18),
              label: Text(context.tr("上一项")),
            ),
            TextButton.icon(
              onPressed:
                  !_loading &&
                      _playlistIndex >= 0 &&
                      _playlistIndex < _lessons.length - 1
                  ? () => _selectAdjacent(1)
                  : null,
              icon: const Icon(Icons.skip_next_outlined, size: 18),
              label: Text(context.tr("下一项")),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() => _showPlaylist = true);
                _save();
              },
              icon: const Icon(Icons.queue_music, size: 19),
              label: Text(context.tr("播放列表")),
            ),
            const SizedBox(width: 14),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.movie_outlined, size: 17),
                  label: Text(context.tr("视频")),
                  enabled: _lesson?.videoPath != null,
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.graphic_eq, size: 17),
                  label: Text(context.tr("音频")),
                  enabled: _lesson?.audioPath != null,
                ),
              ],
              selected: {_audioMode},
              onSelectionChanged: _loading
                  ? null
                  : (value) => _switchMode(value.single),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SubtitleVisibilityControls(
                value: _subtitleVisibility,
                enabled: !_loading,
                onChanged: _setSubtitleVisibility,
              ),
            ),
            TextButton.icon(
              onPressed: _lesson == null || _loading ? null : _showTracks,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(context.tr("字幕与音轨")),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stage(SubtitleCue? current) => GestureDetector(
    key: _stageKey,
    onTap: _ready ? _togglePlayback : null,
    onDoubleTap: () => _setFullScreen(!_fullScreen),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(_fullScreen ? 0 : 14),
      child: ColoredBox(
        color: _lesson != null && !_audioMode
            ? Colors.black
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: LayoutBuilder(
          builder: (context, size) => Stack(
            fit: StackFit.expand,
            children: [
              // Keep the video surface mounted while opening paused media, so it
              // receives the initial decoded frame before _lesson is assigned.
              widget.videoSurface ??
                  Video(
                    controller: _video,
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      visible:
                          (_tracks?.useEmbeddedSubtitles ?? false) &&
                          _subtitleVisibility.video,
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: 1.4,
                        color: Colors.white,
                        backgroundColor: const Color(0xB3000000),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        18,
                        0,
                        18,
                        size.maxHeight * _subtitleBottom,
                      ),
                    ),
                    controls: NoVideoControls,
                    wakelock: false,
                    pauseUponEnteringBackgroundMode: false,
                  ),
              if (_lesson == null || _audioMode)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ),
              if (_lesson == null)
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 62,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          context.tr("你的音视频学习空间"),
                          style: TextStyle(fontSize: 23),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            "拖入视频即可播放；拖入文件夹可批量加入播放列表\n自动配对同名音频、视频和字幕，支持子文件夹",
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 23),
                        FilledButton.icon(
                          onPressed: _openFolder,
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.tr("选择本地文件夹")),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_lesson != null && _audioMode)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 90,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr("音频模式"),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (current != null && (_tracks?.useExternalSubtitles ?? true))
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: size.maxHeight * _subtitleBottom,
                  child: Center(
                    child: ScreenSubtitleText(
                      visible: _subtitleVisibility.video,
                      text: current.text,
                      showReadings: _showReadings,
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (_loading || _playback.buffering)
                const Center(child: CircularProgressIndicator()),
              if (_playback.loop != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Chip(
                    avatar: const Icon(Icons.repeat, size: 16),
                    label: Text(
                      '${_clock(_playback.loop!.start)} — ${_clock(_playback.loop!.end)} · ${_playback.loop!.completedPasses}/${_playback.loop!.repeatCount ?? '∞'}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sidePanel(SubtitleCue? current) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.queue_music, size: 18),
                label: Text(context.tr("播放列表")),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.subtitles_outlined, size: 18),
                label: Text(context.tr("字幕")),
              ),
            ],
            selected: {_showPlaylist},
            onSelectionChanged: (value) {
              setState(() => _showPlaylist = value.single);
              _save();
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _playback,
            builder: (context, _) => _showPlaylist
                ? PlayerPlaylist(
                    lessons: _lessons,
                    current: _lesson,
                    playing: _playback.playing,
                    enabled: !_loading,
                    autoAdvance: _playlistMode.autoAdvance,
                    mode: _playlistMode,
                    onModeChanged: _setPlaylistMode,
                    onMenuClosed: _advanceAfterCompletion,
                    statusOf: _playlistStatus,
                    onSelect: _selectLesson,
                    onReplay: (lesson) => _selectLesson(lesson, restart: true),
                    onRelocate: _relocateLesson,
                    onRemove: _removeLesson,
                    onReorder: _reorderPlaylist,
                    onClear: _clearPlaylist,
                    onAutoAdvanceChanged: (value) => _setPlaylistMode(
                      value ? PlaylistMode.sequential : PlaylistMode.manual,
                    ),
                  )
                : _subtitlePanel(current),
          ),
        ),
      ],
    ),
  );

  Widget _subtitlePanel(SubtitleCue? current) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr("字幕  {p0}", {'p0': _cues.length}),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: _follow ? context.tr("关闭字幕跟随") : context.tr("跟随当前句"),
                isSelected: _follow,
                onPressed: () => setState(() => _follow = !_follow),
                icon: const Icon(Icons.my_location, size: 19),
              ),
              IconButton(
                tooltip: _subtitleVisibility.list
                    ? context.tr("隐藏列表字幕")
                    : context.tr("显示列表字幕"),
                onPressed: () => _setSubtitleVisibility(
                  _subtitleVisibility.copyWith(list: !_subtitleVisibility.list),
                ),
                icon: Icon(
                  _subtitleVisibility.list
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
              ),
              IconButton(
                tooltip: context.tr("字幕设置"),
                onPressed: _subtitleSettings,
                icon: const Icon(Icons.tune, size: 19),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: (_tracks != null && !_tracks.useExternalSubtitles)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      _tracks.useEmbeddedSubtitles
                          ? context.tr("正在显示视频内字幕\n逐句列表和假名需要外部 SRT / VTT")
                          : context.tr("字幕已关闭\n可在“字幕与音轨”中选择或载入字幕"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.8),
                    ),
                  ),
                )
              : _cues.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      context.tr("尚未载入字幕\n支持 SRT / VTT；VTT 可含人工假名"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.8,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _subtitleScroll,
                  itemExtent: 104,
                  itemCount: _cues.length,
                  itemBuilder: (context, index) {
                    final cue = _cues[index];
                    final selected = current?.index == index;
                    return Material(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      child: InkWell(
                        onTap: _ready ? () => _jump(cue) : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${index + 1}    ${_clock(cue.start + _offset)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SubtitleListText(
                                visible: _subtitleVisibility.list,
                                text: cue.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.25,
                                  color: _subtitleVisibility.list
                                      ? selected
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            onPressed: _lesson == null || _loading ? null : _pickSubtitle,
            icon: const Icon(Icons.subtitles_outlined, size: 17),
            label: Text(context.tr("载入字幕")),
          ),
        ),
      ],
    ),
  );

  Widget _controls(BuildContext context, {bool compact = false}) {
    final total = _lesson == null ? Duration.zero : _playback.duration;
    final max = total.inMilliseconds.toDouble();
    final value =
        (_lesson == null
                ? 0.0
                : _dragPosition ?? _playback.position.inMilliseconds.toDouble())
            .clamp(0.0, max > 0 ? max : 1.0);
    final position = Duration(milliseconds: value.round());
    final hasExternal = _tracks?.useExternalSubtitles ?? true;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 4 : 10, 24, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_clock(position), style: const TextStyle(fontSize: 12)),
              Expanded(
                child: Semantics(
                  label: context.tr("播放进度"),
                  child: StableSlider(
                    value: value,
                    max: max > 0 ? max : 1,
                    label: _clock(position),
                    showValueIndicator: ShowValueIndicator.onDrag,
                    semanticFormatterCallback: (value) =>
                        context.tr("{p0}，总时长 {p1}", {
                          'p0': _clock(Duration(milliseconds: value.round())),
                          'p1': _clock(total),
                        }),
                    onChanged: !_ready
                        ? null
                        : (value) => setState(() => _dragPosition = value),
                    onChangeStart: (_) {
                      _hoveringChrome = true;
                      _chromeTimer?.cancel();
                    },
                    onChangeEnd: (value) {
                      setState(() => _dragPosition = null);
                      _hoveringChrome = false;
                      unawaited(_seekTo(Duration(milliseconds: value.round())));
                    },
                  ),
                ),
              ),
              Text(
                compact ? '−${_clock(total - position)}' : _clock(total),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              if (compact) ...[
                _controlIcon(
                  context.tr("上一项"),
                  Icons.skip_previous_outlined,
                  !_loading && _playlistIndex > 0
                      ? () => _selectAdjacent(-1)
                      : null,
                ),
                _controlIcon(
                  context.tr("下一项"),
                  Icons.skip_next_outlined,
                  !_loading &&
                          _playlistIndex >= 0 &&
                          _playlistIndex < _lessons.length - 1
                      ? () => _selectAdjacent(1)
                      : null,
                ),
              ],
              _controlIcon(
                context.tr("快退10秒 (J)"),
                Icons.replay_10,
                _ready
                    ? () => _seekRelative(const Duration(seconds: -10))
                    : null,
              ),
              Tooltip(
                message: _playback.playing
                    ? context.tr("暂停 (空格)")
                    : context.tr("播放 (空格)"),
                child: FilledButton(
                  onPressed: _ready ? _togglePlayback : null,
                  child: Icon(
                    _playback.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 29,
                    semanticLabel: _playback.playing
                        ? context.tr("暂停")
                        : context.tr("播放"),
                  ),
                ),
              ),
              _controlIcon(
                context.tr("快进10秒 (L)"),
                Icons.forward_10,
                _ready
                    ? () => _seekRelative(const Duration(seconds: 10))
                    : null,
              ),
              if (_cues.isNotEmpty && hasExternal) ...[
                _controlIcon(
                  context.tr("上一句 (Alt + ←)"),
                  Icons.navigate_before,
                  _ready
                      ? () => _jump(
                          previousCue(
                            _cues,
                            _playback.position,
                            offset: _offset,
                          ),
                        )
                      : null,
                ),
                _controlIcon(
                  context.tr("下一句 (Alt + →)"),
                  Icons.navigate_next,
                  _ready
                      ? () => _jump(
                          nextCue(_cues, _playback.position, offset: _offset),
                        )
                      : null,
                ),
              ],
              PopupMenuButton<double>(
                tooltip: context.tr("播放速度"),
                initialValue: _playback.rate,
                onOpened: () {
                  _speedMenuRoute = null;
                  _overlayDepth++;
                  _chromeTimer?.cancel();
                },
                onCanceled: () => unawaited(_afterSpeedMenu(() async {})),
                onSelected: (rate) => unawaited(
                  _afterSpeedMenu(() async {
                    await _playback.setRate(rate);
                    _save();
                    _revealChrome();
                  }),
                ),
                itemBuilder: (_) => [
                  for (final rate in [
                    0.25,
                    0.5,
                    0.75,
                    1.0,
                    1.25,
                    1.5,
                    2.0,
                    3.0,
                    4.0,
                  ])
                    PopupMenuItem(
                      value: rate,
                      child: Builder(
                        builder: (itemContext) {
                          final route = ModalRoute.of(itemContext);
                          if (route is PopupRoute) _speedMenuRoute = route;
                          return Text('$rate×');
                        },
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    '${_playback.rate}×',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              _controlIcon(
                context.tr("跳转到时间 (G)"),
                Icons.more_time,
                _ready ? _goToTime : null,
              ),
              _controlIcon(
                context.tr("音轨与字幕"),
                Icons.tune,
                _lesson == null || _loading ? null : _showTracks,
              ),
              if (!compact) _studyLoopControls(context),
              SizedBox(
                width: 156,
                child: Row(
                  children: [
                    _controlIcon(
                      _muted || _volume == 0
                          ? context.tr("取消静音 (M)")
                          : context.tr("静音 (M)"),
                      _muted || _volume == 0
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                      _toggleMute,
                    ),
                    Expanded(
                      child: Semantics(
                        label: context.tr("音量"),
                        child: StableSlider(
                          value: _muted ? 0 : _volume,
                          max: 100,
                          semanticFormatterCallback: (value) =>
                              '${value.round()}%',
                          onChanged: _setVolume,
                          onChangeStart: (_) {
                            _hoveringChrome = true;
                            _chromeTimer?.cancel();
                          },
                          onChangeEnd: (_) {
                            _hoveringChrome = false;
                            _armChromeTimer();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _controlIcon(
                _fullScreen ? context.tr("退出全屏 (Esc)") : context.tr("全屏播放 (F)"),
                _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                _fullScreenChanging ? null : () => _setFullScreen(!_fullScreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlIcon(String label, IconData icon, VoidCallback? onPressed) =>
      IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, semanticLabel: label, size: 22),
      );

  Widget _studyLoopControls(BuildContext context) => Wrap(
    spacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed:
            _ready &&
                _current != null &&
                (_tracks?.useExternalSubtitles ?? true)
            ? _loopCue
            : null,
        icon: const Icon(Icons.repeat_one, size: 18),
        label: Text(context.tr("循环当前句")),
      ),
      DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _passes ?? 0,
          items: [
            for (final option in [
              (0, context.tr("无限")),
              (1, context.tr("1遍停")),
              (3, context.tr("3遍停")),
            ])
              DropdownMenuItem(
                value: option.$1,
                child: Builder(
                  builder: (itemContext) {
                    final route = ModalRoute.of(itemContext);
                    if (route is PopupRoute &&
                        !identical(route, _passesMenuRoute)) {
                      _passesMenuRoute = route;
                      _watchMenuCancellation(route);
                    }
                    return Text(option.$2);
                  },
                ),
              ),
          ],
          onChanged: _setPassesAfterMenu,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      TextButton(
        onPressed: _ready
            ? () => setState(() => _pointA = _playback.position)
            : null,
        child: Text(
          _pointA == null ? context.tr("设 A") : 'A ${_clock(_pointA!)}',
        ),
      ),
      TextButton(
        onPressed: _ready && _pointA != null
            ? () => _run(() async {
                await _playback.setLoop(
                  _pointA!,
                  _playback.position,
                  repeatCount: _passes,
                );
                await _playback.play();
              })
            : null,
        child: Text(context.tr("设 B")),
      ),
      _controlIcon(
        context.tr("取消句子／A–B循环"),
        Icons.repeat_on_outlined,
        _playback.loop == null
            ? null
            : () {
                _playback.clearLoop();
                setState(() => _pointA = null);
              },
      ),
      PopupMenuButton<int>(
        tooltip: context.tr("睡眠定时"),
        onSelected: _setStopAfterMenu,
        icon: Icon(
          Icons.bedtime_outlined,
          size: 20,
          color: _stopAt == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
        itemBuilder: (_) => [
          for (final minutes in [0, 5, 15, 30, 60])
            PopupMenuItem(
              value: minutes,
              child: Builder(
                builder: (itemContext) {
                  final route = ModalRoute.of(itemContext);
                  if (route is PopupRoute &&
                      !identical(route, _sleepMenuRoute)) {
                    _sleepMenuRoute = route;
                    _watchMenuCancellation(route);
                  }
                  return Text(
                    minutes == 0
                        ? context.tr("关闭定时停止")
                        : context.tr("{p0} 分钟后停止", {'p0': minutes}),
                  );
                },
              ),
            ),
        ],
      ),
    ],
  );

  Future<void> _subtitleSettings() async {
    _overlayDepth++;
    _revealChrome();
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(context.tr("字幕显示")),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr("字号  {p0}", {'p0': _fontSize.round()})),
                StableSlider(
                  value: _fontSize,
                  min: 16,
                  max: 46,
                  divisions: 30,
                  onChanged: (value) {
                    setState(() => _fontSize = value);
                    refresh(() {});
                  },
                ),
                Text(context.tr("垂直位置")),
                StableSlider(
                  value: _subtitleBottom,
                  min: 0.02,
                  max: 0.65,
                  onChanged: (value) {
                    setState(() => _subtitleBottom = value);
                    refresh(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr("时间偏移  {p0} ms", {'p0': _offset.inMilliseconds}),
                ),
                const SizedBox(height: 5),
                Text(
                  context.tr("正数让字幕更晚显示"),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(
                          () => _offset -= const Duration(milliseconds: 100),
                        );
                        unawaited(_run(_applyNativeSubtitleOffset));
                        refresh(() {});
                      },
                      child: const Text('−100 ms'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _offset = Duration.zero);
                        unawaited(_run(_applyNativeSubtitleOffset));
                        refresh(() {});
                      },
                      child: Text(context.tr("归零")),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(
                          () => _offset += const Duration(milliseconds: 100),
                        );
                        unawaited(_run(_applyNativeSubtitleOffset));
                        refresh(() {});
                      },
                      child: const Text('+100 ms'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr("显示画面字幕")),
                  value: _subtitleVisibility.video,
                  onChanged: (value) {
                    _setSubtitleVisibility(
                      _subtitleVisibility.copyWith(video: value),
                    );
                    refresh(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr("显示列表字幕")),
                  value: _subtitleVisibility.list,
                  onChanged: (value) {
                    _setSubtitleVisibility(
                      _subtitleVisibility.copyWith(list: value),
                    );
                    refresh(() {});
                  },
                ),
                if (_hasReadings)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr("显示已标注的假名")),
                    subtitle: Text(
                      context.tr("只显示字幕内已有的读音，不自动生成"),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _showReadings,
                    onChanged: (value) {
                      setState(() => _showReadings = value);
                      refresh(() {});
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _save();
                Navigator.pop(context);
              },
              child: Text(context.tr("完成")),
            ),
          ],
        ),
      ),
    );
    try {
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      _overlayDepth--;
      if (mounted) {
        _armChromeTimer();
        _advanceAfterCompletion();
      }
    }
  }

  String _clock(Duration value) => formatPlaybackTime(value);
}
