import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum AppLanguage {
  chinese('zh', '中文'),
  japanese('ja', '日本語'),
  english('en', 'English');

  const AppLanguage(this.code, this.nativeName);
  final String code;
  final String nativeName;
  Locale get locale => Locale(code);

  static AppLanguage fromCode(Object? code) =>
      values.where((language) => language.code == code).firstOrNull ?? chinese;
}

class LanguagePreferences {
  LanguagePreferences({this.directory});
  final Directory? directory;
  Future<void> _pending = Future.value();

  Future<File> _file() async {
    final location = directory ?? await getApplicationSupportDirectory();
    await location.create(recursive: true);
    return File('${location.path}/interface-language.json');
  }

  Future<AppLanguage> read() async {
    try {
      final file = await _file();
      if (!await file.exists() || await file.length() > 4096) {
        return AppLanguage.chinese;
      }
      final data = jsonDecode(await file.readAsString());
      return AppLanguage.fromCode(data is Map ? data['language'] : null);
    } on FormatException {
      return AppLanguage.chinese;
    } on FileSystemException {
      return AppLanguage.chinese;
    }
  }

  Future<void> write(AppLanguage language) {
    final next = _pending.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsString(
          jsonEncode({'language': language.code}),
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

class AppLanguageController extends ChangeNotifier {
  AppLanguageController({LanguagePreferences? preferences})
    : _preferences = preferences ?? LanguagePreferences();
  final LanguagePreferences _preferences;
  AppLanguage _language = AppLanguage.chinese;
  int _revision = 0;

  AppLanguage get language => _language;
  Locale get locale => _language.locale;

  Future<void> load() async {
    final revision = _revision;
    final saved = await _preferences.read();
    if (revision == _revision && saved != _language) {
      _language = saved;
      notifyListeners();
    }
    if (revision == _revision) await _synchronizeMenus();
  }

  Future<void> setLanguage(AppLanguage value) async {
    _revision++;
    if (value != _language) {
      _language = value;
      notifyListeners();
    }
    await Future.wait([_preferences.write(value), _synchronizeMenus()]);
  }

  Future<void> flush() => _preferences.flush();

  Future<void> _synchronizeMenus() async {
    if (!Platform.isMacOS) return;
    try {
      await const MethodChannel('offline_player/local_files')
          .invokeMethod<void>('setInterfaceLanguage', {
            'language': _language.code,
          });
    } on MissingPluginException {
      // Standalone widget hosts do not install the desktop window channel.
    } on PlatformException {
      // The Flutter interface and its saved preference remain available.
    }
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.notifier;

  static AppLanguageController of(BuildContext context) => maybeOf(context)!;
}
