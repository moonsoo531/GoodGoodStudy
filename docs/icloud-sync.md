# 可选 iCloud 同步 / Optional iCloud Sync / iCloud 同期

GoodGoodStudy 默认使用设备上的本地副本，**iCloud 同步默认关闭**。在设置中开启后，应用通过 Apple 的 iCloud Documents 同步用户自己的学习资料与学习记录，不需要创建 GoodGoodStudy 账号，也不使用开发者运营的同步服务器。用户须自行准备有权使用的资源；开源仓库和安装包仍不附带教材、题库或音频。

同步依赖各设备登录同一个 Apple Account，并开启系统 iCloud Drive 及本应用的 iCloud 使用权限。iOS 和 macOS 应用必须获得同一 iCloud 容器的授权。仅使用同一 Apple Account 安装一个未授权的构建，不足以启用同步。

## 同步范围和设备副本

开启同步后，范围包括已导入的学习包、测验包、包内音频，以及学习笔记和学习进度。另一台设备在同步完成后使用自己的本地副本；网络不可用时，已经下载的内容仍可在本机使用。

未完成的试卷、播放器指向外部文件的书签和本机路径保留在各设备。这些路径在另一台设备上通常不可用，不作为同步资源。播放器的任意外部音视频不会因为启用学习资料同步而自动上传。

删除操作不会自动传播到其他设备。不同设备对同一份记录产生分叉时，保留双方版本并供用户选择，不能静默覆盖其中一方。关闭同步后继续使用本地副本；关闭操作本身不删除其他设备或 iCloud 中的文件。

“自动同步”指开启后由应用与系统在可用时发现和传输更改，并不保证即时到达。系统账号状态、网络、iCloud 剩余空间和文件下载状态都会影响完成时间。界面必须显示实际可用性和同步状态；无法授权、传输失败或尚未下载时，不得显示为已完成。用户不应把同步视为独立备份。

## Apple 平台签名与容器配置

本仓库只提供源码配置，不提供开发者证书、个人团队信息或 provisioning profile。曾用于本地 iPhone 0.7.2 验证的 wildcard profile **没有 iCloud 权限和容器授权，不能用于本功能**。本项目随后已在 0.8.1 的 iPhone 与 Mac 开发签名包中核对了共享容器权限，iPhone 界面也确认 iCloud 可用；这不能替代双设备传输验收，也不代表独立发行者的签名已配置。

准备可用构建需要：

1. 在自己的开发团队中为应用配置显式 App ID，启用 iCloud Documents，并关联容器。
2. 让 iOS 与 macOS 的 App ID 均授权访问同一个容器，重新生成适用的开发或发行 profile。
3. 在两端源码与构建设置中保持容器一致。默认值为 `iCloud.dev.learnjapanese.offlinePlayer`；独立发行者应使用自己团队管理的容器。
4. 使用与这些权限相符的有效签名。历史 macOS ad-hoc 签名包没有团队和 profile 授权，不能作为 iCloud 已可用的证明。Mac 的实际发行方式可以按 Apple 支持范围选择 Mac App Store 或 Developer ID；采用 Developer ID 的高级能力时也需相应 profile。签名身份发生变化时，macOS 可能要求确认现有应用数据容器的访问权限，不应通过删除用户容器或降低安全设置来绕过。

容器由 `GOODGOODSTUDY_ICLOUD_CONTAINER` 构建设置提供，原生桥读取的 Info.plist 键为 `GoodGoodStudyICloudContainerIdentifier`，其值为 `$(GOODGOODSTUDY_ICLOUD_CONTAINER)`。两类 entitlement 的容器数组也引用同一构建宏；各构建配置应保留明确的源码默认值。改为自有容器时同时修改两端默认值和对应签名授权。不要把 Apple Account 密码、证书或 profile 提交到仓库。

原生桥为：

- `ios/Runner/GoodGoodStudyICloudBridge.swift`
- `macos/Runner/GoodGoodStudyICloudBridge.swift`

