import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:offline_player/playback/media_tracks.dart';
import 'package:offline_player/widgets/player_track_sheet.dart';

const _availableTracks = Tracks(
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
  late _FakeTrackSource source;
  late MediaTracksController controller;
  var changed = 0;
  var picked = 0;

  Future<void> initialize(WidgetTester tester) async {
    changed = 0;
    picked = 0;
    source = _FakeTrackSource(_availableTracks);
    controller = MediaTracksController.withSource(source);
    final applying = controller.applyPreferences(
      const MediaTrackPreferences(subtitleSource: SubtitleSource.off),
      hasExternalSubtitles: true,
    );
    await tester.pump();
    await applying;
    source.commands.clear();
  }

  tearDown(() async {
    controller.dispose();
    await source.close();
  });

  Widget sheet({bool enabled = true}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: PlayerTrackSheet(
          controller: controller,
          enabled: enabled,
          onPickExternal: () => picked++,
          onChanged: () => changed++,
        ),
      ),
    ),
  );

  Future<void> choose(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String key) =>
      tester.widget<ListTile>(find.byKey(ValueKey(key))).selected;

  int selectedSubtitles(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .where(
        (tile) =>
            (tile.key as ValueKey<String>).value.startsWith('subtitle-') &&
            tile.selected,
      )
      .length;

  testWidgets('audio and subtitle choices are labeled and mutually exclusive', (
    tester,
  ) async {
    await initialize(tester);
    await tester.pumpWidget(sheet());
    expect(find.text('音轨与字幕'), findsOneWidget);
    expect(find.text('自动选择'), findsOneWidget);
    expect(find.text('关闭音轨'), findsOneWidget);
    expect(find.text('日语 · 主音轨 · AAC'), findsOneWidget);
    expect(find.textContaining('不提供逐句列表或假名'), findsOneWidget);
    expect(selected(tester, 'audio-auto'), isTrue);
    expect(selectedSubtitles(tester), 1);

    await choose(tester, 'audio-2');
    expect(controller.preferences.audioId, '2');
    expect(selected(tester, 'audio-2'), isTrue);
    expect(selected(tester, 'audio-auto'), isFalse);

    await choose(tester, 'subtitle-external');
    expect(controller.useExternalSubtitles, isTrue);
    expect(source.selectedTracks.subtitle.id, 'no');
    expect(selectedSubtitles(tester), 1);

    await choose(tester, 'subtitle-embedded-auto');
    expect(controller.useEmbeddedSubtitles, isTrue);
    expect(controller.useExternalSubtitles, isFalse);
    expect(selected(tester, 'subtitle-external'), isFalse);
    expect(selected(tester, 'subtitle-embedded-auto'), isTrue);
    expect(selectedSubtitles(tester), 1);

    await choose(tester, 'subtitle-embedded-4');
    expect(source.selectedTracks.subtitle.id, '4');
    expect(selected(tester, 'subtitle-embedded-auto'), isFalse);
    expect(selected(tester, 'subtitle-embedded-4'), isTrue);
    expect(selectedSubtitles(tester), 1);

    await choose(tester, 'subtitle-off');
    expect(controller.preferences.subtitleSource, SubtitleSource.off);
    expect(source.selectedTracks.subtitle.id, 'no');
    expect(selectedSubtitles(tester), 1);
    expect(changed, 5);
    final calls = source.commands.length;
    await choose(tester, 'subtitle-off');
    expect(source.commands, hasLength(calls));
    expect(changed, 5);
  });

  testWidgets(
    'unavailable external subtitles cannot be selected; picker remains available',
    (tester) async {
      await initialize(tester);
      controller.setExternalSubtitlesAvailable(false);
      await tester.pumpWidget(sheet());
      final external = tester.widget<ListTile>(
        find.byKey(const ValueKey('subtitle-external')),
      );
      expect(external.enabled, isFalse);
      expect(external.onTap, isNull);
      expect(find.text('尚未载入外部字幕'), findsOneWidget);
      await choose(tester, 'subtitle-external');
      expect(controller.preferences.subtitleSource, SubtitleSource.off);
      expect(changed, 0);
      await choose(tester, 'pick-external-subtitles');
      expect(picked, 1);
      expect(source.commands, isEmpty);
      expect(changed, 0);
    },
  );

  testWidgets('disabled sheet prevents selections and external picker', (
    tester,
  ) async {
    await initialize(tester);
    await tester.pumpWidget(sheet(enabled: false));
    expect(find.text('打开媒体后可选择音轨和字幕。'), findsOneWidget);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .every((tile) => !tile.enabled && tile.onTap == null),
      isTrue,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('pick-external-subtitles')),
          )
          .onPressed,
      isNull,
    );
    await choose(tester, 'audio-1');
    expect(source.commands, isEmpty);
    expect(changed, 0);
    expect(picked, 0);
  });

  testWidgets(
    'native track changes refresh the open sheet without a parent rebuild',
    (tester) async {
      await initialize(tester);
      await tester.pumpWidget(sheet());
      source.setAvailable(
        const Tracks(audio: [AudioTrack('5', '新音轨', 'ja')], subtitle: []),
      );
      await tester.pump();
      expect(find.text('日语 · 新音轨'), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('subtitle-embedded-auto')),
        findsNothing,
      );
      expect(find.text('当前媒体没有内嵌字幕。'), findsOneWidget);
      expect(changed, 0);
      controller.setExternalSubtitlesAvailable(false);
      await tester.pump();
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('subtitle-external')))
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets(
    'selection waits for the native command and prevents overlapping actions',
    (tester) async {
      await initialize(tester);
      final pending = Completer<void>();
      source.audioWait = pending.future;
      await tester.pumpWidget(sheet());
      await tester.ensureVisible(find.byKey(const ValueKey('audio-2')));
      await tester.tap(find.byKey(const ValueKey('audio-2')));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(controller.preferences.audioId, 'auto');
      expect(changed, 0);
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .every((tile) => !tile.enabled),
        isTrue,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('pick-external-subtitles')),
            )
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(controller.preferences.audioId, '2');
      expect(changed, 1);
      expect(source.commands, ['audio:2']);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'selection errors stay in the sheet and successful retry clears them',
    (tester) async {
      await initialize(tester);
      source.failAudio = true;
      await tester.pumpWidget(sheet());
      await choose(tester, 'audio-2');
      expect(find.text('切换失败：音轨暂时无法切换'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(controller.preferences.audioId, 'auto');
      expect(selected(tester, 'audio-auto'), isTrue);
      expect(changed, 0);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('track-selection-error')))
            .dy,
        greaterThanOrEqualTo(0),
      );
      source.failAudio = false;
      await choose(tester, 'audio-1');
      expect(find.byKey(const ValueKey('track-selection-error')), findsNothing);
      expect(controller.preferences.audioId, '1');
      expect(changed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a completed command is persisted when the sheet closes while waiting',
    (tester) async {
      await initialize(tester);
      final pending = Completer<void>();
      source.audioWait = pending.future;
      await tester.pumpWidget(sheet());
      await tester.ensureVisible(find.byKey(const ValueKey('audio-2')));
      await tester.tap(find.byKey(const ValueKey('audio-2')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(controller.preferences.audioId, '2');
      expect(changed, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeTrackSource implements MediaTrackSource {
  _FakeTrackSource(this.availableTracks);

  @override
  Tracks availableTracks;
  @override
  Track selectedTracks = const Track();
  final _available = StreamController<Tracks>.broadcast(sync: true);
  final _selected = StreamController<Track>.broadcast(sync: true);
  final commands = <String>[];
  bool failAudio = false;
  Future<void>? audioWait;

  @override
  Stream<Tracks> get tracksStream => _available.stream;
  @override
  Stream<Track> get selectedStream => _selected.stream;

  void setAvailable(Tracks tracks) {
    availableTracks = tracks;
    _available.add(tracks);
  }

  @override
  Future<void> selectAudio(AudioTrack track) async {
    commands.add('audio:${track.id}');
    await audioWait;
    if (failAudio) throw StateError('音轨暂时无法切换');
    selectedTracks = selectedTracks.copyWith(audio: track);
    _selected.add(selectedTracks);
  }

  @override
  Future<void> selectSubtitle(SubtitleTrack track) async {
    commands.add('subtitle:${track.id}');
    selectedTracks = selectedTracks.copyWith(subtitle: track);
    _selected.add(selectedTracks);
  }

  Future<void> close() async {
    await _available.close();
    await _selected.close();
  }
}
