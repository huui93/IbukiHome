import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/localization/app_language.dart';
import 'package:ibukihome/app/localization/app_messages.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/preferences/app_language_preferences.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';

void main() {
  testWidgets('language updates workspaces and is restored after restart', (
    tester,
  ) async {
    final store = InMemorySecureValueStore();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> startApp() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiSecureValueStoreProvider.overrideWithValue(store)],
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    await startApp();
    expect(find.text('还没有消息'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-nav-settings')));
    await tester.pumpAndSettle();

    for (final (code, label, locale) in [
      ('en', 'Language', const Locale('en')),
      ('fr', 'Langue', const Locale('fr')),
      ('zh', '语言', const Locale('zh', 'CN')),
      ('ja', '言語', const Locale('ja')),
    ]) {
      final preference = find.byKey(const Key('settings-language'));
      await tester.tap(preference);
      await tester.pumpAndSettle();
      for (final name in ['English', 'Français', '简体中文', '日本語']) {
        expect(
          find.descendant(
            of: find.byKey(const Key('language-options')),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(ValueKey('language-option-$code')));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(Localizations.localeOf(tester.element(preference)), locale);
      expect(await store.read(AppLanguagePreferences.storageKey), code);
    }
    expect(find.text('設定'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-nav-novel')));
    await tester.pumpAndSettle();
    expect(find.text('本棚'), findsOneWidget);
    expect(find.text('作品はまだありません'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await startApp();
    expect(find.text('メッセージはまだありません'), findsOneWidget);
    expect(find.text('チャット'), findsOneWidget);
  });

  test('unknown preferences retain Chinese and templates keep arguments', () {
    expect(AppLanguage.fromCode('stale-value'), AppLanguage.chinese);
    final placeholders = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');
    Set<String> arguments(String value) =>
        placeholders.allMatches(value).map((match) => match[0]!).toSet();
    for (final MapEntry(key: source, value: entry) in appMessages.entries) {
      final expected = arguments(source);
      expect(arguments(entry.en), expected, reason: source);
      expect(arguments(entry.fr), expected, reason: source);
      expect(arguments(entry.ja), expected, reason: source);
    }
  });
}
