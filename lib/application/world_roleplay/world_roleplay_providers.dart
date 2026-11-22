import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memory/in_memory_world_roleplay_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../providers/repository_providers.dart';
import '../ai/ai_runtime_providers.dart';
import '../plugins/plugin_providers.dart';
import '../import/sillytavern_import_providers.dart';
import 'world_context_builder.dart';
import 'world_director.dart';
import 'world_mutation_service.dart';
import 'world_roleplay_engine.dart';
import 'world_speaker_selector.dart';
import 'world_roleplay_service.dart';

final worldRoleplayRepositoryProvider = Provider<WorldRoleplayRepository>((
  ref,
) {
  return InMemoryWorldRoleplayRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final worldRoleplayServiceProvider = Provider<WorldRoleplayService>((ref) {
  return WorldRoleplayService(
    repository: ref.watch(worldRoleplayRepositoryProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    clock: ref.watch(utcClockProvider),
  );
});

final worldRoleplayContextBuilderProvider =
    Provider<WorldRoleplayContextBuilder>((ref) {
      return WorldRoleplayContextBuilder(
        worlds: ref.watch(worldRoleplayRepositoryProvider),
        characters: ref.watch(characterRepositoryProvider),
        compatibility: ref.watch(compatibilityImportRepositoryProvider),
      );
    });

final worldDirectorProvider = Provider<WorldDirector>((ref) {
  return AiWorldDirector(
    runtime: ref.watch(aiGenerationServiceProvider),
    modelResolver: ref.watch(aiModelResolverProvider),
    promptPipeline: ref.watch(ibukiPromptPipelineProvider),
  );
});

final worldMutationServiceProvider = Provider<WorldMutationService>((ref) {
  return WorldMutationService(
    repository: ref.watch(worldRoleplayRepositoryProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    clock: ref.watch(utcClockProvider),
  );
});

final worldRoleplayEngineProvider = Provider<WorldRoleplayEngine>((ref) {
  return WorldRoleplayEngine(
    repository: ref.watch(worldRoleplayRepositoryProvider),
    contextBuilder: ref.watch(worldRoleplayContextBuilderProvider),
    director: ref.watch(worldDirectorProvider),
    speakerSelector: const WorldSpeakerSelector(),
    mutationService: ref.watch(worldMutationServiceProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    modelResolver: ref.watch(aiModelResolverProvider),
    promptPipeline: ref.watch(ibukiPromptPipelineProvider),
    hooks: ref.watch(ibukiHookBusProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    clock: ref.watch(utcClockProvider),
  );
});

final worldRoleplayRevisionProvider =
    NotifierProvider<WorldRoleplayRevisionController, int>(
      WorldRoleplayRevisionController.new,
    );

class WorldRoleplayRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

void notifyWorldRoleplayChanged(WidgetRef ref) {
  ref.read(worldRoleplayRevisionProvider.notifier).bump();
}

void _watchWorlds(Ref ref) {
  ref.watch(worldRoleplayRevisionProvider);
}

final roleplayWorldListProvider = FutureProvider<List<RoleplayWorld>>((ref) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listWorlds();
});

final roleplayWorldByIdProvider = FutureProvider.family<RoleplayWorld, String>((
  ref,
  id,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).getWorld(id);
});

final worldSessionListProvider =
    FutureProvider.family<List<WorldSession>, String>((ref, worldId) {
      _watchWorlds(ref);
      return ref.watch(worldRoleplayRepositoryProvider).listSessions(worldId);
    });

final worldSessionByIdProvider = FutureProvider.family<WorldSession, String>((
  ref,
  id,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).getSession(id);
});

final worldBookListProvider = FutureProvider.family<List<WorldBook>, String>((
  ref,
  worldId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listWorldBooks(worldId);
});

final worldBookLibraryProvider = FutureProvider<List<WorldBook>>((ref) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listWorldBookLibrary();
});

final worldBookReferenceListProvider =
    FutureProvider.family<List<WorldWorldBookReference>, String>((
      ref,
      worldId,
    ) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listWorldBookReferences(worldId);
    });

final worldBookOverrideListProvider =
    FutureProvider.family<List<WorldSessionWorldBookOverride>, String>((
      ref,
      sessionId,
    ) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listWorldBookOverrides(sessionId);
    });

final loreEntryListProvider = FutureProvider.family<List<LoreEntry>, String>((
  ref,
  worldBookId,
) {
  _watchWorlds(ref);
  return ref
      .watch(worldRoleplayRepositoryProvider)
      .listLoreEntries(worldBookId);
});

