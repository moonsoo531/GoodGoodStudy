import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// External subtitles are rendered by the study player's cue/ruby widgets;
/// embedded subtitles are rendered by media_kit. Only one source is active.
enum SubtitleSource { off, external, embedded }

@immutable
class MediaTrackPreferences {
  const MediaTrackPreferences({
    this.audioId = 'auto',
    this.subtitleSource = SubtitleSource.external,
    this.subtitleId = 'auto',
  });

  final String audioId;
  final SubtitleSource subtitleSource;
  final String subtitleId;

  MediaTrackPreferences copyWith({
    String? audioId,
    SubtitleSource? subtitleSource,
    String? subtitleId,
  }) => MediaTrackPreferences(
    audioId: audioId ?? this.audioId,
    subtitleSource: subtitleSource ?? this.subtitleSource,
    subtitleId: subtitleId ?? this.subtitleId,
  );

  Map<String, dynamic> toJson() => {
    'audioId': audioId,
    'subtitleSource': subtitleSource.name,
    'subtitleId': subtitleId,
  };

  factory MediaTrackPreferences.fromJson(Map<String, dynamic> json) {
    final source = SubtitleSource.values.where(
      (value) => value.name == json['subtitleSource'],
    );
    return MediaTrackPreferences(
      audioId: json['audioId'] is String ? json['audioId'] as String : 'auto',
      subtitleSource: source.firstOrNull ?? SubtitleSource.external,
      subtitleId: json['subtitleId'] is String
          ? json['subtitleId'] as String
          : 'auto',
    );
  }
}

@immutable
class MediaTrackOption {
  const MediaTrackOption({
    required this.id,
    required this.label,
    this.language,
    this.isGeneratedLabel = false,
  });

  final String id;
  final String label;
  final String? language;

  /// Distinguishes an app-generated track number from an identical source title.
  final bool isGeneratedLabel;
}

/// Narrow adapter so track selection can be tested without a native player.
abstract interface class MediaTrackSource {
  Tracks get availableTracks;
  Track get selectedTracks;
  Stream<Tracks> get tracksStream;
  Stream<Track> get selectedStream;
  Future<void> selectAudio(AudioTrack track);
  Future<void> selectSubtitle(SubtitleTrack track);
}

class MediaTracksController extends ChangeNotifier {
  MediaTracksController(Player player)
    : this.withSource(_MediaKitTrackSource(player));

  @visibleForTesting
  MediaTracksController.withSource(this._source) {
    _tracks = _source.availableTracks;
    _selected = _source.selectedTracks;
    _subscriptions.addAll([
      _source.tracksStream.listen((value) {
        _tracks = value;
        _notify();
      }),
      _source.selectedStream.listen((value) {
        _selected = value;
        _notify();
      }),
    ]);
  }

  final MediaTrackSource _source;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late Tracks _tracks;
  late Track _selected;
  MediaTrackPreferences _preferences = const MediaTrackPreferences();
  Future<void> _commands = Future.value();
  bool _disposed = false;
  bool _hasExternalSubtitles = false;

  MediaTrackPreferences get preferences => _preferences;
  Track get selectedTracks => _selected;
  bool get hasExternalSubtitles => _hasExternalSubtitles;
  bool get hasEmbeddedSubtitles => _embeddedSubtitles.isNotEmpty;
  bool get useExternalSubtitles =>
      _preferences.subtitleSource == SubtitleSource.external &&
      _hasExternalSubtitles;
  bool get useEmbeddedSubtitles =>
      _preferences.subtitleSource == SubtitleSource.embedded;

  List<AudioTrack> get _embeddedAudio => _tracks.audio
      .where((track) => !track.uri && track.id != 'auto' && track.id != 'no')
      .toList();
  List<SubtitleTrack> get _embeddedSubtitles => _tracks.subtitle
      .where(
        (track) =>
            !track.uri && !track.data && track.id != 'auto' && track.id != 'no',
      )
      .toList();

  List<MediaTrackOption> get audioOptions => [
    const MediaTrackOption(id: 'auto', label: '自动选择'),
    const MediaTrackOption(id: 'no', label: '关闭音轨'),
    for (final track in _embeddedAudio)
      MediaTrackOption(
        id: track.id,
        label: _label(track.id, track.title, track.language, track.codec, '音轨'),
        language: track.language,
        isGeneratedLabel:
            (track.title?.trim().isEmpty ?? true) &&
            (track.language?.trim().isEmpty ?? true),
      ),
  ];

  List<MediaTrackOption> get embeddedSubtitleOptions => [
    if (hasEmbeddedSubtitles)
      const MediaTrackOption(id: 'auto', label: '自动选择内嵌字幕'),
    for (final track in _embeddedSubtitles)
      MediaTrackOption(
        id: track.id,
        label: _label(track.id, track.title, track.language, track.codec, '字幕'),
        language: track.language,
        isGeneratedLabel:
            (track.title?.trim().isEmpty ?? true) &&
            (track.language?.trim().isEmpty ?? true),
      ),
  ];

  MediaTrackPreferences defaults({required bool hasExternalSubtitles}) {
    _tracks = _source.availableTracks;
    return MediaTrackPreferences(
      subtitleSource: hasExternalSubtitles
          ? SubtitleSource.external
          : hasEmbeddedSubtitles
          ? SubtitleSource.embedded
          : SubtitleSource.off,
    );
  }

