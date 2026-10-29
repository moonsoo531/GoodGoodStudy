# Offline playback core

This AGPL-3.0 prototype derives its media_kit adapter design from Enjoy Player at commit `dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff`:

- `lib/features/player/application/engines/media_kit/media_kit_player_engine.dart`: one owned Player, native state and streams, open/seek/rate/play/pause/dispose, embedded-subtitle disabling.
- `lib/features/player/application/echo_enforcer.dart`: media-clock loop enforcement, serialized seeks, and generation invalidation when changing media.

`playback_transport.dart` is a reduced local-only adapter; `offline_playback.dart` implements the new prototype's state and loop policy. No account, HTTP, AI, sync, statistics, update or monetization dependencies are imported. The UI receives the same owned Player for its VideoController; creating another Player is unnecessary.

## Contract

- `openLocal(path, position: ..., autoplay: ...)` accepts an existing absolute local media path or `file:` URI; unsupported schemes, remote file hosts, relative paths, missing files, directories and playlist extensions are rejected before backend access. First open plays by default; later opens preserve the playing state and rate. UI switches between separately imported audio and video by supplying the shared current position.
- `setLoop(start, end, repeatCount: ...)` seeks to the loop's start without changing play/pause state. Count is the total number of passes; null repeats indefinitely. The final counted pass pauses at the loop end. Playing again restarts the counted loop. Seeking outside the loop clears it.
- Loops use media position/end events. Event delivery and seek latency determine the actual endpoint error; audio leakage and clipping still require real-device listening tests. No wall-clock timer substitutes for media time.
- Commands are serialized. Clearing a loop or opening another media invalidates pending loop rewinds. The external SRT renderer owns displayed subtitles; native embedded subtitles are disabled.
- `dispose()` is the synchronous widget lifecycle method. `await close()` is available when a test or application shutdown must await backend release.

The local-path gate is not a complete network sandbox: a malicious media file can embed remote references. The macOS target must additionally omit outgoing/incoming network entitlements; release validation must inspect the signed entitlement set and observe actual network behavior. Other targets need equivalent platform validation before claiming the same isolation.

## Verification

Run `flutter analyze` and `flutter test` from the prototype root. Core tests inject a transport and do not initialize native libmpv. They cover network rejection, actual-file checks, media-switch state preservation, counted and infinite loops, seek cancellation, end-of-file restart, failure recovery and cleanup.
