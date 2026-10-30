# Local subtitles

The cue model, SRT/WebVTT parsers and cue lookup were independently rewritten for GoodGoodStudy 0.9.0+31 under the project's [MIT License](../../LICENSE). `subtitles.dart` remains the public import. The module imports only `dart:collection` and local files; it performs no network, filesystem access, byte decoding or pronunciation inference.

## Current structure

- `subtitle_cue.dart`: immutable index, start, end and unchanged text with value equality/hash and duration.
- `srt_parser.dart` and `webvtt_parser.dart`: format-specific complete timestamp grammars and block selection.
- `src/parser_support.dart`: blank-separated blocks, line-ending normalization, opaque payload preservation and bounded timestamp conversion.
- `src/track.dart`: stable ordering, immutable parsed lists and the end-time range-maximum tree.
- `cue_lookup.dart`: active/previous/next public functions. `subtitle_timeline.dart` is only a compatibility export of those functions.
- `ruby_text_parser.dart` and subtitle visibility/rendering consumers remain separate project code outside the parser/timeline replacement.

## Contract

- Both parsers return immutable start-sorted lists. Equal starts preserve source order; `SubtitleCue.index` is assigned consecutively from zero after sorting, regardless of source numbering.
- SRT accepts numbered/indexless blocks, a leading BOM, LF/CRLF/CR line endings, one/two-digit hours and exactly three fractional digits separated by comma or dot. Minutes and seconds must be 00..59. Invalid timestamp tokens, blank payloads and nonpositive ranges are discarded; malformed times never become time-zero cues.
- WebVTT accepts `MM:SS.mmm` and `HH:MM:SS.mmm` with two-or-more-digit hours, optional identifiers/settings and an optional header. Headerless timing blocks are a product tolerance. Initial header metadata and complete NOTE/STYLE/REGION blocks are skipped; NOTEBOOK is an identifier. Comma fractions, malformed/overflowing times, blank payloads and nonpositive ranges are rejected. This is a text-cue subset, not a full WebVTT CSS/layout renderer.
- Dialogue, markup, ruby, entities, speaker/effect labels and internal line breaks are retained; only the complete payload's outer whitespace is trimmed. Settings are ignored, not executed. UTF-8 decoding remains the caller's responsibility.
- Lookup requires start-sorted input and compares `position - offset`; positive offset delays subtitles without changing stored times. Starts are inclusive, ends exclusive. The last containing cue in sorted order wins, including tied starts. An earlier long cue may resume after a later short cue ends.
- While active, previous/next return adjacent list entries. In a gap they return the most recently started/first upcoming cue. Boundaries and empty tracks return null.
- Parsed tracks use O(n) index space after O(n log n) sorting. Start binary search and a right-first range-maximum end-tree query provide O(log n) active lookup, including long overlaps. Caller-supplied sorted lists use an uncached backward containment scan with O(n) worst case so edits remain visible. Offset arithmetic checks Duration's integer limits.

## Manually authored ruby

`parseRubyText(String)` returns an immutable list of `RubyTextSegment(text: ..., reading: ...)`. For `<ruby>漢字<rt>かんじ</rt></ruby>`, `text` is `漢字` and `reading` is `かんじ`. It reads only the annotation that is already in the file. It performs no segmentation, dictionary lookup, pronunciation inference or correction. Plain kanji remains unannotated.

Cue parsing leaves markup and entities unchanged. Inline parsing decodes supported named entities (`amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`, `lrm`, `rlm`) and valid decimal/hexadecimal Unicode entities exactly once. Escaped markup becomes literal text, never another parsing pass. Presentation tags are discarded while their text is retained. `<br>` becomes a newline; original newlines also survive. The parser returns strings, never an HTML view or executable markup.

Multiple base/reading pairs inside a ruby group and separate adjacent groups are supported. Valid `<rp>` fallback parentheses are hidden. Malformed/unclosed/nested ruby groups fall back to their text in original order, including both base and reading, rather than dropping Japanese text. Non-tag Japanese angle brackets and unknown/invalid entities remain visible.

`plainSubtitleText(String)` joins segment base text for the transcript sidebar, accessibility and exports. Valid readings are omitted. Malformed-group fallback text stays readable. Consumers that render reading annotations should use the segment model rather than altering raw cue text.

## Sources and history

The authors used the [functional contract](../../docs/independent-replacement-contract.md), the official [Library of Congress SRT description](https://www.loc.gov/preservation/digital/formats/fdd/fdd000569.shtml) and [W3C WebVTT draft](https://www.w3.org/TR/2026/CRD-webvtt1-20260520/), without reading legacy implementations or tests. The [independent replacement record](../../docs/independent-replacement.md) documents actual inputs, design, source hashes and completed integration/native checks with their remaining limits. Process evidence is not a legal guarantee.

Historical versions through 0.8.2 used or referenced Enjoy Player's SRT scanning, cue model, timeline and WebVTT behavior; those versions retain AGPL and their original attribution. The [historical source map](../../docs/upstream-provenance.md#historical-code-through-082) and [upstream license](../../licenses/Enjoy-Player-AGPL-3.0.txt) remain available. The current MIT choice does not relicense that third-party history. Existing project synthetic tests had used upstream test categories as a reference and are distinct from the newly isolated author tests.

## Verification

From the repository root:

```sh
./flutterw test test/subtitles
```

Tests use synthetic text and cover timestamp rejection, payload preservation, immutable values/lists, ordering, offsets, boundaries, gaps, resumed overlaps, mutable external tracks and larger indexed tracks. The newly authored cases are in `test/subtitles/independent_subtitle_contract_test.dart`. Integrated results are tracked in the [replacement record](../../docs/independent-replacement.md): 187 targeted cases passed, including 55 playback/parser/timeline compatibility cases and the independently authored suite. Native playback verification is recorded separately and is not a claim of full WebVTT rendering or store approval.

Optional `local_sample_test.dart` and `manual_sample_test.dart` access external user files only when their explicit environment variables are set; otherwise they skip. Source subtitles and personal resources are not shipped in this repository or release assets.
