# App Store 隐私与 SDK 审查记录

审查日期：2026-10-30。对象：GoodGoodStudy 0.8.2+30 的公开源码、锁定依赖和本地已解析的 SDK 来源，并只读检查同版本 iOS 本地构建。本文不是 App Store Connect 中已经提交的隐私回答，也不代表最终发行 archive 已验证。

## 已落地的材料

- [三语隐私政策](privacy-policy.md)：中文、English、日本語，覆盖本地记录、默认关闭的 iCloud Documents、同步标记、账号切换、保留/删除和系统备份。
- [同内容静态 HTML](privacy.html)：无脚本、分析像素、外部字体或外部资源；可本地查看。仅准备文件，没有启用 GitHub Pages。
- `ios/Runner/PrivacyInfo.xcprivacy`：声明不跟踪、无开发者收集的数据类别，以及已确认的 FileTimestamp / `C617.1`。SDK 自身的 manifest 应随其所属 bundle 保留。

政策联系渠道为本项目 GitHub Issues，并提醒用户不要公开附上个人资料。源文件 URL 和将来可能启用的 Pages URL，必须在发布后实际确认能匿名访问，才能作为商店隐私政策 URL。不要把未启用的 Pages 地址填为已上线服务。

## 应用自身的 required reason API 证据

`StudyStore.loadResumeLocation` 在旧版恢复分支调用 `progressFile.lastModified()`，比较已安装资料包的进度文件，恢复用户最后学习的篇目。文件由 `_stateFile` 创建于应用自己的 `Application Support/study/state`，生产环境根目录来自 `getApplicationSupportDirectory()`；测试注入目录不是发行行为。

因此，应用自己的 manifest 使用 `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1`。Apple 对该理由的范围是应用容器、App Group 容器或应用 CloudKit 容器中的文件元数据；本项目只依据第一项，不把 iCloud Documents 容器误称为 CloudKit 容器。这里不要求进度 JSON 本身是用户直接打开的文档，恢复学习位置是其面向用户的用途。该迁移不会扫描其他应用的文件，也不会把读取到的原始文件时间戳写入同步记录。

源码中的 `DateTime.now()` 是当前日期时间，不等于调用系统启动时间 API。macOS 书签桥使用 `UserDefaults`，没有据此向 **iOS** manifest 添加 UserDefaults 理由。原生音频/同步桥的 `attributesOfItem` 目前只取文件类型或大小，未发现额外直接读取创建/修改时间的用途；不能为了凑齐类别而填写与真实用途无关的理由。

依据：[Apple API 类别](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)、[批准的理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)。

## 当前 iOS 依赖清单

以下是已解析来源的静态盘点。依赖存在、来源有 manifest、manifest 最终装入发行 bundle，是三个需要分别核对的事实。

