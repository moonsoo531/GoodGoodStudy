import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/answer_comparison.dart';
import 'package:offline_player/study/answer_input.dart';
import 'package:offline_player/theme/app_theme.dart';

const _correctKey = ValueKey('answer-correct');
const _incorrectKey = ValueKey('answer-incorrect');
const _answerKey = ValueKey('correct-answer');

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      testWidgets(
        '${brightness.name} ${size.width.toInt()}x${size.height.toInt()} colors correct input green and incorrect input red while preserving concise feedback and tap reset',
        (tester) async {
          final controller = StudyAnswerController();
          const answer = '私は猫が好きです。';
          const incorrect = '私は犬が好きです。';
          try {
            await _mount(
              tester,
              controller,
              brightness: brightness,
              size: size,
              expected: answer,
            );
            await tester.enterText(find.byType(TextField), incorrect);
            await tester.pump();
            expect(controller.comparison, isNull);
            _expectNoResult();
            _expectInputNeutral(tester, controller, brightness);

            await _check(tester);
            final colors = buildAppTheme(brightness).colorScheme;
            expect(controller.text, incorrect);
            expect(find.byKey(_incorrectKey), findsOneWidget);
            expect(find.byKey(_correctKey), findsNothing);
            final cross = tester.widget<Icon>(find.byKey(_incorrectKey));
            expect(cross.icon, Icons.close_rounded);
            expect(cross.color, colors.error);
            final displayed = tester.widget<Text>(find.byKey(_answerKey));
            expect(displayed.data, answer);
            expect(
              DefaultTextStyle.of(tester.element(find.byKey(_answerKey))).style
                  .merge(displayed.style)
                  .color,
              colors.onSurface,
            );
            expect(_inputSpan(tester, controller).toPlainText(), incorrect);
            expect(
              _coloredText(_inputSpan(tester, controller), colors.error),
              '犬',
            );
            expect(
              _coloredText(
                _inputSpan(tester, controller),
                _successColor(brightness),
              ),
              '私はが好きです。',
            );
            expect(find.text('参考原文（红色为应改或漏写）'), findsNothing);
            expect(find.text('红色标出了与原文不同的文字。'), findsNothing);
            expect(tester.takeException(), isNull);

            // Clicking is sufficient: do not type or replace the answer yet.
            await tester.ensureVisible(find.byType(TextField));
            await tester.tap(find.byType(TextField));
            await tester.pump();
            expect(controller.text, incorrect);
            expect(controller.comparison, isNull);
            _expectNoResult();
            _expectInputNeutral(tester, controller, brightness);

            await tester.enterText(find.byType(TextField), answer);
            await _check(tester);
            expect(find.byKey(_incorrectKey), findsNothing);
            expect(find.byKey(_answerKey), findsNothing);
            final check = tester.widget<Icon>(find.byKey(_correctKey));
            expect(check.icon, Icons.check_rounded);
            expect(
              check.color,
              brightness == Brightness.light
                  ? const Color(0xFF16753B)
                  : const Color(0xFF83DB9B),
            );
            expect(find.text('与原文文字一致'), findsNothing);
            expect(_inputSpan(tester, controller).toPlainText(), answer);
            expect(
              _coloredText(
                _inputSpan(tester, controller),
                _successColor(brightness),
              ),
              answer,
            );
            expect(
              _coloredText(_inputSpan(tester, controller), colors.error),
              isEmpty,
            );

            await tester.ensureVisible(find.byType(TextField));
            await tester.tap(find.byType(TextField));
            await tester.pump();
            expect(controller.text, answer);
            expect(controller.comparison, isNull);
            _expectNoResult();
            _expectInputNeutral(tester, controller, brightness);
            expect(tester.takeException(), isNull);
          } finally {
            await _unmount(tester, controller);
          }
        },
      );
    }
  }

  for (final sample in [
    (label: 'missing', input: '私はです。', green: '私はです。', red: ''),
    (label: 'extra', input: '私私は猫です。', green: '私は猫です。', red: '私'),
  ]) {
    testWidgets(
      '${sample.label} text preserves green correct portions and marks only extra input red with a full neutral answer',
      (tester) async {
        final controller = StudyAnswerController(text: sample.input);
        try {
          await _mount(tester, controller, expected: '私は猫です。');
          await _check(tester);
          expect(controller.text, sample.input);
          expect(find.byKey(_incorrectKey), findsOneWidget);
          expect(find.byKey(_correctKey), findsNothing);
          expect(tester.widget<Text>(find.byKey(_answerKey)).data, '私は猫です。');
          expect(
            _coloredText(
              _inputSpan(tester, controller),
              buildAppTheme(Brightness.light).colorScheme.error,
            ),
            sample.red,
          );
          expect(
            _coloredText(
              _inputSpan(tester, controller),
              _successColor(Brightness.light),
            ),
            sample.green,
          );
          final displayed = tester.widget<Text>(find.byKey(_answerKey));
          expect(
            DefaultTextStyle.of(tester.element(find.byKey(_answerKey))).style
                .merge(displayed.style)
                .color,
            buildAppTheme(Brightness.light).colorScheme.onSurface,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester, controller);
        }
      },
    );
  }

  testWidgets(
    'blank input shows a cross and the correct answer rather than success',
    (tester) async {
      final controller = StudyAnswerController();
      try {
        await _mount(tester, controller, expected: '創作する。');
        await _check(tester);
        expect(find.byKey(_incorrectKey), findsOneWidget);
        expect(find.byKey(_correctKey), findsNothing);
        expect(tester.widget<Text>(find.byKey(_answerKey)).data, '創作する。');
        expect(controller.text, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, controller);
      }
    },
  );

  testWidgets(
    'tapping an already focused input hides the result without editing text',
    (tester) async {
      final controller = StudyAnswerController(text: '犬');
      try {
        await _mount(tester, controller, expected: '猫');
        final field = find.byType(TextField);
        await tester.tap(field);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          controller.compareWith('猫');
          await tester.pump();
          expect(find.byKey(_incorrectKey), findsOneWidget);
          expect(find.byKey(_answerKey), findsOneWidget);
          expect(
            _coloredText(
              _inputSpan(tester, controller),
              buildAppTheme(Brightness.light).colorScheme.error,
            ),
            '犬',
          );
          await tester.tap(field);
          await tester.pump();
          expect(controller.text, '犬');
          expect(controller.comparison, isNull);
          _expectNoResult();
          _expectInputNeutral(tester, controller, Brightness.light);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, controller);
      }
    },
  );

  testWidgets(
    'Japanese composing range remains native and typing invalidates comparison',
    (tester) async {
      final controller = StudyAnswerController();
      try {
        await _mount(tester, controller, expected: '漢字');
        controller.value = const TextEditingValue(
          text: 'かんじ',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        );
        controller.compareWith('漢字');
        await tester.pump();
        final span = _inputSpan(tester, controller);
        expect(span.toPlainText(), 'かんじ');
        expect(controller.value.composing, const TextRange(start: 0, end: 3));
        expect(
          _coloredText(span, buildAppTheme(Brightness.light).colorScheme.error),
          isEmpty,
        );
        expect(_coloredText(span, _successColor(Brightness.light)), isEmpty);
        controller.value = const TextEditingValue(
          text: '漢字',
          selection: TextSelection.collapsed(offset: 2),
        );
        await tester.pump();
        expect(controller.comparison, isNull);
        _expectNoResult();
        expect(_inputSpan(tester, controller).toPlainText(), '漢字');
        _expectInputNeutral(tester, controller, Brightness.light);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, controller);
      }
    },
  );

  testWidgets(
    'long input explains the limit without a misleading icon or answer',
    (tester) async {
      final controller = StudyAnswerController(
        text: 'あ' * (maxStudyComparisonCharacters + 1),
      );
      try {
        await _mount(tester, controller, expected: 'あ');
        await _check(tester);
        expect(find.text('内容较长，请使用「对照原文」自行核对。'), findsOneWidget);
        _expectNoResult();
        expect(controller.comparison!.tooLong, isTrue);
        _expectInputNeutral(tester, controller, Brightness.light);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, controller);
      }
    },
  );
}

