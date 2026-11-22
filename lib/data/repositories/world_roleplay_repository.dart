import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';

abstract class WorldRoleplayRepository {
  Future<List<RoleplayWorld>> listWorlds();
  Future<RoleplayWorld> getWorld(String id);
  Future<void> upsertWorld(RoleplayWorld world);
  Future<void> deleteWorld(String id);

  Future<List<WorldSession>> listSessions(String worldId);
  Future<WorldSession> getSession(String id);
  Future<void> upsertSession(WorldSession session);
  Future<void> deleteSession(String id);

  Future<List<WorldBook>> listWorldBooks(String worldId);
  Future<List<WorldBook>> listWorldBookLibrary({String query = ''});
  Future<WorldBook> getWorldBook(String id);
  Future<void> upsertWorldBook(WorldBook book);
  Future<void> deleteWorldBook(String id);

  Future<List<WorldWorldBookReference>> listWorldBookReferences(String worldId);
  Future<void> upsertWorldBookReference(WorldWorldBookReference reference);
  Future<void> deleteWorldBookReference(String id);
  Future<List<WorldSessionWorldBookOverride>> listWorldBookOverrides(
    String worldSessionId,
  );
  Future<void> upsertWorldBookOverride(WorldSessionWorldBookOverride override);
  Future<void> deleteWorldBookOverride(String id);
  Future<List<EntityWorldBookReference>> listCharacterWorldBookReferences(
    String characterCardId,
  );
  Future<void> upsertCharacterWorldBookReference(
    EntityWorldBookReference reference,
  );
  Future<void> deleteCharacterWorldBookReference(String id);
  Future<List<EntityWorldBookReference>> listPersonaWorldBookReferences(
    String playerPersonaId,
  );
  Future<void> upsertPersonaWorldBookReference(
    EntityWorldBookReference reference,
  );
  Future<void> deletePersonaWorldBookReference(String id);
  Future<int> countWorldBookReferences(String worldBookId);

  Future<List<LoreEntry>> listLoreEntries(
    String worldBookId, {
    String query = '',
  });
  Future<LoreEntry> getLoreEntry(String id);
  Future<void> upsertLoreEntry(LoreEntry entry);
  Future<void> deleteLoreEntry(String id);

  Future<List<PlayerPersona>> listPersonas(String worldId);
  Future<PlayerPersona> getPersona(String id);
  Future<void> upsertPersona(PlayerPersona persona);
  Future<void> deletePersona(String id);

  Future<List<WorldPlayerInstance>> listPlayerInstances(String worldSessionId);
  Future<WorldPlayerInstance> getPlayerInstance(String id);
  Future<void> upsertPlayerInstance(WorldPlayerInstance instance);
  Future<void> deletePlayerInstance(String id);

  Future<List<WorldCharacterInstance>> listCharacterInstances(
    String worldSessionId,
  );
  Future<WorldCharacterInstance> getCharacterInstance(String id);
  Future<void> upsertCharacterInstance(WorldCharacterInstance instance);
  Future<void> deleteCharacterInstance(String id);

  Future<List<WorldScene>> listScenes(String worldSessionId);
  Future<WorldScene> getScene(String id);
  Future<void> upsertScene(WorldScene scene);
  Future<void> deleteScene(String id);
  Future<Set<String>> listSceneCast(String sceneId);
  Future<void> setSceneCast(String sceneId, Set<String> characterInstanceIds);

  Future<List<WorldStateEntry>> listStateEntries(String worldSessionId);
  Future<WorldStateEntry> getStateEntry(String id);
  Future<void> upsertStateEntry(WorldStateEntry entry);
  Future<void> deleteStateEntry(String id);

  Future<List<WorldRelationship>> listRelationships(String worldSessionId);
  Future<WorldRelationship> getRelationship(String id);
  Future<void> upsertRelationship(WorldRelationship relationship);
  Future<void> deleteRelationship(String id);

  Future<List<WorldMemoryEntry>> listMemories(
    String worldSessionId, {
    String query = '',
  });
  Future<WorldMemoryEntry> getMemory(String id);
  Future<void> upsertMemory(WorldMemoryEntry memory);
  Future<void> deleteMemory(String id);

  Future<List<WorldTimelineEvent>> listTimelineEvents(
    String worldSessionId, {
    String query = '',
  });
  Future<WorldTimelineEvent> getTimelineEvent(String id);
  Future<void> upsertTimelineEvent(WorldTimelineEvent event);
  Future<void> deleteTimelineEvent(String id);

  Future<List<WorldBranch>> listBranches(String worldSessionId);
  Future<WorldBranch> getBranch(String id);
  Future<void> upsertBranch(WorldBranch branch);
  Future<void> setCurrentBranch(String worldSessionId, String branchId);
  Future<void> deleteBranch(String id);

  Future<List<WorldFeedEntry>> listFeedEntries(
    String worldSessionId, {
    String? branchId,
    int? limit,
  });
  Future<void> upsertFeedEntry(WorldFeedEntry entry);
  Future<void> deleteFeedEntry(String id);

  Future<List<WorldTurn>> listTurns(String worldSessionId, {int? limit});
  Future<WorldTurn> getTurn(String id);
  Future<void> upsertTurn(WorldTurn turn);
  Future<void> commitWorldMutation(WorldMutationCommit commit);

  Future<WorldDatabaseCounts> getDatabaseCounts(String worldSessionId);
  Future<List<WorldSearchResult>> searchWorldDatabase(
    String worldSessionId,
    String query,
  );
}
