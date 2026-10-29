import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:offline_player/playback/media_tracks.dart';

const _tracks = Tracks(
  audio: [
    AudioTrack('auto', null, null),
    AudioTrack('no', null, null),
    AudioTrack('1', '主音轨', 'jpn', codec: 'aac'),
    AudioTrack('2', 'Commentary', 'eng'),
  ],
  subtitle: [
    SubtitleTrack('auto', null, null),
    SubtitleTrack('no', null, null),
    SubtitleTrack('3', '日文', 'ja', codec: 'ass'),
    SubtitleTrack('4', '中文', 'zho'),
  ],
);

void main() {
  test(
    'track choices label embedded tracks and exclude URI/data tracks',
    () async {
      final source = _TrackSource(
        Tracks(
          audio: [..._tracks.audio, AudioTrack.uri('/temporary/other.mp3')],
          subtitle: [
            ..._tracks.subtitle,
            SubtitleTrack.uri('/temporary/external.srt'),
            SubtitleTrack.data('some external subtitle text'),
          ],
        ),
      );
      final controller = MediaTracksController.withSource(source);
      expect(controller.audioOptions.map((track) => track.id), [
        'auto',
        'no',
        '1',
        '2',
      ]);
      expect(controller.audioOptions[2].label, '日语 · 主音轨 · AAC');
      expect(controller.embeddedSubtitleOptions.map((track) => track.id), [
        'auto',
        '3',
        '4',
      ]);
      expect(controller.embeddedSubtitleOptions[1].label, '日语 · 日文 · ASS');
      controller.dispose();
      await source.close();
    },
  );

  test('defaults prefer external, then embedded, then off', () async {
    final source = _TrackSource(_tracks);
    final controller = MediaTracksController.withSource(source);
    expect(
      controller.defaults(hasExternalSubtitles: true).subtitleSource,
      SubtitleSource.external,
    );
    expect(
      controller.defaults(hasExternalSubtitles: false).subtitleSource,
      SubtitleSource.embedded,
    );
    source.setTracks(const Tracks());
    expect(
      controller.defaults(hasExternalSubtitles: false).subtitleSource,
      SubtitleSource.off,
    );
    controller.dispose();
    await source.close();
  });

  test(
    'new media defaults use current tracks before the stream arrives',
    () async {
      final source = _TrackSource(const Tracks());
      final controller = MediaTracksController.withSource(source);
      source.availableTracks = _tracks;
      expect(
        controller.defaults(hasExternalSubtitles: false).subtitleSource,
        SubtitleSource.embedded,
      );
      controller.dispose();
      await source.close();
    },
  );

  test(
    'saved embedded and audio selections are applied to current media',
    () async {
      final source = _TrackSource(_tracks);
      final controller = MediaTracksController.withSource(source);
      await controller.applyPreferences(
        const MediaTrackPreferences(
          audioId: '2',
          subtitleSource: SubtitleSource.embedded,
          subtitleId: '3',
        ),
        hasExternalSubtitles: true,
      );
      expect(source.commands, ['audio:2', 'subtitle:3']);
      expect(controller.preferences.audioId, '2');
      expect(controller.preferences.subtitleId, '3');
      expect(controller.useEmbeddedSubtitles, isTrue);
      expect(controller.useExternalSubtitles, isFalse);
      expect(controller.selectedTracks.audio.id, '2');
      controller.dispose();
      await source.close();
    },
  );

  test(
    'external, embedded and off selections never render two sources',
    () async {
      final source = _TrackSource(_tracks);
      final controller = MediaTracksController.withSource(source);
      await controller.applyPreferences(
        const MediaTrackPreferences(),
        hasExternalSubtitles: true,
      );
      expect(source.selectedTracks.subtitle.id, 'no');
      expect(controller.useExternalSubtitles, isTrue);
      expect(controller.useEmbeddedSubtitles, isFalse);
      await controller.selectEmbeddedSubtitles('4');
      expect(source.selectedTracks.subtitle.id, '4');
      expect(controller.useExternalSubtitles, isFalse);
      expect(controller.useEmbeddedSubtitles, isTrue);
      await controller.selectExternalSubtitles();
      expect(source.selectedTracks.subtitle.id, 'no');
      expect(controller.useExternalSubtitles, isTrue);
      await controller.disableSubtitles();
      expect(source.selectedTracks.subtitle.id, 'no');
      expect(controller.useEmbeddedSubtitles, isFalse);
      expect(controller.useExternalSubtitles, isFalse);
      expect(controller.preferences.subtitleSource, SubtitleSource.off);
      controller.dispose();
      await source.close();
    },
  );

  test(
    'missing saved IDs fall back, but explicit invalid selection is rejected',
    () async {
      final source = _TrackSource(_tracks);
      final controller = MediaTracksController.withSource(source);
      await controller.applyPreferences(
        const MediaTrackPreferences(
          audioId: '99',
          subtitleSource: SubtitleSource.embedded,
          subtitleId: '99',
        ),
        hasExternalSubtitles: false,
      );
      expect(source.commands, ['audio:auto', 'subtitle:auto']);
      await expectLater(
        controller.selectAudio('file:///tmp/new.mp3'),
        throwsArgumentError,
      );
      await expectLater(
        controller.selectEmbeddedSubtitles('file:///tmp/new.srt'),
        throwsArgumentError,
      );
      expect(source.commands, ['audio:auto', 'subtitle:auto']);
      await controller.selectAudio('no');
      expect(controller.preferences.audioId, 'no');
      controller.dispose();
      await source.close();
    },
  );

  test(
    'unavailable subtitle sources fall back without losing explicit off',
    () async {
      final source = _TrackSource(const Tracks());
      final controller = MediaTracksController.withSource(source);
      await controller.applyPreferences(
        const MediaTrackPreferences(subtitleSource: SubtitleSource.embedded),
        hasExternalSubtitles: true,
      );
      expect(controller.useExternalSubtitles, isTrue);
      await controller.applyPreferences(
        const MediaTrackPreferences(),
        hasExternalSubtitles: false,
      );
      expect(controller.preferences.subtitleSource, SubtitleSource.off);
      await expectLater(controller.selectExternalSubtitles(), throwsStateError);
      await expectLater(controller.selectEmbeddedSubtitles(), throwsStateError);
      source.setTracks(_tracks);
      await controller.applyPreferences(
        const MediaTrackPreferences(subtitleSource: SubtitleSource.off),
        hasExternalSubtitles: true,
      );
      expect(controller.preferences.subtitleSource, SubtitleSource.off);
      expect(source.selectedTracks.subtitle.id, 'no');
      controller.dispose();
      await source.close();
    },
  );

  test(
    'native updates notify listeners without changing external intent',
    () async {
      final source = _TrackSource(_tracks);
      final controller = MediaTracksController.withSource(source);
      await controller.applyPreferences(
        const MediaTrackPreferences(),
        hasExternalSubtitles: true,
      );
      var changes = 0;
      controller.addListener(() => changes++);
      source.setTracks(const Tracks());
      source.emitSelected(const Track(audio: AudioTrack('2', null, null)));
      expect(changes, 2);
      expect(controller.preferences.subtitleSource, SubtitleSource.external);
      expect(controller.embeddedSubtitleOptions, isEmpty);
      controller.dispose();
      source.setTracks(_tracks);
      expect(changes, 2);
      await source.close();
    },
  );

  test('preferences round trip and tolerate unknown old fields', () {
    const preferences = MediaTrackPreferences(
      audioId: '2',
      subtitleSource: SubtitleSource.embedded,
      subtitleId: '3',
    );
    final restored = MediaTrackPreferences.fromJson(preferences.toJson());
    expect(restored.toJson(), preferences.toJson());
    final fallback = MediaTrackPreferences.fromJson({
      'audioId': 3,
      'subtitleSource': 'removed-mode',
    });
    expect(fallback.audioId, 'auto');
    expect(fallback.subtitleSource, SubtitleSource.external);
  });
}

class _TrackSource implements MediaTrackSource {
  _TrackSource(this.availableTracks);

  @override
  Tracks availableTracks;
  @override
  Track selectedTracks = const Track();
  final _available = StreamController<Tracks>.broadcast(sync: true);
  final _selected = StreamController<Track>.broadcast(sync: true);
  final commands = <String>[];

  @override
  Stream<Tracks> get tracksStream => _available.stream;
  @override
  Stream<Track> get selectedStream => _selected.stream;

  void setTracks(Tracks tracks) {
    availableTracks = tracks;
    _available.add(tracks);
  }

  void emitSelected(Track tracks) {
    selectedTracks = tracks;
    _selected.add(tracks);
  }

  @override
  Future<void> selectAudio(AudioTrack track) async {
    commands.add('audio:${track.id}');
    emitSelected(selectedTracks.copyWith(audio: track));
  }

  @override
  Future<void> selectSubtitle(SubtitleTrack track) async {
    commands.add('subtitle:${track.id}');
    emitSelected(selectedTracks.copyWith(subtitle: track));
  }

  Future<void> close() async {
    await _available.close();
    await _selected.close();
  }
}
