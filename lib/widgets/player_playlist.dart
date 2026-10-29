import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../library/local_library.dart';
import '../library/playlist_mode.dart';

@immutable
class PlaylistItemStatus {
  const PlaylistItemStatus({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.completed = false,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final bool completed;
  final String? error;

  double? get progress => completed
      ? 1
      : duration > Duration.zero
      ? (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0, 1)
            .toDouble()
      : null;
}

class PlayerPlaylist extends StatefulWidget {
  const PlayerPlaylist({
    super.key,
    required this.lessons,
    required this.current,
    required this.playing,
    required this.enabled,
    required this.autoAdvance,
    required this.onSelect,
    required this.onRemove,
    required this.onReorder,
    required this.onClear,
    required this.onAutoAdvanceChanged,
    this.statusOf,
    this.mode,
    this.onModeChanged,
    this.onReplay,
    this.onRelocate,
    this.onMenuClosed,
  });

  final List<LocalLesson> lessons;
  final LocalLesson? current;
  final bool playing;
  final bool enabled;
  final bool autoAdvance;
  final ValueChanged<LocalLesson> onSelect;
  final ValueChanged<LocalLesson> onRemove;
  final ReorderCallback onReorder;
  final VoidCallback onClear;
  final ValueChanged<bool> onAutoAdvanceChanged;
  final PlaylistItemStatus Function(LocalLesson)? statusOf;
  final PlaylistMode? mode;
  final ValueChanged<PlaylistMode>? onModeChanged;
  final ValueChanged<LocalLesson>? onReplay;
  final ValueChanged<LocalLesson>? onRelocate;

  /// Runs after the popup route is completely removed, including cancellation.
  /// For a selected value, the corresponding action callback runs first.
  final VoidCallback? onMenuClosed;

  @override
  State<PlayerPlaylist> createState() => _PlayerPlaylistState();
}

class _PlayerPlaylistState extends State<PlayerPlaylist> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  TransitionRoute<dynamic>? _modeRoute;

  double get _itemExtent => widget.statusOf == null ? 72 : 96;
  bool get _filtering => _query.isNotEmpty;
  bool get _canLocate =>
      widget.current != null &&
      widget.lessons.any(
        (lesson) => lesson.identity == widget.current!.identity,
      );

  @override
  void initState() {
    super.initState();
    _scheduleLocate();
  }

  @override
  void didUpdateWidget(covariant PlayerPlaylist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current?.identity != widget.current?.identity &&
        !_filtering) {
      _scheduleLocate();
    }
  }

