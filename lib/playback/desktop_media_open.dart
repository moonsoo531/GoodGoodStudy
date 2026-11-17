import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/local_library.dart';
import '../navigation/app_navigation.dart';

/// A separate, app-wide channel keeps Finder requests alive outside the player.
class DesktopMediaOpenController extends ChangeNotifier {
  DesktopMediaOpenController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('goodgoodstudy/open_media');

  final MethodChannel _channel;
  final Queue<List<String>> _pending = Queue();
  Future<void>? _pulling;
  bool _pullAgain = false;
  bool _disposed = false;

  bool get hasPending => _pending.isNotEmpty;
  List<String>? get next => _pending.firstOrNull;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'filesAvailable') await _pull();
    });
    await _pull();
  }

  Future<void> _pull() {
    _pullAgain = true;
    return _pulling ??= _readPending().whenComplete(() => _pulling = null);
  }

  Future<void> _readPending() async {
    do {
      _pullAgain = false;
      try {
        final requests = await _channel.invokeListMethod<dynamic>(
          'takePending',
        );
        if (_disposed) return;
        for (final request in requests ?? const []) {
          if (request is! List) continue;
          final paths = request
              .whereType<String>()
              .where((path) {
                return path.startsWith('/') &&
                    !path.contains('\u0000') &&
                    (videoExtensions.contains(extensionOf(path)) ||
                        audioExtensions.contains(extensionOf(path)));
              })
              .toSet()
              .toList();
          if (paths.isNotEmpty) _pending.add(List.unmodifiable(paths));
        }
        notifyListeners();
      } on MissingPluginException {
        return;
      } on PlatformException {
        // A later native notification retries without dropping queued requests.
        return;
      }
    } while (_pullAgain && !_disposed);
  }

  List<String>? takeNext() {
    if (_pending.isEmpty) return null;
    final request = _pending.removeFirst();
    notifyListeners();
    return request;
  }

  Future<String?> requestFolderAccess(String path, String language) =>
      _channel.invokeMethod<String>('requestFolderAccess', {
        'path': path,
        'language': language,
      });

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Lists only direct video children after the user accepts the folder prompt.
Future<List<String>> siblingVideoPaths(Directory directory) async {
  final videos = <String>[];
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is File &&
        !fileName(entry.path).startsWith('.') &&
        videoExtensions.contains(extensionOf(entry.path))) {
      videos.add(entry.path);
    }
  }
  videos.sort((a, b) => compareNaturalNames(fileName(a), fileName(b)));
  return videos;
}

class DesktopMediaOpenRouter extends StatefulWidget {
  const DesktopMediaOpenRouter({
    super.key,
    required this.controller,
    required this.navigation,
    required this.child,
  });
  final DesktopMediaOpenController? controller;
  final AppNavigationController navigation;
  final Widget child;

  @override
  State<DesktopMediaOpenRouter> createState() => _DesktopMediaOpenRouterState();
}

class _DesktopMediaOpenRouterState extends State<DesktopMediaOpenRouter> {
  List<String>? _attempted;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_requestsChanged);
    widget.navigation.addListener(_changed);
    _changed();
  }

  void _requestsChanged() {
    _attempted = null;
    _changed();
  }

  void _changed() {
    final request = widget.controller?.next;
    final navigation = widget.navigation;
    if (!mounted ||
        request == null ||
        _scheduled ||
        identical(request, _attempted) ||
        !navigation.isReady ||
        navigation.isSwitching ||
        navigation.section == AppSection.player) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted || widget.controller?.next == null) return;
      if (navigation.isSwitching) return;
      _attempted = request;
      await navigation.navigate(AppSection.player);
      if (mounted) _changed();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_requestsChanged);
    widget.navigation.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
