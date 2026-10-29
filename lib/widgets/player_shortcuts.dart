import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Player shortcuts yield to editors, including the playlist search and IME.
class PlayerShortcuts extends StatefulWidget {
  const PlayerShortcuts({
    super.key,
    required this.child,
    required this.enabled,
    required this.onToggle,
    required this.onSeek,
    required this.onVolume,
    required this.onMute,
    required this.onFullScreen,
    required this.onEscape,
    required this.onPreviousCue,
    required this.onNextCue,
    required this.onGoToTime,
    this.onTraverseControls,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  final VoidCallback onFullScreen;
  final VoidCallback onEscape;
  final VoidCallback onPreviousCue;
  final VoidCallback onNextCue;
  final VoidCallback onGoToTime;
  final bool Function(bool backwards)? onTraverseControls;

  @override
  State<PlayerShortcuts> createState() => _PlayerShortcutsState();
}

class _PlayerShortcutsState extends State<PlayerShortcuts> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    super.dispose();
  }

  bool get _editing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // Handle playback keys before a focused Material button's ActivateIntent.
  // A handler on an ancestor Focus runs too late: Space can already have
  // activated a playlist item or another focused button by then.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _editing ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        widget.onTraverseControls?.call(keyboard.isShiftPressed) == true) {
      return KeyEventResult.handled;
    }
    final bindings = <SingleActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, includeRepeats: false):
          widget.onFullScreen,
      const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
          widget.onEscape,
      if (widget.enabled) ...{
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
            widget.onToggle,
        const SingleActivator(LogicalKeyboardKey.keyM, includeRepeats: false):
            widget.onMute,
        const SingleActivator(LogicalKeyboardKey.keyG, includeRepeats: false):
            widget.onGoToTime,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            widget.onSeek(const Duration(seconds: -5)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            widget.onSeek(const Duration(seconds: 5)),
        const SingleActivator(LogicalKeyboardKey.keyJ): () =>
            widget.onSeek(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            widget.onSeek(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            widget.onVolume(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            widget.onVolume(-5),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
          includeRepeats: false,
        ): widget.onPreviousCue,
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          alt: true,
          includeRepeats: false,
        ): widget.onNextCue,
      },
    };
    for (final entry in bindings.entries) {
      if (entry.key.accepts(event, keyboard)) {
        entry.value();
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent &&
          !entry.key.includeRepeats &&
          SingleActivator(
            entry.key.trigger,
            control: entry.key.control,
            shift: entry.key.shift,
            alt: entry.key.alt,
            meta: entry.key.meta,
            numLock: entry.key.numLock,
          ).accepts(event, keyboard)) {
        // A repeated one-shot shortcut remains ours even though it must not
        // run twice. Letting it bubble could activate the focused child.
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, child: widget.child);
}
