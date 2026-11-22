import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_generation_service.dart';
import 'ai_request_coordinator.dart';
import 'ai_settings_controller.dart';
import 'ai_output_preferences.dart';

final aiGenerationServiceProvider = Provider<AiGenerationRuntime>((ref) {
  final service = AiGenerationService(
    configRepository: ref.watch(aiProviderConfigRepositoryProvider),
    apiKeyStore: ref.watch(secureApiKeyStoreProvider),
    registry: ref.watch(aiProviderRegistryProvider),
    streamOutputEnabled: () async {
      try {
        return await ref.read(aiOutputPreferencesProvider.future);
      } catch (_) {
        return ref.read(aiOutputPreferencesProvider).value ?? true;
      }
    },
  );
  ref.onDispose(service.close);
  return service;
});

final aiRequestCoordinatorProvider = Provider<AiRequestCoordinator>((ref) {
  return AiRequestCoordinator();
});

final defaultAiLabelProvider = FutureProvider<String?>((ref) async {
  ref.watch(aiSettingsControllerProvider);
  try {
    return (await ref.watch(aiGenerationServiceProvider).resolveDefault())
        .displayLabel;
  } catch (_) {
    return null;
  }
});
