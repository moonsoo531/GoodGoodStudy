import 'package:flutter/material.dart';

import 'quiz_models.dart';
import '../widgets/inline_ruby_unit.dart';
import '../widgets/range_underline.dart';

/// Displays prepared annotations above immutable question/option text.
class QuizRubyText extends StatelessWidget {
  const QuizRubyText({
    super.key,
    required this.text,
    required this.ruby,
    required this.showReadings,
    this.underlines = const [],
    this.prefix = '',
    this.style,
  });

  final String text;
  final List<QuizRuby> ruby;
  final bool showReadings;
  final List<QuizUnderline> underlines;
  final String prefix;
  final TextStyle? style;

  List<TextRange> _ranges(int start, int end, {int targetStart = 0}) => [
    for (final underline in underlines)
      if (underline.end > start && underline.start < end)
        TextRange(
          start:
              targetStart +
              (underline.start > start ? underline.start : start) -
              start,
          end:
              targetStart + (underline.end < end ? underline.end : end) - start,
        ),
  ];

  Widget _paragraph(
    BuildContext context,
    List<InlineSpan> spans,
    List<TextRange> ranges,
    TextStyle style, {
    TextAlign? textAlign,
    bool preserveUnderlineScope = false,
  }) {
    final child = Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
    );
    if (ranges.isEmpty && !preserveUnderlineScope) return child;
    return RangeUnderline(
      ranges: ranges,
      color:
          style.foreground?.color ??
          style.color ??
          Theme.of(context).colorScheme.onSurface,
      thickness: 2,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    if (!showReadings || ruby.isEmpty) {
      return _paragraph(
        context,
        [TextSpan(text: '$prefix$text')],
        _ranges(0, text.length, targetStart: prefix.length),
        baseStyle,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final spans = <InlineSpan>[
          if (prefix.isNotEmpty) TextSpan(text: prefix),
        ];
        final ranges = <TextRange>[];
        var sourceOffset = 0;
        var paragraphOffset = prefix.length;
        void appendText(int end) {
          if (sourceOffset == end) return;
          spans.add(TextSpan(text: text.substring(sourceOffset, end)));
          ranges.addAll(
            _ranges(sourceOffset, end, targetStart: paragraphOffset),
          );
          paragraphOffset += end - sourceOffset;
        }

        for (final reading in ruby) {
          appendText(reading.start);
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InlineRubyUnit(
                key: ValueKey('quiz-ruby-${reading.start}-${reading.end}'),
                reading: reading.reading,
                readingStyle: baseStyle.copyWith(
                  fontSize: (baseStyle.fontSize ?? 18) * .48,
                  height: 1,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
                maxWidth: constraints.maxWidth,
                child: _paragraph(
                  context,
                  [TextSpan(text: text.substring(reading.start, reading.end))],
                  _ranges(reading.start, reading.end),
                  baseStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
          // In the outer paragraph a ruby unit occupies one replacement
          // character. Keep original UTF-16 ranges local to its base text.
          paragraphOffset++;
          sourceOffset = reading.end;
        }
        appendText(text.length);
        return Semantics(
          label: '$prefix$text',
          child: ExcludeSemantics(
            child: _paragraph(
              context,
              spans,
              ranges,
              baseStyle,
              preserveUnderlineScope: underlines.isNotEmpty,
            ),
          ),
        );
      },
    );
  }
}
