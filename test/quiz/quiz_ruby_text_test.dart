import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_ruby_text.dart';

void main() {
  testWidgets(
    'readings sit above unchanged base and preserve spoken question text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        const ruby = [
          QuizRuby(start: 0, end: 2, reading: 'がっこう'),
          QuizRuby(start: 3, end: 4, reading: 'い'),
        ];
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: QuizRubyText(
                  text: '学校へ行く。',
                  ruby: ruby,
                  showReadings: true,
                  prefix: '1. ',
                  underlines: [QuizUnderline(start: 1, end: 4)],
                  style: TextStyle(fontSize: 22, height: 1.8),
                ),
              ),
            ),
          ),
        );
        expect(find.text('がっこう'), findsOneWidget);
        expect(find.text('い'), findsOneWidget);
        final readingY = tester.getTopLeft(find.text('がっこう')).dy;
        final base = find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == '学校',
        );
        expect(base, findsOneWidget);
        expect(readingY, lessThan(tester.getTopLeft(base).dy));
        expect(find.bySemanticsLabel('1. 学校へ行く。'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: QuizRubyText(
                text: '学校へ行く。',
                ruby: ruby,
                showReadings: false,
                prefix: '1. ',
                underlines: [QuizUnderline(start: 1, end: 4)],
              ),
            ),
          ),
        );
        expect(find.text('がっこう'), findsNothing);
        expect(find.text('1. 学校へ行く。'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'narrow layout with long readings and large text has no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 200,
                  child: QuizRubyText(
                    text: '学校へ行く。長い文章です。',
                    ruby: const [
                      QuizRuby(start: 0, end: 2, reading: 'とてもながいがっこうのよみがな'),
                    ],
                    showReadings: true,
                    style: const TextStyle(fontSize: 23, height: 1.8),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('とてもながいがっこうのよみがな'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
