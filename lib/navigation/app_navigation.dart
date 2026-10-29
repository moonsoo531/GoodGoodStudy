import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum AppSection { home, study, quiz, player }

typedef BeforeSectionLeave = Future<bool> Function();

/// Navigation preferences never share a file with study, quiz or media state.
class NavigationPreferences {
  NavigationPreferences({this.directory});
  final Directory? directory;
  Future<void> _pending = Future.value();

  Future<File> _file() async {
    final root = directory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File('${root.path}/last-section.json');
  }

  Future<AppSection> read() async {
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 4096) {
        return AppSection.home;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return AppSection.home;
      return AppSection.values
              .where(
                (section) =>
                    section != AppSection.home &&
                    section.name == data['section'],
              )
              .firstOrNull ??
          AppSection.home;
    } on FileSystemException {
      return AppSection.home;
    } on FormatException {
      return AppSection.home;
    }
  }

  Future<void> write(AppSection section) {
    if (section == AppSection.home) return Future.value();
    final next = _pending.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsString(
          jsonEncode({'version': 1, 'section': section.name}),
          flush: true,
        );
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> flush() => _pending;
}

/// Only one module is mounted. Leave guards finish before its widget is
/// removed, and asynchronous shutdown completes before the next module mounts.
class AppNavigationController extends ChangeNotifier {
  AppNavigationController({NavigationPreferences? preferences})
    : _preferences = preferences ?? NavigationPreferences();
  final NavigationPreferences _preferences;
  AppSection _section = AppSection.home;
  AppSection? _lastActivity;
  bool _loaded = false;
  bool _switching = false;
  bool _moduleMounted = true;
  bool _disposed = false;
  String? _errorMessage;
  BeforeSectionLeave? _beforeLeave;
  final Set<Future<void>> _shutdown = {};
  Object? _shutdownFailure;
  Future<void>? _loading;

  AppSection get section => _section;
  AppSection get currentSection => _section;
  AppSection? get lastActivity => _lastActivity;
  bool get isReady => _loaded;
  bool get isSwitching => _switching;
  bool get isModuleMounted => _moduleMounted;
  String? get errorMessage => _errorMessage;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final saved = await _preferences.read();
    if (_disposed) return;
    _section = saved;
    _lastActivity = saved == AppSection.home ? null : saved;
    _loaded = true;
    notifyListeners();
  }

  VoidCallback registerBeforeLeave(BeforeSectionLeave callback) {
    _beforeLeave = callback;
    return () {
      if (identical(_beforeLeave, callback)) _beforeLeave = null;
    };
  }

  /// Call from a module's dispose when closing a native audio session, or when
  /// flushing asynchronous state. All errors are observed by this controller.
  void trackShutdown(Future<void> future) {
    final tracked = future.then<void>(
      (_) {},
      onError: (Object error) {
        _shutdownFailure ??= error;
      },
    );
    _shutdown.add(tracked);
    unawaited(tracked.whenComplete(() => _shutdown.remove(tracked)));
  }

  Future<void> navigate(AppSection target) async {
    if (!_loaded || _switching || _disposed || target == _section) return;
    _switching = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final guard = _beforeLeave;
      if (guard != null && !await guard()) return;
      if (_disposed) return;
      _moduleMounted = false;
      notifyListeners();
      // Disposing the old module registers any outstanding audio shutdown.
      await WidgetsBinding.instance.endOfFrame;
      while (_shutdown.isNotEmpty) {
        await Future.wait(List<Future<void>>.of(_shutdown));
      }
      if (_disposed) return;
      if (_shutdownFailure != null) {
        _shutdownFailure = null;
        throw StateError('Module shutdown failed');
      }
      _beforeLeave = null;
      _section = target;
      if (target != AppSection.home) {
        _lastActivity = target;
        try {
          await _preferences.write(target);
        } catch (_) {
          _errorMessage = '页面已切换，但保存失败。';
        }
      }
    } catch (_) {
      if (!_moduleMounted) _section = AppSection.home;
      _errorMessage = '无法切换页面，请重试。';
    } finally {
      _moduleMounted = true;
      _switching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> flush() => _preferences.flush();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppNavigationScope extends InheritedNotifier<AppNavigationController> {
  const AppNavigationScope({
    super.key,
    required AppNavigationController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppNavigationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppNavigationScope>()
      ?.notifier;
  static AppNavigationController of(BuildContext context) => maybeOf(context)!;
}
