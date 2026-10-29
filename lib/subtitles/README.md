# Local subtitles

`subtitles.dart` is the public import. This module imports only `dart:collection` and local files. It performs no network or filesystem operations.

## Contract

- `parseSrt(String)` returns an immutable list sorted by start time. `SubtitleCue.index` is its zero-based chronological position, independent of original SRT numbering. Identical start times retain source order.
- `parseWebVtt(String)` uses the same cue model and lookup contract. It accepts `HH:MM:SS.mmm` or `MM:SS.mmm`, optional cue identifiers and timing settings, and skips `WEBVTT` header metadata plus `NOTE`, `STYLE` and `REGION` blocks. Unsupported layout/style settings are not executed. Headerless timestamp blocks are accepted. Invalid timing ranges are discarded.
- Source dialogue, bracket readings, speaker labels, sound effects, multiline text and markup are retained. Leading/trailing whitespace around the complete cue is trimmed.
- UTF-8 decoding is the caller's responsibility. The parser accepts a leading Unicode BOM, CRLF/LF/CR line separators, comma/dot millisecond separators, numbered/indexless cues and one/two-digit hours. Invalid timestamps, empty cues, zero-length cues and reversed ranges are discarded.
- `cueAt(cues, position, offset: ...)` uses inclusive start/exclusive end. A positive offset delays subtitles; the comparison uses `position - offset`. Stored times are never changed. With overlapping cues, the most recently started cue that still contains the position wins; an earlier long cue may resume when a later short cue ends.
- `previousCue`/`nextCue` return chronological neighbors while a cue is active. In a gap, they return the nearest preceding/following cue. They return `null` at the corresponding end of the track.
- All lookup functions require start-time-sorted input. Lists returned by the parser carry a prefix maximum-end index so gaps and nonoverlapping tracks take `O(log n)` lookup. Overlap fallback is `O(log n + k)` in the affected region. Arbitrary externally supplied sorted lists are supported without cached metadata; gap/overlap fallback can take `O(n)`.

## Manually authored ruby

`parseRubyText(String)` returns an immutable list of `RubyTextSegment(text: ..., reading: ...)`. For `<ruby>漢字<rt>かんじ</rt></ruby>`, `text` is `漢字` and `reading` is `かんじ`. It reads only the annotation that is already in the file. It performs no segmentation, dictionary lookup, pronunciation inference or correction. Plain kanji remains unannotated.

Cue parsing leaves markup and entities unchanged. Inline parsing decodes supported named entities (`amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`, `lrm`, `rlm`) and valid decimal/hexadecimal Unicode entities exactly once. Escaped markup becomes literal text, never another parsing pass. Presentation tags are discarded while their text is retained. `<br>` becomes a newline; original newlines also survive. The parser returns strings, never an HTML view or executable markup.

Multiple base/reading pairs inside a ruby group and separate adjacent groups are supported. Valid `<rp>` fallback parentheses are hidden. Malformed/unclosed/nested ruby groups fall back to their text in original order, including both base and reading, rather than dropping Japanese text. Non-tag Japanese angle brackets and unknown/invalid entities remain visible.

`plainSubtitleText(String)` joins segment base text for the transcript sidebar, accessibility and exports. Valid readings are omitted. Malformed-group fallback text stays readable. Consumers that render reading annotations should use the segment model rather than altering raw cue text.

## Upstream source

Adapted from Enjoy Player, commit `dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff`, under AGPL-3.0:

- `lib/data/subtitle/subtitle_parser.dart`: extracted and adapted SRT scanning, newline normalization, digit helpers and timestamp parsing. Changes include explicit invalid-timestamp rejection, BOM normalization, anchored timestamp matching, stable sorting and immutable output.
- `lib/data/subtitle/transcript_line.dart`: value-model behavior reference. The replacement contains only `index`, `start`, `end`, `text`, duration and value equality.
- `lib/features/transcript/data/transcript_timeline_codec.dart`: adapted the binary-search core of `transcriptActiveIndex`, adding containment, offset, overlap and neighbor behavior.
- `test/data/subtitle/subtitle_parser_test.dart` and `subtitle_parser_perf_test.dart`: boundary-case reference for synthetic tests.
- `lib/data/subtitle/subtitle_parser.dart` / `VttParser`: behavior reference for the new block-based WebVTT parser. Unlike upstream's display-text stripping, this version retains authored ruby markup for the inline parser. `ruby_text_parser.dart` is newly authored pure Dart code for reading explicitly supplied annotations.

The upstream snapshot is retained separately in `vendor/enjoy-player-upstream`; it is not modified by this module. No cloud, account, billing, analytics or network parser dependencies are copied.

## Verification

Run standard parser and timeline tests:

```sh
flutter test test/subtitles
```

Optionally point `SAMPLE_SRT` at the user's local 704-cue SRT to enable `local_sample_test.dart`. Source subtitles are not copied into the repository or release assets.

The local sample test checks all 704 chronological indices, valid ranges, each start boundary, each positive-offset start, adjacent-cue navigation and the sample's first/last timestamps. Synthetic tests cover both offset directions, exact ends, gaps, malformed timestamps, unchanged text, overlapping cues and large tracks.
