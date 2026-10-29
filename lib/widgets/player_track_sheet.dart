import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../playback/media_tracks.dart';

/// Content for the player's audio/subtitle bottom sheet. The caller owns the
/// modal route and closes it before opening the external subtitle file picker.
class PlayerTrackSheet extends StatefulWidget {
  const PlayerTrackSheet({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onPickExternal,
    required this.onChanged,
  });

  final MediaTracksController controller;
  final bool enabled;
  final VoidCallback onPickExternal;
  final VoidCallback onChanged;

  @override
  State<PlayerTrackSheet> createState() => _PlayerTrackSheetState();
}

class _PlayerTrackSheetState extends State<PlayerTrackSheet> {
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;

  bool get _interactive => widget.enabled && !_busy;

  Future<void> _select(Future<void> Function() action) async {
    if (!_interactive) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // Persist a successful selection even if the user has dismissed the
      // modal while the native player was completing its command.
      widget.onChanged();
    } catch (error) {
      if (mounted) {
        setState(() {
          final message = error is StateError ? error.message : '$error';
          _error = '切换失败：$message';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final tracks = widget.controller;
      final preferences = tracks.preferences;
      final theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('音轨与字幕'), style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  widget.enabled
                      ? context.tr('选择立即生效，记住当前媒体的偏好。')
                      : context.tr('打开媒体后可选择音轨和字幕。'),
                  style: theme.textTheme.bodySmall,
                ),
                if (_busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.trMessage(_error!),
                        key: const ValueKey('track-selection-error'),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _heading('音轨'),
                for (final option in tracks.audioOptions)
                  _choice(
                    key: ValueKey('audio-${option.id}'),
                    title: _trackLabel(option),
                    localizedTitle: true,
                    selected: preferences.audioId == option.id,
                    onTap: () => _select(() => tracks.selectAudio(option.id)),
                  ),
                const Divider(height: 26),
                _heading('字幕'),
                _choice(
                  key: const ValueKey('subtitle-off'),
                  title: '关闭字幕',
                  selected: preferences.subtitleSource == SubtitleSource.off,
                  onTap: () => _select(tracks.disableSubtitles),
                ),
                _choice(
                  key: const ValueKey('subtitle-external'),
                  title: '外部字幕（SRT / VTT）',
                  subtitle: tracks.hasExternalSubtitles
                      ? '支持逐句列表和已有假名'
                      : '尚未载入外部字幕',
                  selected:
                      preferences.subtitleSource == SubtitleSource.external,
                  available: tracks.hasExternalSubtitles,
                  onTap: () => _select(tracks.selectExternalSubtitles),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('pick-external-subtitles'),
                      onPressed: _interactive ? widget.onPickExternal : null,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: Text(context.tr('载入 SRT / VTT')),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _heading('内嵌字幕'),
                if (tracks.embeddedSubtitleOptions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      context.tr('当前媒体没有内嵌字幕。'),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  for (final option in tracks.embeddedSubtitleOptions)
                    _choice(
                      key: ValueKey('subtitle-embedded-${option.id}'),
                      title: _trackLabel(option),
                      localizedTitle: true,
                      selected:
                          preferences.subtitleSource ==
                              SubtitleSource.embedded &&
                          preferences.subtitleId == option.id,
                      onTap: () => _select(
                        () => tracks.selectEmbeddedSubtitles(option.id),
                      ),
                    ),
                const SizedBox(height: 12),
                Text(
                  context.tr('内嵌字幕显示在视频画面中，不提供逐句列表或假名。'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  String _trackLabel(MediaTrackOption option) {
    if (option.id == 'auto' || option.id == 'no') {
      return context.tr(option.label);
    }
    final pieces = option.label.split(' · ');
    if (option.language?.trim().isNotEmpty ?? false) {
      pieces[0] = context.tr(pieces[0]);
    } else if (option.isGeneratedLabel && pieces[0] == '音轨 ${option.id}') {
      pieces[0] = context.tr('音轨 {id}', {'id': option.id});
    } else if (option.isGeneratedLabel && pieces[0] == '字幕 ${option.id}') {
      pieces[0] = context.tr('字幕 {id}', {'id': option.id});
    }
    return pieces.join(' · ');
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Text(
      context.tr(text),
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _choice({
    required Key key,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
    bool available = true,
    bool localizedTitle = false,
  }) => ListTile(
    key: key,
    dense: true,
    enabled: _interactive && available,
    selected: selected,
    title: Text(localizedTitle ? title : context.tr(title)),
    subtitle: subtitle == null ? null : Text(context.tr(subtitle)),
    trailing: selected ? const Icon(Icons.check, size: 20) : null,
    onTap: _interactive && available && !selected ? onTap : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
