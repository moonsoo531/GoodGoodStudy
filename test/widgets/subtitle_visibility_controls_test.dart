import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitle_visibility.dart';
import 'package:offline_player/theme/app_theme.dart';
import 'package:offline_player/widgets/player_subtitles.dart';
import 'package:offline_player/widgets/ruby_subtitle_text.dart';

const _caption = '<ruby>創作<rt>そうさく</rt></ruby>する。';

void main() {
  testWidgets(
    'sidebar readings sit above kanji and follow text and display changes',
    (tester) async {
      Future<void> showList(
        String text,
        bool visible,
        Color color, {
        bool showReadings = true,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: SubtitleListText(
                visible: visible,
                text: text,
                showReadings: showReadings,
                style: TextStyle(color: color, fontSize: 14, height: 1.25),
              ),
            ),
          ),
        ),
      );

      await showList(_caption, true, Colors.black);
      final state = tester.state(find.byType(RubySubtitleText));
      expect(find.text('そうさく'), findsOneWidget);
      final reading = tester.getRect(find.text('そうさく'));
      final base = tester.getRect(find.text('創作'));
      expect(reading.bottom, lessThanOrEqualTo(base.top + 0.1));
      expect(
        tester
            .widget<RubySubtitleText>(find.byType(RubySubtitleText))
            .textAlign,
        TextAlign.left,
      );

      await showList(_caption, true, Colors.black, showReadings: false);
      expect(tester.state(find.byType(RubySubtitleText)), same(state));
      expect(find.text('そうさく'), findsNothing);
      expect(find.text('創作する。'), findsOneWidget);

      await showList(_caption, false, Colors.black);
      expect(find.byType(RubySubtitleText), findsNothing);
      expect(find.text('創作する。'), findsNothing);
      expect(find.text('列表字幕已隐藏'), findsOneWidget);
      const next = '<ruby>練習<rt>れんしゅう</rt></ruby>する。';
      await showList(next, false, Colors.white);
      expect(find.byType(RubySubtitleText), findsNothing);
      expect(find.text('れんしゅう'), findsNothing);

      await showList(next, true, Colors.white);
      expect(find.text('練習'), findsOneWidget);
      expect(find.text('れんしゅう'), findsOneWidget);
      expect(find.text('そうさく'), findsNothing);
      expect(
        tester
            .widget<RubySubtitleText>(find.byType(RubySubtitleText))
            .style!
            .color,
        Colors.white,
      );
      await showList(next, true, Colors.black);
      expect(
        tester
            .widget<RubySubtitleText>(find.byType(RubySubtitleText))
            .style!
            .color,
        Colors.black,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} regions toggle independently without leaking hidden text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              home: const _Harness(),
            ),
          );
          expect(find.byType(RubySubtitleText), findsNWidgets(2));
          expect(find.text('そうさく'), findsNWidgets(2));

          // Leave only the list visible.
          await tester.tap(find.text('画面字幕'));
          await tester.pumpAndSettle();
          expect(find.byType(RubySubtitleText), findsOneWidget);
          expect(find.text('そうさく'), findsOneWidget);
          expect(find.byTooltip('显示画面字幕'), findsOneWidget);
          expect(find.byTooltip('隐藏列表字幕'), findsOneWidget);
          expect(_semanticsLabels(tester), isNot(contains('そうさく')));

          // Hide both; only the navigation timeline and a safe placeholder remain.
          await tester.tap(find.text('列表字幕'));
          await tester.pumpAndSettle();
          expect(find.text('列表字幕已隐藏'), findsOneWidget);
          expect(find.text('創作する。'), findsNothing);
          expect(find.byType(RubySubtitleText), findsNothing);
          expect(_semanticsLabels(tester), isNot(contains('創作')));
          expect(_semanticsLabels(tester), isNot(contains('そうさく')));
          expect(find.text('00:42'), findsOneWidget);
          await tester.tap(find.text('00:42'));
          await tester.pumpAndSettle();
          expect(find.text('已跳转 1 次'), findsOneWidget);

          // Leave only the screen visible; the list remains hidden.
          await tester.tap(find.text('画面字幕'));
          await tester.pumpAndSettle();
          expect(find.byType(RubySubtitleText), findsOneWidget);
          expect(find.text('列表字幕已隐藏'), findsOneWidget);
          expect(find.text('創作する。'), findsNothing);
          expect(find.byTooltip('隐藏画面字幕'), findsOneWidget);
          expect(find.byTooltip('显示列表字幕'), findsOneWidget);

          await tester.tap(find.text('列表字幕'));
          await tester.pumpAndSettle();
          expect(find.byType(RubySubtitleText), findsNWidgets(2));
          expect(find.text('そうさく'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          semantics.dispose();
        }
      },
    );
  }
}

String _semanticsLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    labels.add(node.getSemanticsData().label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester
      .element(find.byType(Scaffold))
      .findRenderObject()
      ?.owner
      ?.semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return labels.join('\n');
}

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  SubtitleVisibility visibility = const SubtitleVisibility();
  int jumped = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SubtitleVisibilityControls(
          value: visibility,
          onChanged: (value) => setState(() => visibility = value),
        ),
        ScreenSubtitleText(
          visible: visibility.video,
          text: _caption,
          showReadings: true,
          style: const TextStyle(fontSize: 22, color: Colors.white),
        ),
        InkWell(
          onTap: () => setState(() => jumped++),
          child: Column(
            children: [
              const Text('00:42'),
              SubtitleListText(
                visible: visibility.list,
                text: _caption,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Text('已跳转 $jumped 次'),
      ],
    ),
  );
}
