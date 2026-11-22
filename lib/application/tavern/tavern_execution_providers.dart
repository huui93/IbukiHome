import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/ai/tavern_provider_adapter.dart';
import '../../data/memory/in_memory_tavern_repository.dart';
import '../../data/repositories/tavern_repository.dart';
import '../ai/ai_settings_controller.dart';
import '../providers/repository_providers.dart';
import '../world_roleplay/world_roleplay_providers.dart';
import '../import/sillytavern_import_providers.dart';
import '../import/sillytavern_character_context.dart';
import 'provider/tavern_model_profile_store.dart';
import 'provider/tavern_provider_driver.dart';
import 'tavern_generation_orchestrator.dart';
import 'tavern_source_resolver.dart';

final tavernRepositoryProvider = Provider<TavernRepository>(
  (ref) => InMemoryTavernRepository(),
);
final tavernModelProfilesProvider = Provider<TavernModelProfileStore>(
  (ref) => TavernModelProfileStore(ref.watch(aiSecureValueStoreProvider)),
);

// Root ProviderScope owns one environment; screen navigation never recreates it.
final tavernExecutionProvider = Provider<TavernGenerationOrchestrator>((ref) {
  final repo = ref.watch(tavernRepositoryProvider);
  late final TavernGenerationOrchestrator owner;
  final driver = TavernProviderDriver(
    TavernProviderAdapter(ref.watch(aiHttpClientFactoryProvider)),
    onStage: (id, streaming) => owner.observeProviderStage(id, streaming),
  );
  owner = TavernGenerationOrchestrator(
    repository: repo,
    configs: ref.watch(aiProviderConfigRepositoryProvider),
    keys: ref.watch(secureApiKeyStoreProvider),
    sources: NativeTavernSourceResolver(
      repository: repo,
      characters: ref.watch(characterRepositoryProvider),
      worlds: ref.watch(worldRoleplayRepositoryProvider),
      compatibility: SillyTavernCharacterContextResolver(
        ref.watch(compatibilityImportRepositoryProvider),
      ),
      worldCards: ref.watch(worldRepositoryProvider),
    ),
    driver: driver,
  );
  ref.onDispose(() {
    unawaited(owner.dispose());
  });
  return owner;
});
