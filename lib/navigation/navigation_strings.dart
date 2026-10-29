import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'app_navigation.dart';

class NavigationStrings {
  NavigationStrings(BuildContext context)
    : language = AppLocalizations.of(context).locale.languageCode;
  final String language;
  String text(String zh, String ja, String en) => language == 'ja'
      ? ja
      : language == 'en'
      ? en
      : zh;
  String get home => text('首页', 'ホーム', 'Home');
  String get backToHome => text('返回首页', 'ホームに戻る', 'Back to home');
  String get study => text('学习', '学習', 'Study');
  String get quiz => text('测试', 'テスト', 'Quiz');
  String get player => text('本地播放', 'ローカル再生', 'Local playback');
  String label(AppSection section) => switch (section) {
    AppSection.home => home,
    AppSection.study => study,
    AppSection.quiz => quiz,
    AppSection.player => player,
  };
  String get switchPage => text('切换页面', 'ページを切り替える', 'Switch page');
  String get close => text('关闭', '閉じる', 'Close');
  String get headline =>
      text('今天，学一点新的。', '今日も、ひとつ学ぼう。', 'A little learning, every day.');
  String get subtitle => text(
    '选择一种方式，开始今天的学习。',
    '学び方を選んで、今日の学習を始めましょう。',
    'Choose how you would like to begin.',
  );
  String get eyebrow =>
      text('你的离线学习空间', 'あなたのオフライン学習空間', 'YOUR OFFLINE STUDY SPACE');
  String description(AppSection section) => switch (section) {
    AppSection.study => text(
      '听读、回想与笔记，按自己的节奏掌握新知识。',
      '音読・復習・ノートで、自分のペースで学びましょう。',
      'Read, listen and recall at your own pace.',
    ),
    AppSection.quiz => text(
      '用一道道题目，检验掌握的知识。',
      '問題を解いて、身についた知識を確かめましょう。',
      'Put what you have learned into practice.',
    ),
    AppSection.player => text(
      '打开自己的音频、视频与字幕资源。',
      '自分の音声・動画・字幕を開きましょう。',
      'Open your own audio, video and subtitles.',
    ),
    AppSection.home => '',
  };
  String get phonePlayerDescription => text(
    '打开自己的音频与字幕，专注听力练习。',
    '自分の音声・字幕で、リスニングに集中しましょう。',
    'Listen to your own audio with subtitles.',
  );
  String get resources => text(
    '资源由你准备，所有资料保存在本机。',
    '教材はご自身で用意し、データはこの端末に保存されます。',
    'Bring your own resources. Your materials stay on this device.',
  );
  String get switching => text('正在切换…', '切り替え中…', 'Switching…');
  String get loading => text('正在打开…', '開いています…', 'Opening…');
  String message(String source) => switch (source) {
    '页面已切换，但保存失败。' => text(
      source,
      'ページは切り替わりましたが、保存できませんでした。',
      'Page changed, but the preference could not be saved.',
    ),
    '无法切换页面，请重试。' => text(
      source,
      'ページを切り替えられません。もう一度お試しください。',
      'Could not switch pages. Please try again.',
    ),
    _ => source,
  };
}
