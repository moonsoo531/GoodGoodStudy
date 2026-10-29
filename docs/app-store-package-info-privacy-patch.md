# package_info_plus 10.2.2 的本项目构建资源补丁

日期：2026-10-30。此补丁补全 **SDK 自己的资源 bundle** 中的 FileTimestamp 理由声明，不更改 SDK 的行为，也不把本来合法的本应用元数据读取称为跟踪或违规行为。它是 GoodGoodStudy 维护的本地构建补丁，不是供应方发布的新版本。

## 问题与用途

锁定依赖链是 `media_kit_video 2.0.1 → wakelock_plus 1.8.0 → package_info_plus 10.2.2`。该 SDK 的 iOS `getInstallDate` / `getUpdateDate` 读取宿主应用自己的 Documents 目录和 app bundle 元数据，计算安装/更新时间，包含 `fileModificationDate`；其发布包附带的 manifest 的 `NSPrivacyAccessedAPITypes` 是空数组。

只读检查过的本地 0.8.2+30 iOS Runner 中已链接该 SDK 类/方法，SwiftPM 也已复制它自己的 `package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy`。补丁只向该 SDK 声明加入 `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1`，其用途与 [Apple 批准的应用自身容器元数据理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)相符。原有无跟踪及无收集类别声明保留。

## 来源、许可与哈希

机器可读记录见 `tool/patches/package_info_plus-10.2.2-privacy.json`，其中包含原始 manifest 全文和变更用途。

| 项目 | 固定值 |
|---|---|
| 上游发布版本 | [package_info_plus 10.2.2](https://pub.dev/packages/package_info_plus/versions/10.2.2) |
| pub archive SHA-256 | `73ef2cd5c11a7548f9b7f6fc2a4f6113de2e64aa2a70de63feede95548822908` |
| 上游原始 manifest SHA-256 | `6d2da0d8d930227d428c1d9363b0ad6e3a12e2c9b68c5ce297158a7412fc8c31` |
| 本项目补全后的 manifest SHA-256 | `37f23fa7aabe84ee3c9a1f162c2c036612e5142aa6e3ce1dfc711161572d3131` |
| 已审阅的上游 ObjC 实现 SHA-256 | `24d5bed1b615d38e79f8b75d59e7ac372aba828d08e3b86df85b1a6dbe7c9c39` |
| 保留的 SDK 许可 | [BSD 3-Clause 原文](../licenses/package_info_plus-10.2.2.txt) |

供应方[公开问题 #3627](https://github.com/fluttercommunity/plus_plugins/issues/3627)记录了相关疑点。审查时发布页最新仍为 10.2.2，官方 main 仍有相同 API 与空理由数组；没有据此声称上游已修复，也没有替供应方提交声明。

## Xcode 接入边界

iOS Runner 的专用 build phase 在所有相关资源复制、Flutter embed 完成后运行，**必须早于 Runner 最终 CodeSign**：

```sh
/usr/bin/python3 "$SRCROOT/../tool/apply_package_info_privacy_patch.py" --root "$SRCROOT/.."
```

脚本兼容 Python 3.9，仅使用标准库。它从 Xcode 的 `TARGET_BUILD_DIR` 和单层 `CONTENTS_FOLDER_PATH` 计算固定目标：

```text
<TARGET_BUILD_DIR>/<CONTENTS_FOLDER_PATH>/package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy
```

正常 device/simulator 构建要求 `TARGET_BUILD_DIR` 与 `BUILT_PRODUCTS_DIR` 一致。Archive 的标准布局会把真实应用安装到同一 `ArchiveIntermediates/<scheme>/InstallationBuildProductsLocation/Applications`，并从 `BuildProductsPath/<configuration>-<platform>/<app>.app` 创建 alias。脚本只在两个根目录满足这一准确关系、alias 恰好解析到目标 app 时接受该 Archive 布局，始终从真实安装目录写入，不沿 alias 修改。任意其他跨目录跳转都会拒绝。

它还校验 iOS/device 或 simulator 平台、宿主 app identifier、SDK bundle 名称及包含版本的 identifier、锁定版本/来源/archive checksum、原始 manifest 完整哈希与 schema。仅接受精确原版或精确已补状态；换版本、换内容、缺资源或真实目标 app 及其 SDK/Info/manifest 路径为符号链接时拒绝。上述标准 build-product alias 例外不会放开 SDK 资源的符号链接检查。SDK bundle 必须没有 executable 和独立 `_CodeSignature`，否则拒绝修改，不能静默破坏嵌套代码签名。

资源通过同目录临时文件、flush/fsync 和原子替换提交；第二次运行不重写已正确补全的文件。脚本不遍历寻找目标、不改 pub-cache、不改供应方源码、不改 app 自己的 manifest、不更新依赖锁或基线。若构建改用不同的资源打包路径，脚本会失败，必须先复核，不扩大搜索范围猜测目标。

当前 SDK 是静态链接到 Runner，目标是其独立的纯资源 bundle。按上述 phase 顺序，Runner 随后的 CodeSign 会封存修改后的资源。不能在已签名的发行包上事后运行写入模式；那会使原签名失效。最终签名及 App Store 的实际接受状态仍须由构建/发行流程验证。

## 验证

本项目提供 12 项专项测试，覆盖固定目标写入、声明保留、幂等、只读检查、版本/checksum 不匹配、未知 manifest、符号链接、越界路径、嵌套签名、缺资源，以及标准 Archive alias 和不可信 alias 拒绝：

```sh
python3 -m unittest tool/test_package_info_privacy_patch.py -v
```

最终构建中检查 SDK 的 manifest 的 API 数组及上述补丁后哈希；使用相同 Xcode 环境传入 `--check` 可只读验证。之后验证 Runner 的完整代码签名，并从发行 archive 生成 Privacy Report。应用自身 manifest 和 SDK 资源声明仍分别归属，不能互相替代。

后续供应方发布修复或版本变化时，先核对新源码、许可、用途和最终资源，再决定删除或更新此补丁。不得只替换允许的哈希来绕过审查。
