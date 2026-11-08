import 'package:flutter/material.dart';
import 'package:offline_player/subtitles/subtitles.dart';

import 'inline_ruby_unit.dart';

class RubySubtitleText extends StatefulWidget {
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
  State<RubySubtitleText> createState() => _RubySubtitleTextState();
}

class _RubySubtitleTextState extends State<RubySubtitleText> {
  // Only the cue text affects parsing. Theme, scaling and reading visibility
  // can change without reparsing markup or duplicating the accessibility pass.
  late List<RubyTextSegment> _segments;
  late String _baseText;

  @override
  void initState() {
    super.initState();
    _parseText();
  }

  @override
  void didUpdateWidget(RubySubtitleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parseText();
  }

  void _parseText() {
    _segments = parseRubyText(widget.text);
    _baseText = _segments.map((segment) => segment.text).join();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final readingStyle = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14) * widget.readingScale,
      height: 1,
    );
    return Semantics(
      label: _baseText,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) => Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              for (final segment in _segments)
                if (widget.showReadings &&
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
          textAlign: widget.textAlign,
          textScaler: scaler,
          maxLines: widget.maxLines,
          overflow: widget.maxLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
