import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_language.dart';
import '../ai/ai_settings_controller.dart';

final appLanguageProvider =
    AsyncNotifierProvider<AppLanguagePreferences, AppLanguage>(
      AppLanguagePreferences.new,
    );

class AppLanguagePreferences extends AsyncNotifier<AppLanguage> {
  static const storageKey = 'appearance.language.v1';

  Future<void> _writes = Future<void>.value();

  @override
  Future<AppLanguage> build() async => AppLanguage.fromCode(
    await ref.watch(aiSecureValueStoreProvider).read(storageKey),
  );

  Future<void> setLanguage(AppLanguage language) {
    final store = ref.read(aiSecureValueStoreProvider);
    final write = _writes.catchError((Object _) {}).then((_) async {
      await store.write(storageKey, language.code);
      if (ref.mounted) state = AsyncData(language);
    });
    _writes = write;
    return write;
  }
}
