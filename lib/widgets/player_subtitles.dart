import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../subtitles/ruby_text_parser.dart';
import '../subtitles/subtitle_visibility.dart';
import 'ruby_subtitle_text.dart';

class SubtitleVisibilityControls extends StatelessWidget {
  const SubtitleVisibilityControls({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final SubtitleVisibility value;
  final ValueChanged<SubtitleVisibility> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      Tooltip(
        message: value.video ? context.tr('隐藏画面字幕') : context.tr('显示画面字幕'),
        child: FilterChip(
          avatar: const Icon(Icons.subtitles_outlined, size: 17),
          label: Text(context.tr('画面字幕')),
          selected: value.video,
          onSelected: enabled
              ? (visible) => onChanged(value.copyWith(video: visible))
              : null,
          visualDensity: VisualDensity.compact,
        ),
      ),
      Tooltip(
        message: value.list ? context.tr('隐藏列表字幕') : context.tr('显示列表字幕'),
        child: FilterChip(
          avatar: const Icon(Icons.view_list_outlined, size: 17),
          label: Text(context.tr('列表字幕')),
          selected: value.list,
          onSelected: enabled
              ? (visible) => onChanged(value.copyWith(list: visible))
              : null,
          visualDensity: VisualDensity.compact,
        ),
      ),
    ],
  );
}

/// Hidden screen captions are not built, including their ruby and semantics.
class ScreenSubtitleText extends StatelessWidget {
  const ScreenSubtitleText({
    super.key,
    required this.visible,
    required this.text,
    required this.style,
    required this.showReadings,
  });

  final bool visible;
  final String text;
  final TextStyle style;
  final bool showReadings;

  @override
  Widget build(BuildContext context) => !visible
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(7),
          ),
          child: RubySubtitleText(
            text: text,
            showReadings: showReadings,
            textAlign: TextAlign.center,
            style: style,
          ),
        );
}

/// Keep the time row and jump action outside this widget when hiding its body.
class SubtitleListText extends StatelessWidget {
  const SubtitleListText({
    super.key,
    required this.visible,
    required this.text,
    required this.style,
  });

  final bool visible;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    visible ? plainSubtitleText(text) : context.tr('列表字幕已隐藏'),
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}
