import 'package:flutter/widgets.dart';

enum AppLanguage {
  english(Locale('en'), 'English'),
  french(Locale('fr'), 'Français'),
  chinese(Locale('zh', 'CN'), '简体中文'),
  japanese(Locale('ja'), '日本語');

  const AppLanguage(this.locale, this.displayName);

  final Locale locale;
  final String displayName;

  String get code => locale.languageCode;

  static const fallback = chinese;

  static AppLanguage fromCode(String? value) => values.firstWhere(
    (language) => language.code == value,
    orElse: () => fallback,
  );
}
