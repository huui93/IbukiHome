import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world/world_card.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../common/entity_id_generator.dart';
import '../common/utc_clock.dart';

typedef WorldCreationResult = ({
  RoleplayWorld world,
  WorldSession session,
  WorldBook worldBook,
  WorldBranch branch,
});

class WorldRoleplayService {
  const WorldRoleplayService({
    required this.repository,
    required this.ids,
    required this.clock,
  });

  final WorldRoleplayRepository repository;
  final EntityIdGenerator ids;
  final UtcClock clock;

  Future<WorldCreationResult> createWorld({
    required String name,
    String description = '',
    WorldCard? importWorldCard,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '世界名称不能为空');
    }
    final now = clock.now();
    final world = RoleplayWorld(
      entity: _entity(ids.nextId('roleplay_world'), now),
      name: normalizedName,
      description: description.trim(),
    );
    await repository.upsertWorld(world);
    try {
      final book = WorldBook(
        entity: _entity(ids.nextId('world_book'), now),
        worldId: world.id,
        name: '$normalizedName · 世界书',
        isPrimary: true,
      );
      await repository.upsertWorldBook(book);
      final session = WorldSession(
        entity: _entity(ids.nextId('world_session'), now),
        worldId: world.id,
        name: '$normalizedName · 第一条世界线',
      );
      await repository.upsertSession(session);
      final branch = WorldBranch(
        entity: _entity(ids.nextId('world_branch'), now),
        worldSessionId: session.id,
        name: '主世界线',
        isCurrent: true,
      );
      await repository.upsertBranch(branch);
      final readySession = session.copyWith(
        entity: _next(session.entity, now),
        currentBranchId: branch.id,
      );
      await repository.upsertSession(readySession);
      final readyWorld = world.copyWith(
        entity: _next(world.entity, now),
        defaultSessionId: session.id,
      );
      await repository.upsertWorld(readyWorld);
      if (importWorldCard != null) {
        await importWorldCardAsLore(
          worldBookId: book.id,
          source: importWorldCard,
        );
      }
      return (
        world: readyWorld,
        session: readySession,
        worldBook: book,
        branch: branch,
      );
    } catch (_) {
      await repository.deleteWorld(world.id);
      rethrow;
    }
  }

  Future<WorldSession> createWorldSession({
    required String worldId,
    required String name,
  }) async {
    final now = clock.now();
    final session = WorldSession(
      entity: _entity(ids.nextId('world_session'), now),
      worldId: worldId,
      name: name.trim().isEmpty ? '新的世界线存档' : name.trim(),
    );
    await repository.upsertSession(session);
    try {
      final branch = await createWorldBranch(
        worldSessionId: session.id,
        name: '主世界线',
        makeCurrent: true,
      );
      return session.copyWith(currentBranchId: branch.id);
    } catch (_) {
      await repository.deleteSession(session.id);
      rethrow;
    }
  }

  Future<PlayerPersona> createPersona({
    required String worldId,
    required String name,
    String description = '',
    String appearance = '',
    String background = '',
    String notes = '',
    String? avatarReference,
    Map<String, Object?> metadata = const {},
  }) async {
    final now = clock.now();
    final persona = PlayerPersona(
      entity: _entity(ids.nextId('world_persona'), now),
      worldId: worldId,
      name: name.trim().isEmpty ? '我' : name.trim(),
      description: description.trim(),
      appearance: appearance.trim(),
      background: background.trim(),
      notes: notes.trim(),
      avatarReference: avatarReference,
      metadata: Map.unmodifiable(metadata),
    );
    await repository.upsertPersona(persona);
    return persona;
  }

  Future<WorldPlayerInstance> activatePlayerPersona({
    required String worldSessionId,
    required String playerPersonaId,
  }) async {
    final session = await repository.getSession(worldSessionId);
    final persona = await repository.getPersona(playerPersonaId);
    if (persona.worldId != session.worldId) {
      throw ArgumentError('玩家身份定义不属于当前世界');
    }
    final existing = await repository.listPlayerInstances(worldSessionId);
    WorldPlayerInstance? instance;
    for (final item in existing) {
      if (item.playerPersonaId == playerPersonaId) {
        instance = item;
        break;
      }
    }
    final now = clock.now();
    instance = instance == null
        ? WorldPlayerInstance(
            entity: _entity(ids.nextId('world_player'), now),
            worldSessionId: worldSessionId,
            playerPersonaId: playerPersonaId,
            lastActiveAt: now,
          )
        : instance.copyWith(
            entity: _next(instance.entity, now),
            isActive: true,
            lastActiveAt: now,
          );
    await repository.upsertPlayerInstance(instance);
    await repository.upsertSession(
      session.copyWith(
        entity: _next(session.entity, now),
        currentPlayerInstanceId: instance.id,
      ),
    );
    return instance;
  }

  Future<WorldCharacterInstance> addCharacterToWorld({
    required String worldSessionId,
    required String characterCardId,
    String? displayNameOverride,
  }) async {
    final now = clock.now();
    final instance = WorldCharacterInstance(
      entity: _entity(ids.nextId('world_character'), now),
      worldSessionId: worldSessionId,
      characterCardId: characterCardId,
      displayNameOverride: displayNameOverride?.trim().isEmpty == true
          ? null
          : displayNameOverride?.trim(),
      lastActiveAt: now,
    );
    await repository.upsertCharacterInstance(instance);
    return instance;
  }

  Future<WorldScene> createScene({
    required String worldSessionId,
    required String name,
    String description = '',
    String location = '',
    String timeText = '',
    String weather = '',
    String atmosphere = '',
    String currentEvent = '',
  }) async {
    final now = clock.now();
    final scene = WorldScene(
      entity: _entity(ids.nextId('world_scene'), now),
      worldSessionId: worldSessionId,
      name: name.trim().isEmpty ? '初始场景' : name.trim(),
      description: description.trim(),
      location: location.trim(),
      timeText: timeText.trim(),
      weather: weather.trim(),
      atmosphere: atmosphere.trim(),
      currentEvent: currentEvent.trim(),
    );
    await repository.upsertScene(scene);
    return scene;
  }

  Future<void> setCurrentScene({
    required String worldSessionId,
    required String sceneId,
    required Set<String> presentCharacterInstanceIds,
  }) async {
    final session = await repository.getSession(worldSessionId);
    final scene = await repository.getScene(sceneId);
    if (scene.worldSessionId != worldSessionId) {
      throw ArgumentError('场景不属于当前世界存档');
    }
    await repository.setSceneCast(sceneId, presentCharacterInstanceIds);
    final now = clock.now();
    await repository.upsertSession(
      session.copyWith(
        entity: _next(session.entity, now),
        currentSceneId: sceneId,
        worldTime: scene.timeText,
      ),
    );
  }

  Future<WorldStateEntry> saveWorldState({
    required String worldSessionId,
    required String key,
    required Object? value,
    String category = 'general',
    String source = 'manual',
  }) async {
    final now = clock.now();
    final entry = WorldStateEntry(
      entity: _entity(ids.nextId('world_state'), now),
      worldSessionId: worldSessionId,
      key: key.trim(),
      value: value,
      category: category.trim(),
      source: source.trim(),
    );
    await repository.upsertStateEntry(entry);
    return entry;
  }

  Future<WorldMemoryEntry> addWorldMemory({
    required String worldSessionId,
    required String summary,
    String content = '',
    String type = 'manual',
    double importance = 0.5,
    List<String> relatedCharacterIds = const [],
    String? relatedSceneId,
  }) async {
    final now = clock.now();
    final entry = WorldMemoryEntry(
      entity: _entity(ids.nextId('world_memory'), now),
      worldSessionId: worldSessionId,
      type: type,
      summary: summary.trim(),
      content: content.trim(),
      importance: importance.clamp(0, 1),
      relatedCharacterIds: List.unmodifiable(relatedCharacterIds),
      relatedSceneId: relatedSceneId,
    );
    await repository.upsertMemory(entry);
    return entry;
  }

  Future<WorldTimelineEvent> addTimelineEvent({
    required String worldSessionId,
    required String title,
    String description = '',
    String worldTime = '',
    String? sceneId,
    List<String> characterIds = const [],
    String eventType = 'manual',
    double importance = 0.5,
  }) async {
    final now = clock.now();
    final event = WorldTimelineEvent(
      entity: _entity(ids.nextId('world_event'), now),
      worldSessionId: worldSessionId,
      title: title.trim(),
      description: description.trim(),
      worldTime: worldTime.trim(),
      sceneId: sceneId,
      characterIds: List.unmodifiable(characterIds),
      eventType: eventType,
      importance: importance.clamp(0, 1),
    );
    await repository.upsertTimelineEvent(event);
    return event;
  }

  Future<WorldBranch> createWorldBranch({
    required String worldSessionId,
    required String name,
    String? parentBranchId,
    String? branchPointMessageId,
    String? branchPointEventId,
    bool makeCurrent = false,
    bool inheritParentFeed = true,
    Map<String, Object?> metadata = const {},
  }) async {
    final now = clock.now();
    final branch = WorldBranch(
      entity: _entity(ids.nextId('world_branch'), now),
      worldSessionId: worldSessionId,
      name: name.trim().isEmpty ? '新世界线' : name.trim(),
      parentBranchId: parentBranchId,
      branchPointMessageId: branchPointMessageId,
      branchPointEventId: branchPointEventId,
      isCurrent: false,
      metadata: {
        ...metadata,
        if (!inheritParentFeed) 'inheritParentFeed': false,
      },
    );
    await repository.upsertBranch(branch);
    if (makeCurrent) {
      await repository.setCurrentBranch(worldSessionId, branch.id);
      return branch.copyWith(isCurrent: true);
    }
    return branch;
  }

  Future<LoreEntry> importWorldCardAsLore({
    required String worldBookId,
    required WorldCard source,
  }) async {
    final now = clock.now();
    final entry = LoreEntry(
      entity: _entity(ids.nextId('lore_entry'), now),
      worldBookId: worldBookId,
      title: source.title,
      content: source.content,
      activationMode: LoreActivationMode.always,
      sourceWorldCardId: source.id,
      metadata: {'sourceType': 'worldCard'},
    );
    await repository.upsertLoreEntry(entry);
    return entry;
  }

  Future<WorldFeedEntry> addFeedEntry({
    required String worldSessionId,
    required String branchId,
    required WorldFeedEntryType type,
    required String content,
    String? speakerCharacterInstanceId,
  }) async {
    final now = clock.now();
    final entry = WorldFeedEntry(
      entity: _entity(ids.nextId('world_feed'), now),
      worldSessionId: worldSessionId,
      branchId: branchId,
      type: type,
      speakerCharacterInstanceId: speakerCharacterInstanceId,
      content: content.trim(),
    );
    await repository.upsertFeedEntry(entry);
    return entry;
  }
}

EntityMetadata _entity(String id, DateTime now) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

EntityMetadata _next(EntityMetadata value, DateTime now) =>
    value.copyWith(updatedAt: now, revision: value.revision + 1);
