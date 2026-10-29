import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

class SyncStrings {
  SyncStrings(BuildContext context)
    : language = AppLocalizations.of(context).locale.languageCode;

  final String language;

  String text(String zh, String ja, String en) => language == 'ja'
      ? ja
      : language == 'en'
      ? en
      : zh;

  String get title => text('iCloud 同步', 'iCloud 同期', 'iCloud sync');
  String get intro => text(
    '在使用同一 Apple ID 的设备间同步自己的学习资料，保留本机离线副本。',
    '同じ Apple ID の端末間で学習教材を同期し、この端末にもオフライン用のコピーを保存します。',
    'Sync your learning materials across devices using the same Apple ID, while keeping an offline copy on this device.',
  );
  String get enable =>
      text('开启 iCloud 同步', 'iCloud 同期を有効にする', 'Enable iCloud sync');
  String get optIn => text(
    '默认关闭。开启后会自动检查并同步资料。',
    '初期設定はオフです。有効にすると、自動で確認・同期します。',
    'Off by default. When enabled, materials are checked and synced automatically.',
  );
  String get disabling => text(
    '关闭只会停止后续同步，不会删除本机或 iCloud 中的资料。',
    'オフにすると以後の同期を停止します。この端末や iCloud の教材は削除されません。',
    'Turning sync off stops future syncing. It does not delete materials from this device or iCloud.',
  );
  String get included => text('同步范围', '同期するもの', 'What syncs');
  String get packages =>
      text('学习包与题库', '学習パックと問題集', 'Study packages and question banks');
  String get packageAudio =>
      text('学习包内的音频', '学習パック内の音声', 'Audio included in study packages');
  String get progress => text(
    '学习笔记、自定义属性与学习进度',
    '学習ノート・カスタム属性・学習の進み具合',
    'Study notes, custom attributes and learning progress',
  );
  String get excluded => text(
    '未完成测试、测试答案与成绩，以及播放器单独导入的音视频和字幕不参与同步。',
    '未完了のテスト・解答と成績、およびプレーヤーに個別に読み込んだ音声・動画・字幕は同期しません。',
    'Unfinished quizzes, answers and scores, and media or subtitles imported separately into the player are excluded.',
  );
  String get status => text('同步状态', '同期の状態', 'Sync status');
  String get syncNow => text('立即同步', '今すぐ同期', 'Sync now');
  String get checkingTime => text('上次检查', '前回の確認', 'Last checked');
  String get notChecked => text('尚未检查', '未確認', 'Not checked yet');
  String transfers(int uploads, int downloads) => text(
    '待上传 $uploads 项 · 待下载 $downloads 项',
    'アップロード待ち $uploads 件・ダウンロード待ち $downloads 件',
    'Uploads waiting: $uploads · Downloads waiting: $downloads',
  );
  String availability(String value) => switch (value) {
    'available' => text('iCloud 可用', 'iCloud を利用できます', 'iCloud is available'),
    'notConfigured' => text(
      '当前应用尚未配置 iCloud 同步。',
      'このアプリでは iCloud 同期がまだ設定されていません。',
      'iCloud sync is not configured for this app yet.',
    ),
    'notSignedIn' => text(
      '请先在系统设置中登录 iCloud，并开启 iCloud 云盘。',
      'システム設定で iCloud にサインインし、iCloud Drive を有効にしてください。',
      'Sign in to iCloud in system settings and enable iCloud Drive.',
    ),
    'unavailable' => text(
      'iCloud 暂时不可用，请稍后重试。本机资料仍可离线使用。',
      '現在 iCloud を利用できません。後でもう一度お試しください。この端末の教材はオフラインでも利用できます。',
      'iCloud is temporarily unavailable. Try again later. Local materials remain available offline.',
    ),
    'unsupported' => text(
      '当前平台不支持 iCloud 同步。',
      'このプラットフォームは iCloud 同期に対応していません。',
      'iCloud sync is not supported on this platform.',
    ),
    _ => text(
      '尚未检查 iCloud 状态',
      'iCloud の状態は未確認です',
      'iCloud availability has not been checked',
    ),
  };
  String phase(String value) => switch (value) {
    'checking' => text('正在检查…', '確認中…', 'Checking…'),
    'uploading' => text('正在上传…', 'アップロード中…', 'Uploading…'),
    'downloading' => text('正在下载…', 'ダウンロード中…', 'Downloading…'),
    'ready' => text('本次检查已完成', '今回の確認が完了しました', 'Check complete'),
    'waiting' => text('等待同步', '同期を待機中', 'Waiting to sync'),
    'conflict' => text(
      '有内容需要你选择',
      '選択が必要な内容があります',
      'Some content needs your choice',
    ),
    'error' => text('本次同步未完成', '今回の同期は完了していません', 'Sync did not complete'),
    _ => text('同步已关闭', '同期はオフです', 'Sync is off'),
  };
  String get failure => text(
    '同步暂未完成，请稍后重试。本机资料会保留。',
    '同期を完了できませんでした。後でもう一度お試しください。この端末の教材は保持されます。',
    'Sync could not be completed. Try again later. Materials on this device are preserved.',
  );
  String get pendingRemote => text(
    '有云端更新等待应用。下次返回首页后，会在保存本机进度后安全应用，不会打断当前学习、测试或播放。',
    'クラウドの更新が適用待ちです。次にホームに戻ると、この端末の進捗を保存してから適用します。現在の学習・テスト・再生は中断しません。',
    'Cloud updates are waiting to be applied. They will be applied safely after saving local progress the next time you return home, without interrupting study, quizzes or playback.',
  );
  String get accountChanged => text(
    '检测到 iCloud 账号变化。重新开启前，请确认要将本机学习资料同步到当前 Apple ID。',
    'iCloud アカウントが変更されました。再度有効にする前に、この端末の教材を現在の Apple ID と同期することを確認してください。',
    'The iCloud account has changed. Before enabling sync again, confirm that you want to sync local learning materials with the current Apple ID.',
  );
  String get confirmAndEnable =>
      text('确认并开启', '確認して有効にする', 'Confirm and enable');
  String get confirmAccountTitle => text(
    '同步到当前 Apple ID？',
    '現在の Apple ID と同期しますか？',
    'Sync with the current Apple ID?',
  );
  String get confirmAccountBody => text(
    '继续开启后，本机学习资料和笔记会上传到当前 Apple ID 的 iCloud。原账号中的云端副本不会自动转移。请确认当前账号是你要使用的账号。',
    '有効にすると、この端末の教材とノートが現在の Apple ID の iCloud にアップロードされます。以前のアカウントのクラウドコピーは自動では移りません。利用するアカウントをご確認ください。',
    'Enabling sync will upload local learning materials and notes to the current Apple ID’s iCloud. Cloud copies in the previous account will not be transferred automatically. Confirm that this is the account you want to use.',
  );
  String get conflicts => text('需要处理的冲突', '確認が必要な競合', 'Conflicts to review');
  String kind(String value) => switch (value) {
    'studyPackage' => text('学习包', '学習パック', 'Study package'),
    'quizPackage' => text('题库', '問題集', 'Question bank'),
    _ => text('学习笔记与进度', '学習ノートと進捗', 'Study notes and progress'),
  };
  String get progressConflict => text(
    '本机和云端的修改有冲突，两份内容都会保留。请选择本设备采用的版本。',
    'この端末とクラウドの変更が競合しています。両方の内容を保持します。この端末で使うバージョンを選んでください。',
    'Local and cloud changes conflict. Both copies are preserved. Choose which version this device should use.',
  );
  String get packageConflict => text(
    '资料不会被自动覆盖。如果同一版本的资料内容不同，请提高资料包的版本号后重新导入。',
    '教材を自動で上書きすることはありません。同じバージョンで内容が異なる場合は、教材のバージョン番号を上げて再読み込みしてください。',
    'Materials are not overwritten automatically. If the same package version has different contents, increase its version number and import it again.',
  );
  String get keepLocal => text('保留本机', 'この端末の内容を使う', 'Keep local');
  String get useRemote => text('使用云端', 'クラウドの内容を使う', 'Use cloud');
  String get confirmRemoteTitle =>
      text('采用云端版本？', 'クラウド版を使いますか？', 'Use the cloud version?');
  String get confirmRemoteBody => text(
    '本设备将采用这份云端内容。本机现有版本会保留为副本，不会直接删除。更新会在安全返回首页后应用。',
    'この端末ではクラウドの内容を使います。現在の端末側バージョンはコピーとして保持し、直接削除しません。更新は安全にホームへ戻ってから適用します。',
    'This device will use the cloud content. The existing local version will be retained as a copy rather than deleted. The update will be applied after returning safely to home.',
  );
  String get cancel => text('取消', 'キャンセル', 'Cancel');
}
