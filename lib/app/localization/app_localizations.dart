import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_language.dart';
import 'app_messages.dart';

class AppLocalizations {
  const AppLocalizations(this.language);

  final AppLanguage language;

  static const delegate = _AppLocalizationsDelegate();

  static final supportedLocales = List<Locale>.unmodifiable(
    AppLanguage.values.map((language) => language.locale),
  );

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(AppLanguage.fallback);

  static final _parameter = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');

  String translate(
    String source, [
    Map<String, Object?> parameters = const {},
  ]) {
    final translated = switch ((language, appMessages[source])) {
      (AppLanguage.english, final message?) => message.en,
      (AppLanguage.french, final message?) => message.fr,
      (AppLanguage.japanese, final message?) => message.ja,
      _ => source,
    };
    if (parameters.isEmpty) return translated;
    return translated.replaceAllMapped(_parameter, (match) {
      return parameters[match[1]]?.toString() ?? match[0]!;
    });
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLanguage.values.any(
    (language) => language.code == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(
    AppLocalizations(AppLanguage.fromCode(locale.languageCode)),
  );

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension LocalizedUiText on BuildContext {
  String tr(String source, [Map<String, Object?> parameters = const {}]) =>
      AppLocalizations.of(this).translate(source, parameters);
}
