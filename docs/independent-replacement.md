# Independent playback and subtitle replacement

Recorded on 2026-10-30 for GoodGoodStudy **0.9.0+31**. The project owner selected [MIT](../LICENSE) for the current project-owned code and independently rewritten implementation. This document records sources, process and implementation scope. It does not certify every copyright interest, grant an upstream exception, or represent Apple approval.

## Scope and historical baseline

The previous release line, through 0.8.2 and revision [`5fc65d6a05fba762bf3de69d1c86d72107b98cd7`](https://github.com/moonsoo531/GoodGoodStudy/tree/5fc65d6a05fba762bf3de69d1c86d72107b98cd7), selectively derived playback/subtitle code from Enjoy Player. That history remains AGPL v3, with the original [license text](../licenses/Enjoy-Player-AGPL-3.0.txt) and [historical source map](upstream-provenance.md#historical-code-through-082) retained. The MIT choice does not relicense the third-party historical code.

Six legacy files were replaced in full:

- `lib/playback/playback_transport.dart`
- `lib/playback/offline_playback.dart`
- `lib/subtitles/subtitle_cue.dart`
- `lib/subtitles/srt_parser.dart`
- `lib/subtitles/webvtt_parser.dart`
- `lib/subtitles/subtitle_timeline.dart`

The old timeline path is now only a compatibility export of the independent `cue_lookup.dart`. New subtitle support lives in `src/parser_support.dart` and `src/track.dart`. WebVTT was included because the old module README recorded its upstream behavior reference, even though the older top-level attribution table did not list it separately. Other project features, existing ruby parsing/rendering and the separate iOS Apple audio bridge were outside this replacement scope.

## Inputs and separation of authoring from integration

New authors worked in separate draft packages from the [functional contract](independent-replacement-contract.md). They did not read the six legacy implementations, old application tests, repository history, Enjoy Player source or other application subtitle/player implementations. Public interface names and observable behavior were retained for interoperability; comments, private helper structure and error wording were not supplied as implementation material.

The initial authoring contract had SHA-256 `e21ef9f161bd923989841d5b670dbdfafddfbfa05c40ff649b9fd0ee3d0305bc`; a preserved copy remains in the maintainer's private process records. The public contract now also records later integration clarifications. Reviewers who could inspect the old code ran compatibility tests after the drafts were complete and supplied observable event sequences/results and lint findings, without legacy source or test excerpts. Feedback addressed exception categories, synchronous EOF/seek ordering, EOF-only loop passes, autoplay after unload, pending-unload busy state and rejection of network-style file authorities.

The playback controller author used the new adapter from the same draft package. The adapter author recorded the following files read in the permitted MIT `media_kit` 1.2.6 package, with paths relative to that package:

- `lib/media_kit.dart`
- `lib/src/player/player.dart`
- `lib/src/player/platform_player.dart`
- `lib/src/player/native/player/real.dart`
- `lib/src/models/player_state.dart`
- `lib/src/models/player_stream.dart`
- `lib/src/models/track.dart`
- `lib/src/models/media/media_native.dart`

Those reads covered the public configuration, streams, state, open/stop and native property APIs. The author recorded that no package code was copied into the draft. The [media_kit MIT notice](../licenses/media_kit-1.2.6.txt) remains retained regardless of that distinction.

The subtitle author consulted official format syntax without using a third-party parser implementation or linked test suite. The author recorded using an independently designed block reader and bounded decimal conversion rather than translating the WebVTT parsing algorithm, and recorded that no specification example content or code was copied. Code and test payloads were newly written. The complete input/design records are retained by the maintainer; this public summary omits local machine paths and private resource information.

### Permitted public technical references

| Reference | Use |
|---|---|
| [Library of Congress SRT format description](https://www.loc.gov/preservation/digital/formats/fdd/fdd000569.shtml) | Cue counters, timing pairs, text lines and separators; the product contract specifies additional tolerances because SRT has no single normative standard |
| [W3C WebVTT Candidate Recommendation Draft, 20 May 2026](https://www.w3.org/TR/2026/CRD-webvtt1-20260520/) | Text-cue syntax, reserved blocks and timestamp fields; this implementation does not claim full WebVTT layout/CSS conformance |
| [media_kit 1.2.6](https://pub.dev/packages/media_kit/versions/1.2.6), [official package repository](https://github.com/media-kit/media-kit) | Public playback APIs and the permitted package-source reads listed above |
| [Dart API reference](https://api.dart.dev/), [Flutter API reference](https://api.flutter.dev/) | Standard language, collection, asynchronous stream and ChangeNotifier APIs |

## Current implementation structure

The playback adapter owns one `media_kit` Player for its lifetime, forwards its state/streams and reuses it for rendering. It serializes commands, stops old media before opening paused and checks new-file metadata readiness. On supported native media_kit platforms it compares current `path` and positive `duration` metadata before accepting readiness; decoder errors or a 15-second limit fail the open. It disables automatic/embedded subtitle selection so the external renderer can own subtitle display. Configuration allows the `file` protocol only, but this source-level setting is not proof of complete runtime network isolation.

The controller keeps an ordered backend-command lane separate from observed stream state and requested play intent. Loop jobs capture the intent version and selected loop; explicit user actions invalidate obsolete boundary work immediately. Completion state distinguishes natural EOF from endpoint seeks, loops and duplicate callbacks. Successful unload closes the observation gate and preserves the Player, speed and monotonic playlist completion signal. Instance and global close operations share pending cleanup futures and attempt every live backend. See the [playback module](../lib/playback/README.md) for the public behavior contract.

Subtitle parsing normalizes line endings, reads blank-separated blocks, validates complete timestamp tokens with bounded decimal arithmetic, and retains payload markup/entities verbatim. Accepted drafts are sorted by start and source ordinal, then assigned consecutive indices. Immutable parsed tracks carry a complete range-maximum tree over end times: start-time binary search plus a right-first tree query finds the latest containing cue in O(log n), including when an earlier long cue resumes after later short cues expire. Ordinary caller-supplied sorted lists are scanned without caching, so mutations remain visible. Lookup uses `position - offset` and start-inclusive/end-exclusive intervals. See the [subtitle module](../lib/subtitles/README.md).

## Source review and license boundary

The integration source review examined the historical source map, the six legacy files and related upstream files, author records, tests and lexical-match triage of 121 project Dart source/test files against 1700 upstream Dart files. Review outside the six targets found common Flutter UI/test constructions rather than additional Enjoy Player-specific expression requiring replacement. Exact platform-scaffolding matches also matched the official Flutter templates and retain BSD attribution. The review did not equate a low similarity score, a Git author name or the separation process with a legal guarantee.

Existing project subtitle tests had used upstream test categories as a historical reference; they are not retrospectively described as isolated author tests. Review found no copied distinctive upstream test fixture or implementation fragment in them. New independently authored tests are separately named below. No textbooks, user subtitles, recordings, personal data or private device information are included as inputs or release assets.

This closes the identified source-dependency replacement route for the current project-owned/replacement code. Flutter templates/patches, Dart and native dependencies keep their respective licenses. The macOS libmpv/FFmpeg artifact, SDK privacy declarations, final package notices and App Store checks remain independent; see [third-party notices](../THIRD_PARTY_NOTICES.md) and the [release-license review](licenses-release-review.md).

## Validation status at this record

The integration reviewer reported **187 targeted tests passed** across two runs on 2026-10-30: 55 existing compatibility tests (28 playback controller, 10 SRT, 10 timeline and 7 WebVTT) plus a separate 132-case run including the 24 independent author tests and interface/consumer/page tests. The complete analyzer reported no issues. Synthetic data and fake playback transports do not establish real decoder, device, timing or network behavior.

| Check | Recorded status |
|---|---|
| Existing playback/SRT/timeline/WebVTT compatibility suite | 55 passed |
| Integrated independent author tests in `test/playback/independent_playback_state_test.dart` and `test/subtitles/independent_subtitle_contract_test.dart` | 24 passed, included in the separate 132-case interface/consumer/page run |
| Interface/consumer/page regression run | 132 passed including the 24 author cases; combined with the separate compatibility run: 187 targeted tests |
| Complete analyzer | No issues |
| Integration normalization | Import/style normalization and removal of an unused test counter; no algorithm changes reported |
| Real macOS native playback smoke | 22/22 passed with original synthetic media; details below |
| iPad simulator in-place 0.9.0 (31) update and Apple AVPlayer | Two full-file passes completed, then stopped at 00:08; About displayed MIT and the project LicenseRegistry entry body was visible |
| iOS development IPA and signed macOS release | Both built; strict/deep signature checks passed, existing bundle identity/signing team and iCloud entitlements retained; bundled MIT asset exactly matched the root LICENSE |
| Physical iPhone in-place update | Install succeeded; installed version read back as 0.9.0 (31), existing bundle identity retained, with no uninstall or data reset |
| Source/build-input consistency | All 73 reviewed release inputs matched between canonical source and the private build copy, including 69 Dart files plus manifests/licenses |
| Integration revision | Fixed by the integration commit containing this record and the source hashes below; no self-referential commit hash is embedded |
| Remaining validation | Interactive physical-iPhone behavior and real two-device iCloud round trip not verified; no TestFlight upload or App Store review completed |

The draft authors recorded their own synthetic/analyzer checks separately. Those draft results are not substituted for checks of the integrated project. The independent playback tests use a synchronous fake transport with controllable operation gates and temporary synthetic files. Subtitle tests include invalid timestamp matrices, immutable values/lists, seeded overlap queries against a linear reference and a large long-overlap track. Performance timings are diagnostic rather than a portable wall-clock pass threshold.

The existing compatibility suite can be run from the repository root:

```sh
./flutterw test test/playback/offline_playback_test.dart test/subtitles/srt_parser_test.dart test/subtitles/subtitle_timeline_test.dart test/subtitles/webvtt_parser_test.dart
```

The independent integration cases are separate:

```sh
./flutterw test test/playback/independent_playback_state_test.dart test/subtitles/independent_subtitle_contract_test.dart
```

## Native and package verification

A separate temporary macOS release harness exercised the unchanged current controller/transport with original synthetic media: a three-second PCM WAV, an H.264/AAC MP4 and a synthetic subtitle sidecar. All **22 checks passed**, with no decoder errors. Coverage included metadata readiness, play/pause and position stability, seek, rate, natural completion/duplicate suppression, a finite interval loop with three passes, two full-file EOF passes, WAV/MP4 switching while retaining the same Player, subtitle-selection suppression, clear/unload, default-autoplay reopen and idempotent disposal. The official VideoController/Video output produced an actual decoded 320×180 frame, which was visually checked.

This was a dedicated probe with sandboxing disabled to access its own synthetic fixtures and result directory. It validates native playback of the current code; it does not establish the production sandbox's complete runtime network behavior or native-library distribution rights. Production signed-package checks were performed separately. The probe source, original fixtures, screenshots, private paths and device/signing details are retained in private verification records and are not release assets.

The iPad simulator was updated in place to 0.9.0 (31). Its Apple AVPlayer completed two full-file passes and stopped at 00:08; the About page and project license entry displayed MIT. The physical iPhone update also completed in place and the installed version was read back as 0.9.0 (31), without uninstalling or resetting data. Interactive phone playback remains unverified because interactive screen access was unavailable. Neither signed iCloud entitlements nor the synthetic sync tests prove an actual two-device iCloud round trip; that remains unverified.

The iOS development export and the macOS signed release passed strict/deep signature verification, retained the existing bundle/signing identity and iCloud entitlements, and contained a project MIT asset identical to the root LICENSE. The iOS SDK's own patched `package_info_plus` manifest matched `37f23fa7aabe84ee3c9a1f162c2c036612e5142aa6e3ce1dfc711161572d3131`; the macOS SDK kept its platform-specific original manifest rather than receiving the iOS patch.

| Locally verified 0.9.0 (31) artifact | SHA-256 |
|---|---|
| iOS development IPA | `776b04a5f7195bff98982df5e585769d8b8433091b5fa952bd51f2c31770bab1` |
| Signed macOS release ZIP | `232272d7f860a91c84ec6c7b42c946a9d96c0211c5114a71740b7dfb3bd7491f` |

These hashes identify locally built packages, not public download links or App Store acceptance. No TestFlight upload has been made for this release. Final SDK/store applicability checks and the macOS native-component license inventory remain independent of the source replacement.

## Current source SHA-256 snapshot

Captured at **2026-10-30T00:57:34Z** from the verified 0.9.0+31 inputs. This record and the listed sources are fixed together by their integration commit. These content hashes do not claim that the remaining phone/iCloud/store checks have finished; refresh them if a listed file changes.

| Repository-relative file | SHA-256 |
|---|---|
| `lib/playback/playback_transport.dart` | `9fd2bb5253c37d8984578ec7a24644dd6ea0fc38423a91f0afe9d455bd6607f2` |
| `lib/playback/offline_playback.dart` | `fc9f1e2a93ada0e0c4072ffd73fd5f266429edea64035cd8d8b6577018e6fbc0` |
| `lib/subtitles/subtitle_cue.dart` | `1397c41e3527dfad5e661da101e345fb1c6ea39c46417b4290f3de27aa2ddc91` |
| `lib/subtitles/srt_parser.dart` | `ad414d6b2f39b5591330a1de6efbf691e6fbee118180382fa4fe9dccc73d0692` |
| `lib/subtitles/webvtt_parser.dart` | `2c2fe7c390efd4c67fd6e6c9505aed7099cce087a16128e9e6814f1edced0883` |
| `lib/subtitles/subtitle_timeline.dart` | `863378c8800ab417119941f930f756f7dc2768c13d4ee8380b14610b6fd348d1` |
| `lib/subtitles/cue_lookup.dart` | `b95ccc27685a218966390fa78436f77fdbe8c3749c558c909f1b1595e0f02b78` |
| `lib/subtitles/src/parser_support.dart` | `a345bb4c19803e003324f3a27281a1b134e9d7b39cc1ca0ec893bc6cf16a26db` |
| `lib/subtitles/src/track.dart` | `f1b87bbca48c6c6dc958a769012040d27908f91cbc120835200f0680ab07d4db` |
| `test/playback/independent_playback_state_test.dart` | `0f3a22fd82a83fd42c4db3135851a58a66cc24b96938b61bf1896f4676a69d1a` |
| `test/subtitles/independent_subtitle_contract_test.dart` | `2e2690bb214038de13e0c61805bde133bcad4389f1109cbddaf17b2c18bbc66a` |
| `docs/independent-replacement-contract.md` | `01c2be401424804565ccdb223fb49059eeebbe48d829229ae76c54d30b8181ef` |
