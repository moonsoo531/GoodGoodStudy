import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:offline_player/playback/offline_playback.dart';
import 'package:offline_player/subtitles/subtitles.dart';

const _sampleDirectory = String.fromEnvironment('SAMPLE_DIR');
const _resultPath = String.fromEnvironment('PROBE_RESULT');
const _autostart = bool.fromEnvironment('PROBE_AUTOSTART');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: NativeMediaProbe()));
}

class NativeMediaProbe extends StatefulWidget {
  const NativeMediaProbe({super.key});

  @override
  State<NativeMediaProbe> createState() => _NativeMediaProbeState();
}

class _NativeMediaProbeState extends State<NativeMediaProbe> {
  static const _files = MethodChannel('offline_player/local_files');

  late final OfflinePlayback _playback;
  late final VideoController _video;
  StreamSubscription<String>? _nativeErrors;
  String _directory = _sampleDirectory;
  String _status = '请选择 Sample 文件夹，然后运行原生播放器验证。';
  String _summary = '';
  String _phase = 'idle';
  bool _running = false;
  bool _cancelled = false;
  final List<Map<String, Object?>> _checks = [];
  final List<String> _errors = [];
  final List<int> _loopPasses = [];
  final List<String> _accessWarnings = [];

  @override
  void initState() {
    super.initState();
    _playback = OfflinePlayback();
    _video = VideoController(_playback.player);
    _playback.addListener(_observePlayback);
    _nativeErrors = _playback.player.stream.error.listen(_errors.add);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreAndMaybeStart());
    });
  }

  Future<void> _restoreAndMaybeStart() async {
    try {
      final restored = await _files.invokeMethod<List<dynamic>>('restorePaths');
      if (_directory.isEmpty) {
        for (final path in restored ?? const []) {
          if (path is String && await Directory(path).exists()) {
            _directory = path;
            break;
          }
        }
      }
    } catch (error) {
      _accessWarnings.add('Could not restore directory bookmarks: $error');
    }
    if (!mounted) return;
    setState(() {});
    if (_autostart && _directory.isNotEmpty) await _run();
  }

  void _observePlayback() {
    if (_phase != 'mkv_finite_loop') return;
    final passes = _playback.loop?.completedPasses;
    if (passes != null && (_loopPasses.isEmpty || _loopPasses.last != passes)) {
      _loopPasses.add(passes);
    }
  }

  Future<void> _chooseDirectory() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '授权并选择包含 MKV、MP3、SRT 的 Sample 文件夹',
      initialDirectory: _directory.isEmpty ? null : _directory,
    );
    if (selected != null && mounted) {
      try {
        await _files.invokeMethod<void>('rememberPaths', [selected]);
      } catch (error) {
        _accessWarnings.add(
          'Could not retain selected directory access: $error',
        );
      }
      if (!mounted) return;
      setState(() {
        _directory = selected;
        _status = '文件夹已选择，可以开始验证。';
      });
    }
  }

  Future<void> _run() async {
    if (_running || _directory.isEmpty) return;
    setState(() {
      _running = true;
      _cancelled = false;
      _summary = '';
      _checks.clear();
      _errors.clear();
      _loopPasses.clear();
    });
    final watch = Stopwatch()..start();
    String? failure;
    Map<String, Object?>? failureDiagnostic;
    try {
      await _exercise().timeout(const Duration(seconds: 26));
      _require(_errors.isEmpty, 'Native player reported an error.');
    } catch (error) {
      failure = error.toString();
      failureDiagnostic = _diagnostic();
    } finally {
      _cancelled = true;
      try {
        await _playback.pause().timeout(const Duration(seconds: 2));
      } catch (error) {
        failure ??= 'Could not pause native player: $error';
      }
      watch.stop();
    }

    final result = <String, Object?>{
      'schema': 'offline-player-native-probe-v1',
      'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'passed': failure == null,
      'elapsedMs': watch.elapsedMilliseconds,
      'muted': _playback.player.state.volume == 0,
      'checks': List.of(_checks),
      'nativeErrors': List.of(_errors),
      'accessWarnings': List.of(_accessWarnings),
      'failure': failure,
      'failureDiagnostic': failureDiagnostic,
      'finalDiagnostic': _diagnostic(),
    };
    await _writeResult(result);
    stdout.writeln('NATIVE_PROBE_OUTPUT ${result['resultPath']}');
    stdout.writeln('NATIVE_PROBE_DONE ${jsonEncode(result)}');
    if (mounted) {
      setState(() {
        _running = false;
        _phase = 'done';
        _status = result['passed'] == true ? '验证通过，播放器已静音暂停。' : '验证失败，请查看下方结果。';
        _summary = const JsonEncoder.withIndent('  ').convert(result);
      });
    }
  }

  Future<void> _writeResult(Map<String, Object?> result) async {
    final fallback = File(
      '${Directory.systemTemp.path}/learnjapanese-native-probe.json',
    );
    final candidates = [
      if (_resultPath.isNotEmpty) File(_resultPath),
      if (_resultPath != fallback.path) fallback,
    ];
    final warnings = <String>[];
    result['writeWarnings'] = warnings;
    for (final output in candidates) {
      try {
        _require(output.isAbsolute, 'PROBE_RESULT must be an absolute path.');
        result['resultPath'] = output.path;
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(result),
        );
        return;
      } catch (error) {
        warnings.add('Could not write ${output.path}: $error');
      }
    }
    result['resultPath'] = null;
  }

  Map<String, Object?> _diagnostic() {
    final native = _playback.player.state;
    final loop = _playback.loop;
    return {
      'phase': _phase,
      'native': {
        'positionMs': native.position.inMilliseconds,
        'durationMs': native.duration.inMilliseconds,
        'playing': native.playing,
        'completed': native.completed,
        'buffering': native.buffering,
        'rate': native.rate,
        'volume': native.volume,
        'width': native.width,
        'height': native.height,
        'playlistIndex': native.playlist.index,
        'playlistUris': native.playlist.medias
            .map((media) => media.uri)
            .toList(),
        'audioParams': {
          'format': native.audioParams.format,
          'sampleRate': native.audioParams.sampleRate,
          'channels': native.audioParams.channels,
          'channelCount': native.audioParams.channelCount,
        },
      },
      'playback': {
        'positionMs': _playback.position.inMilliseconds,
        'durationMs': _playback.duration.inMilliseconds,
        'playing': _playback.playing,
        'buffering': _playback.buffering,
        'busy': _playback.busy,
        'rate': _playback.rate,
        'localPath': _playback.localPath,
        'error': _playback.error,
        'loop': loop == null
            ? null
            : {
                'startMs': loop.start.inMilliseconds,
                'endMs': loop.end.inMilliseconds,
                'repeatCount': loop.repeatCount,
                'completedPasses': loop.completedPasses,
              },
      },
    };
  }

  Future<void> _exercise() async {
    _require(
      Platform.isMacOS,
      'This probe requires a real macOS Flutter runner.',
    );
    final folder = Directory(_directory);
    _require(folder.isAbsolute, 'SAMPLE_DIR must be an absolute path.');
    final files = await folder.list().where((entry) => entry is File).toList();
    final videos =
        files
            .where((entry) => entry.path.toLowerCase().endsWith('.mkv'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    _require(videos.isNotEmpty, 'The selected folder has no original MKV.');
    final video = File(videos.first.path);
    final stem = video.path.substring(0, video.path.length - 4);
    final audio = File('$stem.mp3');
    final subtitles = File('$stem.srt');
    _require(await audio.exists(), 'Missing matching MP3.');
    _require(await subtitles.exists(), 'Missing matching SRT.');
    final cues = parseSrt(await subtitles.readAsString());
    _require(cues.isNotEmpty, 'No valid subtitle cues.');
    final cue = cues.firstWhere(
      (candidate) =>
          candidate.duration >= const Duration(milliseconds: 1000) &&
          candidate.duration <= const Duration(seconds: 3),
    );
    final originalPlayer = _playback.player;
    final midpoint =
        cue.start + Duration(microseconds: cue.duration.inMicroseconds ~/ 2);
    await _playback.player.setVolume(0);

    _stage('mkv_open');
    await _playback.openLocal(video.path, autoplay: false);
    await _playback.play();
    await _video.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 5),
    );
    await _waitFor(
      () =>
          _playback.duration > Duration.zero &&
          (_playback.player.state.width ?? 0) > 0 &&
          (_playback.player.state.height ?? 0) > 0,
    );
    await _playback.pause();
    final videoDuration = _playback.duration;
    final frame = await _playback.player.screenshot(format: 'image/png');
    _require(frame != null && frame.isNotEmpty, 'No decoded video frame.');
    _pass({
      'durationMs': videoDuration.inMilliseconds,
      'decodedWidth': _playback.player.state.width,
      'decodedHeight': _playback.player.state.height,
      'framePngBytes': frame!.length,
      'textureId': _video.id.value,
      'cueCount': cues.length,
    });

    _stage('mkv_seek_subtitle');
    await _playback.seek(midpoint);
    await _waitFor(() => _near(_playback.player.state.position, midpoint));
    _require(
      cueAt(cues, _playback.player.state.position) == cue,
      'Video seek selects another cue.',
    );
    _pass({
      'cueIndex': cue.index,
      'targetMs': midpoint.inMilliseconds,
      'nativePositionMs': _playback.player.state.position.inMilliseconds,
    });

    _stage('mkv_rate_1_5');
    await _playback.setRate(1.5);
    await _playback.play();
    await _waitFor(
      () => _playback.player.state.playing && !_playback.buffering,
    );
    final before = _playback.player.state.position;
    final rateWatch = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    final after = _playback.player.state.position;
    rateWatch.stop();
    await _playback.pause();
    final measuredRate =
        (after - before).inMicroseconds / rateWatch.elapsedMicroseconds;
    _require(
      (measuredRate - 1.5).abs() <= 0.4,
      '1.5x clock rate outside tolerance: $measuredRate',
    );
    _require(
      _playback.player.state.rate == 1.5,
      'Native rate did not become 1.5.',
    );
    _pass({
      'requestedRate': 1.5,
      'nativeRate': _playback.player.state.rate,
      'wallMs': rateWatch.elapsedMilliseconds,
      'mediaMs': (after - before).inMilliseconds,
      'measuredRate': measuredRate,
    });

    _stage('mkv_finite_loop');
    await _playback.setLoop(cue.start, cue.end, repeatCount: 2);
    await _playback.play();
    await _waitFor(
      () =>
          _playback.loop?.completed == true &&
          !_playback.playing &&
          !_playback.player.state.playing,
      timeout: const Duration(seconds: 7),
    );
    _require(
      _playback.loop?.completedPasses == 2,
      'Finite loop did not complete two passes.',
    );
    _require(
      _loopPasses.contains(1) && _loopPasses.contains(2),
      'Native loop pass events were incomplete.',
    );
    await _waitFor(() => _near(_playback.player.state.position, cue.end));
    _pass({
      'repeatCount': 2,
      'completedPasses': _playback.loop?.completedPasses,
      'observedPassEvents': List.of(_loopPasses),
      'endMs': cue.end.inMilliseconds,
      'nativePositionMs': _playback.player.state.position.inMilliseconds,
      'pausedAtEnd': !_playback.player.state.playing,
    });
    _playback.clearLoop();

    _stage('switch_mkv_to_mp3');
    await _playback.seek(midpoint);
    await _playback.openLocal(audio.path, position: midpoint, autoplay: false);
    await _waitFor(
      () =>
          _near(_playback.player.state.position, midpoint) &&
          _playback.duration > Duration.zero,
    );
    _require(
      identical(_playback.player, originalPlayer),
      'The shared native player was replaced.',
    );
    _require(
      _playback.player.state.rate == 1.5,
      'MP3 switch lost playback rate.',
    );
    _require(
      cueAt(cues, _playback.player.state.position) == cue,
      'MP3 switch lost the current subtitle cue.',
    );
    _require(
      (_playback.duration - videoDuration).inMilliseconds.abs() <= 1000,
      'Sample audio and video durations differ by over one second.',
    );
    _pass({
      'samePlayer': identical(_playback.player, originalPlayer),
      'durationMs': _playback.duration.inMilliseconds,
      'nativePositionMs': _playback.player.state.position.inMilliseconds,
      'cueIndex': cueAt(cues, _playback.player.state.position)?.index,
      'nativeRate': _playback.player.state.rate,
    });

    _stage('mp3_decode');
    final audioStart = _playback.player.state.position;
    await _playback.play();
    await _waitFor(
      () =>
          _playback.player.state.position >
              audioStart + const Duration(milliseconds: 350) &&
          (_playback.player.state.audioParams.sampleRate ?? 0) > 0,
    );
    await _playback.pause();
    _pass({
      'sampleRate': _playback.player.state.audioParams.sampleRate,
      'channels': _playback.player.state.audioParams.channelCount,
      'advancedMs':
          (_playback.player.state.position - audioStart).inMilliseconds,
    });

    _stage('switch_mp3_to_mkv');
    await _playback.seek(midpoint);
    await _playback.openLocal(video.path, position: midpoint, autoplay: false);
    await _waitFor(() => _near(_playback.player.state.position, midpoint));
    _require(
      identical(_playback.player, originalPlayer),
      'Return switch created another native player.',
    );
    _require(
      _playback.player.state.rate == 1.5,
      'Return switch lost playback rate.',
    );
    _require(
      cueAt(cues, _playback.player.state.position) == cue,
      'Return switch lost current subtitle cue.',
    );
    _require(_playback.player.state.volume == 0, 'Playback became audible.');
    _pass({
      'samePlayer': true,
      'nativePositionMs': _playback.player.state.position.inMilliseconds,
      'cueIndex': cue.index,
      'nativeRate': _playback.player.state.rate,
      'volume': _playback.player.state.volume,
    });
  }

  Future<void> _waitFor(
    bool Function() ready, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final watch = Stopwatch()..start();
    while (!ready()) {
      if (_cancelled) {
        throw StateError('Probe cancelled after its runtime limit.');
      }
      if (watch.elapsed >= timeout) {
        throw TimeoutException(
          '$_phase did not reach its expected native state.',
          timeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  bool _near(Duration actual, Duration target) =>
      (actual - target).inMilliseconds.abs() <= 250;

  void _stage(String name) {
    if (_cancelled) {
      throw StateError('Probe cancelled after its runtime limit.');
    }
    _phase = name;
    if (mounted) setState(() => _status = '验证中：$name');
    stdout.writeln('NATIVE_PROBE_STEP $name');
  }

  void _pass(Map<String, Object?> metrics) {
    _checks.add({'name': _phase, 'passed': true, ...metrics});
  }

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_nativeErrors?.cancel());
    _playback.removeListener(_observePlayback);
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('macOS 原生播放器验证')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status),
          const SizedBox(height: 8),
          Text(_directory.isEmpty ? '尚未选择文件夹' : _directory),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _running ? null : _chooseDirectory,
                child: const Text('选择并授权 Sample 文件夹'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _running || _directory.isEmpty ? null : _run,
                child: const Text('运行静音验证（约 15～30 秒）'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Video(controller: _video, controls: NoVideoControls),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _summary.isEmpty ? '结果将显示在这里。验证不会修改样本，全部播放静音。' : _summary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