  /// Call after opening a local media file. Missing saved tracks fall back to
  /// automatic selection; an unavailable subtitle source falls back to a
  /// source that exists for this file, or off.
  Future<void> applyPreferences(
    MediaTrackPreferences preferences, {
    required bool hasExternalSubtitles,
  }) => _execute(() async {
    _tracks = _source.availableTracks;
    _selected = _source.selectedTracks;
    _hasExternalSubtitles = hasExternalSubtitles;
    final audio = _audio(preferences.audioId, fallback: true);
    var source = preferences.subtitleSource;
    if (source == SubtitleSource.external && !hasExternalSubtitles) {
      source = hasEmbeddedSubtitles
          ? SubtitleSource.embedded
          : SubtitleSource.off;
    } else if (source == SubtitleSource.embedded && !hasEmbeddedSubtitles) {
      source = hasExternalSubtitles
          ? SubtitleSource.external
          : SubtitleSource.off;
    }
    final subtitle = source == SubtitleSource.embedded
        ? _subtitle(preferences.subtitleId, fallback: true)
        : SubtitleTrack.no();
    await _source.selectAudio(audio);
    await _source.selectSubtitle(subtitle);
    _preferences = MediaTrackPreferences(
      audioId: audio.id,
      subtitleSource: source,
      subtitleId: source == SubtitleSource.embedded ? subtitle.id : 'auto',
    );
    _notify();
  });

  Future<void> selectAudio(String id) => _execute(() async {
    final track = _audio(id);
    await _source.selectAudio(track);
    _preferences = _preferences.copyWith(audioId: track.id);
    _notify();
  });

  void setExternalSubtitlesAvailable(bool available) {
    _hasExternalSubtitles = available;
    _notify();
  }

  Future<void> selectExternalSubtitles() => _execute(() async {
    if (!_hasExternalSubtitles) {
      throw StateError('请先载入外部字幕。');
    }
    await _source.selectSubtitle(SubtitleTrack.no());
    _preferences = _preferences.copyWith(
      subtitleSource: SubtitleSource.external,
      subtitleId: 'auto',
    );
    _notify();
  });

  Future<void> selectEmbeddedSubtitles([String id = 'auto']) =>
      _execute(() async {
        if (!hasEmbeddedSubtitles) {
          throw StateError('当前媒体没有内嵌字幕。');
        }
        final track = _subtitle(id);
        await _source.selectSubtitle(track);
        _preferences = _preferences.copyWith(
          subtitleSource: SubtitleSource.embedded,
          subtitleId: track.id,
        );
        _notify();
      });

  Future<void> disableSubtitles() => _execute(() async {
    await _source.selectSubtitle(SubtitleTrack.no());
    _preferences = _preferences.copyWith(subtitleSource: SubtitleSource.off);
    _notify();
  });

  AudioTrack _audio(String id, {bool fallback = false}) {
    if (id == 'auto') return AudioTrack.auto();
    if (id == 'no') return AudioTrack.no();
    for (final track in _embeddedAudio) {
      if (track.id == id) return track;
    }
    if (fallback) return AudioTrack.auto();
    throw ArgumentError.value(id, 'id', '音轨不在当前媒体中。');
  }

  SubtitleTrack _subtitle(String id, {bool fallback = false}) {
    if (id == 'auto') return SubtitleTrack.auto();
    for (final track in _embeddedSubtitles) {
      if (track.id == id) return track;
    }
    if (fallback) return SubtitleTrack.auto();
    throw ArgumentError.value(id, 'id', '字幕轨道不在当前媒体中。');
  }

  Future<void> _execute(Future<void> Function() action) {
    final next = _commands.then((_) async {
      if (_disposed) return;
      await action();
    });
    _commands = next.catchError((Object _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

class _MediaKitTrackSource implements MediaTrackSource {
  const _MediaKitTrackSource(this.player);
  final Player player;

  @override
  Tracks get availableTracks => player.state.tracks;
  @override
  Track get selectedTracks => player.state.track;
  @override
  Stream<Tracks> get tracksStream => player.stream.tracks;
  @override
  Stream<Track> get selectedStream => player.stream.track;
  @override
  Future<void> selectAudio(AudioTrack track) => player.setAudioTrack(track);
  @override
  Future<void> selectSubtitle(SubtitleTrack track) =>
      player.setSubtitleTrack(track);
}

String _label(
  String id,
  String? title,
  String? language,
  String? codec,
  String fallback,
) {
  final parts = <String>[];
  if (language != null && language.trim().isNotEmpty) {
    parts.add(switch (language.toLowerCase()) {
      'ja' || 'jpn' => '日语',
      'zh' || 'zho' || 'chi' => '中文',
      'en' || 'eng' => '英语',
      'ko' || 'kor' => '韩语',
      _ => language,
    });
  }
  if (title != null && title.trim().isNotEmpty) parts.add(title.trim());
  if (parts.isEmpty) parts.add('$fallback $id');
  if (codec != null && codec.trim().isNotEmpty) parts.add(codec.toUpperCase());
  return parts.join(' · ');
}
