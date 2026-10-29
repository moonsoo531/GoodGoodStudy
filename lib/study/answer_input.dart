import 'package:flutter/material.dart';

import 'answer_comparison.dart';
import '../l10n/app_localizations.dart';

Color _correctColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF83DB9B)
    : const Color(0xFF16753B);

/// Keeps the user's original text intact, including Japanese IME composition.
class StudyAnswerController extends TextEditingController {
  StudyAnswerController({super.text});

  AnswerComparison? _comparison;
  AnswerComparison? get comparison => _comparison;

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != value.text) _comparison = null;
    super.value = newValue;
  }

  void compareWith(String expected) {
    _comparison = compareStudyAnswer(text, expected);
    notifyListeners();
  }

  void clearComparison() {
    if (_comparison == null) return;
    _comparison = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final result = _comparison;
    final composing = value.composing;
    if (result == null ||
        result.tooLong ||
        !result.hasContent ||
        (withComposing && composing.isValid && !composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final errorColor = Theme.of(context).colorScheme.error;
    return TextSpan(
      style: style,
      children: [
        for (final span in result.actualSpans)
          TextSpan(
            text: span.text,
            style: TextStyle(
              color: span.different ? errorColor : _correctColor(context),
              decoration: span.different ? TextDecoration.underline : null,
              decorationColor: span.different ? errorColor : null,
            ),
          ),
      ],
    );
  }
}

class StudyAnswerInput extends StatelessWidget {
  const StudyAnswerInput({
    super.key,
    required this.controller,
    required this.expected,
    required this.labelText,
    required this.maxLines,
  });

  final StudyAnswerController controller;
  final String expected;
  final String labelText;
  final int maxLines;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final comparison = controller.comparison;
      // A changed reference must not display an old comparison.
      final result =
          comparison != null &&
              comparison.expectedSpans.map((span) => span.text).join() ==
                  expected
          ? comparison
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: maxLines,
            autocorrect: false,
            onTapAlwaysCalled: true,
            onTap: controller.clearComparison,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: labelText,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                controller.compareWith(expected);
              },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(
                result == null ? context.tr('核对答案') : context.tr('重新核对'),
              ),
            ),
          ),
          if (result != null)
            Semantics(
              liveRegion: true,
              label: result.tooLong
                  ? null
                  : result.matches
                  ? context.tr('核对正确')
                  : context.tr('核对有差异，正确答案：{answer}', {'answer': expected}),
              child: result.tooLong
                  ? Text(
                      context.tr('内容较长，请使用「对照原文」自行核对。'),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  : ExcludeSemantics(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            key: ValueKey(
                              result.matches
                                  ? 'answer-correct'
                                  : 'answer-incorrect',
                            ),
                            result.matches
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            color: result.matches
                                ? _correctColor(context)
                                : colors.error,
                            size: 24,
                          ),
                          if (!result.matches) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                expected,
                                key: const ValueKey('correct-answer'),
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.5,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
        ],
      );
    },
  );
}
