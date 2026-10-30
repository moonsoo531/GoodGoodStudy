# Offline playback core

The desktop playback adapter/controller were independently rewritten for GoodGoodStudy 0.9.0+31 under the project's [MIT License](../../LICENSE). Their inputs, source hashes and integration status are recorded in the [independent replacement record](../../docs/independent-replacement.md). Earlier versions through 0.8.2 retain their Enjoy Player attribution and AGPL terms in the [historical source map](../../docs/upstream-provenance.md#historical-code-through-082).

## Structure

- `playback_transport.dart` defines the snapshot and injectable transport contracts. `MediaKitPlaybackTransport` owns one media_kit Player, forwards state/streams, opens only hostless local file URIs, serializes native commands and unloads through `stop()` without replacing the Player. The UI receives this owned Player for its VideoController.
- `offline_playback.dart` coordinates requested playback intent, observed events, range loops, playlist completion signals and shared asynchronous cleanup. A queued boundary job cannot restore an intent invalidated by a later explicit command.
- `apple_audio_controller.dart` is the separate project-specific iOS Apple AVPlayer channel controller. It was outside the six-file independent replacement; the iOS product supports local audio. Metadata probing and track selection also remain separate consumers of their respective adapters.

The media_kit adapter reads the supported native `path` and `duration` properties to verify that positive metadata belongs to the newly opened file. Decoder errors or a 15-second metadata timeout reject the open. It selects no subtitle track, disables sidecar autoload on supported native backends and sets a file-only protocol whitelist. No HTTP client or remote scheme is introduced by these modules.

## Public behavior

- `openLocal(path, position: ..., autoplay: ...)` accepts an existing regular file at an absolute local path or hostless `file:` URI. Relative paths, remote/network authorities, other schemes, missing files, directories and unsupported media types are rejected before opening the backend. First open defaults to playing; later opens preserve active/paused intent and speed unless autoplay is explicit. An open after successful unload is a new first open. Position defaults to zero and is clamped to known duration.
- `setLoop(start, end, repeatCount: ..., completedPasses: ...)` seeks to the loop start while preserving play/pause intent. The count means total passes; null repeats indefinitely. Restored completed passes are retained. The final finite pass pauses at the endpoint; playing that completed loop restarts its count. Seeking outside an unfinished loop clears it.
- Loop boundaries use media position and EOF events. Duplicate boundary callbacks cannot count a pass twice; EOF-only backends are supported. There is no repeating wall-clock timer for loop timing. Decoder/event/seek latency still requires real-device listening checks.
- `completedCount` is a monotonic playlist signal for natural EOF from active playback. Endpoint seeks, active loops, duplicate EOF and events after unload do not advance it.
- Backend commands are ordered. Explicit seek, pause, changed loop, media change and unload invalidate obsolete pending boundary work. Successful unload resets the media timeline/event gate while preserving speed, completion count and the native Player. Failed unload leaves the media truthfully loaded and allows retry.
- `dispose()` synchronously cleans up ChangeNotifier listeners and initiates asynchronous release. `await close()` awaits one instance's pending work/subscriptions/backend disposal. Concurrent `close()` and `closeAll()` callers share cleanup; global close attempts every live/closing backend even if one fails.

The local-input gate and backend protocol configuration do not alone prove complete runtime isolation, especially for malicious container references. Actual native behavior and final signed macOS entitlements need separate release validation. Optional app iCloud synchronization has its own narrow native bridge and is not supplied by this playback adapter.

## Verification and licenses

Core tests inject fake transports and use temporary synthetic file entries, without initializing native libmpv or opening user media:

```sh
./flutterw test test/playback/offline_playback_test.dart test/playback/independent_playback_state_test.dart
```

The [replacement record](../../docs/independent-replacement.md) records 187 targeted tests and a separate 22/22 real native playback smoke using original synthetic WAV/MP4 fixtures, including decoded 320×180 video output, finite interval/full-file loops, switching, unload and disposal. The iPad Apple AVPlayer check completed two full-file passes. Signed-package checks and the physical-iPhone in-place update also passed; interactive phone behavior, real iCloud round trip and store review remain unverified. A fake-transport result alone is not a decoder compatibility or audio-timing result.

The adapter uses MIT `media_kit` 1.2.6 public APIs. Flutter and native playback libraries retain their own terms; the project MIT license does not replace libmpv/FFmpeg obligations. See [third-party notices](../../THIRD_PARTY_NOTICES.md).
