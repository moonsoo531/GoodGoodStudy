import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core_strings.dart';
import 'main_strings.dart';
import 'player_strings.dart';
import 'quiz_strings.dart';
import 'study_strings.dart';

final Map<String, List<String>> interfaceTranslations = {
  ...playerStrings,
  ...studyStrings,
  ...quizStrings,
  ...mainStrings,
  ...coreStrings,
};

const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;
  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('zh'), Locale('ja'), Locale('en')];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('zh'));

  String text(String source, [Map<String, Object?> arguments = const {}]) {
    final variants = interfaceTranslations[source];
    final index = locale.languageCode == 'ja' ? 0 : 1;
    final translated = locale.languageCode == 'zh' || variants == null
        ? source
        : variants[index];
    return translated.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final key = match[1]!;
      return arguments.containsKey(key) ? '${arguments[key]}' : match[0]!;
    });
  }

  /// For UI errors produced by storage/controllers. Content strings must use
  /// their original text instead of passing through this translation method.
  String message(String source, [int depth = 0]) {
    if (locale.languageCode == 'zh' || depth > 3) return source;
    if (interfaceTranslations.containsKey(source)) return text(source);
    if (source.contains('\n')) {
      return source.split('\n').map((line) => message(line, depth)).join('\n');
    }
    for (final prefix in ['FormatException: ', 'StateError: ', 'Bad state: ']) {
      if (source.startsWith(prefix)) {
        return message(source.substring(prefix.length), depth + 1);
      }
    }
    for (final template in _messageTemplates) {
      final match = template.pattern.firstMatch(source);
      if (match == null) continue;
      final arguments = <String, Object?>{};
      for (var i = 0; i < template.names.length; i++) {
        final name = template.names[i];
        final value = match.group(i + 1)!;
        arguments[name] =
            const {'error', 'label', 'reason', 'message'}.contains(name)
            ? message(value, depth + 1)
            : value;
      }
      return text(template.source, arguments);
    }
    return source;
  }
}

final _messageTemplates = [
  for (final key in interfaceTranslations.keys)
    if (RegExp(r'\{\w+\}').hasMatch(key)) _MessageTemplate(key),
]..sort((a, b) => b.source.length.compareTo(a.source.length));

class _MessageTemplate {
  _MessageTemplate(this.source) {
    var start = 0;
    final parts = <String>['^'];
    for (final match in RegExp(r'\{(\w+)\}').allMatches(source)) {
      parts.add(RegExp.escape(source.substring(start, match.start)));
      parts.add('([\\s\\S]*?)');
      names.add(match[1]!);
      start = match.end;
    }
    parts.add(RegExp.escape(source.substring(start)));
    parts.add(r'$');
    pattern = RegExp(parts.join());
  }
  final String source;
  final List<String> names = [];
  late final RegExp pattern;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      const ['zh', 'ja', 'en'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension InterfaceTranslation on BuildContext {
  String tr(String source, [Map<String, Object?> arguments = const {}]) =>
      AppLocalizations.of(this).text(source, arguments);
  String trMessage(String source) => AppLocalizations.of(this).message(source);
}
