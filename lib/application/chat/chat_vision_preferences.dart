import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/ai/ai_default_selection.dart';
import '../ai/ai_settings_controller.dart';

final chatVisionPreferencesProvider =
    AsyncNotifierProvider<ChatVisionPreferences, AiDefaultSelection?>(
      ChatVisionPreferences.new,
    );

class ChatVisionPreferences extends AsyncNotifier<AiDefaultSelection?> {
  static const storageKey = 'chat.vision.selection.v1';
  Future<void> _writes = Future.value();
  @override
  Future<AiDefaultSelection?> build() async {
    final raw = await ref.watch(aiSecureValueStoreProvider).read(storageKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final provider = json['provider'] as String;
    final model = json['model'] as String;
    if (provider.trim().isEmpty || model.trim().isEmpty) {
      throw const FormatException('识图模型设置无效，请重新设置。');
    }
    return AiDefaultSelection(
      providerId: provider,
      modelId: model,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<void> setSelection(AiDefaultSelection? selection) {
    final store = ref.read(aiSecureValueStoreProvider);
    final write = _writes.catchError((Object _) {}).then((_) async {
      if (selection == null) {
        await store.delete(storageKey);
      } else {
        await store.write(
          storageKey,
          jsonEncode({
            'provider': selection.providerId,
            'model': selection.modelId,
          }),
        );
      }
      if (ref.mounted) state = AsyncData(selection);
    });
    _writes = write;
    return write;
  }
}