两端使用 `goodgoodstudy/icloud` channel 和 Foundation 的 FileManager、ubiquity 与 metadata 查询能力。CryptoKit 用于对系统账号标记生成摘要，macOS 的 Security 框架用于读取应用自身的签名权限。该实现不引入 Dart 网络包、CloudKit 后端或第三方云 SDK。系统负责 iCloud Documents 的传输；不为本功能开放 macOS `com.apple.security.network.client`。

配置来源：[Apple 启用能力与关联容器](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)、[App ID 配置](https://developer.apple.com/help/account/identifiers/register-an-app-id/)、[Developer ID 与高级能力](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)。

## 静态政策与发布说明

`tool/offline_guard.py` 保留原有 HTTP、遥测、远程服务和第三方云 SDK 禁令，仅为上述两份原生桥提供 iCloud Documents 例外：

- ubiquity、metadata 查询及文件协调 API 只能出现在指定桥文件中；桥内仍不能使用通用 HTTP API。
- 只允许已审查的 Runner entitlement 文件声明 iCloud；服务必须为 `CloudDocuments`，`icloud-container-identifiers` 与 `ubiquity-container-identifiers` 都必须只包含一致的一个容器，与桥的签名权限检查相符。
- 不允许 CloudKit、iCloud key-value store 或其他 iCloud entitlement，也不放开 macOS outgoing-network 权限。
- 原生工程中的容器设置必须是明确、无通配符的 ID，且 iOS/macOS 一致。源码中的替代容器也接受同一政策检查，仍须由开发者自行正确授权。
- 依赖基线仍独立检查。使用 Foundation 原生桥不增加依赖，因此不应重新接受基线来掩盖无关变更。

Guard 是源码和配置检查，不能证明实际签名具有权限，也不能证明账号、默认开关、冲突处理或传输完成状态正确。启用同步后，发布说明应写明“本地优先，可选 Apple iCloud 同步”；不能再无条件宣称应用从不联网或所有资料只留在一台设备。资源、笔记和进度会在用户开启后交由其 iCloud 账户存储和传输。

## English

iCloud Sync is **off by default**. When enabled, GoodGoodStudy syncs imported study and quiz packages, included audio, study notes and study progress through Apple iCloud Documents. Each device keeps a local copy. Sign in to the same Apple Account, enable iCloud Drive, and use properly signed builds authorized for the same container.

Unfinished quiz sessions and external media bookmarks or device paths stay on their device. Deletions do not automatically propagate. Divergent edits keep both versions for the user to choose. Turning sync off preserves local copies. Transfers depend on system availability and may take time.

The old wildcard iPhone profile and ad-hoc Mac build do not authorize this feature. Developers need explicit App IDs, a shared container and suitable signing profiles. This feature adds no developer-hosted service, CloudKit backend, generic HTTP access or third-party cloud SDK. Resources must still be provided lawfully by the user.

## 日本語

iCloud 同期は**初期状態ではオフ**です。有効にすると、読み込み済みの学習・テストパッケージ、パッケージ内の音声、学習ノートと学習の進捗を Apple の iCloud Documents で同期します。各端末にはローカルのコピーを保持します。同じ Apple Account でサインインし、iCloud Drive を有効にしたうえで、同じコンテナへの権限を持つ正しく署名されたアプリを使用してください。

解答途中のテスト、外部メディアのブックマークと端末固有のパスは同期しません。削除は他の端末へ自動的に反映しません。変更が分岐した場合は両方を保持してユーザーが選択できます。同期をオフにしてもローカルのコピーは残ります。転送には時間がかかる場合があります。

以前の wildcard iPhone プロファイルと ad-hoc 署名の Mac アプリには、この機能の権限がありません。開発者は明示的な App ID、共有コンテナ、適切な署名プロファイルを設定する必要があります。開発者の同期サーバーや第三者のクラウド SDK は使用しません。教材は引き続き利用権のあるものを各自で用意してください。
