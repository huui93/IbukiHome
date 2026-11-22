import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_settings_controller.dart';

final aiOutputPreferencesProvider =
    AsyncNotifierProvider<AiOutputPreferences, bool>(AiOutputPreferences.new);

/// A display preference shared by novel and chat, independent of their data.
class AiOutputPreferences extends AsyncNotifier<bool> {
  static const storageKey = 'ai.output.streaming.v1';
  Future<void> _writes = Future.value();

  @override
  Future<bool> build() async =>
      await ref.watch(aiSecureValueStoreProvider).read(storageKey) != 'false';

  Future<void> setStreaming(bool enabled) {
    final store = ref.read(aiSecureValueStoreProvider);
    final write = _writes.catchError((Object _) {}).then((_) async {
      final previous = state.value ?? true;
      try {
        await store.write(storageKey, enabled.toString());
        if (ref.mounted) state = AsyncData(enabled);
      } catch (_) {
        if (ref.mounted) state = AsyncData(previous);
        rethrow;
      }
    });
    _writes = write;
    return write;
  }
}