| 组件 | 解析版本 / 来源事实 | 来源中的隐私声明 | 发行前剩余核实 |
|---|---|---|---|
| Flutter / Dart runtime | Flutter 3.47.7；已检查缓存的 iOS Release engine manifest | 无跟踪、无数据类别；FileTimestamp `0A2A.1` / `C617.1`，SystemBootTime `35F9.1` | 最终 Flutter.framework 保留供应方原始文件，不能复制供应方 wrapper 理由到 app 以替代它 |
| file_picker → file_picker_darwin | 12.3.0 → 1.2.0 | 无跟踪、无数据类别；Package.swift `.process` 与 podspec privacy resource bundle 均包含 manifest | 实际采用 SPM 或 Pods 的那条路径正确打包；供应方文件有效 |
| package_info_plus | 10.2.2，由播放依赖引入；现有 0.8.2+30 的 Runner 已链接该类和方法 | iOS manifest 的收集和 API 类别为空、跟踪为 false；SPM / Pods 均声明资源。但 `FPPPackageInfoPlusPlugin.m:getUpdateDate` 直接调用 `fileModificationDate`，还有安装目录创建日期读取；现有包中的该 SDK manifest 也为空 | **合法元数据读取与 SDK 理由声明存在已确认差异**。采用供应方修复或受控、可重现的本地 SDK manifest 补丁，或经审查移除不需要的 iOS SDK 路径；不能用 app 理由掩盖 SDK 缺项 |
| wakelock_plus | 1.8.0，由播放依赖引入 | iOS manifest 的收集和 API 类别为空、跟踪为 false；SPM / Pods 均声明资源 | 最终 bundle 归属与 SDK 签名要求 |
| path_provider → path_provider_foundation | 2.1.6 → 2.6.0；foundation 实现为 Dart plugin + Objective-C FFI，生成元数据 `native_build: false` | 该版本包内未见 `PrivacyInfo.xcprivacy`；已读的目录 API 实现不含 UserDefaults、启动时间或直接文件时间戳读取 | Apple 列表含 path_provider 家族；不能只因 native_build=false 宣称豁免。需要确认此版本的实际归并方式、供应方解释和最终提交验证；若要求 SDK manifest，应获取正确供应方材料或选择已解决该问题的版本，不伪造供应方声明 |
| media_kit_video | 2.0.1，iOS Pod / native plugin | 该包 iOS 来源未见 manifest；当前检查未发现其直接使用 required reason API 的证据 | 确认最终是否链接，以及其静态依赖和 API；不因包名含 video 就误认成 Apple's video_player_avfoundation |
| objective_c / ffi | 9.5.0 / 2.2.0，来自上述 FFI 实现 | 本次未以 native assets 的最终二进制清单核实 | 随最终 archive 核对 native assets、适用 manifest 和许可，不以 pubspec 代替二进制盘点 |
| media_kit_libs_macos_video | 1.1.4 | macOS 专用 | 不应出现在 iOS app 中；macOS 的原生媒体许可另见[发行许可审查](licenses-release-review.md) |

