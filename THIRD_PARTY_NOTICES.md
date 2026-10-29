# Third-party notices

GoodGoodStudy is distributed under GNU Affero General Public License v3; see [LICENSE](LICENSE). The following notices preserve separate upstream terms. This document does not grant rights to textbooks, question banks, recordings, videos, subtitles or user-imported materials.

## Enjoy Player

Local playback and subtitle code is selectively derived from [Enjoy Player](https://github.com/baizhiheizi/enjoy_player), commit `dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff`, under GNU AGPL v3. See [source provenance](docs/upstream-provenance.md) and [the retained upstream license](licenses/Enjoy-Player-AGPL-3.0.txt).

The repository does not contain an App Store-specific permission or alternative license for that upstream code. Publishing source is not by itself a conclusion that a proposed store binary meets every applicable distribution term. The current release review, unresolved rights questions and available next steps are recorded in [the distribution-license review](docs/licenses-release-review.md). This notice does not relicense third-party code or assert that permission has been obtained.

## Flutter and the framework backport

Flutter is Copyright 2014 The Flutter Authors, under BSD 3-Clause. [The full license](licenses/Flutter-BSD-3-Clause.txt) is retained for the reviewed Flutter PR 193372 backport and upstream regression patch in `tool/patches/`. The patch metadata records the source PR, fixed revisions, license, and exact checksums. No Flutter SDK binaries are included in this repository.

## Direct package license texts

The lockfile records exact resolved versions and package checksums. These package-level license texts are retained from the corresponding published package sources:

| Package | License text |
|---|---|
| media_kit 1.2.6 | [MIT](licenses/media_kit-1.2.6.txt) |
| media_kit_video 2.0.1 | [MIT](licenses/media_kit_video-2.0.1.txt) |
| media_kit_libs_macos_video 1.1.4 | [Package MIT license](licenses/media_kit_libs_macos_video-1.1.4.txt) |
| file_picker 12.3.0 | [MIT](licenses/file_picker-12.3.0.txt) |
| path_provider 2.1.6 | [BSD license](licenses/path_provider-2.1.6.txt) |
| archive 4.5.2 | [MIT](licenses/archive-4.5.2.txt) |
| crypto 3.0.7 | [BSD license](licenses/crypto-3.0.7.txt) |
| intl 0.20.3 | [BSD license](licenses/intl-0.20.3.txt) |

Flutter's normal dependency license aggregation covers additional resolved Dart packages in generated application assets. Developers distributing binaries must retain all applicable notices from the exact dependency versions they use; this table is not an exhaustive inventory of every native library.

## Selected resolved Apple-platform dependencies

The following unmodified texts are also retained from the exact resolved package sources reviewed for the Apple-platform privacy audit. Their presence does not replace the final application's complete dependency notices or privacy manifests.

| Package | License text |
|---|---|
| file_picker_darwin 1.2.0 | [MIT](licenses/file_picker_darwin-1.2.0.txt) |
| path_provider_foundation 2.6.0 | [BSD license](licenses/path_provider_foundation-2.6.0.txt) |
| package_info_plus 10.2.2 | [BSD license](licenses/package_info_plus-10.2.2.txt) |
| wakelock_plus 1.8.0 | [BSD 3-Clause](licenses/wakelock_plus-1.8.0.txt) |
| objective_c 9.5.0 | [BSD license](licenses/objective_c-9.5.0.txt) |
| ffi 2.2.0 | [BSD license](licenses/ffi-2.2.0.txt) |

For `package_info_plus` 10.2.2, this project applies a narrowly scoped privacy-manifest correction to the SDK's copied resource bundle during the iOS build, before Runner is signed. The patch declares FileTimestamp/C617.1 for the SDK's existing host-application metadata reads. The vendor cache and implementation are unchanged; the original BSD notice remains retained. This is a GoodGoodStudy build-resource patch, not an upstream release or permission claim. Original and patched hashes, the exact target, purpose and signing boundaries are recorded in [the patch provenance](docs/app-store-package-info-privacy-patch.md) and `tool/patches/package_info_plus-10.2.2-privacy.json`.

## Native playback components

The iOS player uses Apple AVPlayer. The macOS build uses media_kit's native playback libraries. The package-level MIT license for `media_kit_libs_macos_video` does **not** replace the licenses of libmpv, FFmpeg, codecs and other libraries inside a native build.

The pinned package's build configuration obtains the macOS artifact from `media-kit/libmpv-darwin-build` release `v0.6.0`, named `libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz`, with expected SHA-256 `84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`. Native binaries, frameworks and caches are intentionally absent from this source repository. Before separately publishing a binary, review the actual native artifact's license inventory, source availability and any applicable codec rights.

The [pinned build source](https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0) describes the default/full flavors as LGPL configurations. This source-level evidence is not an audit of a final distributed binary, its complete dependency tree, or its relinking/replacement and source-delivery obligations. Those checks remain open in the [distribution-license review](docs/licenses-release-review.md); no native binary is declared cleared for store distribution by this document.
