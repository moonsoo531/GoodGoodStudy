# App Store 发行许可审查

更新日期：2026-10-30。适用当前源码：GoodGoodStudy **0.9.0+31**。项目所有者已选择 **MIT**；已识别的 Enjoy Player 派生实现已通过独立替换路线处理，当前项目自有代码与独立实现采用 MIT。历史版本及第三方组件继续适用各自许可。已完成 187 项针对性用例、完整静态分析及 22/22 真实原生播放检查；签名构建和手机原位更新亦已核实。结果、制品与源码哈希见[独立替换记录](independent-replacement.md)。真实手机交互、两端 iCloud 往返及商店处理仍未验证；本文不代表法律保证或 Apple 批准。

## 当前源码与历史范围

- 六个旧播放／字幕文件已完整替换，包括旧文档中记录过 `VttParser` 行为参考的 WebVTT 文件；timeline 兼容入口只导出新 lookup，新增解析与索引支持文件。旧来源与具体范围见[来源记录](upstream-provenance.md)。
- 新作者根据公开接口／行为合同、官方格式说明、标准 API 和许可允许的 `media_kit` API／包源码，在隔离草稿中完成新实现与合成测试；没有读取旧实现或上游应用源码。审查没有在六目标之外发现需要新增替换的 Enjoy Player 特有表达。
- 以上关闭本项目**已识别的源代码依赖替换路线**，没有替 Enjoy Player 改授许可、取得或声称取得商店例外。输入隔离和文本比对只是来源证据，不能单独证明全部权利状态；已完成的兼容性和原生验证范围见独立替换记录，尚未验证的手机交互、iCloud 往返及发行事项继续保留。
- **0.8.2 及以前的历史版本**，包括提交 [`5fc65d6`](https://github.com/moonsoo531/GoodGoodStudy/tree/5fc65d6a05fba762bf3de69d1c86d72107b98cd7)，仍保留当时的 AGPL v3 与上游归属。历史 root `LICENSE` 与保留的 [Enjoy Player AGPL 原文](../licenses/Enjoy-Player-AGPL-3.0.txt) SHA-256 为 `295bb876726c108705923d975c988e74ccf9557a2fe581fc79f576bb76a26208`。当前 MIT 选择不追溯修改历史版本；若继续分发旧版二进制，应按其实际源码与许可履行当时义务。
- Flutter 模板与框架补丁、Dart 包、SDK 资源补丁和原生媒体库不是统一改授 MIT 的项目自有代码。版权与许可告知见[第三方说明](../THIRD_PARTY_NOTICES.md)。教材、题库、字幕、音视频和用户数据权利也不由软件许可授予。

MIT 的使用、复制、修改和分发条件以[完整 LICENSE](../LICENSE)为准；[OSI 的 MIT 原文](https://opensource.org/license/mit)要求保留版权和许可告知。发行包仍应携带实际所含第三方组件要求的通知，而不能只附项目 MIT 名称。

## 发布检查的当前状态

| 编号 | 当前结论 | 发布记录或下一步 |
|---|---|---|
| LIC-01 已识别派生源码 | 已采用独立替换路线；当前项目自有／独立代码采用 MIT，历史 AGPL 保留 | 本记录随集成提交固定，已记录源码哈希、187 项针对性用例与 22/22 原生检查；不把过程证据描述为法律保证或上游授权 |
| LIC-02 版权、许可与源码版本 | 保留 MIT、历史 AGPL 及第三方原文；应用内 MIT 正文可见，iOS/macOS 包内 MIT 与根 LICENSE 精确一致，73 项构建输入一致 | 核对应用内告知、随包通知、准确源码版本、依赖锁定和补丁来源；历史 AGPL 或原生 LGPL 等若适用，按其实际条款准备相应材料，不提交私人签名密钥 |
| LIC-03 macOS 原生媒体二进制 | 包级 MIT 已保留；实际 libmpv/FFmpeg 等的发行材料仍待闭环 | 按最终 artifact 的组件和构建选项准备许可证、对应源码／补丁，核对链接与替换条件及 codec 权利；不能以 Dart wrapper 的 MIT 替代 |
| LIC-04 SDK 与商店发行 | 独立于当前源码许可选择 | iOS 开发 IPA 与 macOS release 均已构建并通过 strict/deep 签名；iOS SDK 补丁哈希正确，macOS 保留平台原声明。继续核对 Privacy Report、SDK 适用性及实际商店信息；尚未上传 TestFlight 或通过 App Store 审核 |

[Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)、[标准 EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)和[自定义 EULA 要求](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement)仍应按实际发行方式核对。当前路线不依赖旧 AGPL 代码的商店例外，也不能把 TestFlight 或其他分发渠道视为免除第三方义务。

SDK `package_info_plus` 10.2.2 已确认的隐私声明缺项由本项目可重现构建资源补丁处理，且保留原 BSD 通知；应用自身 manifest 不替代 SDK 声明。本轮 iOS 开发 IPA 的 SDK 自身 manifest 已核实补丁后哈希并通过宿主 strict/deep 签名；Apple 处理结果仍未取得，见[隐私与 SDK 审查](app-store-privacy-audit.md)和[补丁来源](app-store-package-info-privacy-patch.md)。

## macOS 原生播放组件

锁定的 `media_kit_libs_macos_video` 1.1.4 下载 `libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz`，预期 SHA-256 为 `84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`。其[对应 v0.6.0 构建来源](https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0)说明 default/full 采用 LGPL 配置；这不等于已审计最终包中的所有二进制。

应按真实 artifact 固定组件版本、构建选项、源码／补丁与许可证，核实适用的链接、修改后替换和源码提供条件，以及 codec 权利。当前源码的 MIT 选择没有关闭这一项。也不能未经检查把 macOS 原生库的结论套到使用 Apple AVPlayer 的 iOS 包。
