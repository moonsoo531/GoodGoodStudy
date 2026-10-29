import 'package:flutter/widgets.dart';

/// Sizes an annotation from the actual text widgets, including their locale,
/// emphasis and accessibility settings, rather than measuring a plain string.
class InlineRubyUnit extends StatelessWidget {
  const InlineRubyUnit({
    super.key,
    required this.reading,
    required this.readingStyle,
    required this.maxWidth,
    required this.child,
    this.readingGap = 2,
  });

  final String reading;
  final TextStyle readingStyle;
  final double maxWidth;
  final Widget child;
  final double readingGap;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    // WidgetSpan already scales its entire child using the paragraph's scaler.
    // Nested Text and WidgetSpans must not apply that scaling a second time.
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(
        // Avoid rounding a fractional glyph advance down into an extra line.
        stepWidth: 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IgnoreBaseline(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: readingGap),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: Text(reading, style: readingStyle),
                    ),
                  ),
                ),
              ),
            ),
            // The base text supplies the baseline of the enclosing WidgetSpan.
            child,
          ],
        ),
      ),
    ),
  );
}
