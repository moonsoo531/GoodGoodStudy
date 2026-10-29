import 'package:flutter/material.dart';
import 'package:offline_player/subtitles/subtitles.dart';

import 'inline_ruby_unit.dart';

class RubySubtitleText extends StatelessWidget {
  const RubySubtitleText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.readingScale = 0.5,
    this.showReadings = true,
    this.maxLines,
  }) : assert(readingScale > 0 && readingScale < double.infinity),
       assert(maxLines == null || maxLines > 0);

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final double readingScale;
  final bool showReadings;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final baseText = plainSubtitleText(text);
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final segments = parseRubyText(text);
    final readingStyle = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) * readingScale,
      height: 1,
    );
    return Semantics(
      label: baseText,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) => Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              for (final segment in segments)
                if (showReadings &&
                    segment.reading != null &&
                    segment.reading!.isNotEmpty &&
                    segment.text.isNotEmpty)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InlineRubyUnit(
                      reading: segment.reading!,
                      readingStyle: readingStyle,
                      maxWidth: constraints.maxWidth,
                      readingGap: 0,
                      child: Text(
                        segment.text,
                        style: baseStyle,
                        textAlign: TextAlign.center,
                        textWidthBasis: TextWidthBasis.parent,
                      ),
                    ),
                  )
                else
                  TextSpan(text: segment.text),
            ],
          ),
          textAlign: textAlign,
          textScaler: scaler,
          maxLines: maxLines,
          overflow: maxLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
