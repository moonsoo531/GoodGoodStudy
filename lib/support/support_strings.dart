import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

class SupportStrings {
  SupportStrings(BuildContext context)
    : language = AppLocalizations.of(context).locale.languageCode;

  final String language;

  String text(String zh, String ja, String en) => language == 'ja'
      ? ja
      : language == 'en'
      ? en
      : zh;

  String get importHelp => text('导入帮助', '読み込みガイド', 'Import help');
  String get about =>
      text('关于 GoodGoodStudy', 'GoodGoodStudy について', 'About GoodGoodStudy');
  String get introduction => text(
    '先准备自己的资料，再到对应模块导入。应用不附带教材、题库或录音。',
    'ご自身の教材を準備し、対応する画面から読み込んでください。教科書・問題集・録音はアプリに付属していません。',
    'Prepare your own materials, then import them in the matching section. Textbooks, question banks and recordings are not included.',
  );
  String get steps => text('开始导入', '読み込みの手順', 'How to import');
  List<String> get importSteps => [
    text(
      '将 ZIP 保存到“文件”或本机文件夹。来自 iCloud 云盘的文件请先下载到本机。',
      'ZIP を「ファイル」または端末内のフォルダに保存します。iCloud Drive 上のファイルは先にダウンロードしてください。',
      'Save the ZIP in Files or a local folder. Download files from iCloud Drive to your device first.',
    ),
    text(
      '在首页选择“学习”或“测试”，点击右上角的导入按钮。',
      'ホームで「学習」または「テスト」を選び、右上の読み込みボタンを押します。',
      'Choose Study or Quiz from home, then tap the import button at the top right.',
    ),
    text(
      '选择对应格式的 ZIP，等待检查完成，再选择篇目或设置测试。',
      '対応する形式の ZIP を選びます。確認が終わったら、学習する課やテストの設定を選んでください。',
      'Select a ZIP in the matching format. After validation, choose a lesson or configure your quiz.',
    ),
  ];
  String get studyZip => text('学习 ZIP', '学習用 ZIP', 'Study ZIP');
  String get studyDescription => text(
    '当前支持 1.0 格式的日语学习包，含日文正文和简体中文讲解。ZIP 根目录直接放入以下三个 UTF-8 JSON 文件，不要再套一层文件夹。',
    '現在は、日本語の本文と簡体字中国語の解説を含む 1.0 形式の学習パックに対応しています。次の UTF-8 JSON ファイルを ZIP の直下に入れてください。外側にフォルダを追加しないでください。',
    'Currently supports version 1.0 study packages with Japanese text and Simplified Chinese explanations. Place these three UTF-8 JSON files directly at the ZIP root, without an enclosing folder.',
  );
  String get studyAudio => text(
    '音频可选。自备音频放在 media/ 中，并在包内清单中登记；文件需与清单中的校验信息一致。没有音频的学习包也可阅读和练习。',
    '音声は任意です。ご自身の音声を media/ に入れ、パックの一覧に登録してください。ファイルと検証情報が一致する必要があります。音声がなくても本文の閲覧や練習ができます。',
    'Audio is optional. Put your own audio in media/ and declare it in the package manifest. Files must match the manifest’s validation information. You can also read and practise with packages that have no audio.',
  );
  String get studyLimits => text(
    'ZIP 最大 512 MiB；展开合计最大 1 GiB；单文件最大 128 MiB；单个 JSON 最大 8 MiB。',
    'ZIP は最大 512 MiB、展開後の合計は 1 GiB、各ファイルは 128 MiB、各 JSON は 8 MiB までです。',
    'Limits: 512 MiB per ZIP, 1 GiB extracted in total, 128 MiB per file and 8 MiB per JSON file.',
  );
  String get studyFormat =>
      text('学习包完整格式说明', '学習パックの詳しい形式', 'Full study package format');
  String get quizZip =>
      text('测试 ZIP（单选题）', 'テスト用 ZIP（単一選択）', 'Quiz ZIP (single choice)');
  String get quizDescription => text(
    '当前支持 1.0 格式的日语单选题库。ZIP 根目录只包含以下两个 UTF-8 JSON 文件，不包含音频、文件夹或其他文件。',
    '現在は 1.0 形式の日本語の単一選択問題集に対応しています。ZIP の直下には次の UTF-8 JSON ファイルだけを入れ、音声・フォルダ・その他のファイルは含めないでください。',
    'Currently supports version 1.0 Japanese single-choice question banks. The ZIP root must contain only these two UTF-8 JSON files, with no audio, folders or other files.',
  );
  String get quizAnswers => text(
    '每题需要 2–8 个选项，并指定正确选项。应用读取准备好的题目和答案，不会自动转换试卷或推断正确答案。',
    '各問題には 2～8 個の選択肢と正解の指定が必要です。準備した問題と解答を読み込みます。試験用紙の自動変換や正解の推測は行いません。',
    'Each question needs 2–8 choices and a specified correct choice. The app reads prepared questions and answers; it does not convert exam papers or infer correct answers.',
  );
  String get quizLimits => text(
    'ZIP 最大 32 MiB；展开合计最大 16 MiB；单个 JSON 最大 8 MiB。',
    'ZIP は最大 32 MiB、展開後の合計は 16 MiB、各 JSON は 8 MiB までです。',
    'Limits: 32 MiB per ZIP, 16 MiB extracted in total and 8 MiB per JSON file.',
  );
  String get quizFormat =>
      text('题库完整格式说明', '問題集の詳しい形式', 'Full quiz package format');
  String get troubleshooting => text('常见问题', 'よくある質問', 'Common questions');
  String get unsupportedTitle => text(
    '普通 ZIP、PDF 或照片能直接导入吗？',
    '一般の ZIP・PDF・写真は読み込めますか？',
    'Can I import an ordinary ZIP, PDF or photo?',
  );
  String get unsupportedBody => text(
    '学习和测试需要上面说明的专用资料包。应用不执行 PDF 转换或文字识别。单独的音频与配套字幕，请从首页的“本地播放”入口导入。',
    '学習とテストには上記の専用パックが必要です。PDF の変換や文字認識には対応していません。個別の音声と対応する字幕はホームの「ローカル再生」から読み込んでください。',
    'Study and Quiz require the package formats above. PDF conversion and text recognition are not supported. Import separate audio and its subtitles from Local playback on home.',
  );
  String get updatesTitle =>
      text('怎样更新资料？', '教材を更新するには？', 'How do I update a package?');
  String get updatesBody => text(
    '更新同一资料时保留资料标识，增加版本号，再重新导入。相同版本中不同的内容不能直接覆盖。导入检查失败不会替换已有资料；笔记和个人测试记录独立保存。',
    '同じ教材を更新する場合は、識別子を保ったままバージョン番号を上げ、再読み込みしてください。同じバージョンの異なる内容は上書きできません。確認に失敗しても既存の教材は置き換えず、ノートや個人のテスト記録は別に保存します。',
    'Keep the package identifier, increase its revision number and import it again. Different contents with the same revision cannot overwrite each other. Failed validation does not replace existing materials; notes and personal quiz records are stored separately.',
  );
  String get formatHint => text(
    '文件夹结构只是第一步，包内内容也需要符合格式。详细字段说明可通过各资料包下方的链接查看。',
    'ファイルの配置に加え、内容も所定の形式に従う必要があります。各パックの下のリンクから詳しい項目を確認できます。',
    'The folder layout is only the first step; the contents must also follow the format. Use the links below each package type for field details.',
  );
  String get ownResources => text(
    '请使用自己有权使用的资料。软件的开源许可不包含教材、题库或录音的使用和分发授权。',
    '利用する権利のある教材をご用意ください。ソフトウェアのオープンソースライセンスは、教科書・問題集・録音の利用や配布の許諾を含みません。',
    'Use materials you have the right to use. The software’s open-source license does not grant rights to textbooks, question banks or recordings.',
  );
  String get summary => text(
    '学习、测试与本地播放。',
    '学習・テスト・ローカル再生。',
    'Study, quizzes and local playback.',
  );
  String version(String version, String build) => text(
    '版本 $version（$build）',
    'バージョン $version（$build）',
    'Version $version ($build)',
  );
  String get loadingVersion =>
      text('正在读取版本…', 'バージョンを確認中…', 'Reading version…');
  String get versionUnavailable => text(
    '暂时无法读取版本信息',
    'バージョン情報を取得できません',
    'Version information is unavailable',
  );
  String get source => text('公开源码', '公開ソースコード', 'Public source code');
  String get license => text(
    '软件许可（AGPL v3）',
    'ソフトウェアライセンス（AGPL v3）',
    'Software license (AGPL v3)',
  );
  String get thirdPartyNotices =>
      text('第三方声明', 'サードパーティーの表記', 'Third-party notices');
  String get componentLicenses =>
      text('开源组件许可', 'オープンソースコンポーネントのライセンス', 'Open-source component licenses');
  String get privacy => text('隐私政策', 'プライバシーポリシー', 'Privacy policy');
  String get licenseSummary => text(
    '软件代码采用 GNU AGPL v3，第三方组件保留各自许可。复制、修改和分发条件请以完整许可为准。',
    'ソフトウェアのコードは GNU AGPL v3 に基づき、サードパーティーのコンポーネントにはそれぞれのライセンスが適用されます。複製・改変・配布の条件は各ライセンスをご確認ください。',
    'The software code uses GNU AGPL v3. Third-party components retain their own licenses. See the full licenses for conditions on copying, modifying and distributing the software.',
  );
  String get cannotOpenLink =>
      text('无法打开链接', 'リンクを開けません', 'Could not open the link');
  String get openLinkHint => text(
    '可以复制地址，在浏览器中查看。',
    'アドレスをコピーしてブラウザで確認できます。',
    'You can copy the address and view it in your browser.',
  );
  String get copyLink => text('复制链接', 'リンクをコピー', 'Copy link');
  String get copied => text('链接已复制', 'リンクをコピーしました', 'Link copied');
  String get cannotCopy =>
      text('暂时无法复制链接', 'リンクをコピーできません', 'Could not copy the link');
  String get close => text('关闭', '閉じる', 'Close');
}
