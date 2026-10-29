import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'study_models.dart';
import '../l10n/app_localizations.dart';
import '../widgets/baseline_underline.dart';
import '../widgets/inline_ruby_unit.dart';

/// Imported readings decorate the immutable base text. Practice answers continue
/// to use StudySegment.text, and highlighted fragments retain their own taps.
class StudyPassageText extends StatelessWidget {
  const StudyPassageText({
    super.key,
    required this.segment,
    required this.entries,
    required this.showReadings,
    required this.onEntryTap,
  });

  final StudySegment segment;
  final Map<String, StudyEntry> entries;
  final bool showReadings;
  final ValueChanged<StudyEntry> onEntryTap;

  static const _style = TextStyle(fontSize: 23, height: 1.8);

  Color _entryColor(BuildContext context, StudyEntry entry) =>
      entry.kind == 'grammar'
      ? Theme.of(context).colorScheme.tertiary
      : Theme.of(context).colorScheme.primary;

  List<InlineSpan> _baseSpans(BuildContext context, int start, int end) {
    final spans = <InlineSpan>[];
    var offset = start;
    for (final highlight in segment.highlights) {
      if (highlight.end <= start || highlight.start >= end) continue;
      final from = math.max(start, highlight.start);
      final to = math.min(end, highlight.end);
      if (offset < from) {
        spans.add(TextSpan(text: segment.text.substring(offset, from)));
      }
      final entry = entries[highlight.entryId]!;
      final color = _entryColor(context, entry);
      final fragment = from == highlight.start ? '' : '-part-$from';
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MediaQuery.withNoTextScaling(
            child: Semantics(
              button: true,
              label: context.tr('查看{term}的讲解', {'term': entry.surface}),
              child: InkWell(
                key: ValueKey('term-${segment.id}-${highlight.start}$fragment'),
                onTap: () => onEntryTap(entry),
                borderRadius: BorderRadius.circular(4),
                child: BaselineUnderline(
                  color: color.withValues(alpha: 0.5),
                  child: Text(
                    segment.text.substring(from, to),
                    style: _style.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      offset = to;
    }
    if (offset < end) {
      spans.add(TextSpan(text: segment.text.substring(offset, end)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (!showReadings || segment.ruby.isEmpty) {
      return Text.rich(
        TextSpan(children: _baseSpans(context, 0, segment.text.length)),
        style: _style,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final baseStyle = DefaultTextStyle.of(context).style.merge(_style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final spans = <InlineSpan>[];
        var offset = 0;
        for (final ruby in segment.ruby) {
          spans.addAll(_baseSpans(context, offset, ruby.start));
          final highlight = segment.highlights
              .where((h) => h.start <= ruby.start && h.end >= ruby.end)
              .firstOrNull;
          final readingColor = highlight == null
              ? colors.onSurfaceVariant
              : _entryColor(context, entries[highlight.entryId]!);
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InlineRubyUnit(
                key: ValueKey('ruby-${segment.id}-${ruby.start}'),
                reading: ruby.reading,
                readingStyle: baseStyle.copyWith(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.normal,
                  decoration: TextDecoration.none,
                  color: readingColor,
                ),
                maxWidth: constraints.maxWidth,
                child: Text.rich(
                  TextSpan(children: _baseSpans(context, ruby.start, ruby.end)),
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
          offset = ruby.end;
        }
        spans.addAll(_baseSpans(context, offset, segment.text.length));
        return Text.rich(TextSpan(children: spans), style: baseStyle);
      },
    );
  }
}