Color _successColor(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFF16753B)
    : const Color(0xFF83DB9B);

void _expectInputNeutral(
  WidgetTester tester,
  StudyAnswerController controller,
  Brightness brightness,
) {
  final span = _inputSpan(tester, controller);
  final colors = buildAppTheme(brightness).colorScheme;
  expect(_coloredText(span, colors.error), isEmpty);
  expect(_coloredText(span, _successColor(brightness)), isEmpty);
  expect(_coloredText(span, colors.onSurface), controller.text);
}

void _expectNoResult() {
  expect(find.byKey(_correctKey), findsNothing);
  expect(find.byKey(_incorrectKey), findsNothing);
  expect(find.byKey(_answerKey), findsNothing);
}

Future<void> _mount(
  WidgetTester tester,
  StudyAnswerController controller, {
  required String expected,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StudyAnswerInput(
            controller: controller,
            expected: expected,
            labelText: '写下日文（选填）',
            maxLines: 5,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester) async {
  final button = find.text('核对答案');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _unmount(
  WidgetTester tester,
  StudyAnswerController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  controller.dispose();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

TextSpan _inputSpan(WidgetTester tester, StudyAnswerController controller) {
  final context = tester.element(find.byType(StudyAnswerInput));
  return controller.buildTextSpan(
    context: context,
    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
    withComposing: true,
  );
}

String _coloredText(InlineSpan span, Color color) => [
  for (final run in _runs(span))
    if (run.style.color == color) run.text,
].join();

Iterable<({String text, TextStyle style})> _runs(
  InlineSpan span, [
  TextStyle inherited = const TextStyle(),
]) sync* {
  if (span is TextSpan) {
    final style = inherited.merge(span.style);
    if (span.text != null) yield (text: span.text!, style: style);
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _runs(child, style);
    }
  }
}
