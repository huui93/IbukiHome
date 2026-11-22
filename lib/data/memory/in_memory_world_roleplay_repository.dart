import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryWorldRoleplayRepository implements WorldRoleplayRepository {
  InMemoryWorldRoleplayRepository(this.coreStore);

  final InMemoryIbukiStore coreStore;

  final Map<String, RoleplayWorld> _worlds = {};
  final Map<String, WorldSession> _sessions = {};
  final Map<String, WorldBook> _books = {};
  final Map<String, WorldWorldBookReference> _worldBookReferences = {};
  final Map<String, WorldSessionWorldBookOverride> _worldBookOverrides = {};
  final Map<String, EntityWorldBookReference> _characterBookReferences = {};
  final Map<String, EntityWorldBookReference> _personaBookReferences = {};
  final Map<String, LoreEntry> _lore = {};
  final Map<String, PlayerPersona> _personas = {};
  final Map<String, WorldPlayerInstance> _playerInstances = {};
  final Map<String, WorldCharacterInstance> _characters = {};
  final Map<String, WorldScene> _scenes = {};
  final Map<String, Set<String>> _sceneCast = {};
  final Map<String, WorldStateEntry> _state = {};
  final Map<String, WorldRelationship> _relationships = {};
  final Map<String, WorldMemoryEntry> _memories = {};
  final Map<String, WorldTimelineEvent> _timeline = {};
  final Map<String, WorldBranch> _branches = {};
  final Map<String, WorldFeedEntry> _feed = {};
  final Map<String, WorldTurn> _turns = {};

  @override
  Future<List<RoleplayWorld>> listWorlds() async {
    final items = _worlds.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(items);
  }

  @override
  Future<RoleplayWorld> getWorld(String id) async =>
      _required(_worlds, id, 'World');

  @override
  Future<void> upsertWorld(RoleplayWorld world) async {
    _worlds[world.id] = world;
  }

  @override
  Future<void> deleteWorld(String id) async {
    _required(_worlds, id, 'World');
    final sessionIds = _sessions.values
        .where((item) => item.worldId == id)
        .map((item) => item.id)
        .toList();
    for (final sessionId in sessionIds) {
      await deleteSession(sessionId);
    }
    for (final entry in _books.entries.toList()) {
      if (entry.value.worldId == id) {
        _books[entry.key] = entry.value.copyWith(
          worldId: null,
          isPrimary: false,
        );
      }
    }
    _worldBookReferences.removeWhere((_, value) => value.worldId == id);
    _personas.removeWhere((_, value) => value.worldId == id);
    _worlds.remove(id);
  }

  @override
  Future<List<WorldSession>> listSessions(String worldId) async =>
      _sortedUpdated(_sessions.values.where((item) => item.worldId == worldId));

  @override
  Future<WorldSession> getSession(String id) async =>
      _required(_sessions, id, 'WorldSession');

  @override
  Future<void> upsertSession(WorldSession session) async {
    _required(_worlds, session.worldId, 'World');
    final playerInstanceId = session.currentPlayerInstanceId;
    if (playerInstanceId != null) {
      final instance = _required(
        _playerInstances,
        playerInstanceId,
        'WorldPlayerInstance',
      );
      if (instance.worldSessionId != session.id) {
        throw const DataConflictException('当前玩家实例必须属于同一个世界存档。');
      }
    }
    _sessions[session.id] = session;
  }

  @override
  Future<void> deleteSession(String id) async {
    _required(_sessions, id, 'WorldSession');
    final sceneIds = _scenes.values
        .where((item) => item.worldSessionId == id)
        .map((item) => item.id)
        .toSet();
    final characterIds = _characters.values
        .where((item) => item.worldSessionId == id)
        .map((item) => item.id)
        .toSet();
    _sceneCast.removeWhere((sceneId, _) => sceneIds.contains(sceneId));
    _playerInstances.removeWhere((_, value) => value.worldSessionId == id);
    _characters.removeWhere((_, value) => value.worldSessionId == id);
    _scenes.removeWhere((_, value) => value.worldSessionId == id);
    _state.removeWhere((_, value) => value.worldSessionId == id);
    _relationships.removeWhere((_, value) => value.worldSessionId == id);
    _memories.removeWhere((_, value) => value.worldSessionId == id);
    _timeline.removeWhere((_, value) => value.worldSessionId == id);
    _branches.removeWhere((_, value) => value.worldSessionId == id);
    _feed.removeWhere(
      (_, value) =>
          value.worldSessionId == id ||
          (value.speakerCharacterInstanceId != null &&
              characterIds.contains(value.speakerCharacterInstanceId)),
    );
    _turns.removeWhere((_, value) => value.worldSessionId == id);
    _worldBookOverrides.removeWhere((_, value) => value.worldSessionId == id);
    _sessions.remove(id);
    for (final entry in _worlds.entries.toList()) {
      if (entry.value.defaultSessionId == id) {
        _worlds[entry.key] = entry.value.copyWith(defaultSessionId: null);
      }
    }
  }

  @override
  Future<List<WorldBook>> listWorldBooks(String worldId) async {
    final items =
        _books.values.where((item) => item.worldId == worldId).toList()
          ..sort((a, b) {
            if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
            return a.name.compareTo(b.name);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<List<WorldBook>> listWorldBookLibrary({String query = ''}) async {
    final needle = query.trim().toLowerCase();
    final matchingIds = _lore.values
        .where(
          (entry) =>
              entry.title.toLowerCase().contains(needle) ||
              entry.content.toLowerCase().contains(needle) ||
              entry.keywords.any((key) => key.toLowerCase().contains(needle)),
        )
        .map((entry) => entry.worldBookId)
        .toSet();
    final items =
        _books.values
            .where(
              (book) =>
                  needle.isEmpty ||
                  book.name.toLowerCase().contains(needle) ||
                  matchingIds.contains(book.id),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(items);
  }

  @override
  Future<WorldBook> getWorldBook(String id) async =>
      _required(_books, id, 'WorldBook');

  @override
  Future<void> upsertWorldBook(WorldBook book) async {
    if (book.worldId != null) _required(_worlds, book.worldId!, 'World');
    if (book.isPrimary &&
        _books.values.any(
          (item) =>
              item.worldId == book.worldId &&
              item.isPrimary &&
              item.id != book.id,
        )) {
      throw const DataConflictException('一个世界只能有一本主世界书。');
    }
    _books[book.id] = book;
  }

  @override
  Future<void> deleteWorldBook(String id) async {
    _required(_books, id, 'WorldBook');
    if (await countWorldBookReferences(id) > 0) {
      throw const DataConflictException('这本世界书仍被引用，请先解除引用。');
    }
    _lore.removeWhere((_, value) => value.worldBookId == id);
    _books.remove(id);
  }

  @override
  Future<List<WorldWorldBookReference>> listWorldBookReferences(
    String worldId,
  ) async => _sortedUpdated(
    _worldBookReferences.values.where((item) => item.worldId == worldId),
  );

  @override
  Future<void> upsertWorldBookReference(
    WorldWorldBookReference reference,
  ) async {
    _required(_worlds, reference.worldId, 'World');
    _required(_books, reference.worldBookId, 'WorldBook');
    _worldBookReferences[reference.id] = reference;
  }

  @override
  Future<void> deleteWorldBookReference(String id) async {
    _required(_worldBookReferences, id, 'WorldBookReference');
    _worldBookReferences.remove(id);
  }

  @override
  Future<List<WorldSessionWorldBookOverride>> listWorldBookOverrides(
    String worldSessionId,
  ) async => _sortedUpdated(
    _worldBookOverrides.values.where(
      (item) => item.worldSessionId == worldSessionId,
    ),
  );

  @override
  Future<void> upsertWorldBookOverride(
    WorldSessionWorldBookOverride override,
  ) async {
    _required(_sessions, override.worldSessionId, 'WorldSession');
    _required(_books, override.worldBookId, 'WorldBook');
    _worldBookOverrides[override.id] = override;
  }

  @override
  Future<void> deleteWorldBookOverride(String id) async {
    _required(_worldBookOverrides, id, 'WorldBookOverride');
    _worldBookOverrides.remove(id);
  }

  @override
  Future<List<EntityWorldBookReference>> listCharacterWorldBookReferences(
    String characterCardId,
  ) async => _sortedUpdated(
    _characterBookReferences.values.where(
      (item) => item.entityId == characterCardId,
    ),
  );

  @override
  Future<void> upsertCharacterWorldBookReference(
    EntityWorldBookReference reference,
  ) async {
    _required(_books, reference.worldBookId, 'WorldBook');
    _characterBookReferences[reference.id] = reference;
  }

  @override
  Future<void> deleteCharacterWorldBookReference(String id) async {
    _required(_characterBookReferences, id, 'CharacterWorldBookReference');
    _characterBookReferences.remove(id);
  }

  @override
  Future<List<EntityWorldBookReference>> listPersonaWorldBookReferences(
    String playerPersonaId,
  ) async => _sortedUpdated(
    _personaBookReferences.values.where(
      (item) => item.entityId == playerPersonaId,
    ),
  );

  @override
  Future<void> upsertPersonaWorldBookReference(
    EntityWorldBookReference reference,
  ) async {
    _required(_books, reference.worldBookId, 'WorldBook');
    _personaBookReferences[reference.id] = reference;
  }

  @override
  Future<void> deletePersonaWorldBookReference(String id) async {
    _required(_personaBookReferences, id, 'PersonaWorldBookReference');
    _personaBookReferences.remove(id);
  }

  @override
  Future<int> countWorldBookReferences(String worldBookId) async =>
      _worldBookReferences.values
          .where((item) => item.worldBookId == worldBookId)
          .length +
      _worldBookOverrides.values
          .where((item) => item.worldBookId == worldBookId)
          .length +
      _characterBookReferences.values
          .where((item) => item.worldBookId == worldBookId)
          .length +
      _personaBookReferences.values
          .where((item) => item.worldBookId == worldBookId)
          .length;

  @override
  Future<List<LoreEntry>> listLoreEntries(
    String worldBookId, {
    String query = '',
  }) async {
    final needle = query.trim().toLowerCase();
    final items =
        _lore.values.where((item) {
          if (item.worldBookId != worldBookId) return false;
          return needle.isEmpty ||
              item.title.toLowerCase().contains(needle) ||
              item.content.toLowerCase().contains(needle);
        }).toList()..sort((a, b) {
          if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
          final priority = b.priority.compareTo(a.priority);
          return priority != 0 ? priority : a.title.compareTo(b.title);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<LoreEntry> getLoreEntry(String id) async =>
      _required(_lore, id, 'LoreEntry');

  @override
  Future<void> upsertLoreEntry(LoreEntry entry) async {
    _required(_books, entry.worldBookId, 'WorldBook');
    _lore[entry.id] = entry;
  }

  @override
  Future<void> deleteLoreEntry(String id) async {
    _required(_lore, id, 'LoreEntry');
    _lore.remove(id);
  }

  @override
  Future<List<PlayerPersona>> listPersonas(String worldId) async {
    final items =
        _personas.values.where((item) => item.worldId == worldId).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(items);
  }

  @override
  Future<PlayerPersona> getPersona(String id) async =>
      _required(_personas, id, 'PlayerPersona');

  @override
  Future<void> upsertPersona(PlayerPersona persona) async {
    _required(_worlds, persona.worldId, 'World');
    _personas[persona.id] = persona;
  }

  @override
  Future<void> deletePersona(String id) async {
    _required(_personas, id, 'PlayerPersona');
    if (_playerInstances.values.any((item) => item.playerPersonaId == id)) {
      throw const DataConflictException('正在世界存档中使用的身份定义不能删除。');
    }
    _personaBookReferences.removeWhere((_, value) => value.entityId == id);
    _personas.remove(id);
  }

  @override
  Future<List<WorldPlayerInstance>> listPlayerInstances(
    String worldSessionId,
  ) async {
    final items =
        _playerInstances.values
            .where((item) => item.worldSessionId == worldSessionId)
            .toList()
          ..sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldPlayerInstance> getPlayerInstance(String id) async =>
      _required(_playerInstances, id, 'WorldPlayerInstance');

  @override
  Future<void> upsertPlayerInstance(WorldPlayerInstance instance) async {
    final session = _required(
      _sessions,
      instance.worldSessionId,
      'WorldSession',
    );
    final persona = _required(
      _personas,
      instance.playerPersonaId,
      'PlayerPersona',
    );
    if (session.worldId != persona.worldId) {
      throw const DataConflictException('玩家身份定义与实例必须属于同一个世界。');
    }
    final duplicate = _playerInstances.values.any(
      (item) =>
          item.worldSessionId == instance.worldSessionId &&
          item.playerPersonaId == instance.playerPersonaId &&
          item.id != instance.id,
    );
    if (duplicate) {
      throw const DataConflictException('同一个身份在一个世界存档中只能实例化一次。');
    }
    _playerInstances[instance.id] = instance;
  }

  @override
  Future<void> deletePlayerInstance(String id) async {
    _required(_playerInstances, id, 'WorldPlayerInstance');
    _playerInstances.remove(id);
    for (final entry in _sessions.entries.toList()) {
      if (entry.value.currentPlayerInstanceId == id) {
        _sessions[entry.key] = entry.value.copyWith(
          currentPlayerInstanceId: null,
        );
      }
    }
  }

  @override
  Future<List<WorldCharacterInstance>> listCharacterInstances(
    String worldSessionId,
  ) async {
    final items =
        _characters.values
            .where((item) => item.worldSessionId == worldSessionId)
            .toList()
          ..sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            if (a.isPresent != b.isPresent) return a.isPresent ? -1 : 1;
            return a.id.compareTo(b.id);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldCharacterInstance> getCharacterInstance(String id) async =>
      _required(_characters, id, 'WorldCharacterInstance');

  @override
  Future<void> upsertCharacterInstance(WorldCharacterInstance instance) async {
    _required(_sessions, instance.worldSessionId, 'WorldSession');
    if (coreStore.character(instance.characterCardId) == null) {
      throw EntityNotFoundException('CharacterCard', instance.characterCardId);
    }
    final duplicate = _characters.values.any(
      (item) =>
          item.worldSessionId == instance.worldSessionId &&
          item.characterCardId == instance.characterCardId &&
          item.id != instance.id,
    );
    if (duplicate) {
      throw const DataConflictException('同一个角色卡在一个世界存档中只能添加一次。');
    }
    _characters[instance.id] = instance;
  }

  @override
  Future<void> deleteCharacterInstance(String id) async {
    _required(_characters, id, 'WorldCharacterInstance');
    for (final cast in _sceneCast.values) {
      cast.remove(id);
    }
    _characters.remove(id);
  }

  @override
  Future<List<WorldScene>> listScenes(String worldSessionId) async =>
      _sortedUpdated(
        _scenes.values.where((item) => item.worldSessionId == worldSessionId),
      );

  @override
  Future<WorldScene> getScene(String id) async =>
      _required(_scenes, id, 'WorldScene');

  @override
  Future<void> upsertScene(WorldScene scene) async {
    _required(_sessions, scene.worldSessionId, 'WorldSession');
    _scenes[scene.id] = scene;
  }

  @override
  Future<void> deleteScene(String id) async {
    _required(_scenes, id, 'WorldScene');
    _sceneCast.remove(id);
    _scenes.remove(id);
    for (final entry in _sessions.entries.toList()) {
      if (entry.value.currentSceneId == id) {
        _sessions[entry.key] = entry.value.copyWith(currentSceneId: null);
      }
    }
  }

  @override
  Future<Set<String>> listSceneCast(String sceneId) async {
    _required(_scenes, sceneId, 'WorldScene');
    return Set.unmodifiable(_sceneCast[sceneId] ?? const {});
  }

  @override
  Future<void> setSceneCast(
    String sceneId,
    Set<String> characterInstanceIds,
  ) async {
    final scene = _required(_scenes, sceneId, 'WorldScene');
    for (final id in characterInstanceIds) {
      final character = _required(_characters, id, 'WorldCharacterInstance');
      if (character.worldSessionId != scene.worldSessionId) {
        throw const DataConflictException('场景角色必须属于同一个世界存档。');
      }
    }
    _sceneCast[sceneId] = Set.of(characterInstanceIds);
    final now = DateTime.now().toUtc();
    for (final entry in _characters.entries.toList()) {
      if (entry.value.worldSessionId != scene.worldSessionId) continue;
      final present = characterInstanceIds.contains(entry.key);
      if (entry.value.isPresent != present) {
        _characters[entry.key] = entry.value.copyWith(
          entity: entry.value.entity.copyWith(
            updatedAt: now,
            revision: entry.value.revision + 1,
          ),
          isPresent: present,
        );
      }
    }
  }

  @override
  Future<List<WorldStateEntry>> listStateEntries(String worldSessionId) async {
    final items =
        _state.values
            .where((item) => item.worldSessionId == worldSessionId)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return List.unmodifiable(items);
  }

  @override
  Future<WorldStateEntry> getStateEntry(String id) async =>
      _required(_state, id, 'WorldStateEntry');

  @override
  Future<void> upsertStateEntry(WorldStateEntry entry) async {
    _required(_sessions, entry.worldSessionId, 'WorldSession');
    if (_state.values.any(
      (item) =>
          item.worldSessionId == entry.worldSessionId &&
          item.key == entry.key &&
          item.id != entry.id,
    )) {
      throw const DataConflictException('世界状态 key 必须唯一。');
    }
    _state[entry.id] = entry;
  }

  @override
  Future<void> deleteStateEntry(String id) async {
    _required(_state, id, 'WorldStateEntry');
    _state.remove(id);
  }

  @override
  Future<List<WorldRelationship>> listRelationships(
    String worldSessionId,
  ) async => _sortedUpdated(
    _relationships.values.where(
      (item) => item.worldSessionId == worldSessionId,
    ),
  );

  @override
  Future<WorldRelationship> getRelationship(String id) async =>
      _required(_relationships, id, 'WorldRelationship');

  @override
  Future<void> upsertRelationship(WorldRelationship relationship) async {
    _required(_sessions, relationship.worldSessionId, 'WorldSession');
    _relationships[relationship.id] = relationship;
  }

  @override
  Future<void> deleteRelationship(String id) async {
    _required(_relationships, id, 'WorldRelationship');
    _relationships.remove(id);
  }

  @override
  Future<List<WorldMemoryEntry>> listMemories(
    String worldSessionId, {
    String query = '',
  }) async {
    final needle = query.trim().toLowerCase();
    final items =
        _memories.values.where((item) {
          if (item.worldSessionId != worldSessionId) return false;
          return needle.isEmpty ||
              item.summary.toLowerCase().contains(needle) ||
              item.content.toLowerCase().contains(needle);
        }).toList()..sort((a, b) {
          if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
          return b.importance.compareTo(a.importance);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldMemoryEntry> getMemory(String id) async =>
      _required(_memories, id, 'WorldMemoryEntry');

  @override
  Future<void> upsertMemory(WorldMemoryEntry memory) async {
    _required(_sessions, memory.worldSessionId, 'WorldSession');
    _memories[memory.id] = memory;
  }

  @override
  Future<void> deleteMemory(String id) async {
    _required(_memories, id, 'WorldMemoryEntry');
    _memories.remove(id);
  }

  @override
  Future<List<WorldTimelineEvent>> listTimelineEvents(
    String worldSessionId, {
    String query = '',
  }) async {
    final needle = query.trim().toLowerCase();
    final items =
        _timeline.values.where((item) {
          if (item.worldSessionId != worldSessionId) return false;
          return needle.isEmpty ||
              item.title.toLowerCase().contains(needle) ||
              item.description.toLowerCase().contains(needle);
        }).toList()..sort((a, b) {
          final worldTime = a.worldTime.compareTo(b.worldTime);
          return worldTime != 0
              ? worldTime
              : a.createdAt.compareTo(b.createdAt);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldTimelineEvent> getTimelineEvent(String id) async =>
      _required(_timeline, id, 'WorldTimelineEvent');

  @override
  Future<void> upsertTimelineEvent(WorldTimelineEvent event) async {
    _required(_sessions, event.worldSessionId, 'WorldSession');
    _timeline[event.id] = event;
  }

  @override
  Future<void> deleteTimelineEvent(String id) async {
    _required(_timeline, id, 'WorldTimelineEvent');
    _timeline.remove(id);
  }

  @override
  Future<List<WorldBranch>> listBranches(String worldSessionId) async {
    final items =
        _branches.values
            .where((item) => item.worldSessionId == worldSessionId)
            .toList()
          ..sort((a, b) {
            if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
            return a.createdAt.compareTo(b.createdAt);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldBranch> getBranch(String id) async =>
      _required(_branches, id, 'WorldBranch');

  @override
  Future<void> upsertBranch(WorldBranch branch) async {
    _required(_sessions, branch.worldSessionId, 'WorldSession');
    if (branch.isCurrent &&
        _branches.values.any(
          (item) =>
              item.worldSessionId == branch.worldSessionId &&
              item.isCurrent &&
              item.id != branch.id,
        )) {
      throw const DataConflictException('一个世界存档只能有一条当前世界线。');
    }
    _branches[branch.id] = branch;
  }

  @override
  Future<void> setCurrentBranch(String worldSessionId, String branchId) async {
    final branch = _required(_branches, branchId, 'WorldBranch');
    if (branch.worldSessionId != worldSessionId) {
      throw const DataConflictException('世界线不属于当前世界存档。');
    }
    final now = DateTime.now().toUtc();
    for (final entry in _branches.entries.toList()) {
      if (entry.value.worldSessionId != worldSessionId) continue;
      _branches[entry.key] = entry.value.copyWith(
        entity: entry.value.entity.copyWith(
          updatedAt: now,
          revision: entry.value.revision + 1,
        ),
        isCurrent: entry.key == branchId,
      );
    }
    final session = _required(_sessions, worldSessionId, 'WorldSession');
    _sessions[worldSessionId] = session.copyWith(
      entity: session.entity.copyWith(
        updatedAt: now,
        revision: session.revision + 1,
      ),
      currentBranchId: branchId,
    );
  }

  @override
  Future<void> deleteBranch(String id) async {
    final branch = _required(_branches, id, 'WorldBranch');
    if (_feed.values.any((item) => item.branchId == id)) {
      throw const DataConflictException('已有世界记录的世界线不能直接删除。');
    }
    _branches.remove(id);
    final session = _sessions[branch.worldSessionId];
    if (session?.currentBranchId == id) {
      _sessions[session!.id] = session.copyWith(currentBranchId: null);
    }
  }

  @override
  Future<List<WorldFeedEntry>> listFeedEntries(
    String worldSessionId, {
    String? branchId,
    int? limit,
  }) async {
    final items = branchId == null
        ? (_feed.values
              .where((item) => item.worldSessionId == worldSessionId)
              .toList()
            ..sort(_compareFeed))
        : _branchFeed(worldSessionId, branchId, <String>{});
    final selected = limit == null || items.length <= limit
        ? items
        : items.sublist(items.length - limit);
    return List.unmodifiable(selected);
  }

  @override
  Future<void> upsertFeedEntry(WorldFeedEntry entry) async {
    _required(_sessions, entry.worldSessionId, 'WorldSession');
    final branch = _required(_branches, entry.branchId, 'WorldBranch');
    if (branch.worldSessionId != entry.worldSessionId) {
      throw const DataConflictException('Feed 与世界线必须属于同一个世界存档。');
    }
    _feed[entry.id] = entry;
  }

  @override
  Future<void> deleteFeedEntry(String id) async {
    _required(_feed, id, 'WorldFeedEntry');
    _feed.remove(id);
  }

  @override
  Future<List<WorldTurn>> listTurns(String worldSessionId, {int? limit}) async {
    final items =
        _turns.values
            .where((item) => item.worldSessionId == worldSessionId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(
      limit == null || items.length <= limit ? items : items.take(limit),
    );
  }

  @override
  Future<WorldTurn> getTurn(String id) async =>
      _required(_turns, id, 'WorldTurn');

  @override
  Future<void> upsertTurn(WorldTurn turn) async {
    final branch = _required(_branches, turn.branchId, 'WorldBranch');
    final feed = _required(_feed, turn.userFeedEntryId, 'WorldFeedEntry');
    if (branch.worldSessionId != turn.worldSessionId ||
        feed.worldSessionId != turn.worldSessionId) {
      throw const DataConflictException('世界回合必须属于同一个世界存档。');
    }
    _turns[turn.id] = turn;
  }

  @override
  Future<void> commitWorldMutation(WorldMutationCommit commit) async {
    _required(_sessions, commit.worldSessionId, 'WorldSession');
    if (commit.turn.worldSessionId != commit.worldSessionId) {
      throw const DataConflictException('世界回合变更范围无效。');
    }
    final session = commit.session;
    if (session != null && session.id != commit.worldSessionId) {
      throw const DataConflictException('世界存档变更范围无效。');
    }
    final scene = commit.scene;
    if (scene != null && scene.worldSessionId != commit.worldSessionId) {
      throw const DataConflictException('场景变更范围无效。');
    }
    for (final character in commit.characterInstances) {
      if (character.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('角色实例变更范围无效。');
      }
    }
    final player = commit.playerInstance;
    if (player != null && player.worldSessionId != commit.worldSessionId) {
      throw const DataConflictException('玩家实例变更范围无效。');
    }
    for (final state in commit.stateUpserts) {
      if (state.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('世界状态变更范围无效。');
      }
    }
    for (final id in commit.stateDeleteIds) {
      final state = _required(_state, id, 'WorldStateEntry');
      if (state.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('世界状态变更范围无效。');
      }
    }
    for (final relationship in commit.relationshipUpserts) {
      if (relationship.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('人物关系变更范围无效。');
      }
    }
    for (final memory in commit.memories) {
      if (memory.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('世界记忆变更范围无效。');
      }
    }
    for (final event in commit.timelineEvents) {
      if (event.worldSessionId != commit.worldSessionId) {
        throw const DataConflictException('时间线变更范围无效。');
      }
    }
    if (commit.sceneCast != null) {
      if (scene == null) {
        throw const DataConflictException('Scene Cast 变更缺少场景。');
      }
      for (final id in commit.sceneCast!) {
        final character = _required(_characters, id, 'WorldCharacterInstance');
        if (character.worldSessionId != commit.worldSessionId) {
          throw const DataConflictException('Scene Cast 变更范围无效。');
        }
      }
    }

    if (session != null) _sessions[session.id] = session;
    if (scene != null) _scenes[scene.id] = scene;
    for (final character in commit.characterInstances) {
      _characters[character.id] = character;
    }
    if (player != null) _playerInstances[player.id] = player;
    for (final state in commit.stateUpserts) {
      _state[state.id] = state;
    }
    for (final id in commit.stateDeleteIds) {
      _state.remove(id);
    }
    for (final relationship in commit.relationshipUpserts) {
      _relationships[relationship.id] = relationship;
    }
    for (final memory in commit.memories) {
      _memories[memory.id] = memory;
    }
    for (final event in commit.timelineEvents) {
      _timeline[event.id] = event;
    }
    if (scene != null && commit.sceneCast != null) {
      _sceneCast[scene.id] = Set.unmodifiable(commit.sceneCast!);
    }
    _turns[commit.turn.id] = commit.turn;
  }

  List<WorldFeedEntry> _branchFeed(
    String worldSessionId,
    String branchId,
    Set<String> visited,
  ) {
    if (!visited.add(branchId)) {
      throw const DataConflictException('世界线父级关系存在循环。');
    }
    final branch = _required(_branches, branchId, 'WorldBranch');
    if (branch.worldSessionId != worldSessionId) {
      throw const DataConflictException('世界线不属于当前世界存档。');
    }
    var inherited = <WorldFeedEntry>[];
    if (branch.parentBranchId != null &&
        branch.metadata['inheritParentFeed'] != false) {
      inherited = _branchFeed(worldSessionId, branch.parentBranchId!, visited);
      final pointId = branch.branchPointMessageId;
      if (pointId != null) {
        final point = inherited.indexWhere((entry) => entry.id == pointId);
        if (point >= 0) inherited = inherited.sublist(0, point + 1);
      }
    }
    final own =
        _feed.values
            .where(
              (entry) =>
                  entry.worldSessionId == worldSessionId &&
                  entry.branchId == branchId,
            )
            .toList()
          ..sort(_compareFeed);
    return [...inherited, ...own];
  }

  @override
  Future<WorldDatabaseCounts> getDatabaseCounts(String worldSessionId) async {
    final session = _required(_sessions, worldSessionId, 'WorldSession');
    final bookIds = _books.values
        .where((item) => item.worldId == session.worldId)
        .map((item) => item.id)
        .toSet();
    return WorldDatabaseCounts(
      characterInstances: _count(
        _characters.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      loreEntries: _count(
        _lore.values,
        (item) => bookIds.contains(item.worldBookId),
      ),
      personas: _count(
        _personas.values,
        (item) => item.worldId == session.worldId,
      ),
      playerInstances: _count(
        _playerInstances.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      scenes: _count(
        _scenes.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      stateEntries: _count(
        _state.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      relationships: _count(
        _relationships.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      memories: _count(
        _memories.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      timelineEvents: _count(
        _timeline.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      branches: _count(
        _branches.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
      feedEntries: _count(
        _feed.values,
        (item) => item.worldSessionId == worldSessionId,
      ),
    );
  }

  @override
  Future<List<WorldSearchResult>> searchWorldDatabase(
    String worldSessionId,
    String query,
  ) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final session = _required(_sessions, worldSessionId, 'WorldSession');
    final bookIds = _books.values
        .where((item) => item.worldId == session.worldId)
        .map((item) => item.id)
        .toSet();
    final results = <WorldSearchResult>[];
    void add(String type, String id, String title, String preview) {
      if ('$title\n$preview'.toLowerCase().contains(needle)) {
        results.add(
          WorldSearchResult(type: type, id: id, title: title, preview: preview),
        );
      }
    }

    for (final item in _lore.values.where(
      (item) => bookIds.contains(item.worldBookId),
    )) {
      add('lore', item.id, item.title, item.content);
    }
    for (final item in _characters.values.where(
      (item) => item.worldSessionId == worldSessionId,
    )) {
      final card = coreStore.character(item.characterCardId);
      add(
        'character',
        item.id,
        item.displayNameOverride ?? card?.name ?? '角色',
        item.currentStatus,
      );
    }
    for (final item in _memories.values.where(
      (item) => item.worldSessionId == worldSessionId,
    )) {
      add('memory', item.id, item.summary, item.content);
    }
    for (final item in _timeline.values.where(
      (item) => item.worldSessionId == worldSessionId,
    )) {
      add('timeline', item.id, item.title, item.description);
    }
    for (final item in _state.values.where(
      (item) => item.worldSessionId == worldSessionId,
    )) {
      add('state', item.id, item.key, item.value.toString());
    }
    for (final item in _scenes.values.where(
      (item) => item.worldSessionId == worldSessionId,
    )) {
      add('scene', item.id, item.name, item.description);
    }
    return List.unmodifiable(results.take(100));
  }
}

T _required<T>(Map<String, T> values, String id, String entityName) {
  final value = values[id];
  if (value == null) throw EntityNotFoundException(entityName, id);
  return value;
}

List<T> _sortedUpdated<T extends WorldRoleplayEntity>(Iterable<T> values) {
  final items = values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return List.unmodifiable(items);
}

int _count<T>(Iterable<T> values, bool Function(T) test) =>
    values.where(test).length;

int _compareFeed(WorldFeedEntry left, WorldFeedEntry right) {
  final time = left.createdAt.compareTo(right.createdAt);
  return time != 0 ? time : left.id.compareTo(right.id);
}
