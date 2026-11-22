import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/ai/save_ai_model_binding.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

void main() {
  test(
    'WorldSession model bindings are isolated and survive resolver restart',
    () async {
      final store = InMemoryIbukiStore();
      final worlds = InMemoryWorldRoleplayRepository(store);
      final service = WorldRoleplayService(
        repository: worlds,
        ids: EntityIdGenerator(),
        clock: const UtcClock(),
      );
      final created = await service.createWorld(name: 'Model Scope World');
      final sessionB = await service.createWorldSession(
        worldId: created.world.id,
        name: 'Session B',
      );
      final save = SaveWorldSessionAiBinding(worlds);
      final now = DateTime.utc(2026, 8, 29);
      await save(
        sessionId: created.session.id,
        providerConfigId: 'gemini',
        model: 'gemini-world-a',
        nowUtc: now,
      );
      await save(
        sessionId: sessionB.id,
        providerConfigId: 'deepseek',
        model: 'deepseek-world-b',
        nowUtc: now,
      );

      AiModelResolver resolver() => AiModelResolver(
        projects: InMemoryProjectRepository(store),
        chats: InMemoryChatRepository(store),
        worlds: worlds,
        runtime: const _BindingRuntime(),
      );

      final firstResolver = resolver();
      final a = await firstResolver.resolveForWorldSession(created.session.id);
      final b = await firstResolver.resolveForWorldSession(sessionB.id);
      expect(a.providerConfigId, 'gemini');
      expect(a.model, 'gemini-world-a');
      expect(a.source, AiModelSelectionSource.worldSessionOverride);
      expect(b.providerConfigId, 'deepseek');
      expect(b.model, 'deepseek-world-b');
      expect(b.source, AiModelSelectionSource.worldSessionOverride);

      await save(
        sessionId: created.session.id,
        providerConfigId: null,
        model: null,
        nowUtc: now.add(const Duration(minutes: 1)),
      );
      final restartedResolver = resolver();
      final defaultA = await restartedResolver.resolveForWorldSession(
        created.session.id,
      );
      final persistedB = await restartedResolver.resolveForWorldSession(
        sessionB.id,
      );
      expect(defaultA.source, AiModelSelectionSource.globalDefault);
      expect(defaultA.model, 'deepseek-default');
      expect(persistedB.model, 'deepseek-world-b');
    },
  );
}

class _BindingRuntime implements AiDetailedGenerationRuntime {
  const _BindingRuntime();

  @override
  Future<AiResolvedProvider> resolveDefault() async =>
      _resolved('deepseek', 'deepseek-default');

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async => providerConfigId == null || model == null
      ? resolveDefault()
      : _resolved(providerConfigId, model);

  AiResolvedProvider _resolved(String providerId, String model) {
    final now = DateTime.utc(2026, 8, 29);
    return AiResolvedProvider(
      config: AiProviderConfig(
        id: providerId,
        type: providerId == 'gemini'
            ? AiProviderType.gemini
            : AiProviderType.deepseek,
        displayName: providerId,
        baseUrl: 'https://example.invalid',
        apiKeyRef: 'secure.$providerId',
        selectedModel: model,
        enabled: true,
        connectionStatus: AiProviderConnectionStatus.connected,
        availableModels: [model],
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
      selection: AiDefaultSelection(
        providerId: providerId,
        modelId: model,
        updatedAtUtc: now,
      ),
    );
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => const Stream.empty();

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => const Stream.empty();
}
