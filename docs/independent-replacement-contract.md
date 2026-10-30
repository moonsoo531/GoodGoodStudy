# Independent replacement: functional contract

This document records interoperability signatures and observable product requirements for a new implementation. It is not source code or pseudocode from the replaced implementation. Implementers must not read the six legacy target files, the Enjoy Player snapshot, its source, or its tests. The integration reviewer may run existing compatibility tests and communicate failing observable behavior without supplying implementation excerpts.

## Scope and permitted sources

Replace the playback adapter/controller plus the subtitle cue model, SRT parser, WebVTT parser and cue lookup. Other application modules consume these public interfaces. Do not copy legacy helper names, control flow, comments, or error wording. Standard value data and public API names must remain compatible. Use a new internal design.

Permitted technical references:

- SRT format description: https://www.loc.gov/preservation/digital/formats/fdd/fdd000569.shtml (SRT has no single normative standard; the tolerances below are this product's requirements).
- WebVTT syntax: https://www.w3.org/TR/2026/CRD-webvtt1-20260520/ (implement the text-cue subset below, not CSS rendering).
- MIT media_kit 1.2.6 API/package source and its documentation: https://pub.dev/packages/media_kit/versions/1.2.6 and https://github.com/media-kit/media-kit . Pin to the installed 1.2.6 API when implementing.
- Dart and Flutter standard API documentation.

Do not use application repositories, third-party subtitle/player implementations, or the legacy test source as implementation references. Write independent synthetic tests. Record references and design choices honestly; separation of inputs is process evidence, not a legal guarantee.

## Subtitle public interface

`SubtitleCue`: const named-argument constructor with required `int index`, `Duration start`, `Duration end`, `String text`; corresponding final fields; `Duration duration` getter; value equality and consistent hash over all four fields.

Functions:

```text
List<SubtitleCue> parseSrt(String raw)
List<SubtitleCue> parseWebVtt(String raw)
SubtitleCue? cueAt(List<SubtitleCue> cues, Duration position, {Duration offset = Duration.zero})
SubtitleCue? previousCue(List<SubtitleCue> cues, Duration position, {Duration offset = Duration.zero})
SubtitleCue? nextCue(List<SubtitleCue> cues, Duration position, {Duration offset = Duration.zero})
```

Both parsers return immutable lists sorted by start time, with original order preserved for equal starts. `index` is assigned consecutively from zero in the returned order, regardless of file numbering. Preserve the payload text (including ruby, entities, speaker/effect labels, markup and internal line breaks), trimming only its outer whitespace. Do not interpret HTML, infer readings, read files, decode bytes or use the network.

SRT accepts numbered and unnumbered blocks, a leading BOM, LF/CRLF/CR and mixed newline forms. Time syntax is H:MM:SS,mmm or HH:MM:SS,mmm; dot may replace comma. Minutes and seconds must be 00..59, fractional precision exactly three digits, and hours one or two digits. Optional whitespace-separated settings after the end time are ignored. Reject malformed/negative/oversized fields, trailing digits, empty text, end <= start, and bad ranges; invalid blocks must not become time-zero cues. Empty/garbage input returns an empty immutable list. A final blank separator is optional. Preserve arbitrary-length dialogue lines.

WebVTT accepts an optional WEBVTT header and header metadata, optional cue identifiers, MM:SS.mmm or HH:MM:SS.mmm with 2+ hour digits, and ignored whitespace-separated cue settings. Skip NOTE comment blocks (NOTE followed by whitespace or end), STYLE and REGION blocks including any timing-looking content they contain. NOTEBOOK is a valid identifier, not a comment. Headerless timing blocks are a supported product tolerance. Reject commas in timestamps, invalid minute/second fields, fraction lengths other than three, overflowing durations, blank payloads and nonpositive ranges. Treat hours above 2562047787 as outside the supported range. Preserve cue markup/entities verbatim for a separate existing ruby renderer.

Lookup input is start-sorted. Compare against `position - offset`; positive offsets delay subtitles without mutating stored times. Starts are inclusive and ends exclusive. When multiple cues contain the time, choose the last such cue in sorted order, including equal-start ties. An earlier long cue can become active again after a later short cue ends. While active, previous/next return the adjacent cue in the sorted list; in a gap they return the most recently started / first upcoming cue respectively. Return null at boundaries and for empty tracks. Plain external sorted Lists must also work. Parsed tracks need efficient repeated lookup for thousands of cues, including long gaps and overlaps; choose the indexing design independently.

## Playback transport interoperability

`PlaybackSnapshot` has a const named constructor and final fields: `Duration position = Duration.zero`, `Duration duration = Duration.zero`, `bool playing = false`, `bool buffering = false`, `double rate = 1`.

`PlaybackTransport` is an abstract interface exposing:

```text
Player? nativePlayer
PlaybackSnapshot snapshot
Stream<Duration> positionStream, durationStream
Stream<bool> playingStream, bufferingStream, completedStream
Stream<String> errorStream
Future<void> open(Uri file), play(), pause(), seek(Duration position), setRate(double rate), dispose()
```

Optional capability `ClearablePlaybackTransport`: `Future<void> clearMedia()`.

`MediaKitPlaybackTransport()` implements both, owns a single media_kit Player for its lifetime, forwards native state/streams and reuses the same Player for video rendering. Open only the local file URI passed by the controller, initially paused. The open future must settle only after the new file's usable metadata is ready (not a stale duration from the previous file); fail on decoder errors or a finite metadata timeout around 15 seconds. Disable auto-loading/selection of sidecar/embedded subtitles so the app's external ruby renderer remains the only subtitle layer. Unload without disposing the Player; dispose exactly once. Use media_kit public APIs, with native properties only where supported. Do not introduce network access, remote schemes or dependencies.

