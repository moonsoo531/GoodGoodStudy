# Source provenance

## Current code: 0.9.0+31

The current project's own code and independently rewritten playback/subtitle implementation use [MIT](../LICENSE). The six identified Enjoy Player-derived legacy files were replaced in full; the old timeline entry point now exports the new cue lookup. New supporting modules are `lib/subtitles/cue_lookup.dart`, `lib/subtitles/src/parser_support.dart` and `lib/subtitles/src/track.dart`.

The authors worked in separate draft packages from the [interoperability contract](independent-replacement-contract.md), official SRT/WebVTT references, standard Dart/Flutter APIs and permitted MIT `media_kit` 1.2.6 APIs/package source. They recorded their inputs and independently authored synthetic tests without reading the legacy implementations, application tests or Enjoy Player snapshot. Reviewers could inspect the historical source and validate observable compatibility without sending its source or algorithms to the authors.

The source review found no additional Enjoy Player-specific expression requiring replacement outside the six-file scope. Short matching UI/test fragments were common Flutter constructions; matching platform scaffolding also matched Flutter's own BSD templates. Existing project synthetic tests had historically used upstream test categories as a reference; they are not described as newly isolated tests. The review found no copied distinctive upstream test fixtures or implementation fragments in them.

The identified source-dependency replacement route is closed for the current code. Input separation, lexical comparison and this review are process evidence, not a legal guarantee or proof of every copyright interest. The [independent replacement record](independent-replacement.md) fixes the current source hashes with the integration commit and records 187 targeted tests, 22 native smoke checks, analyzer and signed-package/in-place-update results. Physical-phone interaction, a real iCloud round trip and store review remain unverified. No upstream store exception or permission is claimed, and third-party components retain their own terms.

## Historical code: through 0.8.2

GoodGoodStudy versions through 0.8.2, including revision [`5fc65d6a05fba762bf3de69d1c86d72107b98cd7`](https://github.com/moonsoo531/GoodGoodStudy/tree/5fc65d6a05fba762bf3de69d1c86d72107b98cd7), selectively derived local playback and subtitle logic from [Enjoy Player](https://github.com/baizhiheizi/enjoy_player), pinned at commit [`dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff`](https://github.com/baizhiheizi/enjoy_player/tree/dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff), under GNU AGPL v3. Those versions retain the license and attribution under which they were released. The current MIT choice does not relicense that third-party code or change historical releases.

| Historical GoodGoodStudy module | Historical upstream source and adaptation |
|---|---|
| `lib/playback/playback_transport.dart` | `lib/features/player/application/engines/media_kit/media_kit_player_engine.dart`: reduced local-only Player transport, native streams, open/seek/rate/play/pause/disposal. |
| `lib/playback/offline_playback.dart` | `lib/features/player/application/echo_enforcer.dart`: media-clock loop and generation/cancellation principles; local state and loop policy authored for this project. |
| `lib/subtitles/srt_parser.dart` | `lib/data/subtitle/subtitle_parser.dart`: adapted SRT scanning, newline handling and timestamp parsing; adds strict validation, stable sorting and immutable results. |
| `lib/subtitles/subtitle_cue.dart` | `lib/data/subtitle/transcript_line.dart`: simplified value-model behavior without account, cloud or AI fields. |
| `lib/subtitles/subtitle_timeline.dart` | `lib/features/transcript/data/transcript_timeline_codec.dart`: adapted binary search with containment, offset, overlap and neighboring-cue behavior. |
| `lib/subtitles/webvtt_parser.dart` | `lib/data/subtitle/subtitle_parser.dart` / `VttParser`: behavior reference for the old block-based WebVTT parser, which retained authored ruby markup instead of stripping display tags. This historical relationship was also recorded in the subtitle module README. |
| Subtitle tests | Upstream parser/performance test categories informed synthetic boundary tests. No source subtitle files are bundled. |

The unmodified [Enjoy Player AGPL v3 text](../licenses/Enjoy-Player-AGPL-3.0.txt) is retained for this historical attribution. Historical root `LICENSE` files remain available in their revisions. The complete upstream application, accounts, cloud services and branding were not included.

## Project additions and other third parties

The study, quiz and navigation modules, application UI, native local-file/iCloud bridges and release tooling are project-specific additions, subject to the separately identified templates and patches. Original imported texts, readings and user records are user data; software licensing grants no rights to those materials.

Flutter-generated platform scaffolding retains Flutter's BSD terms. A reviewed Flutter framework backport is retained under `tool/patches/`, with upstream PR, exact SDK revisions and hashes in its JSON metadata. It is from [Flutter PR 193372](https://github.com/flutter/flutter/pull/193372) under Flutter's BSD 3-Clause license. The SDK itself is not bundled. Applying that patch is an explicit developer action through `flutterw --apply-sdk-patch`.

The `package_info_plus` copied-resource privacy-manifest correction has separate [patch provenance](app-store-package-info-privacy-patch.md) and retains the SDK's BSD notice. Dart packages and native playback components retain their own terms; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). The current MIT license does not clear the macOS libmpv/FFmpeg artifact or replace final SDK/store review.