  void _scheduleLocate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_canLocate) return;
      final index = widget.lessons.indexWhere(
        (lesson) => lesson.identity == widget.current!.identity,
      );
      final target =
          (index * _itemExtent - _scroll.position.viewportDimension * 0.4)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  void _locateCurrent() {
    if (_filtering) {
      _search.clear();
      setState(() => _query = '');
    }
    _scheduleLocate();
  }

  Widget _modeLabel(BuildContext context, PlaylistMode mode) {
    final route = ModalRoute.of(context);
    // The selected item is also built in the page's route. Only remember the
    // actual popup, not that closed-button copy of the item.
    if (route is PopupRoute<dynamic> && !identical(_modeRoute, route)) {
      _modeRoute = route;
      route.popped.then((result) async {
        if (result != null) return;
        await route.completed;
        if (!mounted) return;
        if (identical(_modeRoute, route)) _modeRoute = null;
        widget.onMenuClosed?.call();
      });
    }
    return Text(context.tr(mode.label));
  }

  Future<void> _selectMode(PlaylistMode? mode) async {
    if (mode == null) return;
    final route = _modeRoute;
    if (route == null) return;
    await route.completed;
    if (!mounted) return;
    if (identical(_modeRoute, route)) _modeRoute = null;
    try {
      widget.onModeChanged?.call(mode);
    } finally {
      widget.onMenuClosed?.call();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _filtering
        ? widget.lessons
              .where(
                (lesson) =>
                    lesson.title.toLowerCase().contains(_query) ||
                    lesson.primaryPath.toLowerCase().contains(_query),
              )
              .toList()
        : widget.lessons;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: TextField(
            controller: _search,
            enabled: widget.enabled,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: context.tr('搜索标题或文件夹'),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: !_filtering
                  ? null
                  : IconButton(
                      tooltip: context.tr('清除搜索'),
                      onPressed: widget.enabled
                          ? () {
                              _search.clear();
                              setState(() => _query = '');
                            }
                          : null,
                      icon: const Icon(Icons.close, size: 17),
                    ),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _filtering
                      ? context.tr('找到 {count} / {total} 项', {
                          'count': lessons.length,
                          'total': widget.lessons.length,
                        })
                      : context.tr('共 {count} 项', {
                          'count': widget.lessons.length,
                        }),
                ),
              ),
              IconButton(
                tooltip: context.tr('定位当前项'),
                onPressed: widget.enabled && _canLocate ? _locateCurrent : null,
                icon: const Icon(Icons.my_location, size: 18),
              ),
              TextButton.icon(
                onPressed: widget.enabled && widget.lessons.isNotEmpty
                    ? widget.onClear
                    : null,
                icon: const Icon(Icons.playlist_remove, size: 18),
                label: Text(context.tr('清空')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: lessons.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _filtering
                          ? context.tr('没有找到匹配的媒体')
                          : context.tr('播放列表为空\n拖入视频即可播放\n拖入文件夹可批量添加，包含子文件夹'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.8,
                      ),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: _scroll,
                  itemExtent: _itemExtent,
                  buildDefaultDragHandles: false,
                  itemCount: lessons.length,
                  onReorderItem: widget.enabled && !_filtering
                      ? widget.onReorder
                      : (_, _) {},
                  itemBuilder: (context, index) =>
                      _item(context, lessons[index], index),
                ),
        ),
        const Divider(height: 1),
        if (widget.mode == null)
          SwitchListTile(
            dense: true,
            title: Text(context.tr('自动播放下一项'), style: TextStyle(fontSize: 13)),
            value: widget.autoAdvance,
            onChanged: widget.enabled ? widget.onAutoAdvanceChanged : null,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.repeat, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    label: context.tr('播放模式'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<PlaylistMode>(
                        isExpanded: true,
                        value: widget.mode,
                        onTap: () => _modeRoute = null,
                        items: [
                          for (final mode in PlaylistMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Builder(
                                builder: (context) => _modeLabel(context, mode),
                              ),
                            ),
                        ],
                        onChanged:
                            widget.enabled && widget.onModeChanged != null
                            ? _selectMode
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _item(BuildContext context, LocalLesson lesson, int index) {
    final selected = lesson.identity == widget.current?.identity;
    final status = widget.statusOf?.call(lesson);
    final error = status?.error != null;
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey(lesson.identity),
      color: selected ? colors.primaryContainer : Colors.transparent,
      child: ListTile(
        selected: selected,
        dense: true,
        contentPadding: const EdgeInsets.only(left: 6, right: 4),
        leading: ReorderableDragStartListener(
          index: index,
          enabled: widget.enabled && !_filtering,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message: _filtering ? context.tr('清除搜索后可排序') : context.tr('拖动排序'),
              child: Icon(
                Icons.drag_indicator,
                size: 19,
                color: _filtering
                    ? colors.onSurface.withValues(alpha: 0.25)
                    : null,
              ),
            ),
          ),
        ),
        title: Tooltip(
          message: lesson.primaryPath,
          child: Text(
            lesson.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error
                  ? context.tr('文件不可用')
                  : selected
                  ? widget.playing
                        ? context.tr('正在播放')
                        : context.tr('当前媒体 · 已暂停')
                  : '${widget.lessons.indexOf(lesson) + 1} · ${lesson.videoPath != null ? context.tr('视频') : context.tr('音频')}',
              maxLines: 1,
              style: error ? TextStyle(color: colors.error) : null,
            ),
            if (status != null && !error) ...[
              Text(
                status.completed
                    ? '${context.tr('已播完')}${status.duration > Duration.zero ? ' · ${_clock(status.duration)}' : ''}'
                    : status.duration > Duration.zero
                    ? '${_clock(status.position)} / ${_clock(status.duration)}'
                    : context.tr('尚未播放'),
                maxLines: 1,
                style: const TextStyle(fontSize: 11),
              ),
              if (status.progress != null) ...[
                const SizedBox(height: 3),
                LinearProgressIndicator(value: status.progress, minHeight: 2),
              ],
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onReplay != null || widget.onRelocate != null)
              _PlaylistItemMenu(
                lesson: lesson,
                enabled: widget.enabled,
                onReplay: widget.onReplay,
                onRelocate: widget.onRelocate,
                onMenuClosed: widget.onMenuClosed,
              ),
            IconButton(
              tooltip: context.tr('从播放列表移除'),
              onPressed: widget.enabled ? () => widget.onRemove(lesson) : null,
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ),
        onTap: widget.enabled ? () => widget.onSelect(lesson) : null,
      ),
    );
  }
}

enum _ItemAction { replay, relocate }

class _PlaylistItemMenu extends StatefulWidget {
  const _PlaylistItemMenu({
    required this.lesson,
    required this.enabled,
    this.onReplay,
    this.onRelocate,
    this.onMenuClosed,
  });

  final LocalLesson lesson;
  final bool enabled;
  final ValueChanged<LocalLesson>? onReplay;
  final ValueChanged<LocalLesson>? onRelocate;
  final VoidCallback? onMenuClosed;

  @override
  State<_PlaylistItemMenu> createState() => _PlaylistItemMenuState();
}

class _PlaylistItemMenuState extends State<_PlaylistItemMenu> {
  TransitionRoute<dynamic>? _menuRoute;

  Widget _label(BuildContext context, String text) {
    final route = ModalRoute.of(context);
    if (route is PopupRoute<dynamic> && !identical(_menuRoute, route)) {
      _menuRoute = route;
      route.popped.then((result) async {
        if (result != null) return;
        await route.completed;
        if (!mounted) return;
        if (identical(_menuRoute, route)) _menuRoute = null;
        widget.onMenuClosed?.call();
      });
    }
    return Text(context.tr(text));
  }

  Future<void> _select(_ItemAction action) async {
    final route = _menuRoute;
    if (route == null) return;
    // onSelected is called when the menu starts closing. Its portal and
    // semantics remain attached until the reverse transition has completed.
    await route.completed;
    if (!mounted) return;
    if (identical(_menuRoute, route)) _menuRoute = null;
    try {
      switch (action) {
        case _ItemAction.replay:
          widget.onReplay?.call(widget.lesson);
        case _ItemAction.relocate:
          widget.onRelocate?.call(widget.lesson);
      }
    } finally {
      widget.onMenuClosed?.call();
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ItemAction>(
    tooltip: context.tr('媒体操作'),
    enabled: widget.enabled,
    padding: EdgeInsets.zero,
    iconSize: 18,
    onOpened: () => _menuRoute = null,
    onSelected: _select,
    itemBuilder: (_) => [
      if (widget.onReplay != null)
        PopupMenuItem(
          value: _ItemAction.replay,
          child: Builder(builder: (context) => _label(context, '从头播放')),
        ),
      if (widget.onRelocate != null)
        PopupMenuItem(
          value: _ItemAction.relocate,
          child: Builder(builder: (context) => _label(context, '重新定位文件')),
        ),
    ],
  );
}

String _clock(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = seconds ~/ 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:${(minutes % 60).toString().padLeft(2, '0')}:$tail'
      : '${minutes.toString().padLeft(2, '0')}:$tail';
}