## Playback controller public interface

`PlaybackLoop`: const named constructor `(required Duration start, required Duration end, int? repeatCount, int completedPasses = 0)`; final fields; getters/methods `bool completed`, `PlaybackLoop nextPass()`, `PlaybackLoop restart()`.

`OfflinePlayback extends ChangeNotifier` constructors `OfflinePlayback()` and `OfflinePlayback.withTransport(PlaybackTransport transport)`.

Public getters: `Player player`, `Duration position`, `Duration duration`, `bool playing`, `bool buffering`, `bool busy`, `double rate`, `String? localPath`, `String? error`, `PlaybackLoop? loop`, `int completedCount`.

Methods:

```text
Future<void> openLocal(String path, {Duration? position, bool? autoplay})
Future<void> play(), pause(), toggle(), clearMedia()
Future<void> seek(Duration target)
Future<void> setRate(double value)
Future<void> setLoop(Duration start, Duration end, {int? repeatCount, int completedPasses = 0})
void clearLoop(), clearError(), dispose()
Future<void> close()
static Future<void> closeAll()
```

Requirements:

- Accept only an existing regular file at an absolute local path or hostless file URI. Reject remote file hosts, relative paths, other schemes, missing files, directories and playlist files before calling the backend. Accept file extensions mp3/mp4/m4a/m4v/mkv/mov/wav/flac/aac/aiff/aif/ogg/opus/webm/avi/wma/wmv/mpg/mpeg/ts/m2ts/caf/alac case-insensitively. No generic HTTP/network APIs.
- First open defaults to autoplay; later opens preserve whether playback was active unless explicitly overridden. Omitted position starts at zero; explicit positions are clamped. Switching files preserves speed and the single native Player but clears loops. Open failures reset busy state, expose the backend failure and allow retry.
- Serialize backend commands. Handle synchronous streams, delayed seeks, late completion events, failing operations and lifecycle calls without deadlock or uncaught futures. A pending loop rewind cannot overwrite a subsequent explicit seek, pause, unload, changed loop or new media. Ignore late state/completion/error events after a successful unload and after closing.
- Play/pause/toggle/seek/loop operations need loaded media; the Player getter must throw a StateError when the injected transport has no native Player. Bound seeking to zero..duration (zero duration means no known upper bound). Finite speed 0.25..4 only; invalid values reject without backend mutation.
- A loop uses start-inclusive/end boundary media-time events, not a wall-clock repeating timer. `repeatCount` is total passes, null means unlimited. Validate start >= 0, end > start, repeatCount >= 1 when set, completedPasses >= 0 and less than repeatCount when finite. Bound end by known media duration, reject loops starting past it. Setting a loop seeks to its start and preserves paused/playing state. Restored completedPasses count must be preserved.
- At each loop end count one pass, seek back and continue except on the final finite pass, which pauses at the loop endpoint. Duplicate position/completed callbacks from one boundary must not double-count. Native EOF must also repeat an active loop. Playing a completed finite loop restarts its count from zero; playing naturally completed media restarts from zero. User seeking outside an unfinished loop clears it. `clearLoop()` takes effect synchronously even during a queued rewind.
- `completedCount` is a monotonic playlist signal: increment once per natural EOF reached from active playback, once again if replayed. Do not increment for duplicate EOF, paused/end-seek events, active loops, trailing EOF after the final loop, errors, unloading or native EOF delivered after opening paused at the end. Preserve the counter across opens/unloads.
- `clearMedia()` unloads via the optional capability or otherwise pauses. Only after success clear path/timeline/playing/buffering/error/loop, preserve speed/counter/native Player, and reject late backend events until another open. If unloading fails, keep the file state truthfully loaded, surface the error and allow retry. An already-entered async rewind must finish before unloading, and no later stale rewind may execute.
- `close()` is idempotent and awaits all pending operations/subscription cancellation/backend disposal, including concurrent close callers. `dispose()` is synchronous ChangeNotifier cleanup and initiates the same close. `closeAll()` waits every live/closing instance, attempts all even if one fails, does not dispose the caller's notifier prematurely, forgets failed/finished instances after cleanup and also waits for concurrent global close callers. Never leak async errors or dispose a backend twice.

## Delivery and integration

Authors create replacement files in a separate scratch directory, without reading the legacy targets. Use independent synthetic tests and provide a short source/design record. Keep existing public signatures; new private structures/files are allowed. The integration reviewer stages and runs compatibility/consumer tests only after the independent draft is complete, then sends functional mismatches. Historical AGPL releases and attributions remain preserved in history; no new implementation may be described as cleared solely because its text differs.

### Integration clarifications

The first authoring input was preserved before these clarifications. Compatibility feedback was provided as event sequences and expected public results, without legacy source or test excerpts:

- Missing files and directories use FileSystemException; unsupported input forms remain ArgumentError.
- A seek request disarms natural completion immediately, including an EOF delivered synchronously before the queued seek begins. Seeking to the endpoint does not count as natural EOF.
- EOF-only loop backends may omit a final position callback and never emit completed=false. Each fresh playing=false followed by completed=true after a resumed pass still advances the loop exactly once.
- After a successful unload there is no current media; the next omitted-autoplay open defaults to playing, while preserving speed.
- Busy remains true throughout a pending native unload, before a later queued open may begin.
