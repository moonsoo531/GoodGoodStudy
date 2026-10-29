import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/widgets/ruby_subtitle_text.dart';

void main() {
  const style = TextStyle(fontSize: 24, height: 1.2);

  Future<void> showSubtitle(
    WidgetTester tester,
    String text, {
    double width = 160,
    bool showReadings = true,
    int? maxLines,
    double scale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: width,
              child: RubySubtitleText(
                text: text,
                style: style,
                showReadings: showReadings,
                maxLines: maxLines,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('manual readings sit above base text on the paragraph baseline', (
    tester,
  ) async {
    await showSubtitle(tester, '<ruby>日本<rt>にほん</rt></ruby>語', width: 300);
    final reading = tester.getRect(find.text('にほん'));
    final base = tester.getRect(find.text('日本'));
    expect(reading.bottom, lessThanOrEqualTo(base.top + 0.1));
    expect(tester.widget<Text>(find.text('にほん')).style!.fontSize, 12);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final baseParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text('日本'), matching: find.byType(RichText)),
    );
    final paragraphBaseline = paragraph.localToGlobal(
      Offset(
        0,
        paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        )!,
      ),
    );
    final baseBaseline = baseParagraph.localToGlobal(
      Offset(
        0,
        baseParagraph.getDryBaseline(
          baseParagraph.constraints,
          TextBaseline.alphabetic,
        )!,
      ),
    );
    expect(baseBaseline.dy, closeTo(paragraphBaseline.dy, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed Japanese Chinese and English wrap within a narrow width', (
    tester,
  ) async {
    await showSubtitle(
      tester,
      '<ruby>日本語<rt>にほんご</rt></ruby>を勉強します。中文和English mix。\n'
      '<ruby>明日<rt>あした</rt></ruby>も<ruby>練習<rt>れんしゅう</rt></ruby>します。',
      width: 110,
    );
    final bounds = tester.getRect(find.byType(RubySubtitleText));
    expect(bounds.width, 110);
    expect(bounds.height, greaterThan(100));
    expect(find.text('にほんご'), findsOneWidget);
    expect(find.text('あした'), findsOneWidget);
    for (final finder in ['日本語', '明日', '練習', 'にほんご', 'あした', 'れんしゅう']) {
      final token = tester.getRect(find.text(finder));
      expect(token.left, greaterThanOrEqualTo(bounds.left - 0.1));
      expect(token.right, lessThanOrEqualTo(bounds.right + 0.1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('overwide annotations remain inside bounds with enlarged text', (
    tester,
  ) async {
    await showSubtitle(
      tester,
      '<ruby>外国語学習<rt>がいこくごがくしゅう</rt></ruby>を続ける。',
      width: 90,
      scale: 1.8,
    );
    final bounds = tester.getRect(find.byType(RubySubtitleText));
    final reading = tester.getRect(find.text('がいこくごがくしゅう'));
    final base = tester.getRect(find.text('外国語学習'));
    expect(reading.left, greaterThanOrEqualTo(bounds.left - 0.1));
    expect(reading.right, lessThanOrEqualTo(bounds.right + 0.1));
    expect(base.right, lessThanOrEqualTo(bounds.right + 0.1));
    expect(bounds.height, greaterThan(70));
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessibility reads base once and does not repeat kana', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await showSubtitle(tester, '<ruby>日本語<rt>にほんご</rt></ruby>を勉強します。');
      final node = tester.getSemantics(find.byType(RubySubtitleText));
      expect(node.getSemanticsData().label, '日本語を勉強します。');
      expect(find.bySemanticsLabel(RegExp('にほんご')), findsNothing);
      var children = 0;
      node.visitChildren((_) {
        children++;
        return true;
      });
      expect(children, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('readings can be hidden without changing base text', (
    tester,
  ) async {
    await showSubtitle(
      tester,
      '<ruby>日本語<rt>にほんご</rt></ruby>とEnglish。',
      showReadings: false,
    );
    expect(find.text('にほんご'), findsNothing);
    expect(find.text('日本語とEnglish。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maxLines caps narrow multiline subtitle height', (tester) async {
    const text =
        '<ruby>日本語<rt>にほんご</rt></ruby>と<ruby>英語<rt>えいご</rt></ruby>を学びます。'
        '毎日少しずつ練習を続けます。字幕を読んで聞いて覚えます。';
    await showSubtitle(tester, text, width: 110);
    final expandedHeight = tester.getSize(find.byType(RubySubtitleText)).height;
    await showSubtitle(tester, text, width: 110, maxLines: 2);
    final cappedHeight = tester.getSize(find.byType(RubySubtitleText)).height;
    expect(cappedHeight, lessThan(expandedHeight));
    expect(tester.takeException(), isNull);
  });
}