final worldPersonaListProvider =
    FutureProvider.family<List<PlayerPersona>, String>((ref, worldId) {
      _watchWorlds(ref);
      return ref.watch(worldRoleplayRepositoryProvider).listPersonas(worldId);
    });

typedef WorldPersonaLibraryItem = ({
  PlayerPersona persona,
  RoleplayWorld world,
});

final worldPersonaLibraryProvider =
    FutureProvider<List<WorldPersonaLibraryItem>>((ref) async {
      _watchWorlds(ref);
      final repository = ref.watch(worldRoleplayRepositoryProvider);
      final worlds = await repository.listWorlds();
      final result = <WorldPersonaLibraryItem>[];
      for (final world in worlds) {
        final personas = await repository.listPersonas(world.id);
        result.addAll(
          personas.map((persona) => (persona: persona, world: world)),
        );
      }
      result.sort((left, right) {
        final name = left.persona.name.compareTo(right.persona.name);
        return name != 0 ? name : left.persona.id.compareTo(right.persona.id);
      });
      return List.unmodifiable(result);
    });

final worldPlayerInstanceListProvider =
    FutureProvider.family<List<WorldPlayerInstance>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listPlayerInstances(sessionId);
    });

final worldCharacterInstanceListProvider =
    FutureProvider.family<List<WorldCharacterInstance>, String>((
      ref,
      sessionId,
    ) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listCharacterInstances(sessionId);
    });

final worldSceneListProvider = FutureProvider.family<List<WorldScene>, String>((
  ref,
  sessionId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listScenes(sessionId);
});

final worldSceneCastProvider = FutureProvider.family<Set<String>, String>((
  ref,
  sceneId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listSceneCast(sceneId);
});

final worldStateListProvider =
    FutureProvider.family<List<WorldStateEntry>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listStateEntries(sessionId);
    });

final worldRelationshipListProvider =
    FutureProvider.family<List<WorldRelationship>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listRelationships(sessionId);
    });

final worldMemoryListProvider =
    FutureProvider.family<List<WorldMemoryEntry>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref.watch(worldRoleplayRepositoryProvider).listMemories(sessionId);
    });

final worldTimelineListProvider =
    FutureProvider.family<List<WorldTimelineEvent>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listTimelineEvents(sessionId);
    });

final worldBranchListProvider =
    FutureProvider.family<List<WorldBranch>, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref.watch(worldRoleplayRepositoryProvider).listBranches(sessionId);
    });

final worldFeedListProvider =
    FutureProvider.family<List<WorldFeedEntry>, String>((ref, sessionId) async {
      _watchWorlds(ref);
      final session = await ref
          .watch(worldRoleplayRepositoryProvider)
          .getSession(sessionId);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .listFeedEntries(sessionId, branchId: session.currentBranchId);
    });

final worldTurnListProvider = FutureProvider.family<List<WorldTurn>, String>((
  ref,
  sessionId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRoleplayRepositoryProvider).listTurns(sessionId);
});

final worldDatabaseCountsProvider =
    FutureProvider.family<WorldDatabaseCounts, String>((ref, sessionId) {
      _watchWorlds(ref);
      return ref
          .watch(worldRoleplayRepositoryProvider)
          .getDatabaseCounts(sessionId);
    });

typedef WorldSessionOverview = ({
  RoleplayWorld world,
  WorldSession session,
  WorldScene? scene,
  PlayerPersona? persona,
  WorldPlayerInstance? playerInstance,
  List<WorldCharacterInstance> characters,
  WorldDatabaseCounts counts,
});

final worldSessionOverviewProvider =
    FutureProvider.family<WorldSessionOverview, String>((ref, sessionId) async {
      _watchWorlds(ref);
      final repository = ref.watch(worldRoleplayRepositoryProvider);
      final session = await repository.getSession(sessionId);
      final world = await repository.getWorld(session.worldId);
      final scene = session.currentSceneId == null
          ? null
          : await repository.getScene(session.currentSceneId!);
      final playerInstance = session.currentPlayerInstanceId == null
          ? null
          : await repository.getPlayerInstance(
              session.currentPlayerInstanceId!,
            );
      final persona = playerInstance == null
          ? null
          : await repository.getPersona(playerInstance.playerPersonaId);
      return (
        world: world,
        session: session,
        scene: scene,
        persona: persona,
        playerInstance: playerInstance,
        characters: await repository.listCharacterInstances(sessionId),
        counts: await repository.getDatabaseCounts(sessionId),
      );
    });
