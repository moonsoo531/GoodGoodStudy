import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_language.dart';
import '../l10n/app_localizations.dart';
import '../sync/resource_sync_controller.dart';
import '../sync/sync_settings.dart';
import '../sync/sync_strings.dart';

/// Appearance is independent of playback and study data.
class ThemePreferences {
  ThemePreferences({this.directory});

  final Directory? directory;
  Future<void> _pending = Future<void>.value();

  Future<File> _file() async {
    final location = directory ?? await getApplicationSupportDirectory();
    await location.create(recursive: true);
    return File('${location.path}/appearance.json');
  }

  Future<ThemeMode> read() async {
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 4096) {
        return ThemeMode.system;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return ThemeMode.system;
      return ThemeMode.values
              .where((mode) => mode.name == value['theme_mode'])
              .firstOrNull ??
          ThemeMode.system;
    } on FormatException {
      return ThemeMode.system;
    } on FileSystemException {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) {
    final encoded = jsonEncode({'theme_mode': mode.name});
    final next = _pending.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsString(encoded, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}

class AppThemeController extends ChangeNotifier {
  AppThemeController({ThemePreferences? preferences})
    : _preferences = preferences ?? ThemePreferences();

  final ThemePreferences _preferences;
  ThemeMode _themeMode = ThemeMode.system;
  int _selectionRevision = 0;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final revision = _selectionRevision;
    final saved = await _preferences.read();
    if (revision == _selectionRevision && saved != _themeMode) {
      _themeMode = saved;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _selectionRevision++;
    if (_themeMode != value) {
      _themeMode = value;
      notifyListeners();
    }
    await _preferences.write(value);
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.notifier;

  static AppThemeController of(BuildContext context) => maybeOf(context)!;
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: dark ? const Color(0xFF70D6B3) : const Color(0xFF007557),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF70D6B3) : const Color(0xFF006B50),
        onPrimary: dark ? const Color(0xFF00382A) : Colors.white,
        tertiary: dark ? const Color(0xFFC6B5FF) : const Color(0xFF6842A2),
        onTertiary: dark ? const Color(0xFF33195E) : Colors.white,
        surface: dark ? const Color(0xFF171C23) : Colors.white,
      );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF101419)
        : const Color(0xFFF6F8F7),
    useMaterial3: true,
    sliderTheme: const SliderThemeData(trackHeight: 3),
  );
}

enum _SettingsDestination { sync }

/// Shared settings entry, available on the player, study and quiz pages.
class ThemeMenuButton extends StatelessWidget {
  const ThemeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.maybeOf(context);
    final language = AppLanguageScope.maybeOf(context);
    final sync = ResourceSyncScope.maybeOf(context);
    if (theme == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: context.tr(language == null ? '外观主题' : '设置'),
      icon: language != null
          ? const Icon(Icons.settings_outlined)
          : Icon(switch (theme.themeMode) {
              ThemeMode.system => Icons.brightness_auto_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
            }),
      onPressed: () async {
        final navigator = Navigator.of(context);
        final route = DialogRoute<Object>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text(dialogContext.tr(language == null ? '外观主题' : '设置')),
            children: [
              if (language != null) _heading(dialogContext, '外观主题'),
              for (final mode in ThemeMode.values)
                ListTile(
                  leading: Icon(
                    theme.themeMode == mode
                        ? Icons.check_rounded
                        : Icons.circle_outlined,
                  ),
                  title: Text(
                    dialogContext.tr(switch (mode) {
                      ThemeMode.system => '跟随系统',
                      ThemeMode.light => '浅色',
                      ThemeMode.dark => '深色',
                    }),
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(mode),
                ),
              if (language != null) ...[
                const Divider(),
                _heading(dialogContext, '界面语言'),
                for (final value in AppLanguage.values)
                  ListTile(
                    key: ValueKey('interface-language-${value.code}'),
                    leading: Icon(
                      language.language == value
                          ? Icons.check_rounded
                          : Icons.circle_outlined,
                    ),
                    title: Text(value.nativeName),
                    onTap: () => Navigator.of(dialogContext).pop(value),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text(dialogContext.tr('仅切换界面语言，教材、字幕和题目保留原文。')),
                ),
              ],
              if (sync != null) ...[
                const Divider(),
                ListTile(
                  key: const ValueKey('icloud-sync-settings'),
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(SyncStrings(dialogContext).title),
                  onTap: () =>
                      Navigator.of(dialogContext)
                          .pop(_SettingsDestination.sync),
                ),
              ],
            ],
          ),
        );
        final selection = await navigator.push<Object>(route);
        // Do not rebuild native accessibility portal anchors during dismissal.
        await route.completed;
        if (selection == null || !context.mounted) return;
        if (selection == _SettingsDestination.sync) {
          await showSyncSettings(context);
          return;
        }
        try {
          if (selection is ThemeMode) {
            await theme.setThemeMode(selection);
          } else if (selection is AppLanguage && language != null) {
            await language.setLanguage(selection);
          }
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Builder(
                builder: (context) => Text(
                  context.tr(
                    selection is AppLanguage
                        ? '语言已切换，但保存失败；重新打开应用后可能恢复原设置。'
                        : '主题已切换，但保存失败；重新打开应用后可能恢复原设置。',
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _heading(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
    child: Text(
      context.tr(label),
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );
}
