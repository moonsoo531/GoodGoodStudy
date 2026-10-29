import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/subtitles/subtitle_visibility.dart';
import 'package:offline_player/theme/app_theme.dart';
import 'package:offline_player/widgets/player_subtitles.dart';
import 'package:offline_player/widgets/ruby_subtitle_text.dart';

const _caption = '<ruby>創作<rt>そうさく</rt></ruby>する。';

void main() {
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
          expect(find.byType(RubySubtitleText), findsOneWidget);
          expect(find.text('創作する。'), findsOneWidget);

          // Leave only the list visible.
          await tester.tap(find.text('画面字幕'));
          await tester.pumpAndSettle();
          expect(find.byType(RubySubtitleText), findsNothing);
          expect(find.text('創作する。'), findsOneWidget);
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
          expect(find.byType(RubySubtitleText), findsOneWidget);
          expect(find.text('創作する。'), findsOneWidget);
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
