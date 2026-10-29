# GoodGoodStudy

<img src="assets/branding/goodgoodstudy-icon.png" width="96" alt="GoodGoodStudy icon">

当前版本：**0.7.2+27**。

当前暂定图标为 D4-3：浅桃粉背景、薄荷与白色层叠书页、桃色书签。

GoodGoodStudy 是一个使用本地资料的学习工具，提供 **学习、测试、本地播放** 三个平级入口。首次打开显示首页；之后恢复上一次使用的模块，也可通过页面展开菜单切换。学习与本地播放页左上角提供返回首页的快捷箭头，返回前暂停播放并保存进度。界面支持中文、日本語和 English，主题支持浅色、深色及跟随系统。

本仓库和发行资源不包含教材、题库、录音、视频、用户笔记或个人进度。使用者需自行准备有权使用的学习包、测验包和本地媒体。应用不会自动下载或转换教材，也不提供教材下载服务。

## 功能

- 学习：导入学习 ZIP，显示准备好的假名和词条说明，支持笔记、关键词／全文遮蔽及学习位置保存。
- 测试：导入独立的单选题 ZIP，按设定题数与时间作答，保存未完成试卷、成绩和错题统计。
- 本地播放：macOS 支持本地音视频和字幕；iOS 使用 Apple AVPlayer 播放本地音频及字幕。
- 页面恢复只恢复位置和模块，不自动播放音频或自动开始新的考试。

学习资料、笔记、进度和考试记录保存在使用者自己的设备。不同资料包使用稳定 ID 与递增修订号更新，界面语言与主题偏好独立保存。

格式说明：[学习包](docs/study-package-v1.md)、[测验包](docs/quiz-package-v1.md)。文档中的短句与题目是为解释格式编写的合成示例，不是随应用发行的教材。

## 界面预览

以下为页面结构预览，截图采用图标更新前的版本；当前图标见本文顶部。

<img src="docs/images/home-phone-zh.png" width="250" alt="手机首页">
<img src="docs/images/home-desktop-zh.png" width="700" alt="桌面首页">

## English / 日本語

**English:** An offline study tool with three equal sections: Study, Quiz, and Local Media. It remembers the last section without automatically playing media or starting an exam. Bring your own lawfully obtained materials. No textbooks, question banks, recordings, or personal records are included.

**日本語:** 「学習」「テスト」「ローカル再生」を選べる学習ツールです。次回は前回使用した画面を開きますが、音声の自動再生や新しいテストの自動開始は行いません。教材・問題集・音声は同梱していません。利用権のある資料を各自で用意してください。

## 开发与构建 / Build

iOS/macOS 构建需要 macOS、Xcode 和对应平台 SDK，以及 Python 3.10+；使用 CocoaPods 的插件还需要 CocoaPods。

验证使用的工具链是 **Flutter 3.47.7 / Dart 3.13.5**。SDK 和依赖缓存不随仓库提供。请将 Flutter 加入 PATH，或将 `FLUTTER_ROOT` 指向自己的 SDK 目录。脚本不依赖仓库的父目录或特定用户名。

```sh
./flutterw --version
./flutterw pub get
```

为修复 Flutter 3.47.7 的特定 macOS 无障碍问题，仓库保留了审查过的 Flutter PR 193372 backport。脚本不会自动修改 SDK。使用该版本的开发者可以明确选择检查或应用补丁：

```sh
./flutterw --check-sdk-patch
./flutterw --apply-sdk-patch
```

补丁脚本校验 SDK 修订和前后哈希，拒绝改写不匹配的 SDK。来源和 BSD 许可见 [第三方说明](THIRD_PARTY_NOTICES.md)。`build` 与 `run` 默认检查补丁状态；已自行验证其他 SDK 的开发者可通过 `GOODGOODSTUDY_SKIP_SDK_PATCH_CHECK=1` 跳过该检查。

```sh
./flutterw analyze
./flutterw test
python3 -m unittest discover -s tool -p 'test_*.py'
./flutterw build macos --release
./flutterw build ios --release --no-codesign
```

iOS 真机签名请用 Xcode 打开 `ios/Runner.xcworkspace`，选择自己的开发团队。公开源码没有个人开发团队、证书或描述文件。现有 bundle identifier 为源码兼容而保留；独立发行时应配置自己管理的 ID 和签名。

依赖获取和首次构建可能需要网络。macOS 原生播放库含 Dart 包以外的组件，公开分发二进制前应按实际构成核对其许可证和源码提供义务。

## 测试与公开范围

常规模型、存储和界面测试使用合成数据与临时目录。依赖非公开教材的旧验证、个人端末诊断、过往签名安装包以及显示教材的截图不包含在公开仓库。可选外部字幕验证没有显式环境变量时会跳过。

`tool/offline_guard.py` 检查依赖、权限和应用源码。请先解析依赖并生成原生项目文件。基线变更需要人工核对，静态检查不代表已经穷尽运行时通信行为。

发布源码前的文件、个人路径与秘密信息模式检查：

```sh
python3 tool/audit_public_export.py
```

## 许可证与来源

本项目以 **GNU Affero General Public License v3** 发布。请阅读 [LICENSE](LICENSE) 和 [来源归属](docs/upstream-provenance.md)。Enjoy Player 本地播放与字幕逻辑的上游归属继续保留。软件的开源许可不授予第三方教材、题库或音频的再分发权。

Flutter、Dart 包及原生播放组件分别适用其许可证。来源与随附许可原文见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
