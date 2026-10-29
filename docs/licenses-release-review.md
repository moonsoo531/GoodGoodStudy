# App Store 发行许可审查

审查日期：2026-10-30。适用源码：本轮 GoodGoodStudy 0.8.2+30。状态：**当前含上游 AGPL 派生代码的 App Store 发行路径尚未确认，作为外部分发门槛保留；其他准备工作可继续。** 本文不是新增许可，也不是权利人授权或法律意见书。

## 已确认事实

- 项目保留 Enjoy Player commit `dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff` 的本地播放/字幕派生代码，具体文件见[来源归属](upstream-provenance.md)。iOS 使用 Apple AVPlayer，并不会自动消除其余派生代码的许可问题。
- 项目 `LICENSE` 与 `licenses/Enjoy-Player-AGPL-3.0.txt` 字节相同，SHA-256 为 `295bb876726c108705923d975c988e74ccf9557a2fe581fc79f576bb76a26208`。当前保留材料没有 App Store 专用例外或替代许可的记录。
- [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.en.html) §10 不允许向下游增加限制；§6 的二进制分发条件和 §7 的额外许可需要按实际发行方式处理。公开仓库、免费定价或关闭云同步，均不单独完成发行许可审查。
- [Apple 的标准 EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)包含使用及再分发限制，同时也有针对开源组件的部分保留。Apple 允许[自定义 EULA](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement)，但仍有适用最低条款和分发条件；填写自定义文本本身不能证明全部兼容。
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)要求遵守 FOSS 许可；其项目要求也适用于 TestFlight 等渠道。因此不能把 TestFlight 当作绕过许可的渠道。

[FSF 2010 年关于 App Store 的解释](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement)明确讨论附加限制与强 copyleft 的冲突。这是历史上的权利方解释，不能直接当作对 2026 年 Apple 条款和本项目 AGPLv3 组合的最终裁定。当前需要的是对实际适用条款和实际权利链的确认，而不是笼统宣称“一切开源都能上架”或“一切 AGPL 都绝不可能上架”。

## 需要关闭的许可门槛

| 编号 | 当前结论 | 可关闭的证据 |
|---|---|---|
| LIC-01 上游代码与 Apple 分发条件 | 未确认兼容；本仓库无相关例外授权记录 | 针对实际代码、版权人及实际分发条款的书面兼容性审查，或覆盖相应权利人的明确附加许可/替代许可，或完成有证据的独立替换路线 |
| LIC-02 对应源码与版权告知 | 已保留源码、AGPL 原文、上游归属和构建工具；尚非某个商店二进制的最终源码交付记录 | 为最终 binary 固定准确源码版本、依赖/补丁及构建说明，核实完整 Corresponding Source 和必要告知/安装信息义务，提供稳定可取得的路径；不得提交私人签名密钥 |
| LIC-03 macOS 原生媒体二进制 | 包级 MIT 已保留；实际 libmpv/FFmpeg 等的发行材料未闭环 | 按最终 artifact 的实际组件和构建选项准备许可证原文、对应源码/补丁、链接与替换要求和必要 codec 权利核对；不能以 Dart wrapper 的 MIT 替代 |

这些是项目的发行检查门槛，不是对用户 Apple 开发者账户、版权人私人沟通或未提供法律意见的推测。用户有权开源本项目，并不表示可以替第三方改授不同许可；本审查也没有更改根 `LICENSE` 或删去归属。

## 可行路线

**路线 A：确认现有代码可按拟定方式发行。** 整理派生文件、上游提交、实际版权贡献者、拟用商店 EULA、地区和分发方式，交由有权评估的人核对。若需要额外许可，向有权授权的版权人取得足以覆盖该发行方式的书面许可，并归档范围、版本及条件。维护者身份本身不保证拥有所有贡献的版权。

**路线 B：独立替换相关派生实现。** 依据公开格式规范和产品要求独立实现并验证，保留独立实现过程和来源记录；逐项确认没有残留受原许可约束的表达或其他不兼容依赖。历史 AGPL 版本仍保留原许可；不能只改一行 LICENSE、重命名类或移除版权注释宣称完成。

**路线 C：暂缓商店二进制分发。** 继续完善当前 AGPL 源码、自用构建、隐私、导入体验和质量验证，直到 A 或 B 有明确结论。任何其他对外二进制渠道也按其实际条款和开源义务单独审查，不把更换渠道自动当作免责。

可供权利人审阅的请求草稿（仅准备，未发送）：

> GoodGoodStudy selectively derives the files listed in our provenance document from Enjoy Player commit dfeae6cf09cbd9f22c2cf7cea1bf01e32b0c6fff. We are evaluating distribution of an iOS/macOS app through Apple's App Store and TestFlight. Could the relevant copyright holders confirm whether they authorize the intended distribution under its applicable terms, and, if needed, offer an explicit additional permission or alternative license? Please identify the covered files, revisions, rights holders, conditions and retained notice/source obligations. We will not treat this request or silence as permission.

## macOS 原生播放组件

锁定的 `media_kit_libs_macos_video` 1.1.4 下载 `libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz`，预期 SHA-256 为 `84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6`。其[对应 v0.6.0 构建来源](https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0)说明 default/full 采用 LGPL 配置，区别于 encodersgpl；这不等于本轮已验证最终包中的每个二进制。

下一步应按真实 artifact 固定组件版本、构建选项、源码/补丁与许可证，核实 LGPL 等的链接/修改后替换条件，以及涉及的 codec 权利。GPL/LGPL 不是“禁止商业使用”的同义词。不要根据上游表格里的商业使用图标或 wrapper 的 MIT 名称推导完整法律结论，也不要把 macOS 原生库的结论未经检查套用到使用 AVPlayer 的 iOS 包。

保留的直接和相关平台包文本见[第三方说明](../THIRD_PARTY_NOTICES.md)。它们是必要版权材料的一部分，不是 LIC-01 或 LIC-03 的完成证明。
