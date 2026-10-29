import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide PlaylistMode;
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/library/local_library.dart';
import 'package:offline_player/library/playlist_mode.dart';
import 'package:offline_player/playback/media_tracks.dart';
import 'package:offline_player/subtitles/subtitle_visibility.dart';
import 'package:offline_player/widgets/player_playlist.dart';
import 'package:offline_player/widgets/player_subtitles.dart';
import 'package:offline_player/widgets/player_track_sheet.dart';

Widget _localized(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationDelegates,
  home: Scaffold(body: child),
);

void main() {
  for (final language in ['zh', 'ja', 'en']) {
    testWidgets(
      '$language playlist translates chrome but preserves media titles',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        final locale = Locale(language);
        final strings = AppLocalizations(locale);
        const lessons = [
          LocalLesson(title: '第一课 日本語', videoPath: '/lessons/01.mp4'),
          LocalLesson(title: '第二课 中文', audioPath: '/lessons/02.mp3'),
        ];
        try {
          await tester.pumpWidget(
            _localized(
              locale,
              PlayerPlaylist(
                lessons: lessons,
                current: lessons.first,
                playing: false,
                enabled: true,
                autoAdvance: true,
                mode: PlaylistMode.sequential,
                onModeChanged: (_) {},
                onSelect: (_) {},
                onRemove: (_) {},
                onReorder: (_, _) {},
                onClear: () {},
                onAutoAdvanceChanged: (_) {},
                statusOf: (_) =>
                    const PlaylistItemStatus(duration: Duration(minutes: 3)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('第一课 日本語'), findsOneWidget);
          expect(find.text('第二课 中文'), findsOneWidget);
          expect(
            find.text(strings.text('共 {count} 项', {'count': 2})),
            findsOneWidget,
          );
          expect(find.byTooltip(strings.text('定位当前项')), findsOneWidget);
          expect(find.text(strings.text('当前媒体 · 已暂停')), findsOneWidget);
          if (language != 'zh') {
            expect(find.text('当前媒体 · 已暂停'), findsNothing);
          }
          await tester.tap(find.text(strings.text('顺序播放')));
          await tester.pumpAndSettle();
          expect(find.text(strings.text('单项循环')), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );

    testWidgets(
      '$language caption controls localize without changing captions',
      (tester) async {
        final locale = Locale(language);
        final strings = AppLocalizations(locale);
        await tester.pumpWidget(
          _localized(
            locale,
            Column(
              children: [
                SubtitleVisibilityControls(
                  value: const SubtitleVisibility(),
                  onChanged: (_) {},
                ),
                const SubtitleListText(
                  visible: false,
                  text: '日本語の原文',
                  style: TextStyle(),
                ),
                const ScreenSubtitleText(
                  visible: true,
                  text: '教材の日本語',
                  style: TextStyle(),
                  showReadings: false,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(strings.text('画面字幕')), findsOneWidget);
        expect(find.byTooltip(strings.text('隐藏列表字幕')), findsOneWidget);
        expect(find.text(strings.text('列表字幕已隐藏')), findsOneWidget);
        expect(find.text('教材の日本語'), findsOneWidget);
        expect(find.text('日本語の原文'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$language track sheet preserves source titles and selections',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        final locale = Locale(language);
        final strings = AppLocalizations(locale);
        final source = _Source();
        final tracks = MediaTracksController.withSource(source);
        await tracks.applyPreferences(
          const MediaTrackPreferences(subtitleSource: SubtitleSource.off),
          hasExternalSubtitles: true,
        );
        try {
          await tester.pumpWidget(
            _localized(
              locale,
              PlayerTrackSheet(
                controller: tracks,
                enabled: true,
                onPickExternal: () {},
                onChanged: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(strings.text('音轨与字幕')), findsOneWidget);
          expect(
            find.text('${strings.text('日语')} · 日本語音声 · AAC'),
            findsOneWidget,
          );
          // Even a metadata title that matches a UI key stays in its source language.
          expect(
            find.text('关闭字幕'),
            language == 'zh' ? findsNWidgets(2) : findsOneWidget,
          );
          expect(
            find.text(strings.text('关闭字幕')),
            language == 'zh' ? findsNWidgets(2) : findsOneWidget,
          );
          final off = tester.widget<ListTile>(
            find.byKey(const ValueKey('subtitle-off')),
          );
          expect(off.selected, isTrue);
          final japaneseAudio = find.byKey(const ValueKey('audio-1'));
          await tester.ensureVisible(japaneseAudio);
          await tester.tap(japaneseAudio);
          await tester.pumpAndSettle();
          expect(tracks.preferences.audioId, '1');
          expect(tracks.preferences.subtitleSource, SubtitleSource.off);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tracks.dispose();
          await source.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  }
  for (final language in ['ja', 'en']) {
    testWidgets(
      '$language generated track labels differ from identical source titles',
      (tester) async {
        final locale = Locale(language);
        final strings = AppLocalizations(locale);
        final source = _Source();
        source.availableTracks = const Tracks(
          audio: [AudioTrack('1', '音轨 1', null), AudioTrack('2', null, null)],
          subtitle: [
            SubtitleTrack('1', '字幕 1', null),
            SubtitleTrack('2', null, null),
          ],
        );
        final tracks = MediaTracksController.withSource(source);
        await tracks.applyPreferences(
          const MediaTrackPreferences(subtitleSource: SubtitleSource.off),
          hasExternalSubtitles: false,
        );
        try {
          await tester.pumpWidget(
            _localized(
              locale,
              PlayerTrackSheet(
                controller: tracks,
                enabled: true,
                onPickExternal: () {},
                onChanged: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('音轨 1'), findsOneWidget);
          expect(find.text('字幕 1'), findsOneWidget);
          expect(
            find.text(strings.text('音轨 {id}', {'id': '2'})),
            findsOneWidget,
          );
          expect(
            find.text(strings.text('字幕 {id}', {'id': '2'})),
            findsOneWidget,
          );
          expect(
            tracks.audioOptions
                .singleWhere((option) => option.id == '1')
                .isGeneratedLabel,
            isFalse,
          );
          expect(
            tracks.audioOptions
                .singleWhere((option) => option.id == '2')
                .isGeneratedLabel,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tracks.dispose();
          await source.close();
        }
      },
    );
  }
}

class _Source implements MediaTrackSource {
  final _tracks = StreamController<Tracks>.broadcast(sync: true);
  final _selected = StreamController<Track>.broadcast(sync: true);
  @override
  Tracks availableTracks = const Tracks(
    audio: [
      AudioTrack('auto', null, null),
      AudioTrack('no', null, null),
      AudioTrack('1', '日本語音声', 'ja', codec: 'aac'),
      AudioTrack('2', '关闭字幕', null),
    ],
  );
  @override
  Track selectedTracks = const Track();
  @override
  Stream<Tracks> get tracksStream => _tracks.stream;
  @override
  Stream<Track> get selectedStream => _selected.stream;
  @override
  Future<void> selectAudio(AudioTrack track) async {
    selectedTracks = selectedTracks.copyWith(audio: track);
    _selected.add(selectedTracks);
  }

  @override
  Future<void> selectSubtitle(SubtitleTrack track) async {
    selectedTracks = selectedTracks.copyWith(subtitle: track);
    _selected.add(selectedTracks);
  }

  Future<void> close() async {
    await _tracks.close();
    await _selected.close();
  }
}
