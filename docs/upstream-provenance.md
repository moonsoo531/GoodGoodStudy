# Upstream attribution

GoodGoodStudy selectively derives its local playback adapter and subtitle parsing/timeline logic from [Enjoy Player](https://github.com/baizhiheizi/enjoy_player), pinned at commit [`dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff`](https://github.com/baizhiheizi/enjoy_player/tree/dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff), under GNU AGPL v3. The complete upstream application, accounts, cloud services and branding are not included.

| GoodGoodStudy module | Upstream source and adaptation |
|---|---|
| `lib/playback/playback_transport.dart` | `lib/features/player/application/engines/media_kit/media_kit_player_engine.dart`: reduced local-only Player transport, native streams, open/seek/rate/play/pause/disposal. |
| `lib/playback/offline_playback.dart` | `lib/features/player/application/echo_enforcer.dart`: media-clock loop and generation/cancellation principles; local state and loop policy authored for this project. |
| `lib/subtitles/srt_parser.dart` | `lib/data/subtitle/subtitle_parser.dart`: adapted SRT scanning, newline handling and timestamp parsing; adds strict validation, stable sorting and immutable results. |
| `lib/subtitles/subtitle_cue.dart` | `lib/data/subtitle/transcript_line.dart`: simplified value-model behavior without account, cloud or AI fields. |
| `lib/subtitles/subtitle_timeline.dart` | `lib/features/transcript/data/transcript_timeline_codec.dart`: adapted binary search with containment, offset, overlap and neighboring-cue behavior. |
| Subtitle tests | Upstream parser/performance test categories informed synthetic boundary tests. No source subtitle files are bundled. |

The study, quiz and navigation modules, application UI, native local-file bridge and release tooling are project-specific additions. Original imported texts, readings and user records remain data rather than application source.

The project license is [AGPL v3](../LICENSE); an additional copy of the upstream license is retained at [licenses/Enjoy-Player-AGPL-3.0.txt](../licenses/Enjoy-Player-AGPL-3.0.txt). Third-party package and native component licenses are separate; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

A reviewed Flutter framework backport is retained under `tool/patches/`, with upstream PR, exact SDK revisions and hashes in its JSON metadata. It is from [Flutter PR 193372](https://github.com/flutter/flutter/pull/193372) under Flutter's BSD 3-Clause license. The SDK itself is not bundled. Applying that patch is an explicit developer action through `flutterw --apply-sdk-patch`.