Apple 的清单明确包含 Flutter、file_picker、package_info_plus、path_provider/path_provider_ios、wakelock，并覆盖所列 SDK 的版本和重新打包形式；二进制依赖还有签名要求。名称和架构变化需要具体核实，不能通过 app 的空 manifest 遮盖 SDK 缺项。[Apple 第三方 SDK 要求](https://developer.apple.com/support/third-party-SDK-requirements/)

现有公开 `ios/Podfile.lock` 只列 Flutter 和 media_kit_video，而生成插件清单包含更多组件；SPM、Dart/FFI 和 Pods 并行时，仅看 Podfile.lock 不足以还原最终包。本次没有构建或取得一个新的发行 archive，不能把上表标记为“最终包全部通过”。

package_info_plus 的差异是声明完整性问题，不是非法读取或跟踪行为：其 iOS `getAll` 路径为应用信息计算本应用的安装/更新时间。依赖链是 `media_kit_video 2.0.1 → wakelock_plus 1.8.0 → package_info_plus 10.2.2`，生成 SPM 项目也明确链接该 product。

只读检查的 0.8.2+30 本地构建中，`Runner` 确有 `FPPPackageInfoPlusPlugin`、`getInstallDate` 和 `getUpdateDate` 符号；对应 `package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy` 的 API 数组为空。该 Runner SHA-256 为 `2efb7e001d430352cb92f4fc4c2e80c74c9c33b0dd33bf4ebe622209fb59602c`。这证明代码实际链接，不证明应用曾执行该方法，也不代表提交给商店的最终 archive。

查询时 [官方发布页](https://pub.dev/packages/package_info_plus)的最新版本仍为 10.2.2；[官方 main 的 manifest](https://github.com/fluttercommunity/plus_plugins/blob/main/packages/package_info_plus/package_info_plus/ios/package_info_plus/Sources/package_info_plus/PrivacyInfo.xcprivacy)仍未列 API 理由，[同目录实现](https://github.com/fluttercommunity/plus_plugins/blob/main/packages/package_info_plus/package_info_plus/ios/package_info_plus/Sources/package_info_plus/FPPPackageInfoPlusPlugin.m)仍有上述读取。官方仓库[公开问题 #3627](https://github.com/fluttercommunity/plus_plugins/issues/3627)记录了同类疑点；它是问题报告，不是 Apple 审核结论或已发布修复。本次没有找到可直接升级关闭此差异的官方版本。

若采用本地修复，应把 SDK 自身 manifest 的准确理由变更作为有来源、版本和哈希的受控补丁记录，在保留其 BSD 许可的前提下重建并检查对应 resource bundle；不要手改不可复现的缓存，也不要宣称供应方已经发布修复。

原始 SDK 的声明缺项已通过本项目的受控构建资源补丁修复：`tool/apply_package_info_privacy_patch.py` 仅修改 Xcode 正在构建的该 SDK 纯资源 bundle，并在 Runner 最终 CodeSign 前补全 `FileTimestamp/C617.1`。锁版本、上游原始/补丁后哈希、路径及资源归属均受检查；专项测试 12 项通过，包括标准 Archive alias 与越界 alias 的区分。接入顺序、来源和最终签名验证要求见[补丁记录](app-store-package-info-privacy-patch.md)。这是 SDK 自己的声明修复，app 自身的 manifest 不是替代品；最终 Archive 的资源哈希、隐私报告和签名由发行构建另行记录。

## 商店隐私回答的依据与边界

当前源码未接入开发者服务器、广告、分析、崩溃上传或跨应用跟踪。iCloud Documents 是用户自己的 Apple 账号存储；本地账号摘要仅用于本机隔离，随机同步设备标记在用户的同步记录中。不要因为存在 iCloud 就声称资料永不离开设备，也不要把私有 iCloud 同步误写成开发者可读取的公共后端。

“Data Not Collected / 未收集数据”可以作为当前设计的候选答案，须以最终发行包及实际开发者可获得的数据为准。Apple 的定义区分纯本机处理、开发者实际收集的数据和 Apple 自身处理的数据；后续新增支持表单、诊断上传、统计、后台或 SDK 时必须重新判断。[Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

政策页面和 App Store 隐私标签不替代 manifest；SDK 的 manifest 也不能替代应用自身的 API 理由。[Apple manifest 归因要求](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## 进入发行前的验收点

1. 将应用 manifest 加入 Runner Resources，并在最终 archive 的应用 bundle 中确认有效文件；仅创建源文件不代表完成资源绑定。
2. 从最终 archive 生成 Xcode Privacy Report，核对每个 SDK manifest、API 理由和二进制签名的归属，确认 package_info_plus 的本项目受控补丁已进入正确资源 bundle 且被后续 Runner 签名封存，并关闭 path_provider/FFI 和媒体组件待核实项。不要通过删除 SDK 声明或扩大无依据理由取得表面通过。
3. 对照最终功能确认隐私政策、应用内入口和商店回答一致；匿名访问实际发布的政策链接，验证三语可读。
4. 政策中没有编造邮箱、承诺自动清除云端或声称已获得商店批准。若独立发行者提供不同支持渠道或更改数据用途，先更新政策再发行。

本轮只准备源码与文档；没有接受 Apple 协议、启用网站、提交隐私回答、上传 TestFlight 或提交审核。

## 0.8.2 本地归档验证补充

本项目已完成 iOS Release Archive 与 development/debugging IPA 的本地导出，未上传 App Store Connect。Runner 根目录的 app manifest 和 SDK 自己的 `package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy` 均实际存在；后者已由[受控资源补丁](app-store-package-info-privacy-patch.md)补入 FileTimestamp/C617.1，SHA-256 为 `37f23fa7aabe84ee3c9a1f162c2c036612e5142aa6e3ce1dfc711161572d3131`。归档 App 与重新导出的 App 的 strict/deep 签名检查均通过，供应方缓存未改。此项源码与声明的缺口已在本项目的构建路径关闭。

包内还核实了 Flutter、file_picker_darwin 与 wakelock_plus 的原资源声明。完整私有库存保留在本地验收材料中，不包含用户学习资料。这是本地实际包和签名验证，不等于 App Store 服务验证或 Xcode Organizer Privacy Report；path_provider/FFI 的归并适用性及最终发行配置仍按上表继续核实。
